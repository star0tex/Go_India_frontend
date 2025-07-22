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

  const String apiUrl = 'http://192.168.103.12:5002/api/user';

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
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFFFEE7C2),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background cartoon image
                Image.asset(
                  'assets/images/cartoon_bg.png',
                  width: screenWidth,
                  height: screenHeight * 0.85,
                  fit: BoxFit.cover,
                ),

                // Input Fields Positioned Over Chest
                Positioned(
                  top: screenHeight * 0.37,
                  child: Column(
                    children: [
                      _inputBox(_nameController, 'Enter Your Name'),
                      SizedBox(height: screenHeight * 0.015),
                      _dropdownBox(),
                      SizedBox(height: screenHeight * 0.025),
                      _saveButton(),
                    ],
                  ),
                ),

                // Responsive Welcome Text
                Positioned(
                  bottom: screenHeight * 0.015,
                  left: screenWidth * 0.02,
                  child: Text(
                    "It’s a pleasure to have you, Rider!",
                    style: GoogleFonts.dancingScript(
                      fontSize: screenWidth * 0.055, // Scales with width
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _inputBox(TextEditingController controller, String hintText) {
    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          hintText: hintText,
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _dropdownBox() {
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedGender,
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
        width: 180,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(40),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
        child: Center(
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.black,
                  ),
                )
              : const Text(
                  'Save',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
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
