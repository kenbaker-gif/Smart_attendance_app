import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:local_auth/local_auth.dart';
import 'package:camera/camera.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'signup_screen.dart';
import 'session_gate_screen.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const LoginScreen({super.key, required this.cameras});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  final LocalAuthentication _auth = LocalAuthentication();

  bool _isLoading       = false;
  bool _obscurePassword = true;
  bool _hasSession      = false;

  @override
  void initState() {
    super.initState();
    _hasSession = Supabase.instance.client.auth.currentSession != null;
    GoogleSignIn.instance.initialize(
      serverClientId: dotenv.env['GOOGLE_WEB_CLIENT_ID'],
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Check institution status after auth ───────────────────────────────
  Future<Map<String, dynamic>> _checkInstitutionStatus(String userId) async {
    try {
      final profileRes = await Supabase.instance.client
          .from('profiles')
          .select('institution_id, is_super_admin, role')
          .eq('id', userId)
          .limit(1);

      debugPrint('[StatusCheck] profileRes: $profileRes');

      if (profileRes.isEmpty) {
        return {'error': 'Account not registered. Contact your institution admin.'};
      }

      final isSuperAdmin = profileRes[0]['is_super_admin'];
      final role = profileRes[0]['role']?.toString();

      if (isSuperAdmin == true) {
        return {'role': 'super_admin'};
      }

      // Block roles not allowed in Flutter app
      const flutterAllowed = ['admin', 'dept_admin', 'coordinator'];
      if (role == null || !flutterAllowed.contains(role)) {
        return {'error': 'Your account is only used to confirm attendance sessions, thank you'};
      }

      final institutionId = profileRes[0]['institution_id'];
      if (institutionId == null) {
        return {'role': role};
      }

      final institutionRes = await Supabase.instance.client
          .from('institutions')
          .select('status')
          .eq('id', institutionId)
          .limit(1);

      if (institutionRes.isEmpty) {
        return {'role': role};
      }

      final status = institutionRes[0]['status']?.toString().toLowerCase().trim();

      if (status == 'suspended') {
        return {'error': 'Your institution has been suspended. Contact support.'};
      }
      if (status == 'pending') {
        return {'error': 'Your institution is pending approval.'};
      }

      return {'role': role};
    } catch (e, stack) {
      debugPrint('[StatusCheck] Error: $e');
      debugPrint('[StatusCheck] Stack: $stack');
      return {'role': 'admin'}; // fail open
    }
  }

  // ── Audit: log login event to FastAPI ────────────────────────────────
  Future<void> _logLoginEvent(String jwt) async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final pkgInfo    = await PackageInfo.fromPlatform();
      String deviceModel = 'Unknown';
      String osVersion   = 'Unknown';

      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        deviceModel   = android.model;
        osVersion     = 'Android ${android.version.release}';
      } else if (Platform.isIOS) {
        final ios   = await deviceInfo.iosInfo;
        deviceModel = ios.utsname.machine;
        osVersion   = 'iOS ${ios.systemVersion}';
      }

      final response = await http.post(
        Uri.parse('https://faceattend.app/auth/log-login'),
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer $jwt',
        },
        body: jsonEncode({
          'device_model': deviceModel,
          'os_version':   osVersion,
          'app_version':  '${pkgInfo.version}+${pkgInfo.buildNumber}',
        }),
      );

      if (response.statusCode != 200) {
        debugPrint('[login] log-login failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[login] log-login error: $e');
    }
  }

  // ── Biometric unlock ─────────────────────────────────────────────────
  Future<void> _authenticate() async {
    try {
      final authenticated = await _auth.authenticate(
        localizedReason: 'Scan fingerprint to unlock',
      );
      if (!authenticated || !mounted) return;

      final session = Supabase.instance.client.auth.currentSession;
      final userId  = Supabase.instance.client.auth.currentUser?.id;

      if (userId != null) {
        final result = await _checkInstitutionStatus(userId);
        if (result.containsKey('error')) {
          await Supabase.instance.client.auth.signOut();
          if (mounted) _showSnack(result['error'], isError: true);
          if (mounted) setState(() => _hasSession = false);
          return;
        }
        if (session != null) await _logLoginEvent(session.accessToken);
        if (mounted) await _navigateAfterLogin(result['role'] ?? 'admin');
      }
    } catch (e) {
      debugPrint('Biometric error: $e');
    }
  }

  // ── Email / password login ────────────────────────────────────────────
  Future<void> _login() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      _showSnack("Please enter email and password.");
      return;
    }
    setState(() => _isLoading = true);
    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email:    _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final userId = res.user?.id;
      if (userId != null) {
        final result = await _checkInstitutionStatus(userId);
        if (result.containsKey('error')) {
          await Supabase.instance.client.auth.signOut();
          if (mounted) _showSnack(result['error'], isError: true);
          return;
        }
        if (res.session != null) _logLoginEvent(res.session!.accessToken);
        if (mounted) await _navigateAfterLogin(result['role'] ?? 'admin');
      }
    } on AuthException catch (e) {
      if (mounted) _showSnack(e.message, isError: true);
    } catch (e) {
      if (mounted) _showSnack("Login failed. Please try again.", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Google Sign-In ────────────────────────────────────────────────────
  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final googleUser = await GoogleSignIn.instance.authenticate();
      final idToken = googleUser.authentication.idToken;

      if (idToken == null) {
        if (mounted) _showSnack('Google sign-in failed. Check configuration.', isError: true);
        return;
      }

      // ── Preflight check ─────────────────────────────────────────────
      final preflightRes = await http.post(
        Uri.parse('https://faceattend.app/auth/google-preflight'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id_token': idToken}),
      );

      final preflightData = jsonDecode(preflightRes.body);

      if (preflightRes.statusCode != 200 || preflightData['allow'] != true) {
        await GoogleSignIn.instance.signOut();
        if (mounted) _showSnack(
          preflightData['reason'] ?? 'Access denied. Contact your institution admin.',
          isError: true,
        );
        return;
      }

      // ── Proceed with Supabase auth ───────────────────────────────────
      final res = await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken:  idToken,
      );

      final userId = res.user?.id;
      if (userId != null) {
        final result = await _checkInstitutionStatus(userId);
        if (result.containsKey('error')) {
          await Supabase.instance.client.auth.signOut();
          await GoogleSignIn.instance.signOut();
          if (mounted) _showSnack(result['error'], isError: true);
          return;
        }
        if (res.session != null) _logLoginEvent(res.session!.accessToken);
        if (mounted) await _navigateAfterLogin(result['role'] ?? 'admin');
      }
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return;
      if (mounted) _showSnack('Google sign-in failed. Try again.', isError: true);
    } on AuthException catch (e) {
      if (mounted) _showSnack(e.message, isError: true);
    } catch (e) {
      debugPrint('[Google SignIn] error: $e');
      if (mounted) _showSnack('Google sign-in failed. Try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Role-based navigation ─────────────────────────────────────────────
  Future<void> _navigateAfterLogin(String role) async {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : null,
    ));
  }

  Future<void> _openForgotPassword() async {
    final uri = Uri.parse('https://faceattend.app/reset-password');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[forgot-password] launch error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Could not open browser. Visit faceattend.app/reset-password manually."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 48),

                    // Icon + Title
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withOpacity(0.1),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.cyanAccent.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.face_retouching_natural,
                          size: 72, color: Colors.cyanAccent),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _hasSession ? "Welcome Back" : "FaceAttend",
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 8),
                    Text("Sign in to continue",
                        style: TextStyle(color: Colors.grey[400], fontSize: 14)),
                    const SizedBox(height: 48),

                    // Email
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration("Email", Icons.email_outlined),
                    ),
                    const SizedBox(height: 14),

                    // Password
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration(
                        "Password",
                        Icons.lock_outline,
                        suffix: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: Colors.grey, size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),

                    // Forgot password
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _openForgotPassword,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.cyanAccent,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Forgot password?',
                            style: TextStyle(fontSize: 13)),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Login button
                    _isLoading
                        ? const CircularProgressIndicator(color: Colors.cyanAccent)
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyanAccent,
                              foregroundColor: Colors.black,
                              minimumSize: const Size(double.infinity, 54),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              elevation: 8,
                              shadowColor: Colors.cyanAccent.withOpacity(0.5),
                            ),
                            onPressed: _login,
                            child: const Text("LOGIN",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    letterSpacing: 1.2)),
                          ),

                    const SizedBox(height: 16),

                    // Google Sign-In button
                    if (!_isLoading)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.grey[700]!, width: 1.5),
                          minimumSize: const Size(double.infinity, 54),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          backgroundColor: Colors.grey[900],
                        ),
                        onPressed: _signInWithGoogle,
                        icon: const Icon(Icons.g_mobiledata,
                            size: 26, color: Colors.white),
                        label: const Text("CONTINUE WITH GOOGLE",
                            style: TextStyle(fontSize: 14, letterSpacing: 0.5)),
                      ),

                    // Biometric
                    if (_hasSession && !_isLoading) ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.cyanAccent,
                          side: const BorderSide(color: Colors.cyanAccent, width: 1.5),
                          minimumSize: const Size(double.infinity, 54),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          backgroundColor: Colors.cyanAccent.withOpacity(0.05),
                        ),
                        onPressed: _authenticate,
                        icon: const Icon(Icons.fingerprint, size: 22),
                        label: const Text("USE FINGERPRINT",
                            style: TextStyle(fontSize: 14, letterSpacing: 0.5)),
                      ),
                    ],

                    const SizedBox(height: 32),

                    // Register university
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.cyanAccent,
                        side: BorderSide(color: Colors.grey[800]!, width: 1.5),
                        minimumSize: const Size(double.infinity, 54),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        backgroundColor: Colors.grey[900]?.withOpacity(0.3),
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SignupScreen(cameras: widget.cameras),
                        ),
                      ),
                      icon: const Icon(Icons.school_outlined, size: 20),
                      label: const Text("REGISTER YOUR UNIVERSITY",
                          style: TextStyle(fontSize: 13, letterSpacing: 0.5)),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon,
      {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey),
      prefixIcon: Icon(icon, color: Colors.cyanAccent, size: 20),
      suffixIcon: suffix,
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.grey),
        borderRadius: BorderRadius.circular(10),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.cyanAccent),
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}