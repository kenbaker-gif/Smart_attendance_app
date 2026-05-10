import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:local_auth/local_auth.dart';
import 'package:camera/camera.dart';
// import 'package:google_sign_in/google_sign_in.dart';
import 'signup_screen.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart';
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

  bool _isLoading        = false;
  bool _obscurePassword  = true;
  bool _hasSession       = false;

  @override
  void initState() {
    super.initState();
    _hasSession = Supabase.instance.client.auth.currentSession != null;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Check institution status after auth ───────────────────────────────
  Future<String?> _checkInstitutionStatus(String userId) async {
    try {
      final profileRes = await Supabase.instance.client
          .from('profiles')
          .select('institution_id, is_super_admin')
          .eq('id', userId)
          .limit(1);

      debugPrint('[StatusCheck] profileRes: $profileRes');

      if (profileRes.isEmpty) {
        debugPrint('[StatusCheck] No profile found — allowing login');
        return null;
      }

      final isSuperAdmin = profileRes[0]['is_super_admin'];
      debugPrint('[StatusCheck] is_super_admin: $isSuperAdmin');

      if (isSuperAdmin == true) {
        debugPrint('[StatusCheck] Super admin — bypassing status check');
        return null;
      }

      final institutionId = profileRes[0]['institution_id'];
      debugPrint('[StatusCheck] institution_id: $institutionId');

      if (institutionId == null) {
        debugPrint('[StatusCheck] No institution_id — allowing login');
        return null;
      }

      final institutionRes = await Supabase.instance.client
          .from('institutions')
          .select('status')
          .eq('id', institutionId)
          .limit(1);

      debugPrint('[StatusCheck] institutionRes: $institutionRes');

      if (institutionRes.isEmpty) {
        debugPrint('[StatusCheck] Institution not found — allowing login');
        return null;
      }

      final status = institutionRes[0]['status']?.toString().toLowerCase().trim();
      debugPrint('[StatusCheck] status: "$status"');

      if (status == 'suspended') {
        return 'Your institution has been suspended. Contact support.';
      }
      if (status == 'pending') {
        return 'Your institution is pending approval.';
      }

      debugPrint('[StatusCheck] Status is active — allowing login');
      return null;
    } catch (e, stack) {
      debugPrint('[StatusCheck] Error: $e');
      debugPrint('[StatusCheck] Stack: $stack');
      return null;
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
      // Never block login on audit failure
      debugPrint('[login] log-login error: $e');
    }
  }

  Future<void> _authenticate() async {
    try {
      final authenticated = await _auth.authenticate(
        localizedReason: 'Scan fingerprint to unlock',
      );
      if (!authenticated || !mounted) return;

      final session = Supabase.instance.client.auth.currentSession;
      final userId  = Supabase.instance.client.auth.currentUser?.id;

      if (userId != null) {
        final error = await _checkInstitutionStatus(userId);
        if (error != null) {
          await Supabase.instance.client.auth.signOut();
          if (mounted) _showSnack(error, isError: true);
          if (mounted) setState(() => _hasSession = false);
          return;
        }
      }

      // Log biometric login event
      if (session != null) {
        await _logLoginEvent(session.accessToken);
      }

      if (mounted) _navigateAfterLogin();
    } catch (e) {
      debugPrint('Biometric error: $e');
    }
  }

  Future<void> _login() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      _showSnack("Please enter email and password.");
      return;
    }
    setState(() => _isLoading = true);
    try {
      // 1. Supabase auth
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email:    _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // 2. Check institution status
      final userId = res.user?.id;
      if (userId != null) {
        final error = await _checkInstitutionStatus(userId);
        if (error != null) {
          await Supabase.instance.client.auth.signOut();
          if (mounted) _showSnack(error, isError: true);
          return;
        }
      }

      // 3. Log login event (fire and forget — won't block navigation)
      if (res.session != null) {
        _logLoginEvent(res.session!.accessToken);
      }

      if (mounted) _navigateAfterLogin();
    } on AuthException catch (e) {
      if (mounted) _showSnack(e.message, isError: true);
    } catch (e) {
      if (mounted) _showSnack("Login failed. Please try again.", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateAfterLogin() {
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
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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
                    const SizedBox(height: 40),

                    // Icon + Title
                    const Icon(Icons.face_retouching_natural,
                        size: 72, color: Colors.cyanAccent),
                    const SizedBox(height: 16),
                    Text(
                      _hasSession ? "Welcome Back" : "Smart Attendance",
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 6),
                    const Text("Sign in to continue",
                        style: TextStyle(color: Colors.grey, fontSize: 14)),
                    const SizedBox(height: 40),

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
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),

                    // Forgot password link
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _openForgotPassword,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.cyanAccent,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Forgot password?',
                          style: TextStyle(fontSize: 13),
                        ),
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
                              minimumSize: const Size(double.infinity, 52),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _login,
                            child: const Text("LOGIN",
                                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                          ),

                    // Biometric
                    if (_hasSession) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.cyanAccent,
                          side: const BorderSide(color: Colors.cyanAccent),
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _authenticate,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text("USE FINGERPRINT"),
                      ),
                    ],

                    const SizedBox(height: 28),

                    // Register university
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.cyanAccent,
                        side: const BorderSide(color: Colors.grey),
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SignupScreen(cameras: widget.cameras),
                        ),
                      ),
                      icon: const Icon(Icons.school_outlined, size: 20),
                      label: const Text("REGISTER YOUR UNIVERSITY"),
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

  InputDecoration _inputDecoration(String label, IconData icon, {Widget? suffix}) {
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