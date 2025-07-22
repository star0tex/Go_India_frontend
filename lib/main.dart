import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/real_home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const IndianRideApp());
}

class IndianRideApp extends StatelessWidget {
  const IndianRideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Indian Ride',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.amber,
        useMaterial3: true,
      ),
      home: const RealHomePage(), // ✅ Load Splash first
    );
  }
}
