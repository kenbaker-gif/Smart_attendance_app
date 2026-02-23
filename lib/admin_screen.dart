import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;

class AdminScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const AdminScreen({super.key, required this.cameras});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  File? _selectedImage;
  bool _isUploading = false;
  List<Map<String, dynamic>> _students = [];
  bool _isLoading = true;

  final String registrationUrl = "https://lovely-imagination-production.up.railway.app/upload-student-face";

  @override
  void initState() {
    super.initState();
    _checkAccess();
    _loadStudents();
  }

  Future<void> _checkAccess() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) { _kickOut(); return; }

      final data = await Supabase.instance.client
          .from('profiles')
          .select('is_admin')
          .eq('id', user.id)
          .maybeSingle();

      if (data == null || data['is_admin'] != true) { _kickOut(); }
    } catch (e) { _kickOut(); }
  }

  void _kickOut() {
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Unauthorized Access"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _loadStudents() async {
    try {
      final data = await Supabase.instance.client
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

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 70, 
    );
    if (image != null) setState(() => _selectedImage = File(image.path));
  }

  Future<void> _registerStudent() async {
    final name = _nameController.text.trim();
    final id = _idController.text.trim();

    if (name.isEmpty || id.isEmpty || _selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Missing Data")));
      return;
    }

    setState(() => _isUploading = true);

    try {
      var request = http.MultipartRequest('POST', Uri.parse(registrationUrl));
      request.files.add(await http.MultipartFile.fromPath('file', _selectedImage!.path));
      request.fields['student_id'] = id;
      request.fields['student_name'] = name;

      var response = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 40)));

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Success!"), backgroundColor: Colors.green));
        _nameController.clear();
        _idController.clear();
        setState(() => _selectedImage = null);
        _loadStudents();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text("Admin Portal", style: TextStyle(color: Colors.orangeAccent)),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/stats'),
              icon: const Icon(Icons.bar_chart, color: Colors.cyanAccent),
              label: const Text("STATS", style: TextStyle(color: Colors.cyanAccent)),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.orangeAccent,
            labelColor: Colors.orangeAccent,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(icon: Icon(Icons.person_add), text: "Register"),
              Tab(icon: Icon(Icons.storage), text: "Database"),
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

  Widget _buildRegisterForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.orangeAccent.withOpacity(0.5)),
              ),
              child: _selectedImage == null
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt, color: Colors.orangeAccent, size: 50),
                        SizedBox(height: 10),
                        Text("TAP TO CAPTURE FACE", style: TextStyle(color: Colors.orangeAccent)),
                      ],
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Image.file(_selectedImage!, fit: BoxFit.cover),
                    ),
            ),
          ),
          const SizedBox(height: 30),
          _buildTextField(_nameController, "Full Name", Icons.badge),
          const SizedBox(height: 20),
          _buildTextField(_idController, "Student ID Number", Icons.numbers),
          const SizedBox(height: 40),
          _isUploading
              ? const CircularProgressIndicator(color: Colors.orangeAccent)
              : ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _registerStudent,
                  child: const Text("FINALIZE REGISTRATION", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        prefixIcon: Icon(icon, color: Colors.orangeAccent),
        enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.grey), borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.orangeAccent), borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildStudentList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Colors.orangeAccent));
    if (_students.isEmpty) return const Center(child: Text("No students registered.", style: TextStyle(color: Colors.grey)));

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _students.length,
      separatorBuilder: (_, __) => const Divider(color: Colors.grey),
      itemBuilder: (context, index) {
        final student = _students[index];
        final String studentId = student['id'].toString();
        final String imageUrl = "https://xrlsltunfgjxooyyrora.supabase.co/storage/v1/object/public/raw_faces/$studentId/1.jpg?t=${DateTime.now().millisecondsSinceEpoch}";

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.grey[800],
            backgroundImage: NetworkImage(imageUrl),
            child: const Icon(Icons.person, color: Colors.white24),
          ),
          title: Text(student['name'] ?? "No Name", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: Text("ID: $studentId", style: const TextStyle(color: Colors.grey)),
          trailing: const Icon(Icons.check_circle, color: Colors.green, size: 20),
        );
      },
    );
  }
}