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
  final List<Map<String, dynamic>> courseUnits;

  // ── New session params ─────────────────────────────────────────────────
  final String? sessionId;
  final String? lecturerName;
  final String? lecturerId;

  const VerificationScreen({
    super.key,
    required this.cameras,
    required this.institutionId,
    this.courseUnits = const [],
    this.sessionId,
    this.lecturerName,
    this.lecturerId,
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

  // Session-level selected unit — persists across scans
  Map<String, dynamic>? _selectedCourseUnit;

  // ── Session state ──────────────────────────────────────────────────────
  bool _isEndingSession = false;
  bool _sessionEnded = false;
  bool _isConfirming = false;
  bool _sessionConfirmed = false;
  int _scannedCount = 0;

  @override
  void initState() {
    super.initState();
    _initCamera(_selectedCameraIndex);
    _fetchAdminStatus();

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
      _selectedCameraIndex =
          (_selectedCameraIndex + 1) % widget.cameras.length;
    });
    _initCamera(_selectedCameraIndex);
  }

  Future<File> compressFile(File file) async {
    final filePath = file.absolute.path;
    // Safely compute an output path next to the original file. If the
    // original filename doesn't contain an extension, append _out.jpg.
    final dot = filePath.lastIndexOf('.');
    final base = dot == -1 ? filePath : filePath.substring(0, dot);
    final outPath = '${base}_out.jpg';
    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      outPath,
      quality: 40,
      minWidth: 400,
      minHeight: 400,
    );
    if (result == null) return file; // fallback to original file on failure
    return File(result.path);
  }

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
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Text(
                    unit['name'] ?? unit['id'],
                    style: const TextStyle(
                        color: Colors.cyanAccent, fontSize: 15),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios,
                      color: Colors.white38, size: 14),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ── End session ────────────────────────────────────────────────────────
  Future<void> _endSession() async {
    if (widget.sessionId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0f0f1c),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('End Session',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          '$_scannedCount student${_scannedCount == 1 ? '' : 's'} scanned.\n\nEnd this session? The lecturer will need to confirm.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('End Session',
                style: TextStyle(color: Colors.cyanAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isEndingSession = true);

    try {
      await Supabase.instance.client
          .from('sessions')
          .update({
            'status': 'completed',
            'ended_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', widget.sessionId!);

      if (mounted) {
        setState(() {
          _sessionEnded = true;
          _isEndingSession = false;
        });
      }
    } catch (e) {
      debugPrint('_endSession error: $e');
      if (mounted) {
        setState(() => _isEndingSession = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to end session: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  // ── Lecturer confirmation ──────────────────────────────────────────────
  Future<void> _confirmSession() async {
    if (widget.sessionId == null) return;

    // Ask for lecturer PIN / hand-off confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0f0f1c),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Lecturer Confirmation',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hand the phone to ${widget.lecturerName ?? 'the lecturer'}.',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              'By tapping Confirm, the lecturer acknowledges they taught this session.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm Session Taught',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isConfirming = true);

    try {
      await Supabase.instance.client
          .from('sessions')
          .update({
            'status': 'confirmed',
            'lecturer_confirmed': true,
            'confirmed_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', widget.sessionId!);

      if (mounted) {
        setState(() {
          _sessionConfirmed = true;
          _isConfirming = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Session confirmed by lecturer.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('_confirmSession error: $e');
      if (mounted) {
        setState(() => _isConfirming = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to confirm session: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  // ── Scan face ──────────────────────────────────────────────────────────
  Future<void> _scanFace() async {
    if (!_isCameraInitialized || _isScanning) return;

    // Block scanning if session already ended
    if (_sessionEnded) {
      _showError("Session has ended. Start a new session to continue.");
      return;
    }

    if (widget.courseUnits.length > 1 && _selectedCourseUnit == null) {
      final picked = await _pickCourseUnit();
      if (picked == null) return;
      setState(() => _selectedCourseUnit = picked);
    }

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

      if (_selectedCourseUnit != null) {
        request.fields['course_unit_id'] = _selectedCourseUnit!['id'];
      }

      // ── Send session_id with every scan ────────────────────────────────
      if (widget.sessionId != null) {
        request.fields['session_id'] = widget.sessionId!;
      }

      request.files
          .add(await http.MultipartFile.fromPath('file', fileToSend.path));

      var response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 25)),
      );

      wakeUpTimer.cancel();

      if (response.statusCode == 200) {
        var json = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _result = json;
            // Count successful matches
            if (json['match'] == true || json['status'] == 'success') {
              _scannedCount++;
            }
          });
        }
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

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body:
            Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
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

    // ── Session confirmed screen ───────────────────────────────────────
    if (_sessionConfirmed) {
      return _SessionDoneScreen(
        scannedCount: _scannedCount,
        lecturerName: widget.lecturerName,
        cameras: widget.cameras,
        institutionId: widget.institutionId,
        courseUnits: widget.courseUnits,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. CAMERA FEED — dimmed when session ended
          Opacity(
            opacity: _sessionEnded ? 0.3 : 1.0,
            child: Center(child: CameraPreview(_controller!)),
          ),

          // 2. SCANNER OVERLAY
          if (!_sessionEnded)
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
                  FloatingActionButton.small(
                    heroTag: "btn_admin",
                    backgroundColor: Colors.cyanAccent.withOpacity(0.85),
                    onPressed: () => Navigator.of(context).pushNamed('/admin'),
                    child: const Icon(Icons.admin_panel_settings,
                        color: Colors.black),
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

          // 4. SESSION INFO BAR — lecturer + unit
          if (widget.sessionId != null && !_sessionEnded)
            Positioned(
              top: 110, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_outline,
                          color: Colors.white54, size: 13),
                      const SizedBox(width: 5),
                      Text(
                        widget.lecturerName ?? 'Lecturer',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                      if (_selectedCourseUnit != null) ...[
                        const Text('  ·  ',
                            style: TextStyle(color: Colors.white38)),
                        const Icon(Icons.menu_book_outlined,
                            color: Colors.white54, size: 13),
                        const SizedBox(width: 5),
                        Text(
                          _selectedCourseUnit!['name'] ?? '',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

          // 5. ACTIVE CLASS CHIP — unit switcher (only if no session)
          if (_selectedCourseUnit != null &&
              widget.courseUnits.length > 1 &&
              widget.sessionId == null)
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
                      border:
                          Border.all(color: Colors.cyanAccent, width: 1),
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

          // 6. RESULTS DISPLAY
          if (_result != null && !_sessionEnded)
            Positioned(
              top: 150, left: 20, right: 20,
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

          // 7. SESSION ENDED OVERLAY
          if (_sessionEnded)
            Positioned.fill(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.cyanAccent.withOpacity(0.4)),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.check_circle_outline,
                                color: Colors.cyanAccent, size: 48),
                            const SizedBox(height: 16),
                            const Text(
                              'Session Ended',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$_scannedCount student${_scannedCount == 1 ? '' : 's'} verified',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 14),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Hand the phone to the lecturer to confirm the session.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 13),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.cyanAccent,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(10)),
                                ),
                                onPressed: _isConfirming
                                    ? null
                                    : _confirmSession,
                                child: _isConfirming
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                            color: Colors.black,
                                            strokeWidth: 2),
                                      )
                                    : const Text(
                                        'LECTURER: CONFIRM SESSION',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 8. BOTTOM UI — scan button + end session
          if (!_sessionEnded)
            Positioned(
              bottom: 40, left: 0, right: 0,
              child: Column(
                children: [
                  // Scanned counter
                  if (widget.sessionId != null && _scannedCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '$_scannedCount verified',
                        style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            letterSpacing: 1),
                      ),
                    ),

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
                    _isScanning
                        ? "ANALYZING BIOMETRICS..."
                        : "READY TO SCAN",
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Scan button
                  GestureDetector(
                    onTap: _scanFace,
                    child: Container(
                      height: 85,
                      width: 85,
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

                  // End session button — only if session is active
                  if (widget.sessionId != null) ...[
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: _isEndingSession ? null : _endSession,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.redAccent.withOpacity(0.5)),
                        ),
                        child: _isEndingSession
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.redAccent, strokeWidth: 2),
                              )
                            : const Text(
                                'END SESSION',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 11,
                                  letterSpacing: 1.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
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

// ── Session done screen ────────────────────────────────────────────────────

class _SessionDoneScreen extends StatelessWidget {
  final int scannedCount;
  final String? lecturerName;
  final List<CameraDescription> cameras;
  final String institutionId;
  final List<Map<String, dynamic>> courseUnits;

  const _SessionDoneScreen({
    required this.scannedCount,
    required this.lecturerName,
    required this.cameras,
    required this.institutionId,
    required this.courseUnits,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.green.withOpacity(0.1),
                  border: Border.all(color: Colors.greenAccent, width: 2),
                ),
                child: const Icon(Icons.verified,
                    color: Colors.greenAccent, size: 52),
              ),
              const SizedBox(height: 28),
              const Text(
                'Session Complete',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '$scannedCount student${scannedCount == 1 ? '' : 's'} verified',
                style:
                    const TextStyle(color: Colors.white54, fontSize: 15),
              ),
              if (lecturerName != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Confirmed by $lecturerName',
                  style: const TextStyle(
                      color: Colors.greenAccent, fontSize: 13),
                ),
              ],
              const SizedBox(height: 48),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  // Pop back to session gate for a new session
                  Navigator.of(context).pop();
                },
                child: const Text(
                  'START NEW SESSION',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Scanner overlay painter ────────────────────────────────────────────────

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
    canvas.drawLine(
        Offset(left + boxSize, top), Offset(left + boxSize - len, top), paint);
    canvas.drawLine(
        Offset(left + boxSize, top), Offset(left + boxSize, top + len), paint);
    canvas.drawLine(
        Offset(left, top + boxSize), Offset(left + len, top + boxSize), paint);
    canvas.drawLine(
        Offset(left, top + boxSize), Offset(left, top + boxSize - len), paint);
    canvas.drawLine(Offset(left + boxSize, top + boxSize),
        Offset(left + boxSize - len, top + boxSize), paint);
    canvas.drawLine(Offset(left + boxSize, top + boxSize),
        Offset(left + boxSize, top + boxSize - len), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}