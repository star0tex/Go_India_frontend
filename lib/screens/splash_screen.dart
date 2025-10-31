import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'login_page.dart';
import 'real_home_page.dart';
import 'driver_en_route_page.dart';

const String apiBase = 'https://b23b44ae0c5e.ngrok-free.app';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _statusMessage = 'Initializing...';
  
  @override
  void initState() {
    super.initState();
    _checkSessionAndNavigate();
  }

  Future<void> _checkSessionAndNavigate() async {
    // Wait minimum 2 seconds for splash animation
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    try {
      // Check if user has saved session
      final prefs = await SharedPreferences.getInstance();
      final customerId = prefs.getString("customerId");
      final user = FirebaseAuth.instance.currentUser;

      // If both customerId exists AND Firebase user is logged in
      if (customerId != null && 
          customerId.isNotEmpty && 
          user != null) {
        
        // Verify the token is still valid
        try {
          final token = await user.getIdToken(true); // Force refresh to check validity
          
          if (token == null) {
            // Token is null, clear session and go to login
            print("Token is null, clearing session");
            await FirebaseAuth.instance.signOut();
            await prefs.remove("customerId");
            await prefs.remove("phoneNumber");
            await prefs.remove("active_trip_id");
            
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const LoginPage()),
            );
            return;
          }
          
          setState(() => _statusMessage = 'Checking active rides...');
          
          // ✅ CHECK FOR ACTIVE RIDE FIRST (PRIORITY)
          final activeRideData = await _checkActiveRide(customerId, token);
          
          if (activeRideData != null) {
            // User has an active ride - go directly to DriverEnRoutePage
            debugPrint('✅ Active ride found - navigating to driver page');
            
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => DriverEnRoutePage(
                  driverDetails: Map<String, dynamic>.from(activeRideData['driver']),
                  tripDetails: Map<String, dynamic>.from(activeRideData['trip']),
                ),
              ),
            );
            return;
          }
          
          // No active ride - get location and go to home
          setState(() => _statusMessage = 'Getting your location...');
          
          final locationData = await _getCurrentLocationData();
          
          // Navigate to home with location
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => RealHomePage(
                customerId: customerId,
                initialLocation: locationData,
              ),
            ),
          );
          return;
        } catch (e) {
          // Token is invalid, clear session and go to login
          print("Session invalid: $e");
          await FirebaseAuth.instance.signOut();
          await prefs.remove("customerId");
          await prefs.remove("phoneNumber");
          await prefs.remove("active_trip_id");
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

  /// ✅ NEW: Check if user has an active ride
  Future<Map<String, dynamic>?> _checkActiveRide(String customerId, String token) async {
    try {
      debugPrint('🔍 Checking for active rides for customer: $customerId');
      
      final response = await http.get(
        Uri.parse('$apiBase/api/trip/active/$customerId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      debugPrint('📡 Active ride check response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['hasActiveRide'] == true) {
          debugPrint('✅ Active ride found!');
          debugPrint('📦 Driver: ${data['driver']?['name']}');
          debugPrint('📦 Trip ID: ${data['trip']?['tripId']}');
          
          // Cache the trip ID
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('active_trip_id', data['trip']['tripId']);
          
          return {
            'driver': data['driver'],
            'trip': data['trip'],
          };
        } else {
          debugPrint('ℹ️ No active ride found');
          
          // Clear any stale cached trip ID
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('active_trip_id');
        }
      } else if (response.statusCode == 404) {
        debugPrint('ℹ️ No active ride (404)');
        
        // Clear cached trip ID
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('active_trip_id');
      } else {
        debugPrint('⚠️ Unexpected response: ${response.statusCode}');
      }

      return null;
    } catch (e) {
      debugPrint('❌ Error checking active ride: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _getCurrentLocationData() async {
    try {
      // Check if location services are enabled
      if (!await Geolocator.isLocationServiceEnabled()) {
        print('Location services are disabled');
        return null;
      }

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Location permission denied');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('Location permission permanently denied');
        return null;
      }

      setState(() => _statusMessage = 'Getting your location...');

      // Get current position with timeout
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw Exception('Location fetch timeout');
        },
      );

      // Get address from coordinates
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(
        const Duration(seconds: 3),
        onTimeout: () => [],
      );

      String address = 'Current Location';
      String state = '';
      String city = '';

      if (placemarks.isNotEmpty) {
        Placemark placemark = placemarks.first;
        address = '${placemark.street}, ${placemark.locality}, ${placemark.administrativeArea}';
        state = placemark.administrativeArea ?? '';
        city = placemark.locality ?? placemark.subLocality ?? '';
      }

      final locationData = {
        'lat': position.latitude,
        'lng': position.longitude,
        'address': address,
        'state': state,
        'city': city,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Cache the location
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_pickup_address', address);
      await prefs.setDouble('cached_pickup_lat', position.latitude);
      await prefs.setDouble('cached_pickup_lng', position.longitude);
      await prefs.setString('cached_pickup_state', state);
      await prefs.setString('cached_pickup_city', city);

      print('✅ Location fetched successfully: $address');
      return locationData;
    } catch (e) {
      print('❌ Error getting location: $e');
      
      // Try to load cached location
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedAddress = prefs.getString('cached_pickup_address');
        final cachedLat = prefs.getDouble('cached_pickup_lat');
        final cachedLng = prefs.getDouble('cached_pickup_lng');
        final cachedState = prefs.getString('cached_pickup_state');
        final cachedCity = prefs.getString('cached_pickup_city');

        if (cachedAddress != null && cachedLat != null && cachedLng != null) {
          print('📦 Using cached location');
          return {
            'lat': cachedLat,
            'lng': cachedLng,
            'address': cachedAddress,
            'state': cachedState ?? '',
            'city': cachedCity ?? '',
            'cached': true,
          };
        }
      } catch (e) {
        print('Error loading cached location: $e');
      }
      
      return null;
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
                  'Ghumo India',
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
                const SizedBox(height: 40),
                // Status message
                Text(
                  _statusMessage,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}