import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'login_screen.dart';
import 'package:camera/camera.dart';

class SignupScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const SignupScreen({super.key, required this.cameras});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _uniNameController   = TextEditingController();
  final _adminNameController = TextEditingController();
  final _emailController     = TextEditingController();
  final _phoneController     = TextEditingController();

  File?   _logoFile;
  bool    _isLoading  = false;
  bool    _submitted  = false;
  String? _institutionId;
  String? _errorMessage;

  final String _apiUrl =
      "https://dazzling-intuition-production-297b.up.railway.app/register-institution";

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (image != null) setState(() => _logoFile = File(image.path));
  }

  Future<void> _register() async {
    final uniName   = _uniNameController.text.trim();
    final adminName = _adminNameController.text.trim();
    final email     = _emailController.text.trim();
    final phone     = _phoneController.text.trim();

    if (uniName.isEmpty || adminName.isEmpty || email.isEmpty || phone.isEmpty) {
      setState(() => _errorMessage = "Please fill in all required fields.");
      return;
    }

    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final request = http.MultipartRequest('POST', Uri.parse(_apiUrl));
      request.fields['university_name'] = uniName;
      request.fields['admin_full_name'] = adminName;
      request.fields['admin_email']     = email;
      request.fields['phone']           = phone;

      if (_logoFile != null) {
        request.files.add(await http.MultipartFile.fromPath('logo', _logoFile!.path));
      }

      final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 30)),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          _submitted      = true;
          _institutionId  = data['institution_id'];
        });
      } else {
        setState(() => _errorMessage = data['detail'] ?? 'Registration failed.');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Connection failed. Check your internet.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _uniNameController.dispose();
    _adminNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.cyanAccent),
        title: const Text(
          "Register University",
          style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold),
        ),
      ),
      body: _submitted ? _buildSuccess() : _buildForm(),
    );
  }

  // ── Success screen ─────────────────────────────────────────────────────
  Widget _buildSuccess() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.green, width: 2),
              ),
              child: const Icon(Icons.check, color: Colors.green, size: 40),
            ),
            const SizedBox(height: 28),
            const Text(
              "Registration Successful!",
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              "Institution ID: $_institutionId",
              style: const TextStyle(
                color: Colors.cyanAccent,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[800]!),
              ),
              child: const Text(
                "Check your email to verify your account and activate your 30-day free trial.\n\nOnce verified, log in with your email and password.",
                style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.6),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                    builder: (_) => LoginScreen(cameras: widget.cameras)),
              ),
              child: const Text("Go to Login",
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Form ───────────────────────────────────────────────────────────────
  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Trial banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.cyanAccent.withOpacity(0.2)),
            ),
            child: const Row(
              children: [
                Text("🎉 ", style: TextStyle(fontSize: 18)),
                Expanded(
                  child: Text(
                    "30-day free trial · Full access · No credit card needed",
                    style: TextStyle(color: Colors.cyanAccent, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          _buildField(_uniNameController,   "University Name",  "e.g. Kampala International University", Icons.school),
          const SizedBox(height: 16),
          _buildField(_adminNameController, "Admin Full Name",  "e.g. Dr. John Mukasa",                  Icons.person),
          const SizedBox(height: 16),
          _buildField(_emailController,     "Admin Email",      "admin@university.ac.ug",                Icons.email,   TextInputType.emailAddress),
          const SizedBox(height: 16),
          _buildField(_phoneController,     "Phone Number",     "+256 700 000 000",                      Icons.phone,   TextInputType.phone),
          const SizedBox(height: 16),

          // Logo picker
          GestureDetector(
            onTap: _pickLogo,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _logoFile != null ? Colors.cyanAccent : Colors.grey[700]!,
                  style: BorderStyle.solid,
                ),
              ),
              child: _logoFile != null
                  ? Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(_logoFile!, width: 50, height: 50, fit: BoxFit.cover),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Text("Logo selected — tap to change",
                              style: TextStyle(color: Colors.cyanAccent, fontSize: 13)),
                        ),
                      ],
                    )
                  : const Column(
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            color: Colors.grey, size: 32),
                        SizedBox(height: 8),
                        Text("University Logo (optional)",
                            style: TextStyle(color: Colors.grey, fontSize: 13)),
                        Text("Tap to upload from gallery",
                            style: TextStyle(color: Colors.grey, fontSize: 11)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 8),

          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Text(_errorMessage!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ),
          ],

          const SizedBox(height: 28),

          _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
              : ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _register,
                  child: const Text(
                    "CREATE INSTITUTION ACCOUNT",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),

          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                "Already have an account? Sign in",
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label,
    String hint,
    IconData icon, [
    TextInputType? keyboardType,
  ]) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.grey),
        hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.cyanAccent),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.grey),
          borderRadius: BorderRadius.circular(10),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.cyanAccent),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}