import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:local_auth/local_auth.dart';
import 'package:camera/camera.dart';

class LoginScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const LoginScreen({super.key, required this.cameras});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  final LocalAuthentication auth = LocalAuthentication();
  bool _canCheckBiometrics = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    bool canCheckBiometrics;
    try {
      canCheckBiometrics =
          await auth.canCheckBiometrics && await auth.isDeviceSupported();
    } on PlatformException catch (e) {
      canCheckBiometrics = false;
      debugPrint('Biometrics check error: $e');
    }
    if (!mounted) return;
    setState(() => _canCheckBiometrics = canCheckBiometrics);

    // Auto-trigger biometric if a valid session already exists
    if (_canCheckBiometrics &&
        Supabase.instance.client.auth.currentSession != null) {
      _authenticate();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ✅ Single routing method — always called after successful auth/login.
  //    Fetches the admin flag and pushes the correct named route.
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _navigateAfterLogin() async {
    if (!mounted) return;
    // ✅ Everyone lands on /home — VerificationScreen shows admin buttons conditionally
    Navigator.of(context).pushReplacementNamed('/home');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Biometric unlock (used when a session already exists)
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _authenticate() async {
    bool authenticated = false;
    try {
      authenticated = await auth.authenticate(
        localizedReason: 'Scan fingerprint to unlock Admin Access',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } on PlatformException catch (e) {
      debugPrint('Biometric auth error: $e');
      return;
    }

    if (!mounted) return;

    if (authenticated) {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        // ✅ Use shared routing — checks admin role
        await _navigateAfterLogin();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Session expired. Please login with password."),
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Email + password login
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _login() async {
    setState(() => _isLoading = true);
    try {
      final AuthResponse res =
          await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (res.user != null) {
        // ✅ Use shared routing — checks admin role
        await _navigateAfterLogin();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Access Denied: Wrong Credentials"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bool hasSession =
        Supabase.instance.client.auth.currentSession != null;

    return Scaffold(
      backgroundColor: Colors.black,
      // ✅ SingleChildScrollView prevents the overflow when keyboard appears
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height,
          ),
          child: IntrinsicHeight(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_person, size: 80, color: Colors.cyanAccent),
                const SizedBox(height: 20),
                Text(
                  hasSession ? "Welcome Back" : "Admin Login",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 40),

                if (!hasSession) ...[
                  TextField(
                    controller: _emailController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Email",
                      prefixIcon: Icon(Icons.email, color: Colors.cyanAccent),
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.cyanAccent)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: "Password",
                      prefixIcon: Icon(Icons.key, color: Colors.cyanAccent),
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.cyanAccent)),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],

                if (!hasSession)
                  _isLoading
                      ? const CircularProgressIndicator(
                          color: Colors.cyanAccent)
                      : SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _login,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.cyanAccent),
                            child: const Text(
                              "LOGIN",
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),

                if (_canCheckBiometrics) ...[
                  const SizedBox(height: 40),
                  GestureDetector(
                    onTap: _authenticate,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.cyanAccent.withOpacity(0.5),
                              width: 2,
                            ),
                          ),
                          child: const Icon(Icons.fingerprint,
                              size: 50, color: Colors.cyanAccent),
                        ),
                        const SizedBox(height: 10),
                        const Text("Tap to Unlock",
                            style: TextStyle(color: Colors.cyanAccent)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}