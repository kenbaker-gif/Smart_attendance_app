import 'package:flutter/material.dart';
import 'package:camera/camera.dart'; 
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // ✅ Import dotenv
import 'verification_screen.dart';
import 'login_screen.dart'; 

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Load the Environment File 🔐
  await dotenv.load(fileName: ".env");

  // 2. Initialize Supabase using the secure keys
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,      // Read from .env
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!, // Read from .env
  );
  
  // 3. Find available cameras
  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    print('Error in fetching the cameras: $e');
  }

  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Check Login Status
    final session = Supabase.instance.client.auth.currentSession;
    final bool isLoggedIn = session != null;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Attendance',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.cyanAccent, 
      ),
      home: isLoggedIn 
          ? VerificationScreen(cameras: cameras) 
          : LoginScreen(cameras: cameras),
    );
  }
}