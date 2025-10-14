import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_page.dart';
import 'real_home_page.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkSessionAndNavigate();
  }

  Future<void> _checkSessionAndNavigate() async {
    // Wait for splash animation (minimum 3 seconds)
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    try {
      // Check if user has saved session
      final prefs = await SharedPreferences.getInstance();
      final customerId = prefs.getString("customerId");
      final user = FirebaseAuth.instance.currentUser;

      // If both customerId exists AND Firebase user is logged in, go to home
      if (customerId != null && 
          customerId.isNotEmpty && 
          user != null) {
        
        // Verify the token is still valid
        try {
          await user.getIdToken(true); // Force refresh to check validity
          
          // Token is valid, navigate to home
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => RealHomePage(customerId: customerId),
            ),
          );
          return;
        } catch (e) {
          // Token is invalid, clear session and go to login
          print("Session invalid: $e");
          await FirebaseAuth.instance.signOut();
          await prefs.remove("customerId");
          await prefs.remove("phoneNumber");
        }
      }

      // No valid session found, go to login
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    } catch (e) {
      print("Error checking session: $e");
      // On error, go to login to be safe
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1), // Dark blue
      body: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // India flag in center
            Lottie.asset(
              'assets/india_flag.json',
              width: 250,
              repeat: true,
            ),

            // Rider and title in center above flag
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Indian Ride',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 30),
                Lottie.asset(
                  'assets/bike_ride.json',
                  height: 300,
                  repeat: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}