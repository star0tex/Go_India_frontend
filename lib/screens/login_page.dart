import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
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
  final String apiUrl = 'https://e4784d33af60.ngrok-free.app';

  bool _codeSent = false;
  bool _isLoading = false;
  
  // ✅ NEW: OTP Display Card
  String? _displayedOTP;
  Timer? _otpDisplayTimer;
  int _remainingSeconds = 5;

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
      _displayedOTP = null; // Clear previous OTP
      _remainingSeconds = 5;
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
        Uri.parse("$apiUrl/api/auth/send-otp"),
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
        
        // ✅ NEW: Extract OTP from response if available (for development)
        final otp = data['otp']?.toString();
        
        setState(() {
          _codeSent = true;
          if (otp != null && otp.length == 6) {
            _displayedOTP = otp;
            _startOTPDisplayTimer();
          }
        });
        
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

  // ✅ NEW: Start countdown timer for OTP display
  void _startOTPDisplayTimer() {
    _otpDisplayTimer?.cancel();
    _remainingSeconds = 5;
    
    _otpDisplayTimer = Timer.periodic(const Duration(seconds: 7), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        _remainingSeconds--;
        if (_remainingSeconds <= 0) {
          _displayedOTP = null;
          timer.cancel();
        }
      });
    });
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
        Uri.parse("$apiUrl/api/auth/verify-otp"),
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

        if (profileComplete) {
          _showMessage("Welcome back!", isError: false);
        } else {
          _showMessage("Please complete your profile", isError: false);
        }

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
      } else {
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

  // ✅ NEW: Build OTP Display Card
  Widget _buildOTPDisplayCard() {
    if (_displayedOTP == null) return const SizedBox.shrink();

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 300),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(
            opacity: value,
            child: Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.orange.shade100,
                    Colors.orange.shade50,
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.orange.shade300,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.key,
                          color: Colors.orange,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Development Mode',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Text(
                                  'Your OTP: ',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  _displayedOTP!,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                    color: Colors.orange,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    Clipboard.setData(
                                      ClipboardData(text: _displayedOTP!),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('OTP copied!'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                  child: const Icon(
                                    Icons.copy,
                                    size: 16,
                                    color: Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.orange,
                            width: 3,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '$_remainingSeconds',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _remainingSeconds / 5,
                    backgroundColor: Colors.orange.shade100,
                    color: Colors.orange,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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

                    // ✅ NEW: Show OTP Display Card
                    _buildOTPDisplayCard(),

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
                                      _displayedOTP = null;
                                      _otpDisplayTimer?.cancel();
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
    _otpDisplayTimer?.cancel();
    super.dispose();
  }
}