import 'dart:async';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecurityWrapper extends StatefulWidget {
  final Widget child;
  const SecurityWrapper({super.key, required this.child});

  @override
  State<SecurityWrapper> createState() => _SecurityWrapperState();
}

class _SecurityWrapperState extends State<SecurityWrapper> with WidgetsBindingObserver {
  final LocalAuthentication _auth = LocalAuthentication();
  Timer? _inactivityTimer;
  
  bool _isLocked = false;
  bool _isAppPaused = false;
  bool _isCheckingSecurity = true;

  static const Duration _timeoutLimit = Duration(minutes: 2);
  static const String _storageKey = 'last_interaction_time';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeSecurity();
  }

  Future<void> _initializeSecurity() async {
    final prefs = await SharedPreferences.getInstance();
    final lastActiveStr = prefs.getString(_storageKey);
    
    bool shouldLock = false;
    if (lastActiveStr != null) {
      final lastActive = DateTime.tryParse(lastActiveStr);
      if (lastActive != null && DateTime.now().difference(lastActive) >= _timeoutLimit) {
        shouldLock = true;
      }
    }

    if (mounted) {
      setState(() {
        _isLocked = shouldLock;
        _isCheckingSecurity = false;
      });
      if (shouldLock) _authenticate();
    }
    _resetTimer();
  }

  void _resetTimer() {
    if (_isLocked) return;
    _recordInteraction();
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_timeoutLimit, () {
      if (mounted) setState(() => _isLocked = true);
    });
  }

  Future<void> _recordInteraction() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, DateTime.now().toIso8601String());
  }

  Future<void> _authenticate() async {
    try {
      bool authenticated = await _auth.authenticate(
        localizedReason: 'Scan fingerprint to unlock',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true),
      );

      if (authenticated && mounted) {
        setState(() => _isLocked = false);
        _resetTimer();
      }
    } catch (e) {
      debugPrint("Auth error: $e");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _isAppPaused = (state != AppLifecycleState.resumed));
    if (state == AppLifecycleState.resumed) {
      _initializeSecurity();
    } else {
      _recordInteraction();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingSecurity) return const Scaffold(backgroundColor: Colors.black);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetTimer(),
      child: Stack(
        children: [
          // THE ACTUAL SCREEN (Admin, Stats, etc.)
          widget.child,

          // PRIVACY SCREEN (When in background)
          if (_isAppPaused) Container(color: Colors.black),

          // LOCK SCREEN
          if (_isLocked && !_isAppPaused)
            Material(
              color: Colors.black.withOpacity(0.98),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.fingerprint, size: 80, color: Colors.cyanAccent),
                    const SizedBox(height: 24),
                    const Text("LOCKED", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2)),
                    const SizedBox(height: 48),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black),
                      onPressed: _authenticate,
                      child: const Text("UNLOCK NOW"),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}