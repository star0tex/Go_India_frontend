import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'login_page.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    Future.delayed(const Duration(seconds: 4), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1), // Dark blue
      body: Center(
        // ✅ This centers the whole stack vertically
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 🇮🇳 India flag in center
            Lottie.asset(
              'assets/india_flag.json',
              width: 250,
              repeat: true,
            ),

            // 🛵 Rider and title in center above flag
            Column(
              mainAxisSize: MainAxisSize.min, // ✅ Center vertically
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
