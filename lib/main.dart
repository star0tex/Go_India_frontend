import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:go_china1/services/socket_service.dart'; // Adjust import path
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // ✅ Correct: Connect to the socket BEFORE running the app.
  SocketService().connect("http://192.168.1.28:5002"); // Use your IP

  // Now run the app, which can safely use the connected service.
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
      home: const SplashScreen(),
    );
  }
}