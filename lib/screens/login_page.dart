import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'home_page.dart';          // new‑user flow
import 'real_home_page.dart';     // returning users flow

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocus = FocusNode();

  String _verificationId = '';
  bool _codeSent = false;
  bool _autoVerified = false; // ← TRUE when verificationCompleted fires

  /* ───────────────────────── Helpers ───────────────────────── */
  Future<bool> _checkUserExists(String phoneNo) async {
    try {
      final res = await http.get(Uri.parse('http://192.168.174.12:5002/api/profile/$phoneNo'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return data['user'] != null;
      }
    } catch (e) {
      debugPrint('User‑existence check failed: $e');
    }
    return false;
  }

  Future<void> _routeUser(String phoneOnly) async {
    final bool exists = await _checkUserExists(phoneOnly);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Center(child: Text(exists ? '👋 Welcome back!' : '✅ Phone number verified!',
            style: const TextStyle(fontSize: 16))),
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );

    final Widget next = exists ? const RealHomePage() : HomePage(phone: phoneOnly);
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => next));
  }

  /* ───────────────────── Send OTP (instant UI) ───────────────────── */
  Future<void> _sendOTP() async {
    // Show OTP field instantly and put cursor there
    setState(() => _codeSent = true);
    Future.delayed(const Duration(milliseconds: 100), () => _otpFocus.requestFocus());

    final String phone = "+91${_phoneController.text.trim()}";

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        // This triggers for test numbers or auto‑verify
        try {
          final UC = await FirebaseAuth.instance.signInWithCredential(credential);
          if (UC.user != null) {
            _autoVerified = true;
            _routeUser(_phoneController.text.trim());
          }
        } catch (e) {
          debugPrint('Auto‑verify sign‑in failed: $e');
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Center(child: Text("Verification failed: ${e.message}", textAlign: TextAlign.center)),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      codeSent: (String verId, int? resendToken) {
        _verificationId = verId;
      },
      codeAutoRetrievalTimeout: (String verId) {
        _verificationId = verId;
      },
    );
  }

  /* ───────────────────── Verify OTP & Route ───────────────────── */
  Future<void> _verifyOTP() async {
    if (_autoVerified) return; // already signed in silently

    final String otp = _otpController.text.trim();
    final PhoneAuthCredential credential = PhoneAuthProvider.credential(
      verificationId: _verificationId,
      smsCode: otp,
    );

    try {
      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      if (userCredential.user == null) throw Exception('user is null');

      await _routeUser(_phoneController.text.trim());
    } catch (e) {
      // If already signed‑in (e.g., auto‑verify), proceed anyway
      if (FirebaseAuth.instance.currentUser != null) {
        await _routeUser(_phoneController.text.trim());
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Center(child: Text("Invalid OTP: $e", textAlign: TextAlign.center)),
          backgroundColor: Colors.red[600],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /* ───────────────────────── Widget Build ───────────────────────── */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Welcome to Indian Ride',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            const Text('Enter your mobile number', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 10),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              decoration: InputDecoration(
                prefixText: '+91 ',
                hintText: '0000000000',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                counterText: '',
              ),
            ),
            const SizedBox(height: 20),
            if (_codeSent)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Enter OTP', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _otpController,
                    focusNode: _otpFocus,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(6),
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      hintText: '6‑digit OTP',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      counterText: '',
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D47A1), // dark blue
                  foregroundColor: Colors.white, // white text
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _codeSent ? _verifyOTP : _sendOTP,
                child: Text(_codeSent ? 'Verify OTP' : 'Send OTP'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /* ───────────────────────── Lifecycle ───────────────────────── */
  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _otpFocus.dispose();
    super.dispose();
  }
}
