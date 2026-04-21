import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'verification_screen.dart';
import 'login_screen.dart';
import 'admin_screen.dart';
import 'stats_screen.dart';
import 'security_wrapper.dart';
import 'signup_screen.dart';
import 'config.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    WakelockPlus.enable();
  } catch (e) {
    debugPrint("Wakelock error: $e");
  }

  await dotenv.load(fileName: ".env");
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    debugPrint('Error in fetching the cameras: $e');
  }

  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    final bool isLoggedIn = session != null;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Attendance',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.cyanAccent,
      ),
      builder: (context, child) {
        return ScaffoldMessenger(child: child!);
      },
      initialRoute: isLoggedIn ? '/home' : '/login',
      routes: {
        '/login': (context) => LoginScreen(cameras: cameras),
        '/home': (context) => SecurityWrapper(
              child: _HomeBuilder(cameras: cameras),
            ),
        '/admin': (context) => SecurityWrapper(
              isAdminRoute: true,
              child: TrialGate(
                cameras: cameras,
                child: AdminScreen(cameras: cameras),
              ),
            ),
        '/stats': (context) => SecurityWrapper(
              isAdminRoute: true,
              child: TrialGate(
                cameras: cameras,
                child: const StatsScreen(),
              ),
            ),
      },
    );
  }
}

// ── Home Builder ───────────────────────────────────────────────────────────

class _HomeBuilder extends StatefulWidget {
  final List<CameraDescription> cameras;
  const _HomeBuilder({required this.cameras});

  @override
  State<_HomeBuilder> createState() => _HomeBuilderState();
}

class _HomeBuilderState extends State<_HomeBuilder> {
  String _institutionId = '';
  String? _courseUnitId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadInstitutionId();
  }

  Future<void> _loadInstitutionId() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() => _loading = false);
        return;
      }
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('institution_id, course_unit_id')
          .eq('id', user.id)
          .limit(1)
          .single();
      if (mounted) {
        setState(() {
          _institutionId = profile['institution_id'] as String? ?? '';
          _courseUnitId = profile['course_unit_id'] as String?;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('_HomeBuilder: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
      );
    }
    return TrialGate(
      cameras: widget.cameras,
      child: VerificationScreen(
        cameras: widget.cameras,
        institutionId: _institutionId,
        courseUnitId: _courseUnitId,
      ),
    );
  }
}

// ── Trial Gate ─────────────────────────────────────────────────────────────

class TrialGate extends StatefulWidget {
  final Widget child;
  final List<CameraDescription> cameras;

  const TrialGate({super.key, required this.child, required this.cameras});

  @override
  State<TrialGate> createState() => _TrialGateState();
}

class _TrialGateState extends State<TrialGate> {
  bool _loading = true;
  bool _active = true;
  bool _pending = false;
  String _reason = '';
  int? _daysLeft;

  @override
  void initState() {
    super.initState();
    _checkTrial();
  }

  Future<void> _checkTrial() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() => _loading = false);
        return;
      }

      final profile = await Supabase.instance.client
          .from('profiles')
          .select('institution_id')
          .eq('id', user.id)
          .limit(1)
          .single();

      final institutionId = profile['institution_id'] as String?;
      if (institutionId == null) {
        setState(() => _loading = false);
        return;
      }

      final baseUrl = dotenv.env['API_URL'] ?? AppConfig.checkTrialUrl;
      final response = await http.get(
        Uri.parse('$baseUrl/check-trial/$institutionId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final active = data['active'] as bool? ?? true;
        final reason = data['reason'] as String? ?? '';
        final daysLeft = data['days_left'] as int?;

        setState(() {
          _active = active;
          _reason = reason;
          _daysLeft = daysLeft;
          _pending = reason.toLowerCase().contains('pending');
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('Trial check error: $e');
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.cyanAccent),
        ),
      );
    }

    if (!_active) {
      return _pending
          ? _PendingScreen()
          : _TrialExpiredScreen(reason: _reason);
    }

    if (_daysLeft != null && _daysLeft! <= 7) {
      return Column(
        children: [
          Container(
            width: double.infinity,
            color: _daysLeft! <= 3 ? Colors.red[900] : Colors.orange[900],
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Text(
              '⚠️  Trial expires in $_daysLeft day${_daysLeft == 1 ? '' : 's'}. Contact us to upgrade.',
              style: const TextStyle(color: Colors.white, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(child: widget.child),
        ],
      );
    }

    return widget.child;
  }
}

// ── Pending screen ─────────────────────────────────────────────────────────

class _PendingScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.hourglass_top, color: Colors.cyanAccent, size: 64),
              const SizedBox(height: 24),
              const Text(
                'Awaiting Approval',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Your institution is currently under review. You will receive an email once your account is approved.',
                style: TextStyle(color: Colors.white70, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.cyanAccent,
                  side: const BorderSide(color: Colors.cyanAccent),
                ),
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                  if (context.mounted) {
                    Navigator.pushReplacementNamed(context, '/login');
                  }
                },
                child: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Trial expired screen ───────────────────────────────────────────────────

class _TrialExpiredScreen extends StatelessWidget {
  final String reason;
  const _TrialExpiredScreen({required this.reason});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_clock, color: Colors.orangeAccent, size: 64),
              const SizedBox(height: 24),
              const Text(
                'Trial Expired',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Your 30-day trial has ended. Contact us to upgrade and keep your attendance data.',
                style: TextStyle(color: Colors.white70, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  // TODO: replace with your email or upgrade URL
                },
                child: const Text('Contact Us to Upgrade'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.cyanAccent,
                  side: const BorderSide(color: Colors.cyanAccent),
                ),
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                  if (context.mounted) {
                    Navigator.pushReplacementNamed(context, '/login');
                  }
                },
                child: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}