import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'real_home_page.dart'; // Add this import

class HomePage extends StatefulWidget {
  final String phone;
  final String customerId;

  const HomePage({
    super.key,
    required this.phone,
    required this.customerId,
  });

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

    // Changed to use PUT method for updating existing user profile
    final String apiUrl = 'https://7668d252ef1d.ngrok-free.app/api/user/${widget.phone}';

    try {
      final payload = {
        'name': _nameController.text.trim(),
        'gender': _selectedGender,
      };

      final response = await http.put( // Changed from POST to PUT
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final msg = responseData['message'] ?? 'Profile saved.';
        _showToast(msg);
        
        if (!mounted) return;

        // Store profile completion status
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('profileCompleted', true);

        // Navigate to RealHomePage instead of LongTripPage
        Navigator.pushReplacement( // Changed to pushReplacement for proper flow
          context,
          MaterialPageRoute(
            builder: (context) => RealHomePage(customerId: widget.customerId),
          ),
        );
      } else {
        final errorData = jsonDecode(response.body);
        _showToast('Failed: ${errorData['message'] ?? 'Unknown error'}', isError: true);
      }
    } catch (e) {
      _showToast('Network error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showToast(String text, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Center(child: Text(text, textAlign: TextAlign.center)),
        backgroundColor: isError ? Colors.red[600] : Colors.green[600], // Added success color
        elevation: 2,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: isError ? 3 : 2), // Longer duration for errors
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
                'We\'re almost there! 🚀', // Fixed encoding
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
                "It\'s a pleasure to have you, Rider!", // Fixed encoding
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
      enabled: !_isSaving, // Added to prevent editing while saving
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
          onChanged: _isSaving ? null : (v) => setState(() => _selectedGender = v!), // Disabled while saving
        ),
      ),
    );
  }

  Widget _saveButton() {
    return GestureDetector(
      onTap: _isSaving ? null : _saveDetails, // Prevent multiple taps while saving
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _isSaving 
            ? Colors.grey[400] 
            : const Color.fromRGBO(98, 205, 255, 1), // Visual feedback when disabled
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