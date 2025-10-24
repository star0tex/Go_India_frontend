import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/socket_service.dart';
import 'models/trip_args.dart';
import 'driver_en_route_page.dart';

const String googleMapsApiKey = 'AIzaSyB7VstS4RZlou2jyNgzkKePGqNbs2MyzYY';
const String apiBase = 'https://7668d252ef1d.ngrok-free.app';

const Map<String, String> vehicleAssets = {
  'bike': 'assets/images/bike.png',
  'auto': 'assets/images/auto.png',
  'car': 'assets/images/car.png',
  'premium': 'assets/images/premium.png',
  'xl': 'assets/images/xl.png',
};

const List<String> vehicleLabels = ['bike', 'auto', 'car', 'premium', 'xl'];
const List<String> invalidHistoryTerms = ['auto', 'bike', 'car'];

// --- UPDATED COLOR PALETTE (Matching RealHomePage) ---
class AppColors {
  // Core palette based on 60-30-10 rule
  static const Color primary = Color.fromARGB(255, 212, 120, 0); // 30% Warm Orange
  static const Color background = Colors.white;     // 60% White
  static const Color onSurface = Colors.black;      // 10% Black

  // Derived & Utility Colors
  static const Color surface = Color(0xFFF5F5F5); // Light gray for cards/inputs
  static const Color onPrimary = Colors.white;      // Text color on primary background
  static const Color onSurfaceSecondary = Colors.black54; // For less important text
  static const Color onSurfaceTertiary = Colors.black38;  // For hints and captions
  static const Color divider = Color(0xFFEEEEEE);   // Light gray for dividers

  // Standard Status Colors
  static const Color success = Color.fromARGB(255, 0, 66, 3); // Dark green
  static const Color warning = Color(0xFFFFA000);
  static const Color error = Color(0xFFD32F2F);
  
  // Special
  static const Color serviceCardBg = Color.fromARGB(255, 238, 216, 189); // Light cream
  static const Color shimmer = Color(0xFFE0E0E0);
}

// --- UPDATED TYPOGRAPHY ---
class AppTextStyles {
  static TextStyle get heading1 => GoogleFonts.plusJakartaSans(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: AppColors.onSurface, // Black
        letterSpacing: -0.5,
      );

  static TextStyle get heading2 => GoogleFonts.plusJakartaSans(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.onSurface, // Black
        letterSpacing: -0.3,
      );

  static TextStyle get heading3 => GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurface, // Black
      );

  static TextStyle get body1 => GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurface, // Black
      );

  static TextStyle get body2 => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurfaceSecondary, // Gray
      );

  static TextStyle get caption => GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurfaceTertiary, // Light Gray
        letterSpacing: 0.5,
      );

  static TextStyle get button => GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.onPrimary, // White
      );
}

class ShortTripPage extends StatefulWidget {
  final String? vehicleType;
  final String customerId;
  final TripArgs args;
  final Map<String, dynamic>? initialPickup;
  final Map<String, dynamic>? initialDrop;
  final String? entryMode;

  const ShortTripPage({
    Key? key,
    required this.args,
    this.vehicleType,
    this.initialPickup,
    this.initialDrop,
    this.entryMode,
    required this.customerId,
  }) : super(key: key);

  @override
  State<ShortTripPage> createState() => _ShortTripPageState();
}

class _ShortTripPageState extends State<ShortTripPage>
    with TickerProviderStateMixin {
  // Animation Controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late AnimationController _shimmerController;

  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _shimmerAnimation;

  final Map<String, double> _defaultFares = {
    "bike": 25.0,
    "auto": 40.0,
    "car": 80.0,
    "premium": 150.0,
    "xl": 120.0,
  };
  final Map<String, double> _fares = {};

  // Focus nodes
  final FocusNode _pickupFocusNode = FocusNode();
  final FocusNode _dropFocusNode = FocusNode();
  String _activeField = 'pickup';

  // Controllers and state
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropController = TextEditingController();

  // Location data
  gmaps.LatLng? _pickupPoint;
  gmaps.LatLng? _dropPoint;
  String _pickupAddress = '';
  String _dropAddress = '';
  String _pickupState = '';
  String _pickupCity = '';
  String? _fare;

  // Map & route
  gmaps.GoogleMapController? _mapController;
  List<gmaps.LatLng> _routePoints = [];
  double? _distanceKm;
  double? _durationSec;
  Set<gmaps.Marker> _markers = {};
  List<gmaps.LatLng> _onlineDrivers = [];
  gmaps.BitmapDescriptor? _bikeLiveIcon;
  gmaps.LatLng? _driverPosition;
  Timer? _locationTimer;

  // Services
  late final SocketService _socketService;
  final stt.SpeechToText _speech = stt.SpeechToText();

  // UI State
  int _screenIndex = 0;
  bool _isListening = false;
  bool _isWaitingForDriver = false;
  String? _currentTripId;
  Timer? _rerequestTimer;

  // Data
  List<String> _history = [];
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounce;
  bool _loadingFares = false;
  String? _selectedVehicle;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _setupFocusListeners();
    _selectedVehicle = widget.vehicleType;
    _initializeData();
    _setupSocketService();
    _loadBikeLiveIcon();
    _fetchNearbyDrivers();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForActiveRide();
    });
  }

  Future<void> _checkForActiveRide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedTripId = prefs.getString('active_trip_id');

      if (cachedTripId != null) {
        debugPrint('📦 Found cached trip ID: $cachedTripId');
      }

      final token = await _getFirebaseToken();
      if (token == null) return;

      final response = await http.get(
        Uri.parse('$apiBase/api/trip/active/${widget.customerId}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['hasActiveRide'] == true && mounted) {
          debugPrint('🔄 Restoring active ride from server');

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DriverEnRoutePage(
                driverDetails: Map<String, dynamic>.from(data['driver']),
                tripDetails: Map<String, dynamic>.from(data['trip']),
              ),
            ),
          );
        } else {
          _clearActiveTripId();
        }
      }
    } catch (e) {
      debugPrint('❌ Error checking active ride: $e');
    }
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.elasticOut),
    );
    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.linear),
    );

    _fadeController.forward();
    _slideController.forward();
    _pulseController.repeat(reverse: true);
    _shimmerController.repeat();
  }

  void _setupFocusListeners() {
    _pickupFocusNode.addListener(() {
      if (_pickupFocusNode.hasFocus) {
        setState(() => _activeField = 'pickup');
        HapticFeedback.selectionClick();
      }
    });
    _dropFocusNode.addListener(() {
      if (_dropFocusNode.hasFocus) {
        setState(() => _activeField = 'drop');
        HapticFeedback.selectionClick();
      }
    });
  }

  void _setupSocketService() {
    _socketService = SocketService();
    _socketService.connect(apiBase);
    _socketService.connectCustomer(customerId: widget.customerId);
    _setupSocketListeners();
  }

  Future<String?> _getFirebaseToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      return await user.getIdToken();
    } catch (e) {
      debugPrint('Error getting Firebase token: $e');
      return null;
    }
  }

  Future<void> _saveActiveTripId(String tripId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_trip_id', tripId);
      debugPrint('💾 Saved active trip ID: $tripId');
    } catch (e) {
      debugPrint('❌ Error saving trip ID: $e');
    }
  }

  Future<void> _clearActiveTripId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_trip_id');
      debugPrint('🗑️ Cleared active trip ID');
    } catch (e) {
      debugPrint('❌ Error clearing trip ID: $e');
    }
  }

  void _setupSocketListeners() {
    _socketService.on('trip:accepted', (data) {
      debugPrint("==========================================");
      debugPrint("🔔 Trip accepted event received!");
      debugPrint("📦 Full data: $data");

      final driverDetails = data['driver'] ?? data['driverDetails'] ?? {};
      final tripDetails = data['trip'] ?? data['tripDetails'] ?? {};

      if (driverDetails.isEmpty || tripDetails.isEmpty) {
        debugPrint("❌ Missing driver/trip details in event: $data");
      }

      if (!mounted) return;

      final enrichedTripDetails = <String, dynamic>{
        ...Map<String, dynamic>.from(tripDetails),
        'rideCode': data['rideCode'],
        'tripId': data['tripId'],
      };

      final typedDriverDetails = Map<String, dynamic>.from(driverDetails);
      _saveActiveTripId(data['tripId']);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DriverEnRoutePage(
            driverDetails: typedDriverDetails,
            tripDetails: enrichedTripDetails,
          ),
        ),
      );
    });

    _socketService.on('driver:locationUpdate', (data) {
      final lat = data["latitude"];
      final lng = data["longitude"];
      if (lat is num && lng is num) {
        if (!mounted) return;
        setState(() {
          _driverPosition = gmaps.LatLng(lat.toDouble(), lng.toDouble());
          _updateMarkers();
        });
      }
    });

    _socketService.on('trip:cancelled', (data) {
      if (!mounted) return;

      debugPrint('🚫 Trip cancelled: $data');

      setState(() {
        _isWaitingForDriver = false;
        _currentTripId = null;
      });

      _rerequestTimer?.cancel();
      _clearActiveTripId();

      final cancelledBy = data['cancelledBy'] ?? 'unknown';
      final message = cancelledBy == 'driver'
          ? 'Driver cancelled the trip. You can request a new ride.'
          : 'Trip cancelled successfully.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(color: Colors.white)),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 3),
        ),
      );
    });

    _socketService.on('trip:clear_cache', (data) {
      if (!mounted) return;
      debugPrint('🗑️ Clear cache signal received');
      _clearActiveTripId();
    });

    _socketService.on('trip:timeout', (data) {
      if (!mounted) return;

      debugPrint('⏰ Trip timeout: $data');

      setState(() {
        _isWaitingForDriver = false;
      });

      _rerequestTimer?.cancel();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(data['message'] ?? 'No drivers available. Please try again.'),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 5),
        ),
      );
    });
  }

  Future<void> _loadBikeLiveIcon() async {
    try {
      final bitmap = await gmaps.BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(64, 64)),
        'assets/images/bikelive.png',
      );
      setState(() {
        _bikeLiveIcon = bitmap;
      });
      _updateMarkers();
    } catch (e) {
      debugPrint('Failed to load bike icon: $e');
    }
  }

  Future<void> _fetchNearbyDrivers() async {
    if (_pickupPoint == null) return;

    try {
      final token = await _getFirebaseToken();
      if (token == null) {
        debugPrint('No Firebase token available');
        return;
      }

      final url = Uri.parse(
        '$apiBase/api/driver/nearby?lat=${_pickupPoint!.latitude}&lng=${_pickupPoint!.longitude}&radius=2',
      );

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          setState(() {
            _onlineDrivers = data.map<gmaps.LatLng>((item) {
              return gmaps.LatLng(item['lat'], item['lng']);
            }).toList();
          });
          _updateMarkers();
        }
      } else if (response.statusCode == 401) {
        debugPrint('Authentication failed - token may be expired');
      } else {
        debugPrint('Failed to fetch drivers: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching nearby drivers: $e');
    }
  }

  void _updateMarkers() {
    _markers.clear();

    if (_pickupPoint != null) {
      _markers.add(gmaps.Marker(
        markerId: const gmaps.MarkerId("pickup"),
        position: _pickupPoint!,
        icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
          gmaps.BitmapDescriptor.hueGreen,
        ),
      ));
    }

    if (_dropPoint != null) {
      _markers.add(gmaps.Marker(
        markerId: const gmaps.MarkerId("drop"),
        position: _dropPoint!,
        icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
          gmaps.BitmapDescriptor.hueRed,
        ),
      ));
    }

    if (_driverPosition != null) {
      _markers.add(gmaps.Marker(
        markerId: const gmaps.MarkerId("driver"),
        position: _driverPosition!,
        icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
          gmaps.BitmapDescriptor.hueBlue,
        ),
      ));
    }

    if (_screenIndex == 0 && _bikeLiveIcon != null) {
      for (int i = 0; i < _onlineDrivers.length; i++) {
        _markers.add(gmaps.Marker(
          markerId: gmaps.MarkerId('online_driver_$i'),
          position: _onlineDrivers[i],
          icon: _bikeLiveIcon!,
          anchor: const Offset(0.5, 0.5),
        ));
      }
    }

    setState(() {});
  }

  Future<void> _initializeData() async {
    await _loadHistory();

    if (widget.initialPickup != null) {
      _pickupPoint = gmaps.LatLng(
        widget.initialPickup!['lat'],
        widget.initialPickup!['lng'],
      );
      _pickupAddress = widget.initialPickup!['address'] ?? 'Pickup location';
      _pickupController.text = _pickupAddress;

      final locationData = await _reverseGeocode(_pickupPoint!);
      _pickupState = locationData['state'] ?? '';
      _pickupCity = locationData['city'] ?? '';
      await _fetchNearbyDrivers();
      _updateMarkers();
    } else {
      await _getCurrentLocation();
    }

    if (widget.initialDrop != null) {
      _dropPoint = gmaps.LatLng(
        widget.initialDrop!['lat'],
        widget.initialDrop!['lng'],
      );
      _dropAddress = widget.initialDrop!['address'] ?? 'Drop location';
      _dropController.text = _dropAddress;

      if (widget.entryMode == 'search') {
        setState(() => _screenIndex = 1);
        WidgetsBinding.instance.addPostFrameCallback((_) => _drawRoute());
      }
    }

    if (widget.entryMode == 'search' && widget.initialDrop != null) {
      setState(() => _screenIndex = 1);
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showLocationServiceError();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showLocationPermissionError();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showLocationPermissionError();
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _pickupPoint = gmaps.LatLng(position.latitude, position.longitude);
      final locationData = await _reverseGeocode(_pickupPoint!);

      setState(() {
        _pickupAddress = locationData['displayName'] ?? 'Current Location';
        _pickupState = locationData['state'] ?? '';
        _pickupCity = locationData['city'] ?? '';
        _pickupController.text = _pickupAddress;
      });
      await _fetchNearbyDrivers();
      _updateMarkers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: $e')),
        );
      }
    }
  }

  Future<Map<String, String>> _reverseGeocode(gmaps.LatLng latLng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latLng.latitude,
        latLng.longitude,
      );

      if (placemarks.isEmpty) {
        return {'displayName': 'Unknown Location', 'state': '', 'city': ''};
      }

      Placemark placemark = placemarks.first;
      return {
        'displayName':
            '${placemark.street}, ${placemark.locality}, ${placemark.administrativeArea}',
        'state': placemark.administrativeArea ?? '',
        'city': placemark.locality ?? placemark.subLocality ?? '',
      };
    } catch (e) {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=${latLng.latitude},${latLng.longitude}&key=$googleMapsApiKey',
      );

      try {
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final results = data['results'] as List?;

          if (results != null && results.isNotEmpty) {
            final address = results[0]['formatted_address'] as String?;
            String state = '';
            String city = '';

            final components = results[0]['address_components'] as List;
            for (var component in components) {
              final types = List<String>.from(component['types']);
              if (types.contains('administrative_area_level_1')) {
                state = component['long_name'] as String;
              }
              if (types.contains('locality') || types.contains('sublocality')) {
                city = component['long_name'] as String;
              }
            }

            return {
              'displayName': address ?? 'Unknown Location',
              'state': state,
              'city': city,
            };
          }
        }
      } catch (e) {
        // Ignore
      }

      return {'displayName': 'Unknown Location', 'state': '', 'city': ''};
    }
  }

  void _showLocationServiceError() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text('Location Services Disabled', style: AppTextStyles.heading3),
        content: Text('Please enable location services to use this feature.',
            style: AppTextStyles.body2),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: AppColors.error)),
          ),
          TextButton(
            onPressed: () => Geolocator.openLocationSettings(),
            child: Text('Open Settings', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _showLocationPermissionError() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text('Location Permission Required', style: AppTextStyles.heading3),
        content: Text(
            'This app needs location permission to find nearby rides.',
            style: AppTextStyles.body2),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: AppColors.error)),
          ),
          TextButton(
            onPressed: () => Geolocator.openAppSettings(),
            child: Text('Open Settings', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    final historyKey = 'location_history_${user?.phoneNumber ?? user?.uid}';

    setState(() {
      _history = prefs.getStringList(historyKey) ?? [];
    });
  }

  Future<void> _saveToHistory(String address) async {
    final lowerAddress = address.toLowerCase();
    if (invalidHistoryTerms.any((term) => lowerAddress.contains(term))) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    final historyKey = 'location_history_${user?.phoneNumber ?? user?.uid}';

    _history.remove(address);
    _history.insert(0, address);

    if (_history.length > 5) {
      _history = _history.sublist(0, 5);
    }

    await prefs.setStringList(historyKey, _history);
  }

  Future<void> _onPickupChanged(String value) async {
    debugPrint('🔍 Pickup changed: "$value"');

    if (value.trim().isEmpty) {
      setState(() {
        _pickupPoint = null;
        _pickupAddress = '';
        _suggestions = [];
      });
      return;
    }

    if (value.trim().length < 2) {
      setState(() {
        _suggestions = [];
      });
      return;
    }

    await _fetchSuggestions(value);
  }

  Future<void> _fetchSuggestions(String query) async {
    debugPrint('🔎 Fetching suggestions for: "$query"');

    if (query.trim().length < 2) {
      debugPrint('⚠️ Query too short, clearing suggestions');
      setState(() => _suggestions = []);
      return;
    }

    if (_debounce?.isActive ?? false) {
      debugPrint('⏸️ Canceling previous search');
      _debounce!.cancel();
    }

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        debugPrint('🌐 Making API call to Google Places...');

        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${Uri.encodeComponent(query)}'
          '&key=$googleMapsApiKey'
          '&location=${_pickupPoint?.latitude ?? 17.3850},${_pickupPoint?.longitude ?? 78.4867}'
          '&radius=20000',
        );

        final response = await http.get(url).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint('⏱️ Request timeout');
            throw TimeoutException('Request timeout');
          },
        );

        debugPrint('📥 Response status: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          final status = data['status'];
          if (status != 'OK' && status != 'ZERO_RESULTS') {
            debugPrint('⚠️ API returned status: $status');
          }

          final predictions = data['predictions'] as List?;

          if (predictions == null || predictions.isEmpty) {
            debugPrint('📭 No predictions returned');
            setState(() => _suggestions = []);
            return;
          }

          debugPrint('✅ Found ${predictions.length} predictions');

          List<Map<String, dynamic>> hyderabad = [];
          List<Map<String, dynamic>> telangana = [];
          List<Map<String, dynamic>> india = [];

          for (var prediction in predictions) {
            final placeId = prediction['place_id'] as String;
            final description = prediction['description'] as String;

            String city = '';
            String state = '';
            String country = '';

            try {
              final detailsUrl = Uri.parse(
                'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$googleMapsApiKey&fields=address_components',
              );

              final detailsResp = await http.get(detailsUrl).timeout(
                const Duration(seconds: 3),
              );

              if (detailsResp.statusCode == 200) {
                final details = jsonDecode(detailsResp.body);
                final result = details['result'];
                if (result != null && result['address_components'] != null) {
                  for (var comp in result['address_components']) {
                    final types = List<String>.from(comp['types']);
                    if (types.contains('locality')) {
                      city = comp['long_name'];
                    }
                    if (types.contains('administrative_area_level_1')) {
                      state = comp['long_name'];
                    }
                    if (types.contains('country')) {
                      country = comp['long_name'];
                    }
                  }
                }
              }
            } catch (e) {
              debugPrint('⚠️ Failed to fetch details for $placeId: $e');
            }

            final suggestion = {
              'description': description,
              'place_id': placeId,
              'city': city,
              'state': state,
              'country': country,
            };

            if (city.toLowerCase() == 'hyderabad') {
              hyderabad.add(suggestion);
            } else if (state.toLowerCase() == 'telangana') {
              telangana.add(suggestion);
            } else if (country.toLowerCase() == 'india' || country.isEmpty) {
              india.add(suggestion);
            } else {
              india.add(suggestion);
            }
          }

          final grouped = [
            ...hyderabad,
            ...telangana,
            ...india,
          ];

          if (mounted) {
            setState(() {
              _suggestions = grouped;
            });
          }
        } else {
          debugPrint('❌ HTTP Error: ${response.statusCode}');

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Search failed: ${response.statusCode}'),
                backgroundColor: AppColors.warning,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('❌ Error fetching suggestions: $e');

        if (mounted) {
          setState(() {
            _suggestions = _history
                .where((item) => item.toLowerCase().contains(query.toLowerCase()))
                .map((item) => {'description': item, 'place_id': ''})
                .toList();
          });

          if (_suggestions.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Unable to search. Check your internet connection.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      }
    });
  }

  Future<void> _selectSuggestion(Map<String, dynamic> suggestion) async {
    final placeId = suggestion['place_id'] as String;
    final description = suggestion['description'] as String;

    if (placeId.isEmpty) {
      if (_activeField == 'pickup') {
        _pickupController.text = description;
        await _onPickupChanged(description);
      } else {
        _dropController.text = description;
        await _searchLocation(description);
      }
      return;
    }

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$googleMapsApiKey',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data['result'];
        if (result != null) {
          final geometry = result['geometry'];
          final location = geometry['location'];
          final lat = location['lat'] as double;
          final lng = location['lng'] as double;
          final formatted = result['formatted_address'] ?? description;
          if (_activeField == 'pickup') {
            _pickupPoint = gmaps.LatLng(lat, lng);
            _pickupAddress = formatted;
            _pickupController.text = formatted;
            final locationData = await _reverseGeocode(_pickupPoint!);
            setState(() {
              _pickupState = locationData['state'] ?? '';
              _pickupCity = locationData['city'] ?? '';
            });
            await _fetchNearbyDrivers();
            _updateMarkers();
          } else {
            _dropPoint = gmaps.LatLng(lat, lng);
            _dropAddress = formatted;
            _dropController.text = formatted;
            await _saveToHistory(_dropAddress);
            setState(() => _screenIndex = 1);
            await _drawRoute();
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get location details: $e')),
        );
      }
    }
  }

  Future<void> _searchLocation(String query) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?address=$query&key=$googleMapsApiKey',
      );

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List?;

        if (results != null && results.isNotEmpty) {
          final location = results[0]['geometry']['location'];
          final lat = location['lat'] as double;
          final lng = location['lng'] as double;

          _dropPoint = gmaps.LatLng(lat, lng);
          _dropAddress = results[0]['formatted_address'] as String? ?? query;
          _dropController.text = _dropAddress;

          await _saveToHistory(_dropAddress);
          setState(() => _screenIndex = 1);
          await _drawRoute();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to search location: $e')),
        );
      }
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    bool available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done') {
          setState(() => _isListening = false);
        }
      },
      onError: (error) {
        setState(() => _isListening = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Speech input unavailable, please type')),
          );
        }
      },
    );

    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speech recognition not available')),
        );
      }
      return;
    }

    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          _dropController.text = result.recognizedWords;
          _fetchSuggestions(result.recognizedWords);
        }
      },
    );
  }

  Future<void> _drawRoute() async {
    if (_pickupPoint == null || _dropPoint == null) return;

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${_pickupPoint!.latitude},${_pickupPoint!.longitude}'
        '&destination=${_dropPoint!.latitude},${_dropPoint!.longitude}'
        '&key=$googleMapsApiKey',
      );

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final routes = data['routes'] as List?;

        if (routes != null && routes.isNotEmpty) {
          final route = routes[0];
          final legs = route['legs'] as List?;

          if (legs != null && legs.isNotEmpty) {
            final leg = legs[0];
            _distanceKm = (leg['distance']['value'] as num).toDouble() / 1000;
            _durationSec = (leg['duration']['value'] as num).toDouble();

            final overviewPolyline =
                route['overview_polyline']['points'] as String;
            _routePoints = _decodePolyline(overviewPolyline);
          }
        }

        setState(() {});
        await _fetchFares();
        _fitMapToBounds();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to calculate route: $e')),
        );
      }
    }
  }

  List<gmaps.LatLng> _decodePolyline(String encoded) {
    List<gmaps.LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);

      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);

      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(gmaps.LatLng(lat / 1E5, lng / 1E5));
    }

    return points;
  }

  void _fitMapToBounds() {
    if (_pickupPoint == null || _dropPoint == null || _mapController == null) {
      return;
    }

    final bounds = gmaps.LatLngBounds(
      southwest: gmaps.LatLng(
        _pickupPoint!.latitude < _dropPoint!.latitude
            ? _pickupPoint!.latitude
            : _dropPoint!.latitude,
        _pickupPoint!.longitude < _dropPoint!.longitude
            ? _pickupPoint!.longitude
            : _dropPoint!.longitude,
      ),
      northeast: gmaps.LatLng(
        _pickupPoint!.latitude > _dropPoint!.latitude
            ? _pickupPoint!.latitude
            : _dropPoint!.latitude,
        _pickupPoint!.longitude > _dropPoint!.longitude
            ? _pickupPoint!.longitude
            : _dropPoint!.longitude,
      ),
    );

    _mapController!
        .animateCamera(gmaps.CameraUpdate.newLatLngBounds(bounds, 100));
  }

  Future<void> _fetchFares() async {
    if (_distanceKm == null || _durationSec == null) {
      debugPrint('⚠️ Cannot fetch fares: distanceKm=$_distanceKm, durationSec=$_durationSec');
      return;
    }

    if (_pickupState.isEmpty || _pickupCity.isEmpty) {
      debugPrint('⚠️ Missing location data: state=$_pickupState, city=$_pickupCity');
    }

    setState(() {
      _loadingFares = true;
      _fares.clear();
    });

    final vehiclesToFetch = (widget.vehicleType != null &&
            widget.vehicleType!.isNotEmpty)
        ? [widget.vehicleType!]
        : vehicleLabels.where((v) => v.isNotEmpty).toList();

    try {
      final results = await Future.wait(
        vehiclesToFetch.map((vehicleType) async {
          try {
            final requestBody = {
              'state': _pickupState,
              'city': _pickupCity,
              'vehicleType': vehicleType,
              'category': 'short',
              'distanceKm': _distanceKm,
              'durationMin': _durationSec! / 60,
            };

            final response = await http.post(
              Uri.parse('$apiBase/api/fares/calc'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(requestBody),
            ).timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                throw TimeoutException('Fare calculation timeout');
              },
            );

            if (response.statusCode == 200) {
              final data = jsonDecode(response.body);
              final total = (data['total'] as num).toDouble();
              return MapEntry(vehicleType, total);
            } else {
              final defaultFare = _defaultFares[vehicleType] ?? 0.0;
              return MapEntry(vehicleType, defaultFare);
            }
          } catch (e) {
            final defaultFare = _defaultFares[vehicleType] ?? 0.0;
            return MapEntry(vehicleType, defaultFare);
          }
        }),
      );

      setState(() {
        for (var entry in results) {
          _fares[entry.key] = entry.value;
        }
      });

      if (_fares.values.every((fare) => fare == 0)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to calculate fares. Using estimates.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }

      if (_fares.length == 1 && _selectedVehicle == null) {
        setState(() {
          _selectedVehicle = _fares.keys.first;
        });
      }
    } catch (e) {
      debugPrint('❌ Unexpected error in _fetchFares: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error calculating fares: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _loadingFares = false);
    }
  }

  Future<void> _confirmRide() async {
    await _clearActiveTripId();

    if (_loadingFares) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Calculating fare, please wait...'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (widget.customerId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Customer ID is missing. Please log in again.')),
        );
      }
      return;
    }

    if (_pickupPoint == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a pickup location.')),
        );
      }
      return;
    }

    if (_dropPoint == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a drop location.')),
        );
      }
      return;
    }

    if (_selectedVehicle == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a vehicle type.')),
        );
      }
      return;
    }

    final selected = _selectedVehicle!.toLowerCase().trim();
    final selectedFare = _fares[selected] ?? _defaultFares[selected] ?? 0.0;

    if (selectedFare <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Unable to calculate fare. Please try again.'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () async {
                setState(() => _loadingFares = true);
                await _fetchFares();
              },
            ),
          ),
        );
      }
      return;
    }

    final rideData = {
      "customerId": widget.customerId,
      "pickup": {
        "coordinates": [_pickupPoint!.longitude, _pickupPoint!.latitude],
        "address": _pickupAddress,
      },
      "drop": {
        "coordinates": [_dropPoint!.longitude, _dropPoint!.latitude],
        "address": _dropAddress,
      },
      "vehicleType": selected,
      "fare": selectedFare,
      "timestamp": DateTime.now().toIso8601String(),
    };

    try {
      final response = await http.post(
        Uri.parse("$apiBase/api/trip/short"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(rideData),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Request timed out');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['tripId'] != null) {
          setState(() {
            _currentTripId = data['tripId'];
            _isWaitingForDriver = data['drivers'] > 0;
          });

          if (_isWaitingForDriver) {
            _rerequestTimer?.cancel();
            _rerequestTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
              if (!mounted) {
                timer.cancel();
                return;
              }
              _socketService.emit('trip:rerequest', {'tripId': _currentTripId});
            });
          }
        }

        await _saveToHistory(_dropAddress);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isWaitingForDriver
                  ? 'Searching for nearby drivers...'
                  : 'No drivers available right now.'),
              backgroundColor: _isWaitingForDriver ? AppColors.success : AppColors.warning,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ride request failed: ${response.body}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } on TimeoutException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request timed out. Please check your connection.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send ride request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background, // White background
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: _screenIndex == 0
            ? _buildEnhancedSearchScreen()
            : _buildEnhancedMapScreen(),
      ),
      // Overlay waiting dialog
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _isWaitingForDriver ? _buildWaitingOverlay() : null,
    );
  }

  Widget _buildEnhancedSearchScreen() {
    return SafeArea(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildEnhancedHeader(),
                const SizedBox(height: 20),
                _EnhancedLocationInputBar(
                  pickupController: _pickupController,
                  dropController: _dropController,
                  pickupFocusNode: _pickupFocusNode,
                  dropFocusNode: _dropFocusNode,
                  onPickupChanged: (value) {
                    _onPickupChanged(value);
                    _fetchSuggestions(value);
                  },
                  onDropChanged: (value) => _fetchSuggestions(value),
                  onMicPressed: _toggleListening,
                  isListening: _isListening,
                  pulseAnimation: _pulseAnimation,
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: _buildEnhancedSuggestionsArea(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEnhancedHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.pop(context);
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: const Icon(Icons.arrow_back, color: AppColors.onSurface, size: 20),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Good ${_getTimeGreeting()}!",
                    style: AppTextStyles.body2,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Where are you going?",
                    style: AppTextStyles.heading2,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _getTimeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }

  Widget _buildEnhancedSuggestionsArea() {
    final bool isSearching = _suggestions.isNotEmpty;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: isSearching
          ? _buildEnhancedSuggestionsList()
          : _buildEnhancedHistorySection(),
    );
  }

  Widget _buildEnhancedHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Recent Destinations",
              style: AppTextStyles.heading3.copyWith(fontSize: 17),
            ),
            if (_history.isNotEmpty)
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _history.clear());
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error.withOpacity(0.3)),
                  ),
                  child: Text(
                    "Clear all",
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _history.isEmpty
              ? _buildEmptyHistoryState()
              : _EnhancedHistoryList(
                  history: _history,
                  onHistorySelected: _selectSuggestion,
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyHistoryState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.divider),
            ),
            child: const Icon(
              Icons.explore_outlined,
              size: 48,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "Start exploring",
            style: AppTextStyles.heading3.copyWith(
              color: AppColors.onSurfaceSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Your recent destinations will appear here",
            style: AppTextStyles.body2,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedSuggestionsList() {
    return ListView.builder(
      itemCount: _suggestions.length,
      padding: const EdgeInsets.only(top: 8),
      itemBuilder: (context, index) {
        final suggestion = _suggestions[index];
        return _EnhancedSuggestionCard(
          suggestion: suggestion,
          index: index,
          onTap: () => _selectSuggestion(suggestion),
        );
      },
    );
  }

  Widget _buildEnhancedMapScreen() {
    final screenHeight = MediaQuery.of(context).size.height;
    final mapHeight = screenHeight * 0.5;

    return Stack(
      children: [
        Container(
          height: mapHeight,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(32),
              bottomRight: Radius.circular(32),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(32),
              bottomRight: Radius.circular(32),
            ),
            child: gmaps.GoogleMap(
              onMapCreated: (controller) {
                _mapController = controller;
                _updateMarkers();
              },
              initialCameraPosition: gmaps.CameraPosition(
                target: _pickupPoint ?? const gmaps.LatLng(0, 0),
                zoom: 15,
              ),
              markers: Set<gmaps.Marker>.from(_markers),
              polylines: _routePoints.isNotEmpty
                  ? {
                      gmaps.Polyline(
                        polylineId: const gmaps.PolylineId('route'),
                        points: _routePoints,
                        color: AppColors.primary,
                        width: 6,
                        patterns: [
                          gmaps.PatternItem.dash(20),
                          gmaps.PatternItem.gap(10)
                        ],
                      ),
                    }
                  : {},
              myLocationEnabled: true,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 30,
                    offset: const Offset(0, -10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    height: 4,
                    width: 40,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.only(bottom: 100),
                      child: _EnhancedFarePanel(
                        fares: _fares,
                        loading: _loadingFares,
                        selectedVehicle: _selectedVehicle,
                        durationSec: _durationSec,
                        onVehicleSelected: (vehicle) {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedVehicle = vehicle);
                        },
                        onConfirmRide: _confirmRide,
                        showAll: widget.vehicleType == null,
                        onBack: () {
                          HapticFeedback.lightImpact();
                          setState(() => _screenIndex = 0);
                        },
                        shimmerAnimation: _shimmerAnimation,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 32,
          child: _EnhancedBookButton(
            selectedVehicle: _selectedVehicle,
            onPressed: _selectedVehicle != null ? _confirmRide : null,
          ),
        ),
      ],
    );
  }

  Widget _buildWaitingOverlay() {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.2),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.1),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(_pulseAnimation.value * 0.5),
                    width: 3,
                  ),
                ),
                child: const Icon(
                  Icons.search,
                  size: 40,
                  color: AppColors.primary,
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            'Searching for drivers nearby...',
            style: AppTextStyles.heading3,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'This usually takes less than 30 seconds',
            style: AppTextStyles.body2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _EnhancedCancelButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              setState(() => _isWaitingForDriver = false);
              _rerequestTimer?.cancel();
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    _shimmerController.dispose();
    _pickupFocusNode.dispose();
    _dropFocusNode.dispose();
    _rerequestTimer?.cancel();
    _locationTimer?.cancel();
    _debounce?.cancel();
    _pickupController.dispose();
    _dropController.dispose();
    _mapController?.dispose();
    _speech.stop();
    SocketService().off('trip:accepted');
    SocketService().off('driver:locationUpdate');
    super.dispose();
  }
}

// --- ENHANCED UI COMPONENTS (Updated for Light Theme) ---

class _EnhancedLocationInputBar extends StatelessWidget {
  final TextEditingController pickupController;
  final TextEditingController dropController;
  final FocusNode pickupFocusNode;
  final FocusNode dropFocusNode;
  final ValueChanged<String> onPickupChanged;
  final ValueChanged<String> onDropChanged;
  final VoidCallback onMicPressed;
  final bool isListening;
  final Animation<double> pulseAnimation;

  const _EnhancedLocationInputBar({
    required this.pickupController,
    required this.dropController,
    required this.pickupFocusNode,
    required this.dropFocusNode,
    required this.onPickupChanged,
    required this.onDropChanged,
    required this.onMicPressed,
    required this.isListening,
    required this.pulseAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface, // Light gray background
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.divider,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInputSection(
            label: "FROM",
            icon: Icons.my_location,
            iconColor: AppColors.success,
            controller: pickupController,
            focusNode: pickupFocusNode,
            onChanged: onPickupChanged,
            hintText: "Current location",
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                const Expanded(
                  child: Divider(color: AppColors.divider, thickness: 1),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                  ),
                  child: const Icon(
                    Icons.swap_vert,
                    size: 14,
                    color: AppColors.primary,
                  ),
                ),
                const Expanded(
                  child: Divider(color: AppColors.divider, thickness: 1),
                ),
              ],
            ),
          ),
          _buildInputSection(
            label: "TO",
            icon: Icons.location_on,
            iconColor: AppColors.error,
            controller: dropController,
            focusNode: dropFocusNode,
            onChanged: onDropChanged,
            hintText: "Where to?",
            suffixWidget: _buildMicButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildInputSection({
    required String label,
    required IconData icon,
    required Color iconColor,
    required TextEditingController controller,
    required FocusNode focusNode,
    required ValueChanged<String> onChanged,
    required String hintText,
    Widget? suffixWidget,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            letterSpacing: 1.0,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: iconColor.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                style: AppTextStyles.body1.copyWith(fontSize: 15),
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: AppTextStyles.body1.copyWith(
                    color: AppColors.onSurfaceTertiary,
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                  suffixIcon: suffixWidget,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMicButton() {
    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, child) {
        return GestureDetector(
          onTap: onMicPressed,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isListening
                  ? AppColors.primary.withOpacity(0.1)
                  : AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isListening ? AppColors.primary : AppColors.divider,
                width: isListening ? 2 : 1,
              ),
              boxShadow: isListening
                  ? [
                      BoxShadow(
                        color: AppColors.primary
                            .withOpacity(0.3 * pulseAnimation.value),
                        blurRadius: 15 * pulseAnimation.value,
                        spreadRadius: 3 * pulseAnimation.value,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              isListening ? Icons.mic : Icons.mic_none,
              color: isListening ? AppColors.primary : AppColors.onSurfaceSecondary,
              size: 18,
            ),
          ),
        );
      },
    );
  }
}

class _EnhancedHistoryList extends StatelessWidget {
  final List<String> history;
  final ValueChanged<Map<String, dynamic>> onHistorySelected;

  const _EnhancedHistoryList({
    required this.history,
    required this.onHistorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: history.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = history[index];
        return TweenAnimationBuilder<double>(
          duration: Duration(milliseconds: 200 + (index * 50)),
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 20 * (1 - value)),
              child: Opacity(
                opacity: value,
                child: _EnhancedLocationCard(
                  title: item,
                  subtitle: "Recent destination",
                  icon: Icons.history,
                  iconColor: AppColors.warning,
                  onTap: () => onHistorySelected({
                    'description': item,
                    'place_id': '',
                  }),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _EnhancedSuggestionCard extends StatelessWidget {
  final Map<String, dynamic> suggestion;
  final int index;
  final VoidCallback onTap;

  const _EnhancedSuggestionCard({
    required this.suggestion,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 100 + (index * 50)),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(20 * (1 - value), 0),
          child: Opacity(
            opacity: value,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              child: _EnhancedLocationCard(
                title: suggestion['description'],
                subtitle: _getLocationSubtitle(suggestion),
                icon: Icons.location_on,
                iconColor: AppColors.primary,
                onTap: onTap,
              ),
            ),
          ),
        );
      },
    );
  }

  String _getLocationSubtitle(Map<String, dynamic> suggestion) {
    final city = suggestion['city'] ?? '';
    final state = suggestion['state'] ?? '';
    if (city.isNotEmpty && state.isNotEmpty) {
      return '$city, $state';
    } else if (city.isNotEmpty) {
      return city;
    } else if (state.isNotEmpty) {
      return state;
    }
    return 'Location';
  }
}

class _EnhancedLocationCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const _EnhancedLocationCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.background, // White
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.divider,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: iconColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.body1.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTextStyles.body2.copyWith(fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: AppColors.onSurfaceTertiary,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnhancedFarePanel extends StatelessWidget {
  final Map<String, double> fares;
  final bool loading;
  final String? selectedVehicle;
  final double? durationSec;
  final ValueChanged<String> onVehicleSelected;
  final VoidCallback onConfirmRide;
  final bool showAll;
  final VoidCallback onBack;
  final Animation<double> shimmerAnimation;

  const _EnhancedFarePanel({
    required this.fares,
    required this.loading,
    required this.selectedVehicle,
    required this.durationSec,
    required this.onVehicleSelected,
    required this.onConfirmRide,
    required this.showAll,
    required this.onBack,
    required this.shimmerAnimation,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return _buildShimmerLoading();
    }

    if (fares.isEmpty) {
      return const SizedBox.shrink();
    }

    final vehiclesToShow = showAll
        ? vehicleLabels
        : (selectedVehicle != null ? [selectedVehicle!] : [vehicleLabels.first]);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onBack,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: AppColors.onSurface,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Choose your ride",
                      style: AppTextStyles.heading2,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${vehiclesToShow.length} option${vehiclesToShow.length > 1 ? 's' : ''} available",
                      style: AppTextStyles.body2,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          ...vehiclesToShow.map((vehicle) {
            final fare = fares[vehicle];
            final isSelected = selectedVehicle == vehicle;
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _EnhancedFareCard(
                vehicle: vehicle,
                fare: fare,
                selected: isSelected,
                onTap: () => onVehicleSelected(vehicle),
                durationSec: durationSec,
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _buildShimmerCard(),
          const SizedBox(height: 16),
          _buildShimmerCard(),
          const SizedBox(height: 16),
          _buildShimmerCard(),
        ],
      ),
    );
  }

  Widget _buildShimmerCard() {
    return AnimatedBuilder(
      animation: shimmerAnimation,
      builder: (context, child) {
        return Container(
          height: 80,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1.0 + shimmerAnimation.value, 0.0),
              end: Alignment(0.0 + shimmerAnimation.value, 0.0),
              colors: const [
                AppColors.surface,
                AppColors.shimmer,
                AppColors.surface,
              ],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
        );
      },
    );
  }
}

class _EnhancedFareCard extends StatelessWidget {
  final String vehicle;
  final double? fare;
  final bool selected;
  final VoidCallback onTap;
  final double? durationSec;

  const _EnhancedFareCard({
    required this.vehicle,
    required this.fare,
    required this.selected,
    required this.onTap,
    required this.durationSec,
  });

  @override
  Widget build(BuildContext context) {
    final vehicleIcon = vehicleAssets[vehicle];
    final vehicleInfo = _getVehicleInfo(vehicle);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.serviceCardBg // Light cream
                : AppColors.background, // White
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider,
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.25),
                      blurRadius: 15,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withOpacity(0.1)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.divider,
                  ),
                ),
                child: vehicleIcon != null
                    ? Image.asset(
                        vehicleIcon,
                        height: 32,
                        width: 32,
                        color: selected ? AppColors.primary : null,
                      )
                    : Icon(
                        Icons.directions_car,
                        color: selected ? AppColors.primary : AppColors.onSurface,
                        size: 32,
                      ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _capitalize(vehicle),
                          style: AppTextStyles.heading3.copyWith(
                            color: selected ? AppColors.primary : AppColors.onSurface,
                          ),
                        ),
                        if (vehicle == 'premium') ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.warning.withOpacity(0.5),
                              ),
                            ),
                            child: Text(
                              'LUXURY',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.warning,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      vehicleInfo['description']!,
                      style: AppTextStyles.body2.copyWith(
                        color: selected
                            ? AppColors.primary
                            : AppColors.onSurfaceSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 14,
                          color: AppColors.onSurfaceTertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          vehicleInfo['eta']!,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Icon(
                          Icons.people,
                          size: 14,
                          color: AppColors.onSurfaceTertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          vehicleInfo['capacity']!,
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    fare != null ? '₹${fare!.toStringAsFixed(0)}' : '--',
                    style: AppTextStyles.heading3.copyWith(
                      color: selected ? AppColors.primary : AppColors.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (selected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.success.withOpacity(0.5),
                        ),
                      ),
                      child: Text(
                        'SELECTED',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, String> _getVehicleInfo(String vehicle) {
    switch (vehicle) {
      case 'bike':
        return {
          'description': 'Fast & economical rides',
          'eta': '2 min',
          'capacity': '1 person',
        };
      case 'auto':
        return {
          'description': 'Quick shared rides',
          'eta': '4 min',
          'capacity': '3 people',
        };
      case 'car':
        return {
          'description': 'Comfortable AC rides',
          'eta': '6 min',
          'capacity': '4 people',
        };
      case 'premium':
        return {
          'description': 'Luxury sedan experience',
          'eta': '8 min',
          'capacity': '4 people',
        };
      case 'xl':
        return {
          'description': 'Extra space for groups',
          'eta': '10 min',
          'capacity': '6 people',
        };
      default:
        return {
          'description': 'Standard ride',
          'eta': '5 min',
          'capacity': '4 people',
        };
    }
  }

  String _capitalize(String s) =>
      s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : s;
}

class _EnhancedBookButton extends StatelessWidget {
  final String? selectedVehicle;
  final VoidCallback? onPressed;

  const _EnhancedBookButton({
    required this.selectedVehicle,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = selectedVehicle != null && onPressed != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 60,
      child: ElevatedButton(
        onPressed: isEnabled
            ? () {
                HapticFeedback.mediumImpact();
                onPressed!();
              }
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: isEnabled ? AppColors.primary : AppColors.surface,
          foregroundColor: isEnabled ? AppColors.onPrimary : AppColors.onSurfaceTertiary,
          elevation: isEnabled ? 8 : 0,
          shadowColor: isEnabled ? AppColors.primary.withOpacity(0.3) : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isEnabled) ...[
              const Icon(
                Icons.rocket_launch,
                color: AppColors.onPrimary,
                size: 24,
              ),
              const SizedBox(width: 12),
            ],
            Text(
              isEnabled
                  ? 'Book ${_capitalize(selectedVehicle!)} Now'
                  : 'Select a vehicle',
              style: AppTextStyles.button.copyWith(
                color: isEnabled ? AppColors.onPrimary : AppColors.onSurfaceTertiary,
                fontSize: 18,
              ),
            ),
            if (isEnabled) ...[
              const SizedBox(width: 12),
              const Icon(
                Icons.arrow_forward,
                color: AppColors.onPrimary,
                size: 24,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _capitalize(String s) =>
      s.isNotEmpty ? s[0].toUpperCase() + s.substring(1) : s;
}

class _EnhancedCancelButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _EnhancedCancelButton({
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 50,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: BorderSide(color: AppColors.error, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.close, size: 20),
            const SizedBox(width: 8),
            Text(
              'Cancel Search',
              style: AppTextStyles.button.copyWith(
                color: AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}