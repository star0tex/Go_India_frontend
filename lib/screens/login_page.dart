import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_page.dart';
import 'real_home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocus = FocusNode();
final String apiUrl = 'https://cd4ec7060b0b.ngrok-free.app';

  bool _codeSent = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _sendOTP() async {
  if (_isLoading) return;

  setState(() {
    _codeSent = false;
    _otpController.clear();
    _isLoading = true;
  });

  final rawPhone = _phoneController.text.trim();
  if (rawPhone.length != 10) {
    setState(() => _isLoading = false);
    _showMessage("Please enter a valid 10-digit phone number.", isError: true);
    return;
  }

  final String phoneWithCode = "+91$rawPhone";

  try {
    final response = await http.post(
      Uri.parse("https://cd4ec7060b0b.ngrok-free.app/api/auth/send-otp"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "phone": phoneWithCode,
      }),
    ).timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        throw Exception("Connection timeout");
      },
    );

    setState(() => _isLoading = false);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() => _codeSent = true);
      
      _showMessage(
        "OTP sent to your phone", 
        isError: false
      );
      
      Future.delayed(
        const Duration(milliseconds: 300),
        () => _otpFocus.requestFocus(),
      );
    } else {
      _showMessage("Failed to send OTP. Try again.", isError: true);
    }
  } catch (e) {
    setState(() => _isLoading = false);
    if (e.toString().contains("Connection timeout")) {
      _showMessage("Connection timeout. Check your internet.", isError: true);
    } else {
      _showMessage("Failed to send OTP: ${e.toString()}", isError: true);
    }
    debugPrint("Send OTP error: $e");
  }
}
  Future<void> _verifyOTPAndLogin() async {
    if (_isLoading) return;

    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      _showMessage("Enter the 6-digit OTP.", isError: true);
      return;
    }

    setState(() => _isLoading = true);
    _showLoadingDialog();

    final rawPhone = _phoneController.text.trim();
    final phoneWithCode = "+91$rawPhone";

    try {
      final response = await http.post(
        Uri.parse("https://cd4ec7060b0b.ngrok-free.app/api/auth/verify-otp"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "phone": phoneWithCode,
          "otp": otp,
          "role": "customer",
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception("Connection timeout");
        },
      );

      if (mounted) Navigator.pop(context);
      setState(() => _isLoading = false);

if (response.statusCode == 200) {
  final data = jsonDecode(response.body);
  debugPrint("Server response: $data");

  final profileComplete = data["profileComplete"] == true;

  String customerId = data["customerId"]?.toString() ?? 
                      data["user"]?["_id"]?.toString() ?? 
                      data["userId"]?.toString() ?? 
                      rawPhone;

  debugPrint("Using customerId: $customerId");
  debugPrint("Profile complete: $profileComplete");

  final prefs = await SharedPreferences.getInstance();
  await prefs.setString("customerId", customerId);
  await prefs.setString("phoneNumber", rawPhone);

  if (data["firebaseToken"] != null) {
    try {
      await FirebaseAuth.instance.signInWithCustomToken(data["firebaseToken"]);
    } catch (e) {
      debugPrint("Firebase sign-in failed: $e");
    }
  }

  // Show appropriate message
  if (profileComplete) {
    _showMessage("Welcome back!", isError: false);
  } else {
    _showMessage("Please complete your profile", isError: false);
  }

  // ✅ Navigate based on profile completion
  final Widget next = profileComplete
      ? RealHomePage(customerId: customerId)
      : HomePage(phone: rawPhone, customerId: customerId);

  await Future.delayed(const Duration(milliseconds: 500));

  if (mounted) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => next),
    );
  }
}else {
        final errorData = jsonDecode(response.body);
        _showMessage(
          errorData['message'] ?? "Login failed: ${response.body}", 
          isError: true
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      setState(() => _isLoading = false);
      _showMessage("Connection error: ${e.toString()}", isError: true);
      debugPrint("Login error: $e");
    }
  }

  Future<void> _resendOTP() async {
    _showMessage("Resending OTP...", isError: false);
    await _sendOTP();
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Verifying OTP...", style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessage(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        backgroundColor: isError ? Colors.red[600] : Colors.green[600],
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),

            const Text(
              "GhumoIndia",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 214, 120, 4),
              ),
            ),
            const SizedBox(height: 20),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Welcome',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Login with your mobile number',
                      style: TextStyle(fontSize: 16, color: Colors.black54),
                    ),
                    const SizedBox(height: 30),

                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      enabled: !_codeSent && !_isLoading,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      decoration: InputDecoration(
                        prefixText: '+91 ',
                        labelText: 'Phone Number',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        counterText: '',
                        enabled: !_codeSent,
                      ),
                    ),
                    const SizedBox(height: 20),

                    if (_codeSent) ...[
                      TextField(
                        controller: _otpController,
                        focusNode: _otpFocus,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        enabled: !_isLoading,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(6),
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: 'Enter OTP',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          counterText: '',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: _isLoading ? null : _resendOTP,
                            tooltip: 'Resend OTP',
                          ),
                        ),
                        onSubmitted: (_) => _verifyOTPAndLogin(),
                      ),
                      const SizedBox(height: 10),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: _isLoading
                                ? null
                                : () {
                                    setState(() {
                                      _codeSent = false;
                                      _otpController.clear();
                                    });
                                  },
                            child: const Text('Change Number'),
                          ),
                          TextButton(
                            onPressed: _isLoading ? null : _resendOTP,
                            child: const Text('Resend OTP'),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color.fromARGB(255, 214, 120, 4),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _isLoading
                            ? null
                            : (_codeSent ? _verifyOTPAndLogin : _sendOTP),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(_codeSent ? 'Verify OTP' : 'Send OTP'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Image.asset(
              "assets/images/login_illustration.png",
              height: 180,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const SizedBox(height: 180);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _otpFocus.dispose();
    super.dispose();
  }
}