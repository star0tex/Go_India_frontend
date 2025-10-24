
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

const String googleMapsApiKey = 'YOUR_API_KEY_HERE'; // Replace with your key

// --- NEW COLOR PALETTE (60-30-10) ---
class AppColors {
  // Core palette based on 60-30-10 rule
  static const Color primary = Color.fromARGB(255, 212, 120, 0); // 30% Dark Green
  static const Color background = Colors.white;     // 60% White
  static const Color onSurface = Colors.black;      // 10% Black

  // Derived & Utility Colors
  static const Color surface = Color(0xFFF5F5F5); // Light gray for cards/inputs
  static const Color onPrimary = Colors.white;      // Text color on primary background
  static const Color onSurfaceSecondary = Colors.black54; // For less important text
  static const Color onSurfaceTertiary = Colors.black38;  // For hints and captions
  static const Color divider = Color(0xFFEEEEEE);   // Light gray for dividers

  // Standard Status Colors
  static const Color success = Color.fromARGB(255, 0, 66, 3); // A green that complements the primary
  static const Color warning = Color(0xFFFFA000);
  static const Color error = Color(0xFFD32F2F);
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
        color: AppColors.onSurface, // Black (for light bg buttons)
      );
}

class RealHomePage extends StatefulWidget {
  final String customerId;

  const RealHomePage({super.key, required this.customerId});

  @override
  State<RealHomePage> createState() => _RealHomePageState();
}

class _RealHomePageState extends State<RealHomePage>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  final PageController _pageController = PageController();

  // Animation Controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;

  final TextEditingController _dropController = TextEditingController();
  late final stt.SpeechToText _speech;

  String name = '';
  String phone = '';
  String mongoCustomerId = '';
  List<Map<String, dynamic>> locationHistory = [];

  double? _currentLat;
  double? _currentLng;
  String _currentAddress = '';
  String _currentLocationDisplay = 'Getting location...';
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounce;
  bool _isLocationLoading = true;
  bool _isLocationError = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _checkOldUser();
    _speech = stt.SpeechToText();

    mongoCustomerId = widget.customerId;
    _fetchUserProfile();
    _loadCachedLocation();
    _getCurrentLocation();
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

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _dropController.dispose();
    _speech.stop();
    _debounce?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _checkOldUser() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool? isOldUser = prefs.getBool('isOldUser');
    if (isOldUser == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Welcome back!", style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary)),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      });
    }
  }

  // --- Other methods like _loadCachedLocation, _getCurrentLocation, etc. remain the same ---
  // ... (All backend and logic functions are unchanged)

    Future<void> _loadCachedLocation() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? cachedAddress = prefs.getString('cached_pickup_address');
      double? cachedLat = prefs.getDouble('cached_pickup_lat');
      double? cachedLng = prefs.getDouble('cached_pickup_lng');

      if (cachedAddress != null && cachedLat != null && cachedLng != null) {
        setState(() {
          _currentAddress = cachedAddress;
          _currentLat = cachedLat;
          _currentLng = cachedLng;
          _isLocationLoading = false;
          _currentLocationDisplay = _formatLocationDisplay(cachedAddress);
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
      if (_currentLat != null) await prefs.setDouble('cached_pickup_lat', _currentLat!);
      if (_currentLng != null) await prefs.setDouble('cached_pickup_lng', _currentLng!);
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
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentLat = position.latitude;
        _currentLng = position.longitude;
      });

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark placemark = placemarks.first;
        String address = '${placemark.street}, ${placemark.locality}, ${placemark.administrativeArea}';
        setState(() {
          _currentAddress = address;
          _isLocationLoading = false;
          _isLocationError = false;
          _currentLocationDisplay = _formatLocationDisplay(address);
        });
        _cacheCurrentLocation();
      }
    } catch (e) {
      debugPrint('Error getting current location: $e');
      setState(() {
        _isLocationLoading = false;
        _isLocationError = true;
      });
    }
  }

  String _formatLocationDisplay(String address) {
    final parts = address.split(',');
    if (parts.length >= 2) {
      return '${parts[0].trim()}, ${parts[1].trim()}';
    }
    return address.length > 25 ? '${address.substring(0, 25)}...' : address;
  }
Future<void> _fetchUserProfile() async {
  try {
    if (widget.customerId.isEmpty) {
      debugPrint("Cannot fetch profile: customerId is empty");
      return;
    }
    
    var res = await http.get(
      Uri.parse('https://7668d252ef1d.ngrok-free.app/api/user/id/${widget.customerId}')
    );
    
    if (res.statusCode == 200) {
      final user = json.decode(res.body)['user'];
      setState(() {
        name = user['name'] ?? '';
        phone = user['phone'] ?? '';
        mongoCustomerId = user['_id'];
      });
      await _loadLocationHistory();
    } else {
      debugPrint("Failed to fetch profile: ${res.statusCode}");
    }
  } catch (e) {
    debugPrint("Failed to fetch profile: $e");
  }
}
 Future<void> _loadLocationHistory() async {
  if (phone.isEmpty) {
    debugPrint("Phone not available yet, skipping location history load");
    return;
  }
  
  final prefs = await SharedPreferences.getInstance();
  final key = 'location_history_$phone';
  final rawList = prefs.getStringList(key) ?? [];
  setState(() {
    locationHistory = rawList.map((e) {
      try {
        return jsonDecode(e) as Map<String, dynamic>;
      } catch (_) {
        return {'address': e};
      }
    }).toList();
  });
}
  Future<void> _saveToHistory(String address, {double? lat, double? lng}) async {
    const invalidTerms = ['bike', 'auto', 'car', 'premium', 'xl'];
    if (invalidTerms.any((term) => address.toLowerCase().contains(term))) return;
if (phone.isEmpty) {
    debugPrint("⚠️ Phone not set yet, cannot save to history");
    return;
  }
    final prefs = await SharedPreferences.getInstance();
    final key = 'location_history_${phone.isNotEmpty ? phone : 'unknown'}';
    locationHistory.removeWhere((item) => item['address'] == address);
    locationHistory.insert(0, {
      'address': address,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
    if (locationHistory.length > 10) {
      locationHistory = locationHistory.sublist(0, 10);
    }
    await prefs.setStringList(key, locationHistory.map((e) => jsonEncode(e)).toList());
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
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query'
          '&key=$googleMapsApiKey'
          '&location=$_currentLat,$_currentLng'
          '&radius=20000',
        );

        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final predictions = data['predictions'] as List?;

          if (predictions != null) {
            setState(() {
              _suggestions = predictions.map<Map<String, dynamic>>((prediction) {
                return {
                  'description': prediction['description'] as String,
                  'place_id': prediction['place_id'] as String,
                };
              }).toList();
            });
          }
        }
      } catch (e) {
        setState(() {
          _suggestions = locationHistory
              .where((item) => (item['address'] ?? '').toLowerCase().contains(query.toLowerCase()))
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
      _dropController.text = description;
      double? lat = suggestion['lat'] as double?;
      double? lng = suggestion['lng'] as double?;
      if (lat != null && lng != null) {
        _navigateToShortTripWithDrop(description, dropLat: lat, dropLng: lng);
      } else {
        await _geocodeAndNavigate(description);
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
        SnackBar(
          content: Text('Failed to get location details: $e', style: const TextStyle(color: AppColors.onPrimary)),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _navigateToShortTripWithDrop(String dropAddress, {double? dropLat, double? dropLng}) {
    if (_currentLat == null || _currentLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please wait while we get your location', style: const TextStyle(color: AppColors.onSurface)),
          backgroundColor: AppColors.warning,
        ),
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
            entryMode: 'search',
            customerId: mongoCustomerId,
          ),
        ),
      ).then((_) => _fetchUserProfile());
    } else {
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
                entryMode: 'search',
                customerId: mongoCustomerId,
              ),
            ),
          ).then((_) => _fetchUserProfile());
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to geocode address: $e', style: const TextStyle(color: AppColors.onPrimary)),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _navigateToShortTrip(String vehicleType) {
    if (_currentLat == null || _currentLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please wait while we get your location', style: const TextStyle(color: AppColors.onSurface)),
          backgroundColor: AppColors.warning,
        ),
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
          ),
          customerId: mongoCustomerId,
        ),
      ),
    ).then((_) => _fetchUserProfile());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background, // Set to white
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
          HapticFeedback.selectionClick();
        },
        children: [
          _buildHomePage(),
          const RideHistoryPage(),
          _buildPaymentsPage(),
          const ProfilePage(),
        ],
      ),
      bottomNavigationBar: _buildEnhancedBottomNav(),
    );
  }

  Widget _buildHomePage() {
    return SafeArea(
      child: FadeTransition(
        opacity: _fadeController,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
              .animate(_slideController),
          child: CustomScrollView(
            slivers: [
              _buildEnhancedHeader(),
              _buildSearchBar(),
              if (_suggestions.isNotEmpty) _buildSuggestionsList(),
              if (_suggestions.isEmpty) ...[
                _buildServicesSection(),
                _buildPromotionsSection(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEnhancedHeader() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildHeaderButton(Icons.menu),
                const Spacer(),
                _buildHeaderButton(Icons.notifications_outlined),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              "Good ${_getTimeGreeting()}!",
              style: AppTextStyles.body2,
            ),
            const SizedBox(height: 4),
            Text(
              "Where are you going?",
              style: AppTextStyles.heading1.copyWith(fontSize: 28),
            ),
            const SizedBox(height: 12),
            _buildLocationChip(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderButton(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Icon(icon, color: AppColors.onSurface, size: 24),
    );
  }

  Widget _buildLocationChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.my_location, color: AppColors.success, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Current Location", style: AppTextStyles.caption),
                const SizedBox(height: 2),
                Text(
                  _isLocationLoading ? 'Getting location...' : _currentLocationDisplay,
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.divider),
          ),
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.search, color: AppColors.onPrimary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _dropController,
                  style: AppTextStyles.body1,
                  decoration: InputDecoration(
                    hintText: 'Search for a destination',
                    hintStyle: AppTextStyles.body1.copyWith(color: AppColors.onSurfaceTertiary),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
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
    );
  }

  Widget _buildSuggestionsList() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final suggestion = _suggestions[index];
            return _EnhancedSuggestionCard(
              suggestion: suggestion,
              onTap: () => _selectSuggestion(suggestion),
            );
          },
          childCount: _suggestions.length,
        ),
      ),
    );
  }

  Widget _buildServicesSection() {
    final services = [
      {'label': 'Car', 'image': 'assets/images/car.png', 'type': 'car'},
      {'label': 'Auto', 'image': 'assets/images/auto.png', 'type': 'auto'},
      {'label': 'Bike', 'image': 'assets/images/bike.png', 'type': 'bike'},
      {'label': 'Parcel', 'image': 'assets/images/parcel.png', 'type': 'parcel'},
    ];

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Quick Services", style: AppTextStyles.heading2),
                GestureDetector(
                  onTap: _showAllServices,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Text(
                          "View All",
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.onPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward, color: AppColors.onPrimary, size: 14),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: services.map((service) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: _EnhancedServiceCard(
                      label: service['label'] as String,
                      image: service['image'] as String,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        if (service['type'] == 'parcel') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PickupScreen(customerId: widget.customerId),
                            ),
                          ).then((_) => _fetchUserProfile());
                        } else {
                          _navigateToShortTrip(service['type'] as String);
                        }
                      },
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromotionsSection() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Special Offers", style: AppTextStyles.heading2),
            const SizedBox(height: 20),
            _EnhancedPromoCard(
              title: "Save 20% on first ride!",
              subtitle: "Use code: WELCOME",
              icon: Icons.local_taxi,
              color: AppColors.primary,
            ),
            const SizedBox(height: 16),
            _EnhancedPromoCard(
              title: "Send parcels easily!",
              subtitle: "Fast & reliable delivery",
              icon: Icons.local_shipping,
              color: AppColors.success,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentsPage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.divider)
            ),
            child: const Icon(Icons.credit_card, size: 64, color: AppColors.primary),
          ),
          const SizedBox(height: 24),
          Text("Payments", style: AppTextStyles.heading2),
          const SizedBox(height: 8),
          Text("Coming soon!", style: AppTextStyles.body2),
        ],
      ),
    );
  }

  Widget _buildEnhancedBottomNav() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildBottomNavItem(Icons.home, 'Home', 0),
          _buildBottomNavItem(Icons.track_changes, 'Activity', 1),
          _buildBottomNavItem(Icons.credit_card, 'Payments', 2),
          _buildBottomNavItem(Icons.person_outline, 'Profile', 3),
        ],
      ),
    );
  }

  Widget _buildBottomNavItem(IconData icon, String label, int index) {
    final isActive = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? AppColors.primary : AppColors.onSurfaceTertiary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: isActive ? AppColors.primary : AppColors.onSurfaceTertiary,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTimeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }

    void _showAllServices() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background, // White background
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (ctx) {
        return Container(
          height: 500,
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
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('All Services', style: AppTextStyles.heading2),
              ),
              Expanded(
                child: GridView.count(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  crossAxisCount: 3,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.85,
                  children: [
                    _buildModalServiceCard('Car', 'assets/images/car.png', () {
                      Navigator.pop(ctx);
                      _navigateToShortTrip('car');
                    }),
                    _buildModalServiceCard('Auto', 'assets/images/auto.png', () {
                      Navigator.pop(ctx);
                      _navigateToShortTrip('auto');
                    }),
                    _buildModalServiceCard('Bike', 'assets/images/bike.png', () {
                      Navigator.pop(ctx);
                      _navigateToShortTrip('bike');
                    }),
                    _buildModalServiceCard('Parcel', 'assets/images/parcel.png', () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ParcelLocationPage(customerId: widget.customerId),
                        ),
                      );
                    }),
                    _buildModalServiceCard('Premium', 'assets/images/premium.png', () {
                      Navigator.pop(ctx);
                      _navigateToShortTrip('premium');
                    }),
                    _buildModalServiceCard('XL', 'assets/images/xl.png', () {
                      Navigator.pop(ctx);
                      _navigateToShortTrip('xl');
                    }),
                    _buildModalServiceCard('Car Trip', 'assets/images/cartrip.jpg', () {
                      Navigator.pop(ctx);
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                        ),
                        builder: (_) => CarTripAgreementSheet(customerId: widget.customerId),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModalServiceCard(String label, String imagePath, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
                 boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(imagePath, fit: BoxFit.contain),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: AppTextStyles.body2, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// --- UPDATED UI COMPONENTS ---

class _EnhancedSuggestionCard extends StatelessWidget {
  final Map<String, dynamic> suggestion;
  final VoidCallback onTap;

  const _EnhancedSuggestionCard({required this.suggestion, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.location_on, color: AppColors.onPrimary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    suggestion['description'],
                    style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: AppColors.onSurfaceTertiary, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EnhancedServiceCard extends StatelessWidget {
  final String label;
  final String image;
  final VoidCallback onTap;

  const _EnhancedServiceCard({required this.label, required this.image, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            height: 70,
            width: 90,
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 238, 216, 189),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(image, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _EnhancedPromoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _EnhancedPromoCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: AppTextStyles.heading3.copyWith(color: AppColors.onPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTextStyles.body2.copyWith(color: AppColors.onPrimary.withOpacity(0.9)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.onPrimary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 40, color: AppColors.onPrimary),
          ),
        ],
      ),
    );
  }
}