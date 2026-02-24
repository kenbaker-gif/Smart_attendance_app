import 'package:flutter/material.dart';
import 'package:camera/camera.dart'; 
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:wakelock_plus/wakelock_plus.dart'; 
import 'verification_screen.dart';
import 'login_screen.dart'; 
import 'admin_screen.dart';
import 'stats_screen.dart';           
import 'security_wrapper.dart';       

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Keep screen on for S23 Ultra
  try {
    WakelockPlus.enable();
  } catch (e) {
    debugPrint("Wakelock error: $e");
  }

  // 2. Load Environment & Supabase
  await dotenv.load(fileName: ".env");
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  
  // 3. Find available cameras
  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    debugPrint('Error in fetching the cameras: $e');
  }

  // 4. Run the app
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
      // 🟢 THE RECOMMENDED WRAP: 
      // ScaffoldMessenger allows Snackbars to work over the security layer.
      builder: (context, child) {
        return ScaffoldMessenger(
          child: SecurityWrapper(child: child!),
        );
      },
      initialRoute: isLoggedIn ? '/home' : '/login',
      routes: {
        '/login': (context) => LoginScreen(cameras: cameras),
        '/home': (context) => VerificationScreen(cameras: cameras),
        '/admin': (context) => AdminScreen(cameras: cameras),
        '/stats': (context) => const StatsScreen(),
      },
    );
  }
}