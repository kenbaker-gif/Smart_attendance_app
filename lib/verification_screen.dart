import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';
import 'config.dart';

class VerificationScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final String institutionId;
  // Changed: accepts full list of {id, name} maps instead of a single nullable id
  final List<Map<String, dynamic>> courseUnits;

  const VerificationScreen({
    super.key,
    required this.cameras,
    required this.institutionId,
    this.courseUnits = const [],
  });

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
  bool _isAdmin = false;

  // Session-level selected unit — persists across scans until coordinator changes it
  Map<String, dynamic>? _selectedCourseUnit;

  @override
  void initState() {
    super.initState();
    _initCamera(_selectedCameraIndex);
    _fetchAdminStatus();

    // Auto-select if only one unit assigned
    if (widget.courseUnits.length == 1) {
      _selectedCourseUnit = widget.courseUnits.first;
    }
  }

  Future<void> _fetchAdminStatus() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final result = await Supabase.instance.client
        .from('profiles')
        .select('is_admin')
        .eq('id', user.id)
        .limit(1);
    final data = result.isNotEmpty ? result.first : null;
    if (mounted) {
      setState(() => _isAdmin = data != null && data['is_admin'] == true);
    }
  }

Future<void> _manualLogout() async {
  final session = Supabase.instance.client.auth.currentSession;
  if (session != null) {
    try {
      await http.post(
        Uri.parse('https://faceattend.app/auth/log-logout'),
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'X-Source': 'flutter_app',
        },
      );
    } catch (e) {
      debugPrint('[logout] log-logout error: $e');
    }
  }
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
    final splitted = filePath.substring(0, lastIndex);
    final outPath = "${splitted}_out.jpg";
    var result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path, outPath,
      quality: 40, minWidth: 400, minHeight: 400,
    );
    return File(result!.path);
  }

  // Shows bottom sheet and returns selected unit. Returns null if dismissed.
  Future<Map<String, dynamic>?> _pickCourseUnit() async {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Which class are you taking attendance for?",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ...widget.courseUnits.map((unit) {
                return ListTile(
                  onTap: () => Navigator.of(ctx).pop(unit),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  tileColor: Colors.white.withOpacity(0.05),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Text(
                    unit['name'] ?? unit['id'],
                    style: const TextStyle(color: Colors.cyanAccent, fontSize: 15),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios,
                      color: Colors.white38, size: 14),
                );
              }).toList(),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _scanFace() async {
    if (!_isCameraInitialized || _isScanning) return;

    // If multiple units and none selected yet, force a pick first
    if (widget.courseUnits.length > 1 && _selectedCourseUnit == null) {
      final picked = await _pickCourseUnit();
      if (picked == null) return; // dismissed, do nothing
      setState(() => _selectedCourseUnit = picked);
    }

    // If no units assigned at all, warn and bail
    if (widget.courseUnits.isEmpty) {
      _showError("No course units assigned. Contact your admin.");
      return;
    }

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

      final session = Supabase.instance.client.auth.currentSession;
      final token = session?.accessToken ?? '';

      var request = http.MultipartRequest(
        'POST',
        Uri.parse(AppConfig.faceVerifyUrl),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.fields['institution_id'] = widget.institutionId;

      // Always send the explicitly selected unit — no more relying on server cu[0]
      if (_selectedCourseUnit != null) {
        request.fields['course_unit_id'] = _selectedCourseUnit!['id'];
      }

      request.files.add(
          await http.MultipartFile.fromPath('file', fileToSend.path));

      var response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 25)),
      );

      wakeUpTimer.cancel();

      if (response.statusCode == 200) {
        var json = jsonDecode(response.body);
        if (mounted) setState(() => _result = json);
      } else if (response.statusCode == 401) {
        _showError("Session expired. Trying to refresh session...");
        final refreshed = await _tryRefreshSession();
        if (!refreshed) {
          _showError("Session could not be refreshed. Please log in again.");
          await Supabase.instance.client.auth.signOut();
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (_) => LoginScreen(cameras: widget.cameras)),
              (route) => false,
            );
          }
        }
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

  Future<bool> _tryRefreshSession() async {
    try {
      final result = await Supabase.instance.client.auth.refreshSession();
      return result.session != null;
    } catch (e) {
      debugPrint('Refresh session failed: $e');
      return false;
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
        body: Center(
            child: CircularProgressIndicator(color: Colors.cyanAccent)),
      );
    }

    bool isMatch = false;
    bool isSpoof = false;
    String identity = "Unknown";
    if (_result != null) {
      if (_result!['match'] == true || _result!['status'] == 'success')
        isMatch = true;
      if (_result!['status'] == 'spoof') isSpoof = true;
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
                FloatingActionButton.small(
                  heroTag: "btn_logout",
                  backgroundColor: Colors.red.withOpacity(0.8),
                  onPressed: _manualLogout,
                  child: const Icon(Icons.logout, color: Colors.white),
                ),
                if (_isAdmin)
                  Row(
                    children: [
                      FloatingActionButton.small(
                        heroTag: "btn_admin",
                        backgroundColor: Colors.cyanAccent.withOpacity(0.85),
                        onPressed: () =>
                            Navigator.of(context).pushNamed('/admin'),
                        child: const Icon(Icons.admin_panel_settings,
                            color: Colors.black),
                      ),
                    ],
                  ),
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

          // 4. ACTIVE CLASS CHIP — shown when a unit is selected and multiple exist
          if (_selectedCourseUnit != null && widget.courseUnits.length > 1)
            Positioned(
              top: 110, left: 0, right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () async {
                    final picked = await _pickCourseUnit();
                    if (picked != null) {
                      setState(() => _selectedCourseUnit = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withOpacity(0.15),
                      border: Border.all(color: Colors.cyanAccent, width: 1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.class_outlined,
                            color: Colors.cyanAccent, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          _selectedCourseUnit!['name'] ??
                              _selectedCourseUnit!['id'],
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.swap_horiz,
                            color: Colors.cyanAccent, size: 14),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 5. RESULTS DISPLAY
          if (_result != null)
            Positioned(
              top: _selectedCourseUnit != null && widget.courseUnits.length > 1
                  ? 150
                  : 120,
              left: 20, right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  border: Border.all(
                    color: isMatch
                        ? Colors.greenAccent
                        : isSpoof
                            ? Colors.orangeAccent
                            : Colors.redAccent,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isMatch
                      ? "MATCH: $identity"
                      : isSpoof
                          ? "⚠️ SPOOF DETECTED"
                          : "NO MATCH FOUND",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isMatch
                        ? Colors.greenAccent
                        : isSpoof
                            ? Colors.orangeAccent
                            : Colors.redAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          // 6. BOTTOM UI
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
                    color: Colors.white38,
                    fontSize: 10,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _scanFace,
                  child: Container(
                    height: 85, width: 85,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: Colors.cyanAccent, width: 3),
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
                          ? const CircularProgressIndicator(
                              color: Colors.cyanAccent)
                          : const Icon(Icons.camera_alt_outlined,
                              color: Colors.cyanAccent, size: 40),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_showFlash)
            Container(color: Colors.white.withOpacity(0.5)),
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