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
const String apiBase = 'https://e4784d33af60.ngrok-free.app';

const Map<String, String> vehicleAssets = {
  'bike': 'assets/images/bike.png',
  'auto': 'assets/images/auto.png',
  'car': 'assets/images/car.png',
  'premium': 'assets/images/premium.png',
  'xl': 'assets/images/xl.png',
};

const List<String> vehicleLabels = ['bike', 'auto', 'car', 'premium', 'xl'];
const List<String> invalidHistoryTerms = ['auto', 'bike', 'car'];

// Enhanced Color Palette
class AppColors {
  static const Color primary = Color(0xFF6C5CE7);
  static const Color primaryDark = Color(0xFF5A4FCF);
  static const Color accent = Color(0xFFFF6B6B);
  static const Color accentLight = Color(0xFFFF8E8E);
  static const Color success = Color(0xFF00D684);
  static const Color warning = Color(0xFFFFB800);
  static const Color error = Color(0xFFFF4757);
  static const Color background = Color(0xFF0A0A0F);
  static const Color surface = Color(0xFF1A1A24);
  static const Color surfaceLight = Color(0xFF2A2A38);
  static const Color onSurface = Color(0xFFFFFFFF);
  static const Color onSurfaceSecondary = Color(0xFFB8B8D1);
  static const Color onSurfaceTertiary = Color(0xFF8E8EA9);
  static const Color divider = Color(0xFF2A2A38);
  static const Color shimmer = Color(0xFF3A3A4A);
}

// Enhanced Typography
class AppTextStyles {
  static TextStyle get heading1 => GoogleFonts.plusJakartaSans(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: AppColors.onSurface,
        letterSpacing: -0.5,
      );

  static TextStyle get heading2 => GoogleFonts.plusJakartaSans(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.onSurface,
        letterSpacing: -0.3,
      );

  static TextStyle get heading3 => GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
      );

  static TextStyle get body1 => GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurface,
      );

  static TextStyle get body2 => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurfaceSecondary,
      );

  static TextStyle get caption => GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurfaceTertiary,
        letterSpacing: 0.5,
      );

  static TextStyle get button => GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.onSurface,
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
  "premium": 150.0,  // ✅ ADD THIS
  "xl": 120.0, 
};
final Map<String, double> _fares = {}; // Fetched fares from API

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
  // ADD THIS METHOD to _ShortTripPageState class

Future<void> _checkForActiveRide() async {
  try {
    // ✅ First check SharedPreferences for cached trip ID
    final prefs = await SharedPreferences.getInstance();
    final cachedTripId = prefs.getString('active_trip_id');
    
    if (cachedTripId != null) {
      debugPrint('📦 Found cached trip ID: $cachedTripId');
    }
    
    // Then check server for current status
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
        // ✅ No active ride found, clear cached ID
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
// ✅ Save active trip ID
Future<void> _saveActiveTripId(String tripId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_trip_id', tripId);
    debugPrint('💾 Saved active trip ID: $tripId');
  } catch (e) {
    debugPrint('❌ Error saving trip ID: $e');
  }
}

// ✅ Clear active trip ID
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
      debugPrint("🔑 Data keys: ${data.keys}");
      debugPrint("🎫 rideCode value: ${data['rideCode']}");
      debugPrint("🆔 tripId value: ${data['tripId']}");
      debugPrint("==========================================");
      
      final driverDetails = data['driver'] ?? data['driverDetails'] ?? {};
      final tripDetails = data['trip'] ?? data['tripDetails'] ?? {};

      if (driverDetails.isEmpty || tripDetails.isEmpty) {
        debugPrint("❌ Missing driver/trip details in event: $data");
      }

      if (!mounted) return;

      // ✅ Convert to Map<String, dynamic> and add rideCode and tripId
      final enrichedTripDetails = <String, dynamic>{
        ...Map<String, dynamic>.from(tripDetails),
        'rideCode': data['rideCode'],
        'tripId': data['tripId'],
      };

      debugPrint("✅ Enriched tripDetails: $enrichedTripDetails");
      debugPrint("✅ rideCode in enriched: ${enrichedTripDetails['rideCode']}");

      // ✅ Also convert driverDetails to proper type
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
    _clearActiveTripId(); // Clear cached trip ID
    
    final cancelledBy = data['cancelledBy'] ?? 'unknown';
    final message = cancelledBy == 'driver' 
        ? 'Driver cancelled the trip. You can request a new ride.'
        : 'Trip cancelled successfully.';
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
        action: cancelledBy == 'driver' ? SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ) : null,
      ),
    );
  });
  _socketService.on('trip:clear_cache', (data) {
    if (!mounted) return;
    
    debugPrint('🗑️ Clear cache signal received');
    _clearActiveTripId();
  });

      // ✅ NEW: Listen for trip timeout (Requirement #3)
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
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 5),
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
    // ✅ Get Firebase token
    final token = await _getFirebaseToken();
    if (token == null) {
      debugPrint('No Firebase token available');
      return;
    }

    final url = Uri.parse(
      '$apiBase/api/driver/nearby?lat=${_pickupPoint!.latitude}&lng=${_pickupPoint!.longitude}&radius=2',
    );
    
    // ✅ Add Authorization header
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
      // Optionally refresh token and retry
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
        backgroundColor: AppColors.surface,
        title: Text('Location Services Disabled', style: AppTextStyles.heading3),
        content: Text('Please enable location services to use this feature.',
            style: AppTextStyles.body2),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: AppColors.accent)),
          ),
          TextButton(
            onPressed: () => Geolocator.openLocationSettings(),
            child:
                Text('Open Settings', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _showLocationPermissionError() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title:
            Text('Location Permission Required', style: AppTextStyles.heading3),
        content: Text(
            'This app needs location permission to find nearby rides.',
            style: AppTextStyles.body2),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: AppColors.accent)),
          ),
          TextButton(
            onPressed: () => Geolocator.openAppSettings(),
            child:
                Text('Open Settings', style: TextStyle(color: AppColors.primary)),
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

 // Replace your _onPickupChanged method with this:
Future<void> _onPickupChanged(String value) async {
  debugPrint('🔍 Pickup changed: "$value"');
  
  // Don't clear the point immediately - let user type
  if (value.trim().isEmpty) {
    setState(() {
      _pickupPoint = null;
      _pickupAddress = '';
      _suggestions = [];
    });
    return;
  }

  // ✅ FIX: Don't return early for short input - just don't fetch yet
  if (value.trim().length < 2) {
    // Keep existing pickup point, just clear suggestions
    setState(() {
      _suggestions = [];
    });
    return;
  }

  // ✅ FIX: Allow re-searching even if it matches current address
  // This helps when user is editing or correcting the address
  
  // Fetch suggestions for pickup field
  await _fetchSuggestions(value);
}
 Future<void> _fetchSuggestions(String query) async {
  debugPrint('🔎 Fetching suggestions for: "$query"');
  
  if (query.trim().length < 2) {
    debugPrint('⚠️ Query too short, clearing suggestions');
    setState(() => _suggestions = []);
    return;
  }

  // ✅ FIX: Cancel previous debounce timer
  if (_debounce?.isActive ?? false) {
    debugPrint('⏸️ Canceling previous search');
    _debounce!.cancel();
  }

  // ✅ FIX: Use debounce for ALL fields (pickup and drop)
  _debounce = Timer(const Duration(milliseconds: 300), () async {
    try {
      debugPrint('🌐 Making API call to Google Places...');
      
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${Uri.encodeComponent(query)}'
        '&key=$googleMapsApiKey'
        '&location=${_pickupPoint?.latitude ?? 17.3850},${_pickupPoint?.longitude ?? 78.4867}'
        '&radius=20000',
      );

      debugPrint('📡 URL: $url');

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
        debugPrint('📦 Response data: $data');
        
        final status = data['status'];
        if (status != 'OK' && status != 'ZERO_RESULTS') {
          debugPrint('⚠️ API returned status: $status');
          if (status == 'REQUEST_DENIED') {
            debugPrint('❌ API key issue - check your Google Maps API key');
          }
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
          
          debugPrint('  - $description');
          
          String city = '';
          String state = '';
          String country = '';

          // ✅ FIX: Make details fetch optional - don't block on it
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
            // Continue anyway - we have the basic description
          }

          final suggestion = {
            'description': description,
            'place_id': placeId,
            'city': city,
            'state': state,
            'country': country,
          };

          // Group by location
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
        
        debugPrint('✅ Setting ${grouped.length} suggestions');
        
        if (mounted) {
          setState(() {
            _suggestions = grouped;
          });
        }
      } else {
        debugPrint('❌ HTTP Error: ${response.statusCode}');
        debugPrint('   Body: ${response.body}');
        
        // ✅ FIX: Show user-friendly error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Search failed: ${response.statusCode}'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error fetching suggestions: $e');
      
      // ✅ FIX: Fallback to history
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
  // ✅ FIX 1: Check prerequisites with better logging
  if (_distanceKm == null || _durationSec == null) {
    debugPrint('⚠️ Cannot fetch fares: distanceKm=$_distanceKm, durationSec=$_durationSec');
    return;
  }

  // ✅ FIX 2: Check location data
  if (_pickupState.isEmpty || _pickupCity.isEmpty) {
    debugPrint('⚠️ Missing location data: state=$_pickupState, city=$_pickupCity');
    // Don't return - we'll use defaults
  }

  debugPrint('');
  debugPrint('=' * 60);
  debugPrint('💰 FETCHING FARES');
  debugPrint('   Distance: ${_distanceKm!.toStringAsFixed(2)} km');
  debugPrint('   Duration: ${(_durationSec! / 60).toStringAsFixed(1)} min');
  debugPrint('   State: $_pickupState');
  debugPrint('   City: $_pickupCity');
  debugPrint('=' * 60);

  setState(() {
    _loadingFares = true;
    _fares.clear();
  });

  final vehiclesToFetch = (widget.vehicleType != null &&
          widget.vehicleType!.isNotEmpty)
      ? [widget.vehicleType!]
      : vehicleLabels.where((v) => v.isNotEmpty).toList();

  debugPrint('📋 Vehicles to fetch: $vehiclesToFetch');

  try {
    final results = await Future.wait(
      vehiclesToFetch.map((vehicleType) async {
        try {
          debugPrint('🔍 Fetching fare for vehicleType="$vehicleType"...');

          final requestBody = {
            'state': _pickupState,
            'city': _pickupCity,
            'vehicleType': vehicleType,
            'category': 'short',
            'distanceKm': _distanceKm,
            'durationMin': _durationSec! / 60,
          };

          debugPrint('📤 Request body: ${jsonEncode(requestBody)}');

          final response = await http.post(
            Uri.parse('$apiBase/api/fares/calc'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          ).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('⏱️ Timeout for $vehicleType');
              throw TimeoutException('Fare calculation timeout');
            },
          );

          debugPrint('📥 Response for $vehicleType: ${response.statusCode}');

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            debugPrint('📦 Response data: $data');
            
            final total = (data['total'] as num).toDouble();
            debugPrint('✅ API fare for $vehicleType = ₹$total');
            return MapEntry(vehicleType, total);
          } else if (response.statusCode == 404) {
            final defaultFare = _defaultFares[vehicleType] ?? 0.0;
            debugPrint('⚠️ Rate not found for $vehicleType, using default: ₹$defaultFare');
            return MapEntry(vehicleType, defaultFare);
          } else {
            debugPrint('❌ Failed response ${response.statusCode} for $vehicleType');
            debugPrint('   Body: ${response.body}');
            final defaultFare = _defaultFares[vehicleType] ?? 0.0;
            return MapEntry(vehicleType, defaultFare);
          }
        } on TimeoutException catch (e) {
          debugPrint('⏱️ Timeout for $vehicleType: $e');
          final defaultFare = _defaultFares[vehicleType] ?? 0.0;
          return MapEntry(vehicleType, defaultFare);
        } catch (e) {
          debugPrint('❌ Error fetching fare for $vehicleType: $e');
          final defaultFare = _defaultFares[vehicleType] ?? 0.0;
          return MapEntry(vehicleType, defaultFare);
        }
      }),
    );

    // ✅ FIX 3: Always add fares, even if 0 (for better debugging)
    setState(() {
      for (var entry in results) {
        _fares[entry.key] = entry.value;
        debugPrint('   Added: ${entry.key} = ₹${entry.value}');
      }
    });

    debugPrint('');
    debugPrint('💰 FINAL FARES LOADED:');
    _fares.forEach((key, value) {
      debugPrint('   $key: ₹$value');
    });
  debugPrint('=' * 60);
    debugPrint('');

    // ✅ FIX 4: Warn if all fares are 0
    if (_fares.values.every((fare) => fare == 0)) {
      debugPrint('⚠️ WARNING: All fares are 0! Check API or default fares.');
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

    // ✅ FIX 5: Auto-select vehicle if only one option
    if (_fares.length == 1 && _selectedVehicle == null) {
      setState(() {
        _selectedVehicle = _fares.keys.first;
        debugPrint('🎯 Auto-selected vehicle: $_selectedVehicle');
      });
    }

  } catch (e) {
    debugPrint('❌ Unexpected error in _fetchFares: $e');
    debugPrint('Stack trace: ${StackTrace.current}');
    
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
    debugPrint('✅ _loadingFares set to false');
  }
}

// Replace _confirmRide() with this:
// Replace your existing _confirmRide() method with this fixed version:

// Replace your existing _confirmRide() method with this fixed version:

// Replace your existing _confirmRide() method with this fixed version:

Future<void> _confirmRide() async {
  // ✅ FIX: Use widget.customerId instead of Firebase user
  // Since you're passing MongoDB _id from login, use that directly
    await _clearActiveTripId();

  // ✅ ADD DETAILED LOGGING
  debugPrint('=' * 50);
  debugPrint('🔍 CONFIRM RIDE - VALIDATION CHECK');
  debugPrint('Customer ID: ${widget.customerId}');
  debugPrint('Selected Vehicle: $_selectedVehicle');
  debugPrint('Pickup Point: $_pickupPoint');
  debugPrint('Drop Point: $_dropPoint');
  debugPrint('Fares Map: $_fares');
  debugPrint('Loading Fares: $_loadingFares');
  debugPrint('=' * 50);
  
  // ✅ FIX 1: Check if still loading fares
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
  
  // ✅ FIX 2: More specific error messages - Check customerId instead
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
  
  // ✅ FIX 3: Better fare validation with fallback
  final selectedFare = _fares[selected] ?? _defaultFares[selected] ?? 0.0;

  debugPrint('💰 FARE CALCULATION:');
  debugPrint('   Vehicle: $selected');
  debugPrint('   API Fare: ${_fares[selected]}');
  debugPrint('   Default Fare: ${_defaultFares[selected]}');
  debugPrint('   Final Fare: ₹$selectedFare');

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

  debugPrint("===========================================");
  debugPrint("💰 FARE DETAILS:");
  debugPrint("   Vehicle: $selected");
  debugPrint("   API fare: ${_fares[selected]}");
  debugPrint("   Default fare: ${_defaultFares[selected]}");
  debugPrint("   Final fare: ₹$selectedFare");
  debugPrint("   Source: ${_fares[selected] != null ? 'API (distance-based)' : 'DEFAULT (fallback)'}");
  debugPrint("===========================================");

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

  debugPrint("📤 Sending ride request: ${jsonEncode(rideData)}");

  try {
    // ✅ FIX 4: Add timeout to prevent hanging
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

    debugPrint('📥 Response Status: ${response.statusCode}');
    debugPrint('📥 Response Body: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      debugPrint("✅ Trip created: $data");

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
            debugPrint("Re-requesting trip: $_currentTripId");
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
            backgroundColor: _isWaitingForDriver ? Colors.green : Colors.orange,
          ),
        );
      }
    } else {
      debugPrint("❌ Trip API failed: ${response.statusCode} ${response.body}");
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
    debugPrint("❌ Request timeout: $e");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request timed out. Please check your connection.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } catch (e) {
    debugPrint("❌ Error calling trip API: $e");
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
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0A0A0F),
                  Color(0xFF1A1A24),
                  Color(0xFF0A0A0F),
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),
          AnimatedSwitcher(
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
          if (_isWaitingForDriver) _buildEnhancedWaitingOverlay(),
        ],
      ),
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
        Text(
          "Good ${_getTimeGreeting()}!",
          style: AppTextStyles.body2.copyWith(
            color: AppColors.onSurfaceTertiary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "Where are you going?",
          style: AppTextStyles.heading1.copyWith(fontSize: 28),
        ),
        const SizedBox(height: 8),
        Container(
          height: 3,
          width: 50,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.accent],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppColors.accent.withOpacity(0.3)),
                  ),
                  child: Text(
                    "Clear all",
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
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
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.2),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
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
                color: Colors.black.withOpacity(0.3),
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
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF1A1A24),
                    Color(0xFF0A0A0F),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
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
                      color: AppColors.onSurfaceTertiary,
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

  Widget _buildEnhancedWaitingOverlay() {
    return Positioned.fill(
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 20 * _pulseAnimation.value,
                  sigmaY: 20 * _pulseAnimation.value,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.background.withOpacity(0.7),
                        AppColors.surface.withOpacity(0.8),
                        AppColors.background.withOpacity(0.9),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppColors.primary.withOpacity(0.8),
                            AppColors.accent.withOpacity(0.6),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.7, 1.0],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary
                                .withOpacity(0.5 * _pulseAnimation.value),
                            blurRadius: 60 * _pulseAnimation.value,
                            spreadRadius: 20 * _pulseAnimation.value,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.surface,
                            border: Border.all(
                              color: AppColors.primary,
                              width: 3,
                            ),
                          ),
                          child: const Icon(
                            Icons.search,
                            size: 50,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 40),
                Text(
                  'Searching for drivers nearby...',
                  style: AppTextStyles.heading2.copyWith(
                    color: AppColors.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'This usually takes less than 30 seconds',
                  style: AppTextStyles.body2,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 60),
                _EnhancedCancelButton(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    setState(() => _isWaitingForDriver = false);
                    _rerequestTimer?.cancel();
                  },
                ),
              ],
            ),
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

// Enhanced UI Components

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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2A2A38),
            Color(0xFF1A1A24),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: 2,
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
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: AppColors.primary.withOpacity(0.3)),
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
                color: iconColor.withOpacity(0.15),
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
              child:TextField(
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
  onChanged: (value) {
    debugPrint('🔤 TextField changed: "$value" (${label})');
    onChanged(value);
  },
)
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
                  ? AppColors.accent.withOpacity(0.2)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isListening
                    ? AppColors.accent
                    : AppColors.primary.withOpacity(0.3),
                width: isListening ? 2 : 1,
              ),
              boxShadow: isListening
                  ? [
                      BoxShadow(
                        color: AppColors.accent
                            .withOpacity(0.5 * pulseAnimation.value),
                        blurRadius: 20 * pulseAnimation.value,
                        spreadRadius: 5 * pulseAnimation.value,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              isListening ? Icons.mic : Icons.mic_none,
              color: isListening ? AppColors.accent : AppColors.primary,
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
      separatorBuilder: (context, index) => const SizedBox(height: 10),
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
              margin: const EdgeInsets.only(bottom: 10),
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
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF2A2A38),
                Color(0xFF1A1A24),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primary.withOpacity(0.1),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.15),
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
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.2),
                    ),
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
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary.withOpacity(0.2),
                      AppColors.accent.withOpacity(0.1),
                    ],
                  )
                : const LinearGradient(
                    colors: [
                      Color(0xFF2A2A38),
                      Color(0xFF1A1A24),
                    ],
                  ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color:
                  selected ? AppColors.primary : AppColors.primary.withOpacity(0.1),
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withOpacity(0.2)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : AppColors.primary.withOpacity(0.2),
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
                            ? AppColors.primary.withOpacity(0.8)
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
                        color: AppColors.success.withOpacity(0.2),
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
          backgroundColor:
              isEnabled ? AppColors.primary : AppColors.surface,
          foregroundColor:
              isEnabled ? Colors.white : AppColors.onSurfaceTertiary,
          elevation: isEnabled ? 8 : 0,
          shadowColor: isEnabled ? AppColors.primary.withOpacity(0.5) : null,
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
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 12),
            ],
            Text(
              isEnabled
                  ? 'Book ${_capitalize(selectedVehicle!)} Now'
                  : 'Select a vehicle',
              style: AppTextStyles.button.copyWith(
                color: isEnabled ? Colors.white : AppColors.onSurfaceTertiary,
                fontSize: 18,
              ),
            ),
            if (isEnabled) ...[
              const SizedBox(width: 12),
              const Icon(
                Icons.arrow_forward,
                color: Colors.white,
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
    return Container(
      width: 280,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: AppColors.error.withOpacity(0.5),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.error.withOpacity(0.2),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.error.withOpacity(0.1),
                  AppColors.error.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.close,
                    color: AppColors.error,
                    size: 20,
                  ),
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
          ),
        ),
      ),
    );
  }
}