import 'package:flutter/material.dart';
import 'package:camera/camera.dart'; // Import camera
import 'verification_screen.dart';

// Global variable to store the list of cameras
List<CameraDescription> cameras = [];

Future<void> main() async {
  // 1. Ensure Flutter is ready
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Find available cameras (Front/Back)
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Attendance',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.cyanAccent, // Changed to Cyan for more Sci-Fi look
      ),
      // Pass the cameras to the screen
      home: VerificationScreen(cameras: cameras),
    );
  }
}