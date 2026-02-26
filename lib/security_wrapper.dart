import 'dart:async';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecurityWrapper extends StatefulWidget {
  final Widget child;

  /// Set to true on routes that require admin privileges (e.g. /admin, /stats).
  /// Non-admin users will be ejected back to the first route with a SnackBar.
  final bool isAdminRoute;

  const SecurityWrapper({
    super.key,
    required this.child,
    this.isAdminRoute = false,
  });

  @override
  State<SecurityWrapper> createState() => _SecurityWrapperState();
}

class _SecurityWrapperState extends State<SecurityWrapper>
    with WidgetsBindingObserver {
  final LocalAuthentication _auth = LocalAuthentication();
  Timer? _inactivityTimer;

  bool _isLocked = false;
  bool _isAppPaused = false;

  /// True while we are still doing the async security check on first load.
  bool _isCheckingSecurity = true;

  /// Whether the currently logged-in user has admin privileges.
  bool _isAdmin = false;

  static const Duration _timeoutLimit = Duration(minutes: 2);
  static const String _storageKey = 'last_interaction_time';

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeSecurity();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _isAppPaused = (state != AppLifecycleState.resumed));

    if (state == AppLifecycleState.resumed) {
      // ✅ Only re-check the lock state on resume — do NOT re-fetch _isAdmin.
      //    Re-fetching admin status caused a brief window where _isAdmin was
      //    false, which triggered the unauthorised redirect for real admins.
      _checkLockStatus();
    } else {
      _recordInteraction();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Initialisation (runs once on mount)
  // ─────────────────────────────────────────────────────────────────────────

  /// Full initialisation: checks inactivity timeout AND fetches admin status.
  /// Only called once — on initState.
  Future<void> _initializeSecurity() async {
    // 1. Check inactivity timeout
    final prefs = await SharedPreferences.getInstance();
    final lastActiveStr = prefs.getString(_storageKey);

    bool shouldLock = false;
    if (lastActiveStr != null) {
      final lastActive = DateTime.tryParse(lastActiveStr);
      if (lastActive != null &&
          DateTime.now().difference(lastActive) >= _timeoutLimit) {
        shouldLock = true;
      }
    }

    // 2. Fetch admin status from Supabase (only once)
    final user = Supabase.instance.client.auth.currentUser;
    bool isAdmin = false;
    if (user != null) {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('is_admin')
          .eq('id', user.id)
          .maybeSingle();

      isAdmin = data != null && data['is_admin'] == true;
    }

    // 3. Apply state — both values are set before a single setState call,
    //    so the widget never builds with a stale _isAdmin = false.
    if (mounted) {
      setState(() {
        _isAdmin = isAdmin;
        _isLocked = shouldLock;
        _isCheckingSecurity = false;
      });

      if (shouldLock) _authenticate();
    }

    _resetTimer();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Lock-state check (called on app resume — does NOT touch _isAdmin)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _checkLockStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final lastActiveStr = prefs.getString(_storageKey);

    if (lastActiveStr != null) {
      final lastActive = DateTime.tryParse(lastActiveStr);
      if (lastActive != null &&
          DateTime.now().difference(lastActive) >= _timeoutLimit) {
        if (mounted) setState(() => _isLocked = true);
        _authenticate();
        return;
      }
    }

    _resetTimer();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Inactivity timer
  // ─────────────────────────────────────────────────────────────────────────

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

  // ─────────────────────────────────────────────────────────────────────────
  // Biometric authentication
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _authenticate() async {
    try {
      final authenticated = await _auth.authenticate(
        localizedReason: 'Scan fingerprint to unlock',
        options:
            const AuthenticationOptions(stickyAuth: true, biometricOnly: true),
      );

      if (authenticated && mounted) {
        setState(() => _isLocked = false);
        _resetTimer();
      }
    } catch (e) {
      debugPrint("Auth error: $e");
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Show a blank screen while the async security check runs.
    if (_isCheckingSecurity) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    // ✅ Admin gate — uses the explicit isAdminRoute flag instead of
    //    runtimeType string comparison (which is unreliable in release builds).
    if (widget.isAdminRoute && !_isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Unauthorized: Admin access only"),
              backgroundColor: Colors.red,
            ),
          );
        }
      });
      return const SizedBox.shrink();
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetTimer(),
      child: Stack(
        children: [
          // The actual screen (AdminScreen, StatsScreen, VerificationScreen…)
          widget.child,

          // Privacy overlay — hides content when the app is backgrounded.
          if (_isAppPaused) Container(color: Colors.black),

          // Lock screen overlay — shown after inactivity timeout.
          if (_isLocked && !_isAppPaused)
            Material(
              color: Colors.black.withOpacity(0.98),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.fingerprint,
                      size: 80,
                      color: Colors.cyanAccent,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      "LOCKED",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 48),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent,
                        foregroundColor: Colors.black,
                      ),
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