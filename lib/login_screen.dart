import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:local_auth/local_auth.dart'; // ✅ New Import
import 'verification_screen.dart';
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
  
  // 👆 Biometric Variables
  final LocalAuthentication auth = LocalAuthentication();
  bool _canCheckBiometrics = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  // 1. Check if phone has fingerprint hardware
  Future<void> _checkBiometrics() async {
    bool canCheckBiometrics;
    try {
      canCheckBiometrics = await auth.canCheckBiometrics && await auth.isDeviceSupported();
    } on PlatformException catch (e) {
      canCheckBiometrics = false;
      print(e);
    }
    if (!mounted) return;
    setState(() {
      _canCheckBiometrics = canCheckBiometrics;
    });
    
    // Auto-trigger if session exists (optional)
    if (_canCheckBiometrics && Supabase.instance.client.auth.currentSession != null) {
      _authenticate();
    }
  }

  // 2. The Fingerprint Logic 👆
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
      print(e);
      return;
    }

    if (!mounted) return;

    if (authenticated) {
      // ✅ UNLOCK SUCCESS
      // Check if session is valid, if not, user must use password
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
         Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => VerificationScreen(cameras: widget.cameras)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Session expired. Please login with password first.")),
        );
      }
    }
  }

  Future<void> _login() async {
    setState(() => _isLoading = true);
    try {
      final AuthResponse res = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (res.user != null) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => VerificationScreen(cameras: widget.cameras)),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Access Denied: Wrong Credentials"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check if we have a valid session (just locked)
    final bool hasSession = Supabase.instance.client.auth.currentSession != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_person, size: 80, color: Colors.cyanAccent),
            const SizedBox(height: 20),
            Text(
              hasSession ? "Welcome Back" : "Admin Login", 
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)
            ),
            const SizedBox(height: 40),

            // If session expired, show Email/Pass. If session exists, hide them (Clean UI)
            if (!hasSession) ...[
              TextField(
                controller: _emailController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Email",
                  prefixIcon: Icon(Icons.email, color: Colors.cyanAccent),
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent)),
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
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent)),
                ),
              ),
              const SizedBox(height: 30),
            ],

            // LOGIN BUTTON
            if (!hasSession)
              _isLoading 
                ? const CircularProgressIndicator(color: Colors.cyanAccent)
                : SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _login,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
                      child: const Text("LOGIN", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  ),

            // FINGERPRINT BUTTON (Only shows if hardware is available)
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
                        border: Border.all(color: Colors.cyanAccent.withOpacity(0.5), width: 2),
                      ),
                      child: const Icon(Icons.fingerprint, size: 50, color: Colors.cyanAccent),
                    ),
                    const SizedBox(height: 10),
                    const Text("Tap to Unlock", style: TextStyle(color: Colors.cyanAccent)),
                  ],
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}