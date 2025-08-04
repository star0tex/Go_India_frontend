import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'real_home_page.dart';

class HomePage extends StatefulWidget {
  final String phone;
  const HomePage({super.key, required this.phone});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _nameController = TextEditingController();
  String _selectedGender = 'Male';
  final List<String> _genders = ['Male', 'Female', 'Other'];
  bool _isSaving = false;

  Future<void> _saveDetails() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    if (_nameController.text.trim().isEmpty) {
      _showToast('Please enter your name', isError: true);
      setState(() => _isSaving = false);
      return;
    }

    const String apiUrl = 'http://192.168.210.12:5002/api/user';

    try {
      final payload = {
        'phone': widget.phone,
        'name': _nameController.text.trim(),
        'gender': _selectedGender,
      };

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      final successCodes = {200, 201, 400};
      if (successCodes.contains(response.statusCode)) {
        final msg = jsonDecode(response.body)['message'] ?? 'Profile saved.';
        _showToast(msg);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RealHomePage()),
        );
      } else {
        _showToast('Failed: ${response.body}', isError: true);
      }
    } catch (e) {
      _showToast('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showToast(String text, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Center(child: Text(text, textAlign: TextAlign.center)),
        backgroundColor: isError ? Colors.red[600] : Colors.transparent,
        elevation: isError ? 2 : 0,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),

              // Title
              Text(
                'Complete Your Profile',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[900],
                ),
              ),

              const SizedBox(height: 8),
              Text(
                'We’re almost there! 🚀',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[700],
                ),
              ),

              const SizedBox(height: 40),

              // Input Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 8,
                        offset: Offset(0, 4))
                  ],
                ),
                child: Column(
                  children: [
                    _inputBox(_nameController, 'Enter Your Name'),
                    const SizedBox(height: 20),
                    _dropdownBox(),
                    const SizedBox(height: 30),
                    _saveButton(),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Footer Message
              Text(
                "It’s a pleasure to have you, Rider!",
                style: GoogleFonts.dancingScript(
                  fontSize: screenWidth * 0.055,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputBox(TextEditingController controller, String hintText) {
    return TextField(
      controller: controller,
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        hintText: hintText,
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.black12),
        ),
      ),
    );
  }

  Widget _dropdownBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedGender,
          isExpanded: true,
          items: _genders
              .map((g) => DropdownMenuItem(value: g, child: Text(g)))
              .toList(),
          onChanged: (v) => setState(() => _selectedGender = v!),
        ),
      ),
    );
  }

  Widget _saveButton() {
    return GestureDetector(
      onTap: _saveDetails,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(98, 205, 255, 1),
          borderRadius: BorderRadius.circular(40),
        ),
        child: Center(
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Save',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}
