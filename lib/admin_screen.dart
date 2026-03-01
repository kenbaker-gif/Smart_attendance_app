import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;

// ── 4 capture steps ────────────────────────────────────────────────────────
const List<Map<String, dynamic>> _captureSteps = [
  {"label": "FRONT",      "instruction": "Look straight at the camera",          "icon": Icons.face},
  {"label": "LEFT SIDE",  "instruction": "Turn your head slightly to the left",  "icon": Icons.arrow_back},
  {"label": "RIGHT SIDE", "instruction": "Turn your head slightly to the right", "icon": Icons.arrow_forward},
  {"label": "LOOK UP",    "instruction": "Tilt your head slightly upward",        "icon": Icons.arrow_upward},
];

class AdminScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const AdminScreen({super.key, required this.cameras});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _nameController = TextEditingController();
  final _idController   = TextEditingController();

  // Institution context — fetched once on load
  String? _institutionId;   // e.g. 'MUK' or 'NKU'
  String? _institutionName; // e.g. 'Makerere University'

  // 4 image slots
  final List<File?> _capturedImages = [null, null, null, null];
  int _currentStep = 0;

  bool _isUploading = false;
  List<Map<String, dynamic>> _students = [];
  bool _isLoading = true;

  final String registrationUrl =
      "https://lovely-imagination-production.up.railway.app/upload-student-face";

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  // ── Auth + institution fetch ───────────────────────────────────────────
  Future<void> _checkAccess() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) { _kickOut(); return; }

      final data = await Supabase.instance.client
          .from('profiles')
          .select('is_admin, institution_id, institutions(name)')
          .eq('id', user.id)
          .maybeSingle();

      if (data == null || data['is_admin'] != true) {
        _kickOut();
        return;
      }

      if (mounted) {
        setState(() {
          _institutionId   = data['institution_id'];
          _institutionName = data['institutions']?['name'] ?? _institutionId;
        });
      }

      await _loadStudents();
    } catch (e) {
      _kickOut();
    }
  }

  void _kickOut() {
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Unauthorized Access"), backgroundColor: Colors.red),
      );
    }
  }

  // ── Load students scoped to this institution ───────────────────────────
  Future<void> _loadStudents() async {
    try {
      // .eq() must come before .order() in this Supabase version
      final data = _institutionId != null
          ? await Supabase.instance.client
              .from('students')
              .select()
              .eq('institution_id', _institutionId!)
              .order('created_at', ascending: false)
          : await Supabase.instance.client
              .from('students')
              .select()
              .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _students = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Capture one image for a step ──────────────────────────────────────
  Future<void> _captureStep(int stepIndex) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 70,
    );
    if (image == null) return;

    setState(() {
      _capturedImages[stepIndex] = File(image.path);
      final nextEmpty = _capturedImages.indexWhere((f) => f == null);
      _currentStep = nextEmpty == -1 ? stepIndex : nextEmpty;
    });
  }

  void _retakeStep(int stepIndex) {
    setState(() {
      _capturedImages[stepIndex] = null;
      _currentStep = stepIndex;
    });
    _captureStep(stepIndex);
  }

  // ── Register student ───────────────────────────────────────────────────
  Future<void> _registerStudent() async {
    final name = _nameController.text.trim();
    final rawId = _idController.text.trim();

    if (name.isEmpty || rawId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter Full Name and Student ID.")),
      );
      return;
    }

    if (_capturedImages.where((f) => f != null).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Capture at least one photo before registering.")),
      );
      return;
    }

    // Use student ID as-is — institution_id column separates institutions
    final prefixedId = rawId;

    setState(() => _isUploading = true);

    int successCount = 0;
    int failCount    = 0;

    for (int i = 0; i < _capturedImages.length; i++) {
      final file = _capturedImages[i];
      if (file == null) continue;

      try {
        var request = http.MultipartRequest('POST', Uri.parse(registrationUrl));
        request.files.add(await http.MultipartFile.fromPath(
          'file',
          file.path,
          filename: '${i + 1}.jpg', // saves as 1.jpg, 2.jpg, 3.jpg, 4.jpg
        ));
        request.fields['student_id']     = prefixedId;
        request.fields['name']           = name;
        request.fields['institution_id'] = _institutionId ?? '';

        final response = await http.Response.fromStream(
          await request.send().timeout(const Duration(seconds: 40)),
        );

        if (response.statusCode == 200) {
          successCount++;
        } else {
          failCount++;
          debugPrint("Upload failed for image ${i + 1}: ${response.body}");
        }
      } catch (e) {
        failCount++;
        debugPrint("Upload error for image ${i + 1}: $e");
      }
    }

    if (mounted) {
      setState(() => _isUploading = false);

      if (successCount > 0) {
        final msg = failCount == 0
            ? "✅ Registered $successCount/4 images successfully!"
            : "⚠️ $successCount uploaded, $failCount failed (skipped).";

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: failCount == 0 ? Colors.green : Colors.orange,
          ),
        );

        _nameController.clear();
        _idController.clear();
        setState(() {
          for (int i = 0; i < 4; i++) _capturedImages[i] = null;
          _currentStep = 0;
        });
        _loadStudents();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("All uploads failed. Check your connection."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Admin Portal",
                  style: TextStyle(color: Colors.orangeAccent)),
              if (_institutionName != null)
                Text(
                  _institutionName!,
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/stats'),
              icon: const Icon(Icons.bar_chart, color: Colors.cyanAccent),
              label:
                  const Text("STATS", style: TextStyle(color: Colors.cyanAccent)),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.orangeAccent,
            labelColor: Colors.orangeAccent,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(icon: Icon(Icons.person_add), text: "Register"),
              Tab(icon: Icon(Icons.storage),    text: "Database"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildRegisterForm(),
            _buildStudentList(),
          ],
        ),
      ),
    );
  }

  // ── Register form ──────────────────────────────────────────────────────
  Widget _buildRegisterForm() {
    final int capturedCount = _capturedImages.where((f) => f != null).length;
    final bool allCaptured  = capturedCount == 4;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Institution badge
          if (_institutionId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orangeAccent.withOpacity(0.4)),
              ),
              child: Text(
                "Institution: $_institutionName ($_institutionId)",
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),

          // Progress bar
          Row(
            children: List.generate(4, (i) {
              final done   = _capturedImages[i] != null;
              final active = i == _currentStep && !done;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: done
                        ? Colors.green
                        : active
                            ? Colors.orangeAccent
                            : Colors.grey[800],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text("$capturedCount / 4 photos captured",
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 20),

          // 4 capture tiles
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            itemCount: 4,
            itemBuilder: (context, i) => _buildCaptureTile(i),
          ),

          const SizedBox(height: 28),

          // ID field — shows prefixed preview
          _buildTextField(_nameController, "Full Name", Icons.badge),
          const SizedBox(height: 16),
          TextField(
            controller: _idController,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: "Student ID Number",
              labelStyle: const TextStyle(color: Colors.grey),
              prefixIcon:
                  const Icon(Icons.numbers, color: Colors.orangeAccent),
              // ✅ Show the prefixed ID as a hint
              helperText: _idController.text.isNotEmpty && _institutionId != null
                  ? "Will be saved as: $_institutionId${_idController.text}"
                  : "e.g. 2400102415 → saved as ${_institutionId ?? ''}2400102415",
              helperStyle:
                  const TextStyle(color: Colors.grey, fontSize: 11),
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.grey),
                borderRadius: BorderRadius.circular(10),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.orangeAccent),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 32),

          // Register button
          _isUploading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: Colors.orangeAccent))
              : ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        allCaptured ? Colors.orangeAccent : Colors.grey[700],
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _registerStudent,
                  child: Text(
                    allCaptured
                        ? "FINALIZE REGISTRATION"
                        : "CAPTURE ALL 4 PHOTOS TO REGISTER",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildCaptureTile(int i) {
    final step    = _captureSteps[i];
    final file    = _capturedImages[i];
    final isDone  = file != null;
    final isActive = i == _currentStep && !isDone;

    return GestureDetector(
      onTap: isDone ? () => _retakeStep(i) : () => _captureStep(i),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDone
                ? Colors.green
                : isActive
                    ? Colors.orangeAccent
                    : Colors.grey[700]!,
            width: isActive ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: isDone
                  ? Image.file(file!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity)
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(step['icon'] as IconData,
                              color: isActive
                                  ? Colors.orangeAccent
                                  : Colors.grey,
                              size: 36),
                          const SizedBox(height: 8),
                          Text(
                            step['label'] as String,
                            style: TextStyle(
                              color: isActive
                                  ? Colors.orangeAccent
                                  : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              step['instruction'] as String,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            if (isDone)
              Positioned(
                top: 6, right: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                      color: Colors.green, shape: BoxShape.circle),
                  child: const Icon(Icons.check,
                      color: Colors.white, size: 14),
                ),
              ),
            if (isDone)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(12)),
                  ),
                  child: Text(
                    "TAP TO RETAKE  •  ${step['label']}",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 9),
                  ),
                ),
              ),
            if (isActive)
              const Positioned(
                bottom: 6, left: 0, right: 0,
                child: Text(
                  "TAP TO CAPTURE",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        prefixIcon: Icon(icon, color: Colors.orangeAccent),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.grey),
          borderRadius: BorderRadius.circular(10),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.orangeAccent),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  // ── Student list ───────────────────────────────────────────────────────
  Widget _buildStudentList() {
    if (_isLoading)
      return const Center(
          child: CircularProgressIndicator(color: Colors.orangeAccent));
    if (_students.isEmpty)
      return const Center(
          child: Text("No students registered.",
              style: TextStyle(color: Colors.grey)));

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _students.length,
      separatorBuilder: (_, __) => const Divider(color: Colors.grey),
      itemBuilder: (context, index) {
        final student   = _students[index];
        final studentId = student['id'].toString();
        final imageUrl  =
            "https://xrlsltunfgjxooyyrora.supabase.co/storage/v1/object/public/raw_faces/$studentId/1.jpg?t=${DateTime.now().millisecondsSinceEpoch}";

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.grey[800],
            backgroundImage: NetworkImage(imageUrl),
            onBackgroundImageError: (_, __) {},
            child: const Icon(Icons.person, color: Colors.white24),
          ),
          title: Text(
            student['name'] ?? "No Name",
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: Text("ID: $studentId",
              style: const TextStyle(color: Colors.grey)),
          trailing: const Icon(Icons.check_circle,
              color: Colors.green, size: 20),
        );
      },
    );
  }
}