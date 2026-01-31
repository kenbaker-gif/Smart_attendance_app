import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_image_compress/flutter_image_compress.dart'; // ✅ NEW IMPORT

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
  
  // Track which camera is currently selected
  int _selectedCameraIndex = 0; 

  File? _capturedImage;
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    _selectedCameraIndex = 0;
    _initCamera(_selectedCameraIndex);
  }

  Future<void> _initCamera(int cameraIndex) async {
    if (widget.cameras.isEmpty) return;

    if (_controller != null) {
      await _controller!.dispose();
    }

    // ✅ OPTIMIZATION: Use 'ResolutionPreset.medium' instead of 'high'
    // This makes the camera stream smoother and processing faster.
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

    setState(() {
      _isCameraInitialized = false; 
      _selectedCameraIndex = (_selectedCameraIndex + 1) % widget.cameras.length;
    });

    _initCamera(_selectedCameraIndex);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ✅ NEW HELPER: Compresses Image to <100KB
  Future<File> compressFile(File file) async {
    final filePath = file.absolute.path;
    final lastIndex = filePath.lastIndexOf(RegExp(r'.jp'));
    final splitted = filePath.substring(0, (lastIndex));
    final outPath = "${splitted}_out.jpg";
    
    // Compress logic
    var result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path, 
      outPath,
      quality: 60,      // Quality 60 is perfect for AI
      minWidth: 600,    // Resize to 600px width
      minHeight: 600,
    );

    return File(result!.path);
  }

  Future<void> _scanFace() async {
    if (!_isCameraInitialized || _isScanning) return;

    setState(() {
      _isScanning = true;
      _result = null;
      _showFlash = true;
    });

    // Screen flash (50ms)
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) setState(() => _showFlash = false);
    });

    try {
      // 1. CAPTURE
      final XFile image = await _controller!.takePicture();
      
      // 2. PAUSE PREVIEW (Visual feedback)
      await _controller!.pausePreview();

      File originalFile = File(image.path);

      // ✅ 3. COMPRESS (The Speed Boost 🚀)
      // We swap the huge original file for a tiny one
      File fileToSend = await compressFile(originalFile);

      // 4. SEND TO SERVER
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('https://smartattendancemvp-production.up.railway.app/verify')
      );
      
      // Use the compressed file here!
      request.files.add(await http.MultipartFile.fromPath('file', fileToSend.path));

      // 5. WAIT
      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 15), // Reduced timeout since upload is fast now
        onTimeout: () => throw Exception("Connection too slow."),
      );

      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        var json = jsonDecode(response.body);
        debugPrint("✅ SERVER RESPONSE: $json");
        
        if (mounted) {
          setState(() {
            _result = json;
          });
        }
      } else {
        _showError("Server Error (${response.statusCode})");
      }
    } catch (e) {
      debugPrint("Scan Error: $e");
      _showError("Error: $e");
    } finally {
      // 6. SAFER RESUME
      if (mounted) {
        try {
          if (_controller != null && _controller!.value.isInitialized) {
            await _controller!.resumePreview();
          }
        } catch (e) {
          debugPrint("Camera restart error: $e");
        }
        setState(() => _isScanning = false);
      }
    }
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
      if (_result!['match'] == true || _result!['status'] == 'success' || _result!['status'] == 'authorized') {
        isMatch = true;
      }
      if (_result!['name'] != null) {
        identity = _result!['name'].toString();
      } else if (_result!['identity'] != null) {
        identity = _result!['identity'].toString();
      } else if (_result!['user'] != null) {
        identity = _result!['user'].toString();
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera Feed
          Center(child: CameraPreview(_controller!)),

          // 2. Overlay
          CustomPaint(
            size: Size.infinite,
            painter: ScannerOverlayPainter(),
          ),

          // 3. Result Banner
          Positioned(
            top: 120,
            left: 20,
            right: 20,
            child: Column(
              children: [
                if (_result != null)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      border: Border.all(
                        color: isMatch ? Colors.greenAccent : Colors.redAccent,
                        width: 2
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isMatch ? "AUTHORIZED: $identity" : "ACCESS DENIED",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isMatch ? Colors.greenAccent : Colors.redAccent,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 4. TOP RIGHT: Camera Switch Button
          if (widget.cameras.length > 1)
            Positioned(
              top: 50,
              right: 20,
              child: GestureDetector(
                onTap: _toggleCamera,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.cyanAccent, width: 2),
                  ),
                  child: const Icon(
                    Icons.cameraswitch_rounded, 
                    color: Colors.cyanAccent, 
                    size: 30
                  ),
                ),
              ),
            ),

          // 5. Scan Button
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  _isScanning ? "ANALYZING BIOMETRICS..." : "READY TO SCAN",
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 16,
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _scanFace,
                  child: Container(
                    height: 80,
                    width: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.cyanAccent, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.cyanAccent.withOpacity(0.3),
                          blurRadius: 15,
                          spreadRadius: 2,
                        )
                      ],
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