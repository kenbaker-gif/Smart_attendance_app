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

class _VerificationScreenState extends State<VerificationScreen> {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  bool _isScanning = false;
  bool _showFlash = false;
  bool _serverWakingUp = false;
  int _selectedCameraIndex = 0;
  Map<String, dynamic>? _result;

  // ✅ Admin state
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _initCamera(_selectedCameraIndex);
    _fetchAdminStatus(); // ✅ Check admin role on load
  }

  // ✅ Fetch admin status once when screen loads
  Future<void> _fetchAdminStatus() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final data = await Supabase.instance.client
        .from('profiles')
        .select('is_admin')
        .eq('id', user.id)
        .maybeSingle();

    if (mounted) {
      setState(() => _isAdmin = data != null && data['is_admin'] == true);
    }
  }

  // 🔴 HARD LOGOUT
  Future<void> _manualLogout() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(cameras: widget.cameras)),
      (route) => false,
    );
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
      if (!mounted) return;
      setState(() => _isCameraInitialized = true);
    } catch (e) {
      debugPrint("Camera Init Error: $e");
    }
  }

  void _toggleCamera() {
    if (widget.cameras.length < 2) return;
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
    if (!_isCameraInitialized || _isScanning) return;

    setState(() {
      _isScanning = true;
      _result = null;
      _showFlash = true;
      _serverWakingUp = false;
    });

    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) setState(() => _showFlash = false);
    });

    Timer? wakeUpTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isScanning) setState(() => _serverWakingUp = true);
    });

    try {
      final XFile image = await _controller!.takePicture();
      await _controller!.pausePreview();
      File fileToSend = await compressFile(File(image.path));

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('https://smartattendancemvp-production.up.railway.app/verify'),
      );
      request.files.add(await http.MultipartFile.fromPath('file', fileToSend.path));

      var response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 25)),
      );

      wakeUpTimer.cancel();

      if (response.statusCode == 200) {
        var json = jsonDecode(response.body);
        if (mounted) setState(() => _result = json);
      } else {
        _showError("Server Error (${response.statusCode})");
      }
    } catch (e) {
      wakeUpTimer.cancel();
      _showError("Connection failed. Check your internet.");
    } finally {
      if (mounted) {
        if (_controller != null) await _controller!.resumePreview();
        setState(() {
          _isScanning = false;
          _serverWakingUp = false;
        });
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
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
      );
    }

    bool isMatch = false;
    String identity = "Unknown";
    if (_result != null) {
      if (_result!['match'] == true || _result!['status'] == 'success') isMatch = true;
      if (_result!['name'] != null) identity = _result!['name'].toString();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. CAMERA FEED
          Center(child: CameraPreview(_controller!)),

          // 2. SCANNER OVERLAY
          CustomPaint(size: Size.infinite, painter: ScannerOverlayPainter()),

          // 3. TOP ACTION BAR
          Positioned(
            top: 50, left: 20, right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Logout button (always visible)
                FloatingActionButton.small(
                  heroTag: "btn_logout",
                  backgroundColor: Colors.red.withOpacity(0.8),
                  onPressed: _manualLogout,
                  child: const Icon(Icons.logout, color: Colors.white),
                ),

                // ✅ Admin buttons — only shown if user is admin
                if (_isAdmin)
                  Row(
                    children: [
                      // Admin Screen button
                      FloatingActionButton.small(
                        heroTag: "btn_admin",
                        backgroundColor: Colors.cyanAccent.withOpacity(0.85),
                        onPressed: () => Navigator.of(context).pushNamed('/admin'),
                        child: const Icon(Icons.admin_panel_settings, color: Colors.black),
                      ),
                      const SizedBox(width: 10),
                      // Stats Screen button
                      FloatingActionButton.small(
                        heroTag: "btn_stats",
                        backgroundColor: Colors.cyanAccent.withOpacity(0.85),
                        onPressed: () => Navigator.of(context).pushNamed('/stats'),
                        child: const Icon(Icons.bar_chart, color: Colors.black),
                      ),
                    ],
                  ),

                // Camera switch button (always visible if multiple cameras)
                if (widget.cameras.length > 1)
                  GestureDetector(
                    onTap: _toggleCamera,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.cameraswitch_rounded,
                          color: Colors.cyanAccent, size: 30),
                    ),
                  ),
              ],
            ),
          ),

          // 4. RESULTS DISPLAY
          if (_result != null)
            Positioned(
              top: 120, left: 20, right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  border: Border.all(
                    color: isMatch ? Colors.greenAccent : Colors.redAccent,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isMatch ? "MATCH: $identity" : "NO MATCH FOUND",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isMatch ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          // 5. BOTTOM UI (BUTTON & STATUS)
          Positioned(
            bottom: 60, left: 0, right: 0,
            child: Column(
              children: [
                if (_serverWakingUp)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 15),
                    child: Text(
                      "☕ Server is waking up... please wait",
                      style: TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Text(
                  _isScanning ? "ANALYZING BIOMETRICS..." : "READY TO SCAN",
                  style: const TextStyle(
                    color: Colors.white38, fontSize: 10, letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _scanFace,
                  child: Container(
                    height: 85, width: 85,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.cyanAccent, width: 3),
                      boxShadow: [
                        if (_isScanning)
                          BoxShadow(
                            color: Colors.cyanAccent.withOpacity(0.4),
                            blurRadius: 20,
                          ),
                      ],
                    ),
                    child: Center(
                      child: _isScanning
                          ? const CircularProgressIndicator(color: Colors.cyanAccent)
                          : const Icon(Icons.camera_alt_outlined,
                              color: Colors.cyanAccent, size: 40),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_showFlash) Container(color: Colors.white.withOpacity(0.5)),
        ],
      ),
    );
  }
}

class ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

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