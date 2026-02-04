import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';

class VerificationScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const VerificationScreen({super.key, required this.cameras});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  bool _isScanning = false;
  bool _showFlash = false;
  
  int _selectedCameraIndex = 0; 
  Map<String, dynamic>? _result;

  // ⏱️ SECURITY VARIABLES
  Timer? _inactivityTimer;
  static const int _timeoutSeconds = 120; // 2 Minutes
  DateTime? _pausedTime; 

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startInactivityTimer();
    _selectedCameraIndex = 0;
    _initCamera(_selectedCameraIndex);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedTime = DateTime.now();
      _inactivityTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      if (_pausedTime != null) {
        final timeInBackground = DateTime.now().difference(_pausedTime!);
        
        if (timeInBackground.inSeconds >= _timeoutSeconds) {
          print("Background timeout. Locking...");
          _logout(); // Triggers the Soft Lock
        } else {
          _startInactivityTimer();
        }
      }
    }
  }

  // 🔒 "SOFT LOCK" LOGIC
  Future<void> _logout() async {
    _inactivityTimer?.cancel();
    
    // ⚠️ CRITICAL CHANGE: We DO NOT sign out here.
    // We keep the session alive so Fingerprint/FaceID works on the Login Screen.
    // await Supabase.instance.client.auth.signOut(); <--- REMOVED
    
    if (!mounted) return;
    
    // Return to Login Screen (Session remains valid for Biometric Unlock)
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(cameras: widget.cameras)),
      (route) => false,
    );
  }

  // 🔴 "HARD LOGOUT" (For the button)
  // If the user manually clicks the Logout button, we WANT to kill the session.
  Future<void> _manualLogout() async {
    _inactivityTimer?.cancel();
    await Supabase.instance.client.auth.signOut(); // Kill session
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(cameras: widget.cameras)),
      (route) => false,
    );
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(seconds: _timeoutSeconds), () {
      print("Screen idle timeout. Locking...");
      _logout();
    });
  }

  void _userInteracted() {
    _startInactivityTimer();
  }

  Future<void> _initCamera(int cameraIndex) async {
    if (widget.cameras.isEmpty) return;
    if (_controller != null) await _controller!.dispose();

    _controller = CameraController(
      widget.cameras[cameraIndex],
      ResolutionPreset.medium, 
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      if (_controller!.description.lensDirection == CameraLensDirection.back) {
         await _controller!.setFlashMode(FlashMode.off);
      }
      if (!mounted) return;
      setState(() => _isCameraInitialized = true);
    } catch (e) {
      debugPrint("Camera Init Error: $e");
    }
  }

  void _toggleCamera() {
    if (widget.cameras.length < 2) return; 
    _userInteracted();
    setState(() {
      _isCameraInitialized = false; 
      _selectedCameraIndex = (_selectedCameraIndex + 1) % widget.cameras.length;
    });
    _initCamera(_selectedCameraIndex);
  }

  Future<File> compressFile(File file) async {
    final filePath = file.absolute.path;
    final lastIndex = filePath.lastIndexOf(RegExp(r'.jp'));
    final splitted = filePath.substring(0, (lastIndex));
    final outPath = "${splitted}_out.jpg";
    
    var result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path, outPath,
      quality: 60, minWidth: 600, minHeight: 600,
    );
    return File(result!.path);
  }

  Future<void> _scanFace() async {
    _userInteracted();
    if (!_isCameraInitialized || _isScanning) return;

    setState(() {
      _isScanning = true;
      _result = null;
      _showFlash = true;
    });

    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) setState(() => _showFlash = false);
    });

    try {
      final XFile image = await _controller!.takePicture();
      await _controller!.pausePreview();
      File fileToSend = await compressFile(File(image.path));

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('https://smartattendancemvp-production.up.railway.app/verify')
      );
      request.files.add(await http.MultipartFile.fromPath('file', fileToSend.path));

      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception("Connection too slow."),
      );

      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        var json = jsonDecode(response.body);
        if (mounted) setState(() => _result = json);
      } else {
        _showError("Server Error (${response.statusCode})");
      }
    } catch (e) {
      _showError("Error: $e");
    } finally {
      if (mounted) {
        if (_controller != null && _controller!.value.isInitialized) {
          await _controller!.resumePreview();
        }
        setState(() => _isScanning = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); 
    _inactivityTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.cyanAccent)));
    }

    bool isMatch = false;
    String identity = "Unknown";

    if (_result != null) {
      if (_result!['match'] == true || _result!['status'] == 'success') isMatch = true;
      if (_result!['name'] != null) identity = _result!['name'].toString();
    }

    return Listener(
      onPointerDown: (_) => _userInteracted(), 
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Center(child: CameraPreview(_controller!)),
            CustomPaint(size: Size.infinite, painter: ScannerOverlayPainter()),

            // 🔴 MANUAL LOGOUT BUTTON (Kills session)
            Positioned(
              top: 50, left: 20,
              child: FloatingActionButton.small(
                heroTag: "logout_btn",
                backgroundColor: Colors.red.withOpacity(0.8),
                onPressed: _manualLogout, // Use Manual Logout here!
                child: const Icon(Icons.logout, color: Colors.white),
              ),
            ),

            // 📷 SWITCH CAMERA
            if (widget.cameras.length > 1)
              Positioned(
                top: 50, right: 20,
                child: GestureDetector(
                  onTap: _toggleCamera,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle, border: Border.all(color: Colors.cyanAccent, width: 2)),
                    child: const Icon(Icons.cameraswitch_rounded, color: Colors.cyanAccent, size: 30),
                  ),
                ),
              ),

            // 📝 RESULT
            Positioned(
              top: 120, left: 20, right: 20,
              child: Column(
                children: [
                  if (_result != null)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        border: Border.all(color: isMatch ? Colors.greenAccent : Colors.redAccent, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isMatch ? "AUTHORIZED: $identity" : "ACCESS DENIED",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: isMatch ? Colors.greenAccent : Colors.redAccent, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),

            // 🔘 SCAN BUTTON
            Positioned(
              bottom: 50, left: 0, right: 0,
              child: Column(
                children: [
                  Text(_isScanning ? "ANALYZING..." : "AUTO-LOCK ENABLED (2M)", style: const TextStyle(color: Colors.cyanAccent, fontSize: 14, letterSpacing: 2.0)),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: _scanFace,
                    child: Container(
                      height: 80, width: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.cyanAccent, width: 3),
                        boxShadow: [BoxShadow(color: Colors.cyanAccent.withOpacity(0.3), blurRadius: 15)],
                      ),
                      child: Center(
                        child: _isScanning
                            ? const CircularProgressIndicator(color: Colors.cyanAccent)
                            : const Icon(Icons.fingerprint, color: Colors.cyanAccent, size: 45),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            if (_showFlash) Container(color: Colors.white.withOpacity(0.6)),
          ],
        ),
      ),
    );
  }
}

class ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.cyanAccent..style = PaintingStyle.stroke..strokeWidth = 3.0;
    double boxSize = size.width * 0.75;
    double left = (size.width - boxSize) / 2;
    double top = (size.height - boxSize) / 2.5;
    double len = 30.0;

    canvas.drawLine(Offset(left, top), Offset(left + len, top), paint);
    canvas.drawLine(Offset(left, top), Offset(left, top + len), paint);
    canvas.drawLine(Offset(left + boxSize, top), Offset(left + boxSize - len, top), paint);
    canvas.drawLine(Offset(left + boxSize, top), Offset(left + boxSize, top + len), paint);
    canvas.drawLine(Offset(left, top + boxSize), Offset(left + len, top + boxSize), paint);
    canvas.drawLine(Offset(left, top + boxSize), Offset(left, top + boxSize - len), paint);
    canvas.drawLine(Offset(left + boxSize, top + boxSize), Offset(left + boxSize - len, top + boxSize), paint);
    canvas.drawLine(Offset(left + boxSize, top + boxSize), Offset(left + boxSize, top + boxSize - len), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}