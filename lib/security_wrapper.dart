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
  bool _isCheckingSecurity = true;
  bool _isAuthenticating = false;

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
      _startInactivityTimer();
    }
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_timeoutLimit, () {
      if (mounted && !_isLocked) {
        setState(() => _isLocked = true);
        _authenticate();
      }
    });
  }

  void _resetInactivityTimer() {
    if (_isLocked) return;
    _recordInteraction();
    _startInactivityTimer();
  }

  Future<void> _recordInteraction() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, DateTime.now().toIso8601String());
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;
    _isAuthenticating = true;

    try {
      final authenticated = await _auth.authenticate(
        localizedReason: 'Scan fingerprint to unlock',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true),
      );

      if (authenticated && mounted) {
        setState(() => _isLocked = false);
        _recordInteraction();
        _startInactivityTimer();
      }
    } catch (e) {
      debugPrint("Auth error: $e");
    } finally {
      _isAuthenticating = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initializeSecurity();
    } else if (state == AppLifecycleState.paused) {
      _recordInteraction();
      _inactivityTimer?.cancel();
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
    // If checking, show the app but don't show the lock yet
    if (_isCheckingSecurity) return widget.child;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetInactivityTimer(),
      child: Stack(
        children: [
          // 🔹 THIS IS YOUR APP (Stats, Admin, etc.)
          // It stays exactly where it was.
          widget.child,

          // 🔹 THIS IS THE OVERLAY
          if (_isLocked)
            Material( // Using Material here ensures the lock screen renders correctly
              color: Colors.black.withOpacity(0.98),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.fingerprint, size: 80, color: Colors.cyanAccent),
                    const SizedBox(height: 24),
                    const Text("SECURITY LOCK ACTIVE", 
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2)),
                    const SizedBox(height: 48),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
                      onPressed: _authenticate,
                      child: const Text("UNLOCK", style: TextStyle(color: Colors.black)),
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