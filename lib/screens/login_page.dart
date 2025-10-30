import 'package:firebase_messaging/firebase_messaging.dart';
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
  final String apiUrl = 'https://b23b44ae0c5e.ngrok-free.app';
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _codeSent = false;
  bool _isLoading = false;
  String? _verificationId;
  int? _resendToken;

  @override
  void initState() {
    super.initState();
    _initializeFirebaseAuth();
  }

  Future<void> _initializeFirebaseAuth() async {
    // Set language code for OTP SMS (optional)
    await _auth.setLanguageCode('en');
  }

  // ✅ Send OTP using Firebase Phone Auth (FREE with Spark plan)
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
      // ✅ Firebase Phone Auth - NO COST with Spark plan (10k/month free)
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneWithCode,
        timeout: const Duration(seconds: 60),
        
        // When OTP is sent successfully
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-retrieval or instant verification (Android only)
          debugPrint("✅ Auto verification completed");
          await _signInWithCredential(credential);
        },
        
        // When OTP verification fails
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _isLoading = false);
          debugPrint("❌ Verification failed: ${e.code} - ${e.message}");
          
          if (e.code == 'invalid-phone-number') {
            _showMessage('Invalid phone number format', isError: true);
          } else if (e.code == 'too-many-requests') {
            _showMessage('Too many requests. Try again later.', isError: true);
          } else {
            _showMessage('Verification failed: ${e.message}', isError: true);
          }
        },
        
        // When OTP is sent to the phone
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _isLoading = false;
            _codeSent = true;
            _verificationId = verificationId;
            _resendToken = resendToken;
          });
          
          _showMessage("OTP sent to your phone via Firebase", isError: false);
          
          Future.delayed(
            const Duration(milliseconds: 300),
            () => _otpFocus.requestFocus(),
          );
          
          debugPrint("✅ OTP sent successfully. Verification ID: $verificationId");
        },
        
        // When OTP auto-retrieval times out
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
          debugPrint("⏱️ Auto retrieval timeout");
        },
        
        // For resending OTP
        forceResendingToken: _resendToken,
      );

      // ✅ Register FCM token with your backend
      String? fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await _sendFCMTokenToServer(phoneWithCode, fcmToken);
      }

    } catch (e) {
      setState(() => _isLoading = false);
      _showMessage("Failed to send OTP: ${e.toString()}", isError: true);
      debugPrint("Send OTP error: $e");
    }
  }

  // ✅ Verify OTP and sign in with Firebase
  Future<void> _verifyOTPAndLogin() async {
    if (_isLoading) return;

    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      _showMessage("Enter the 6-digit OTP.", isError: true);
      return;
    }

    if (_verificationId == null) {
      _showMessage("Please request OTP first.", isError: true);
      return;
    }

    setState(() => _isLoading = true);
    _showLoadingDialog();

    try {
      // ✅ Create credential with OTP
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );

      // ✅ Sign in with Firebase
      await _signInWithCredential(credential);

    } catch (e) {
      if (mounted) Navigator.pop(context);
      setState(() => _isLoading = false);
      
      if (e is FirebaseAuthException) {
        if (e.code == 'invalid-verification-code') {
          _showMessage('Invalid OTP. Please try again.', isError: true);
        } else if (e.code == 'session-expired') {
          _showMessage('OTP expired. Request a new one.', isError: true);
          setState(() => _codeSent = false);
        } else {
          _showMessage('Verification failed: ${e.message}', isError: true);
        }
      } else {
        _showMessage("Login error: ${e.toString()}", isError: true);
      }
      
      debugPrint("Login error: $e");
    }
  }

  // ✅ Sign in with Firebase credential and sync with your backend
  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    try {
      // Sign in to Firebase
      UserCredential userCredential = await _auth.signInWithCredential(credential);
      User? firebaseUser = userCredential.user;

      if (firebaseUser == null) {
        throw Exception("Firebase user is null");
      }

      debugPrint("✅ Firebase sign-in successful: ${firebaseUser.uid}");

      // Get phone number
      final phoneNumber = firebaseUser.phoneNumber ?? _phoneController.text.trim();
      final rawPhone = phoneNumber.replaceAll('+91', '').replaceAll('+', '');

      // ✅ Sync with your backend
      await _syncWithBackend(rawPhone, firebaseUser.uid);

    } catch (e) {
      if (mounted) Navigator.pop(context);
      setState(() => _isLoading = false);
      _showMessage("Sign-in failed: ${e.toString()}", isError: true);
      debugPrint("Sign-in error: $e");
    }
  }

  // ✅ Sync Firebase user with your backend
  Future<void> _syncWithBackend(String phone, String firebaseUid) async {
    try {
      final response = await http.post(
        Uri.parse("$apiUrl/api/auth/firebase-sync"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "phone": phone,
          "firebaseUid": firebaseUid,
          "role": "customer",
        }),
      ).timeout(const Duration(seconds: 30));

      if (mounted) Navigator.pop(context);
      setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint("Backend sync response: $data");

        final profileComplete = data["profileComplete"] == true;
        String customerId = data["customerId"]?.toString() ?? 
                            data["user"]?["_id"]?.toString() ?? 
                            phone;

        // Save to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("customerId", customerId);
        await prefs.setString("phoneNumber", phone);

        if (profileComplete) {
          _showMessage("Welcome back!", isError: false);
        } else {
          _showMessage("Please complete your profile", isError: false);
        }

        final Widget next = profileComplete
            ? RealHomePage(customerId: customerId)
            : HomePage(phone: phone, customerId: customerId);

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
          errorData['message'] ?? "Backend sync failed", 
          isError: true
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      setState(() => _isLoading = false);
      _showMessage("Backend sync error: ${e.toString()}", isError: true);
      debugPrint("Backend sync error: $e");
    }
  }

  Future<void> _sendFCMTokenToServer(String phone, String token) async {
    try {
      final response = await http.post(
        Uri.parse("$apiUrl/api/users/update-fcm"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "phone": phone,
          "fcmToken": token,
        }),
      );
      
      if (response.statusCode == 200) {
        debugPrint("✅ FCM token registered for $phone");
      } else {
        debugPrint("⚠️ FCM token registration failed: ${response.body}");
      }
    } catch (e) {
      debugPrint("⚠️ Failed to send FCM token: $e");
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
                                      _verificationId = null;
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