import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'short_trip_page.dart';
import 'profile_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'parcel_location_page.dart';
import 'car_trip_agreement_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'help_page.dart';
import 'parcel_live_tracking_page.dart';
import 'ride_history_page.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'models/trip_args.dart';

// TODO: Replace with project env var
const String googleMapsApiKey = 'AIzaSyCqfjktNhxjKfM-JmpSwBk9KtgY429QWY8';

class RealHomePage extends StatefulWidget {
  final String customerId;

  const RealHomePage({super.key, required this.customerId});

  @override
  State<RealHomePage> createState() => _RealHomePageState();
}

class _RealHomePageState extends State<RealHomePage>
    with TickerProviderStateMixin {
  final services = [
    {'label': 'Bike', 'image': 'assets/images/bike.png'},
    {'label': 'Auto', 'image': 'assets/images/auto.png'},
    {'label': 'Car', 'image': 'assets/images/car.png'},
    {'label': 'Parcel', 'image': 'assets/images/parcel.png'},
  ];

  final allServices = [
    {'label': 'Bike', 'image': 'assets/images/bike.png'},
    {'label': 'Auto', 'image': 'assets/images/auto.png'},
    {'label': 'car', 'image': 'assets/images/car.png'},
    {'label': 'premium', 'image': 'assets/images/Primium.png'},
    {'label': 'XL', 'image': 'assets/images/xl.png'},
    {'label': 'Car Trip', 'image': 'assets/images/car.png'},
    {'label': 'Parcel', 'image': 'assets/images/parcel.png'},
  ];

  late List<AnimationController> _controllers;
  late List<Animation<Offset>> _animations;
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropController = TextEditingController();
  late final stt.SpeechToText _speech;
  String? selectedVehicle;
  String name = '';
  String phone = '';
  String rating = '';
  List<Map<String, dynamic>> locationHistory = [];

  // Current location data
  double? _currentLat;
  double? _currentLng;
  String _currentAddress = '';
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounce;
  bool _isLocationLoading = true;
  bool _isLocationError = false;

  @override
  void initState() {
    super.initState();
    _checkOldUser();

    _speech = stt.SpeechToText();
    _controllers = List.generate(
      services.length,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 800),
      ),
    );
    _animations = List.generate(
      services.length,
      (i) {
        final fromLeft = i % 2 == 0;
        return Tween<Offset>(
          begin: Offset(fromLeft ? -1.5 : 1.5, 0),
          end: Offset.zero,
        ).animate(
            CurvedAnimation(parent: _controllers[i], curve: Curves.easeOut));
      },
    );
    Future.forEach<int>(List.generate(services.length, (i) => i), (i) async {
      await Future.delayed(Duration(milliseconds: i * 300));
      _controllers[i].forward();
    });

    phone =
        FirebaseAuth.instance.currentUser?.phoneNumber?.replaceAll('+91', '') ??
            '';
    _fetchUserProfile();
    _loadLocationHistory();
    _loadCachedLocation();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _dropController.dispose();
    _speech.stop();
    _debounce?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _checkOldUser() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool? isOldUser = prefs.getBool('isOldUser');

    if (isOldUser == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Welcome back, old user!"),
            duration: Duration(seconds: 3),
          ),
        );
      });
    }
  }

  Future<void> _loadCachedLocation() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? cachedAddress = prefs.getString('cached_pickup_address');
      double? cachedLat = prefs.getDouble('cached_pickup_lat');
      double? cachedLng = prefs.getDouble('cached_pickup_lng');

      if (cachedAddress != null && cachedLat != null && cachedLng != null) {
        setState(() {
          _currentAddress = cachedAddress;
          _pickupController.text = cachedAddress;
          _currentLat = cachedLat;
          _currentLng = cachedLng;
          _isLocationLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading cached location: $e');
    }
  }

  Future<void> _cacheCurrentLocation() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_pickup_address', _currentAddress);
      if (_currentLat != null) {
        await prefs.setDouble('cached_pickup_lat', _currentLat!);
      }
      if (_currentLng != null) {
        await prefs.setDouble('cached_pickup_lng', _currentLng!);
      }
    } catch (e) {
      debugPrint('Error caching location: $e');
    }
  }
 

  Future<void> _getCurrentLocation() async {
    try {
      setState(() {
        _isLocationLoading = true;
        _isLocationError = false;
      });

      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() {
          _isLocationError = true;
          _isLocationLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location services are disabled')),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _isLocationError = true;
            _isLocationLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Location permission denied')),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _isLocationError = true;
          _isLocationLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location permission permanently denied')),
        );
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentLat = position.latitude;
        _currentLng = position.longitude;
      });

      // Get address from coordinates
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark placemark = placemarks.first;
        String address =
            '${placemark.street}, ${placemark.locality}, ${placemark.administrativeArea}';
        setState(() {
          _currentAddress = address;
          _pickupController.text = address;
          _isLocationLoading = false;
          _isLocationError = false;
        });
        _cacheCurrentLocation();
      } else {
        // Fallback to Google Geocoding API
        await _reverseGeocodeWithGoogle(position.latitude, position.longitude);
      }
    } catch (e) {
      debugPrint('Error getting current location: $e');
      setState(() {
        _isLocationLoading = false;
        _isLocationError = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to get location: $e')),
      );
    }
  }

  Future<void> _reverseGeocodeWithGoogle(double lat, double lng) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$googleMapsApiKey',
      );

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List?;

        if (results != null && results.isNotEmpty) {
          final address = results[0]['formatted_address'] as String?;
          setState(() {
            _currentAddress = address ?? 'Current Location';
            _pickupController.text = _currentAddress;
            _isLocationLoading = false;
            _isLocationError = false;
          });
          _cacheCurrentLocation();
        }
      }
    } catch (e) {
      debugPrint('Google reverse geocoding failed: $e');
      setState(() {
        _isLocationLoading = false;
        _isLocationError = true;
      });
    }
  }

  Future<void> _fetchUserProfile() async {
    try {
      final res =
          await http.get(Uri.parse('http://192.168.1.28:5002/api/user/$phone'));
      if (res.statusCode == 200) {
        final user = json.decode(res.body)['user'];
        setState(() {
          name = user['name'] ?? '';
          phone = user['phone'] ?? phone;
        });
        _loadLocationHistory();
      }
    } catch (e) {
      debugPrint("Failed to fetch profile: $e");
    }
  }

  Future<void> _loadLocationHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'location_history_${phone.isNotEmpty ? phone : 'unknown'}';
    final rawList = prefs.getStringList(key) ?? [];
    setState(() {
      locationHistory = rawList.map((e) {
        try {
          return jsonDecode(e) as Map<String, dynamic>;
        } catch (_) {
          // fallback for old string-only entries
          return {'address': e};
        }
      }).toList();
    });
  }

  Future<void> _saveToHistory(String address,
      {double? lat, double? lng}) async {
    const invalidTerms = ['bike', 'auto', 'car', 'premium', 'xl'];
    if (invalidTerms.any((term) => address.toLowerCase().contains(term))) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final key = 'location_history_${phone.isNotEmpty ? phone : 'unknown'}';
    // Remove any existing entry with same address
    locationHistory.removeWhere((item) => item['address'] == address);
    locationHistory.insert(0, {
      'address': address,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
    if (locationHistory.length > 10) {
      locationHistory = locationHistory.sublist(0, 10);
    }
    await prefs.setStringList(
        key, locationHistory.map((e) => jsonEncode(e)).toList());
    setState(() {});
  }

  Future<void> _fetchSuggestions(String query) async {
    if (query.trim().length < 2) {
      setState(() => _suggestions = []);
      return;
    }

    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        // Use Google Places API for autocomplete
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query'
          '&key=$googleMapsApiKey'
          '&location=${_currentLat},${_currentLng}'
          '&radius=20000',
        );

        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final predictions = data['predictions'] as List?;

          if (predictions != null) {
            setState(() {
              _suggestions =
                  predictions.map<Map<String, dynamic>>((prediction) {
                return {
                  'description': prediction['description'] as String,
                  'place_id': prediction['place_id'] as String,
                };
              }).toList();
            });
          }
        }
      } catch (e) {
        // Fallback to local history matches
        setState(() {
          _suggestions = locationHistory
              .where((item) => (item['address'] ?? '')
                  .toLowerCase()
                  .contains(query.toLowerCase()))
              .map((item) => {
                    'description': item['address'] ?? '',
                    'place_id': '',
                    'lat': item['lat'],
                    'lng': item['lng'],
                  })
              .toList();
        });
      }
    });
  }

  Future<void> _selectSuggestion(Map<String, dynamic> suggestion) async {
    final placeId = suggestion['place_id'] as String;
    final description = suggestion['description'] as String;

    if (placeId.isEmpty) {
      // History item selected
      _dropController.text = description;
      double? lat = suggestion['lat'] as double?;
      double? lng = suggestion['lng'] as double?;
      if (lat != null && lng != null) {
        _navigateToShortTripWithDrop(description, dropLat: lat, dropLng: lng);
      } else {
        // fallback: geocode
        await _geocodeAndNavigate(description);
      }
      return;
    }

    try {
      // Get place details from Google Places API
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$googleMapsApiKey',
      );

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data['result'];

        if (result != null) {
          final address = result['formatted_address'] ?? description;
          final geometry = result['geometry']?['location'];
          final lat = geometry != null ? geometry['lat'] as double? : null;
          final lng = geometry != null ? geometry['lng'] as double? : null;
          _dropController.text = address;
          _saveToHistory(address, lat: lat, lng: lng);
          _navigateToShortTripWithDrop(address, dropLat: lat, dropLng: lng);
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to get location details: $e')),
      );
    }
  }

  void _navigateToShortTripWithDrop(String dropAddress,
      {double? dropLat, double? dropLng}) {
    if (_currentLat == null || _currentLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please wait while we get your location')),
      );
      return;
    }
    if (dropLat != null && dropLng != null) {
      _saveToHistory(dropAddress, lat: dropLat, lng: dropLng);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ShortTripPage(
            args: TripArgs(
              pickupLat: _currentLat!,
              pickupLng: _currentLng!,
              pickupAddress: _currentAddress,
              dropAddress: dropAddress,
              dropLat: dropLat,
              dropLng: dropLng,
              vehicleType: null,
              showAllFares: true,
            ),
            entryMode: 'search', customerId: '',
          ),
        ),
      ).then((_) => _fetchUserProfile());
    } else {
      // If no lat/lng, geocode first
      _geocodeAndNavigate(dropAddress);
    }
  }

  Future<void> _geocodeAndNavigate(String address) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(address)}&key=$googleMapsApiKey',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final loc = results[0]['geometry']['location'];
          final lat = (loc['lat'] as num).toDouble();
          final lng = (loc['lng'] as num).toDouble();
          _saveToHistory(address, lat: lat, lng: lng);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ShortTripPage(
                args: TripArgs(
                  pickupLat: _currentLat!,
                  pickupLng: _currentLng!,
                  pickupAddress: _currentAddress,
                  dropAddress: address,
                  dropLat: lat,
                  dropLng: lng,
                  vehicleType: null,
                  showAllFares: true,
                ),
                entryMode: 'search', customerId: '',
              ),
            ),
          ).then((_) => _fetchUserProfile());
        } else {
          throw Exception('No geocode result');
        }
      } else {
        throw Exception('Geocode failed');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to geocode address: $e')),
      );
    }
  }

  void _navigateToShortTrip(String vehicleType) {
    if (_currentLat == null || _currentLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please wait while we get your location')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShortTripPage(
          args: TripArgs(
            pickupLat: _currentLat!,
            pickupLng: _currentLng!,
            pickupAddress: _currentAddress,
            vehicleType: vehicleType,
            showAllFares: false,
          ), customerId: '',
        ),
      ),
    ).then((_) => _fetchUserProfile());
  }

  void _showAllServices() {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.black87, // Dark background behind sheet
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return Container(
        height: 420,
        decoration: const BoxDecoration(
          color: Colors.white, // White top sheet
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Text(
              'All Services',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            // Grid of services
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: allServices.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.85,
                ),
                itemBuilder: (ctx, idx) {
                  final data = allServices[idx];
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      if (data['label'] == 'Parcel') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ParcelLocationPage(
                              customerId: widget.customerId,
                            ),
                          ),
                        ).then((_) => _fetchUserProfile());
                      } else if (data['label'] == 'Car Trip') {
                        showModalBottomSheet(
                          context: ctx,
                          isScrollControlled: true,
                          backgroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(24)),
                          ),
                          builder: (_) => CarTripAgreementSheet(
                              customerId: widget.customerId),
                        ).then((_) => _fetchUserProfile());
                      } else {
                        _navigateToShortTrip(data['label']!.toLowerCase());
                      }
                    },
                    child: Column(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                              border: Border.all(
                                  color: Colors.transparent, width: 1),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Image.asset(
                              data['image']!,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          data['label']!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.roboto(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            // Optional: full-width blue button at bottom
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Close',
                  style: GoogleFonts.roboto(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    },
  );
}

  @override
Widget build(BuildContext context) {
  final screenWidth = MediaQuery.of(context).size.width;
  final halfWidth = screenWidth / 2;

  return Scaffold(
    backgroundColor: Colors.white,
    drawer: _buildDrawer(context),
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔹 Header with Search
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: Color.fromRGBO(30, 136, 229, 1), // Blue
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: Offset(0, 2)),
                        ],
                      ),
                      child: Builder(
                        builder: (ctx) => IconButton(
                          icon: const Icon(Icons.menu,
                              color: Colors.black87, size: 26),
                          onPressed: () {
                            Scaffold.of(ctx).openDrawer();
                            _fetchUserProfile();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Search bar
                    Expanded(
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: const [
                            BoxShadow(
                                color: Colors.black12,
                                blurRadius: 6,
                                offset: Offset(0, 3))
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            const Icon(Icons.search, color: Colors.grey),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _dropController,
                                style:
                                    const TextStyle(color: Colors.black87),
                                decoration: const InputDecoration(
                                  hintText: "Where are you going?",
                                  hintStyle: TextStyle(color: Colors.grey),
                                  border: InputBorder.none,
                                ),
                                onChanged: _fetchSuggestions,
                                onSubmitted: (value) {
                                  if (value.isNotEmpty) {
                                    _navigateToShortTripWithDrop(value);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // From field
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black12,
                          blurRadius: 6,
                          offset: Offset(0, 3))
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.location_on,
                          color: _isLocationLoading
                              ? Colors.grey
                              : (_isLocationError ? Colors.red : Colors.green)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _isLocationLoading
                            ? const Text('Getting location...',
                                style: TextStyle(color: Colors.grey))
                            : TextField(
                                controller: _pickupController,
                                style: const TextStyle(color: Colors.black87),
                                decoration: const InputDecoration(
                                  hintText: "From",
                                  hintStyle: TextStyle(color: Colors.grey),
                                  border: InputBorder.none,
                                ),
                                onChanged: (value) {
                                  setState(() => _currentAddress = value);
                                  _cacheCurrentLocation();
                                },
                              ),
                      ),
                      IconButton(
                        icon: _isLocationLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location, color: Colors.grey),
                        onPressed:
                            _isLocationLoading ? null : _getCurrentLocation,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 🔹 Suggestions
          if (_suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: _suggestions
                    .map((s) => ListTile(
                          leading: const Icon(Icons.location_on,
                              color: Colors.blue),
                          title: Text(s['description']),
                          onTap: () => _selectSuggestion(s),
                        ))
                    .toList(),
              ),
            ),

          // 🔹 Recent Locations
          if (locationHistory.isNotEmpty && _suggestions.isEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Recent Destinations",
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 120,
                    child: ListView.separated(
                      itemCount: locationHistory.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Color(0xFFE0E0E0)),
                      itemBuilder: (context, index) {
                        final item = locationHistory[index];
                        final address = item['address'] ?? '';
                        final title = address.split(',')[0].trim();
                        final subtitle =
                            address.replaceFirst(title, '').trim();
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.history,
                              color: Colors.black54),
                          title: Text(title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          trailing: const Icon(Icons.favorite_border,
                              size: 20, color: Colors.grey),
                          onTap: () {
                            _dropController.text = address;
                            final lat = item['lat']?.toDouble();
                            final lng = item['lng']?.toDouble();
                            if (lat != null && lng != null) {
                              _navigateToShortTripWithDrop(address,
                                  dropLat: lat, dropLng: lng);
                            } else {
                              _geocodeAndNavigate(address);
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

          // 🔹 Explore Section
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Explore",
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.blue)),
                InkWell(
                  onTap: _showAllServices,
                  child: Row(
                    children: const [
                      Text("View All",
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.blue)),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios,
                          size: 14, color: Colors.blue),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 🔹 Cards Section
          Expanded(
            child: Stack(
              children: [
                // faint watermark bg
                Transform.translate(
                  offset: const Offset(0, 80),
                  child: Align(
                    child: Opacity(
                      opacity: 0.1,
                      child: Image.asset(
                          'assets/images/charminar_white.png',
                          height: 500,
                          fit: BoxFit.contain),
                    ),
                  ),
                ),
                ListView.builder(
                  padding: const EdgeInsets.only(bottom: 25),
                  itemCount: services.length,
                  itemBuilder: (ctx, idx) {
                    return AnimatedBuilder(
                      animation: _animations[idx],
                      builder: (ctx, child) {
                        final dx = _animations[idx].value.dx;
                        final fromLeft = idx % 2 == 0;
                        return Transform.translate(
                          offset: Offset(dx * halfWidth, 0),
                          child: Align(
                            alignment: fromLeft
                                ? Alignment.centerLeft
                                : Alignment.centerRight,
                            child: _buildHalfCard(
                              services[idx]['label']!,
                              services[idx]['image']!,
                              halfWidth,
                              fromLeft,
                              ctx,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildHalfCard(
    String label, String imagePath, double width, bool fromLeft, BuildContext ctx) {
  const double cardHeight = 65;

  return GestureDetector(
    onTap: () {
      if (label == 'Parcel') {
        Navigator.push(
            ctx,
            MaterialPageRoute(
                builder: (_) => PickupScreen(
                      customerId: widget.customerId,
                    ))).then((_) => _fetchUserProfile());
      } else {
        _navigateToShortTrip(label.toLowerCase());
      }
    },
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: width,
          height: cardHeight,
          margin: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade400, Colors.blue.shade700],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: fromLeft
                ? const BorderRadius.only(
                    topRight: Radius.circular(22),
                    bottomRight: Radius.circular(22))
                : const BorderRadius.only(
                    topLeft: Radius.circular(22),
                    bottomLeft: Radius.circular(22)),
            boxShadow: const [
              BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.15),
                  blurRadius: 12,
                  offset: Offset(0, 5)),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Positioned(
          top: -15,
          left: fromLeft ? width - 75 : null,
          right: fromLeft ? null : width - 55,
          child: Container(
            width: 110,
            height: 110,
            alignment: Alignment.center,
            child: Image.asset(imagePath,
                width: 110, height: 110, fit: BoxFit.contain),
          ),
        ),
      ],
    ),
  );
}

Widget _buildDrawer(BuildContext ctx) {
  return Drawer(
    backgroundColor: Colors.white,
    child: ListView(
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: 40),

        // Profile section
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GestureDetector(
            onTap: () async {
              Navigator.pop(ctx);
              await Navigator.push(
                  ctx, MaterialPageRoute(builder: (_) => const ProfilePage()));
              _fetchUserProfile();
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade400, Colors.blue.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 4)),
                ],
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person, size: 32, color: Colors.blue),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.isNotEmpty ? name : 'Guest',
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                      const SizedBox(height: 4),
                      Text(phone,
                          style: GoogleFonts.poppins(
                              color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Menu Items
        _drawerTile(Icons.help_outline, "Help", onTap: () {
          Navigator.pop(ctx);
          Navigator.push(
            ctx,
            MaterialPageRoute(builder: (_) => const HelpPage()),
          );
        }),
        _drawerTile(Icons.local_shipping_outlined, "Parcel Live Tracking",
            onTap: () {
          Navigator.pop(ctx);
          Navigator.push(
            ctx,
            MaterialPageRoute(
                builder: (_) =>
                    ParcelLiveTrackingPage(customerId: widget.customerId)),
          );
        }),
        _drawerTile(Icons.history, "Ride History", onTap: () {
          Navigator.pop(ctx);
          Navigator.push(
            ctx,
            MaterialPageRoute(builder: (_) => const RideHistoryPage()),
          );
        }),

        _drawerTile(Icons.favorite_border, "Favourites"),
        _drawerTile(Icons.payment, "Payment"),
        _drawerTile(Icons.card_giftcard_outlined, "Refer and Earn"),
        _drawerTile(Icons.notifications_none, "Notifications"),
        _drawerTile(Icons.logout, "Logout"),
        const SizedBox(height: 20),
      ],
    ),
  );
}

Widget _drawerTile(IconData icon, String title, {VoidCallback? onTap}) {
  return ListTile(
    leading: Icon(icon, color: Colors.blue.shade600),
    title: Text(title,
        style: GoogleFonts.poppins(
            fontWeight: FontWeight.w500, color: Colors.black87)),
    onTap: onTap,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    hoverColor: Colors.blue.shade50,
  );
}}