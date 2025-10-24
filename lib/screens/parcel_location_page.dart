import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_china1/screens/driver_en_route_page.dart';
import '../services/socket_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

// Use the same color palette from RealHomePage
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

// ─────────────────────────────
// Screen 1 → Pickup
// ─────────────────────────────
class PickupScreen extends StatefulWidget {
  final String customerId;
  const PickupScreen({super.key, required this.customerId});

  @override
  State<PickupScreen> createState() => _PickupScreenState();
}

class _PickupScreenState extends State<PickupScreen> with TickerProviderStateMixin {
  String _pickupAddress = "Fetching current location...";
  String _dropAddress = "Search drop address";
  bool _isLoading = false;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
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

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoading = true);
    
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        setState(() {
          _pickupAddress = "Location permission denied";
          _isLoading = false;
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final address = [
          place.name,
          place.street,
          place.subLocality,
          place.locality,
          place.subAdministrativeArea,
          place.administrativeArea,
          place.postalCode,
        ].where((e) => e != null && e.isNotEmpty).join(", ");

        setState(() {
          _pickupAddress = address;
          _isLoading = false;
        });
      } else {
        setState(() {
          _pickupAddress = "Unable to fetch address";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _pickupAddress = "Error fetching location: $e";
        _isLoading = false;
      });
    }
  }

  void _swapLocations() {
    HapticFeedback.selectionClick();
    setState(() {
      final temp = _pickupAddress;
      _pickupAddress = _dropAddress;
      _dropAddress = temp;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
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
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPickupCard(),
                          const SizedBox(height: 20),
                          _buildDropCard(),
                          const SizedBox(height: 40),
                          _buildTermsSection(),
                        ],
                      ),
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

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
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
                    border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                  ),
                  child: const Icon(Icons.arrow_back, color: AppColors.onSurface, size: 24),
                ),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            "Send Anything, Anytime",
            style: AppTextStyles.body2.copyWith(color: AppColors.onSurfaceTertiary),
          ),
          const SizedBox(height: 4),
          Text(
            "Parcel Delivery",
            style: AppTextStyles.heading1.copyWith(fontSize: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildPickupCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2A38), Color(0xFF1A1A24)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.success.withOpacity(0.5)),
                ),
                child: const Icon(Icons.my_location, color: AppColors.success, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Pickup from current location",
                  style: AppTextStyles.heading3.copyWith(fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _isLoading
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                )
              : Text(
                  _pickupAddress,
                  style: AppTextStyles.body1.copyWith(fontSize: 14),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: _swapLocations,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.accent],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.swap_vert, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      "Switch",
                      style: AppTextStyles.button.copyWith(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2A38), Color(0xFF1A1A24)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.error.withOpacity(0.5)),
                ),
                child: const Icon(Icons.location_on, color: AppColors.error, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Drop to",
                  style: AppTextStyles.heading3.copyWith(fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () async {
              HapticFeedback.selectionClick();
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DropScreen(customerId: widget.customerId),
                ),
              );

              if (result != null && result is String) {
                setState(() => _dropAddress = result);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: AppColors.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _dropAddress,
                      style: AppTextStyles.body1.copyWith(fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, 
                    color: AppColors.onSurfaceTertiary, size: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTermsSection() {
    return Center(
      child: Column(
        children: [
          Text(
            "Learn more about prohibited items",
            style: AppTextStyles.caption.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 8),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              text: "By using our service, you agree to our ",
              style: AppTextStyles.caption.copyWith(fontSize: 13),
              children: [
                TextSpan(
                  text: "Terms & Conditions",
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────
// Screen 2 → Drop
// ─────────────────────────────

class DropScreen extends StatefulWidget {
  final String customerId;
  const DropScreen({super.key, required this.customerId});

  @override
  State<DropScreen> createState() => _DropScreenState();
}

class _DropScreenState extends State<DropScreen> with TickerProviderStateMixin {
  final TextEditingController dropCtl = TextEditingController();
  List<String> _recentSearches = [];
  List<String> _suggestions = [];
  late GoogleMapsPlaces _places;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _places = GoogleMapsPlaces(
      apiKey: "AIzaSyCqfjktNhxjKfM-JmpSwBk9KtgY429QWY8",
    );
    _loadSearchHistory();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    dropCtl.dispose();
    super.dispose();
  }

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _recentSearches = prefs.getStringList("recentSearches") ?? [];
    });
  }

  Future<void> _saveSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList("recentSearches", _recentSearches);
  }

  Future<void> _getSuggestions(String input) async {
    if (input.trim().isEmpty) {
      setState(() => _suggestions.clear());
      return;
    }

    final response = await _places.autocomplete(
      input,
      types: ["geocode"],
      components: [Component(Component.country, "in")],
    );

    if (response.isOkay && response.predictions.isNotEmpty) {
      setState(() {
        _suggestions = response.predictions
            .map((p) => p.description ?? "")
            .where((d) => d.isNotEmpty)
            .toList();
      });
    } else {
      setState(() => _suggestions.clear());
    }
  }

  void _selectLocation(String? location) async {
    if (location == null || location.isEmpty) return;

    HapticFeedback.selectionClick();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      ),
    );

    if (!_recentSearches.contains(location)) {
      _recentSearches.insert(0, location);
      if (_recentSearches.length > 10) {
        _recentSearches.removeLast();
      }
      await _saveSearchHistory();
    }

    Navigator.pop(context);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ParcelLocationPage(
          customerId: widget.customerId,
          pickupText: location,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTyping = dropCtl.text.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
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
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                _buildHeader(),
                _buildSearchBar(),
                Expanded(child: _buildLocationsList(isTyping)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
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
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: const Icon(Icons.arrow_back, color: AppColors.onSurface, size: 24),
            ),
          ),
          const SizedBox(width: 16),
          Text("Drop to", style: AppTextStyles.heading2.copyWith(fontSize: 20)),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A2A38), Color(0xFF1A1A24)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.1),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.error.withOpacity(0.3)),
              ),
              child: const Icon(Icons.location_on, color: AppColors.error, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: dropCtl,
                style: AppTextStyles.body1.copyWith(fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Search drop location',
                  hintStyle: AppTextStyles.body1.copyWith(
                    color: AppColors.onSurfaceTertiary,
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: _getSuggestions,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationsList(bool isTyping) {
    final items = isTyping ? _suggestions : _recentSearches;
    
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final location = items[index];
        
        return TweenAnimationBuilder<double>(
          duration: Duration(milliseconds: 100 + (index * 50)),
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(20 * (1 - value), 0),
              child: Opacity(
                opacity: value,
                child: _buildLocationCard(location, isTyping),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLocationCard(String location, bool isFromSearch) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _selectLocation(location),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2A2A38), Color(0xFF1A1A24)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withOpacity(0.1)),
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
                    color: isFromSearch 
                        ? AppColors.primary.withOpacity(0.15)
                        : AppColors.onSurfaceTertiary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isFromSearch 
                          ? AppColors.primary.withOpacity(0.3)
                          : AppColors.onSurfaceTertiary.withOpacity(0.3),
                    ),
                  ),
                  child: Icon(
                    isFromSearch ? Icons.place : Icons.history,
                    color: isFromSearch ? AppColors.primary : AppColors.onSurfaceTertiary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    location,
                    style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, 
                  color: AppColors.onSurfaceTertiary, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────
// Screen 3 → Parcel Location Page
// ─────────────────────────────

class ParcelLocationPage extends StatefulWidget {
  final String? pickupText;
  final String customerId;

  const ParcelLocationPage({
    super.key,
    this.pickupText,
    required this.customerId,
  });

  @override
  State<ParcelLocationPage> createState() => _ParcelLocationPageState();
}

class _ParcelLocationPageState extends State<ParcelLocationPage> 
    with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  LatLng? _currentPosition;
  LatLng? _dropPosition;
  bool _showDetailsCard = true;
  bool _showFareCard = false;
  Map<String, dynamic>? _fareData;

  final String _apiKey = "AIzaSyCqfjktNhxjKfM-JmpSwBk9KtgY429QWY8";

  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  File? _parcelPhoto;
  bool _isSubmitting = false;

  String? _currentTripId;
  bool _isWaitingForDriver = false;
  Map<String, dynamic>? _driverDetails;

  late AnimationController _cardSlideController;
  late Animation<Offset> _cardSlideAnimation;

  bool get allInputsFilled {
    return _nameController.text.isNotEmpty &&
        _phoneController.text.isNotEmpty &&
        _weightController.text.isNotEmpty &&
        _parcelPhoto != null;
  }

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _fetchCurrentLocation();
    _setupSocketListeners();
  }

  void _initializeAnimations() {
    _cardSlideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _cardSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _cardSlideController, curve: Curves.easeOutCubic),
    );
    _cardSlideController.forward();
  }

  @override
  void dispose() {
    _cardSlideController.dispose();
    _weightController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    SocketService().disconnect();
    super.dispose();
  }

  void _setupSocketListeners() {
    final socketService = SocketService();
    socketService.connect("https://7668d252ef1d.ngrok-free.app");
    socketService.connectCustomer(customerId: widget.customerId);

    socketService.on('trip:accepted', (data) {
      print("📢 Trip accepted: $data");
      final driverDetails = data['driver'] ?? data['driverDetails'] ?? {};
      final tripDetails = data['trip'] ?? data['tripDetails'] ?? {};

      if (driverDetails.isEmpty || tripDetails.isEmpty) {
        print("⚠️ Missing driver/trip details in trip:accepted: $data");
      }

      if (!mounted) return;

      setState(() {
        _isWaitingForDriver = false;
        _driverDetails = driverDetails;
        _currentTripId = tripDetails['tripId']?.toString();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Driver accepted your parcel delivery!", 
            style: AppTextStyles.body1),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DriverEnRoutePage(
            driverDetails: driverDetails,
            tripDetails: tripDetails,
          ),
        ),
      );
    });

    socketService.onTripRejectedBySystem((data) {
      print("Trip rejected: $data");
      if (data['tripId'] == _currentTripId && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Looking for another driver...", 
              style: AppTextStyles.body1),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  Future<void> _pickParcelPhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      HapticFeedback.selectionClick();
      setState(() {
        _parcelPhoto = File(pickedFile.path);
      });
    }
  }

  Future<void> _fetchFare() async {
    if (_currentPosition == null || _dropPosition == null) {
      print("⚠️ Pickup or drop not set yet");
      return;
    }

    try {
      double finalDistance = 0.1;

      try {
        final distanceMeters = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          _dropPosition!.latitude,
          _dropPosition!.longitude,
        );

        double distanceKm = (distanceMeters / 1000).abs();

        if (distanceKm.isNaN || distanceKm.isInfinite) {
          print("⚠️ Distance calculation invalid, fallback to 0.1 km");
          distanceKm = 0.1;
        }

        finalDistance = distanceKm < 0.1 ? 0.1 : distanceKm;
      } catch (e) {
        print("⚠️ Error calculating distance: $e. Using fallback 0.1 km");
        finalDistance = 0.1;
      }

      print("📏 Distance: $finalDistance km");

      final weight = double.tryParse(_weightController.text) ?? 1;

      final body = {
        "state": "Telangana",
        "city": "Hyderabad",
        "distanceKm": finalDistance,
        "vehicleType": "bike",
        "weight": weight,
        "category": "parcel",
      };

      final url = Uri.parse("https://7668d252ef1d.ngrok-free.app/api/parcels/estimate");

      final res = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        print("✅ Fare Response: $data");

        setState(() {
          _fareData = data;
          _showDetailsCard = false;
          _showFareCard = true;
        });
      } else {
        print("❌ Fare API Error: ${res.statusCode} - ${res.body}");
      }
    } catch (e) {
      print("🔥 Fare fetch failed: $e");
    }
  }

  Future<void> _bookParcel() async {
    if (!allInputsFilled || _currentPosition == null || _dropPosition == null) {
      print("Missing inputs");
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isSubmitting = true);

    try {
      final url = Uri.parse("https://7668d252ef1d.ngrok-free.app/api/trip/parcel");
      
      final distanceMeters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        _dropPosition!.latitude,
        _dropPosition!.longitude,
      );
      final distanceKm = (distanceMeters / 1000).abs();
      final finalDistance = distanceKm < 0.1 ? 0.1 : distanceKm;
      
      final user = FirebaseAuth.instance.currentUser;

      final tripData = {
        "customerId": user?.phoneNumber?.replaceAll('+91', '') ?? user?.uid,
        "vehicleType": "bike",
        "pickup": {
          "coordinates": [_currentPosition!.longitude, _currentPosition!.latitude],
          "address": "Current Location"
        },
        "drop": {
          "coordinates": [_dropPosition!.longitude, _dropPosition!.latitude], 
          "address": widget.pickupText ?? "Drop Location"
        },
        "parcelDetails": {
          "weight": _weightController.text,
          "receiverName": _nameController.text,
          "receiverPhone": _phoneController.text,
          "notes": "Handle with care",
        },
        "fare": _fareData?['cost'] ?? 0,
        "paymentMethod": "cod"
      };

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(tripData),
      );

      print("Response: ${response.statusCode} - ${response.body}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        print("Trip created: $responseData");
        
        _currentTripId = responseData['tripId'];
        
        setState(() {
          _isWaitingForDriver = responseData['drivers'] > 0;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                responseData['drivers'] > 0 
                  ? "Searching for nearby drivers..."
                  : "No drivers available right now",
                style: AppTextStyles.body1,
              ),
              backgroundColor: responseData['drivers'] > 0 
                  ? AppColors.success 
                  : AppColors.warning,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        print("Booking failed: ${response.statusCode} - ${response.body}");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Failed to book parcel. Please try again.", 
                style: AppTextStyles.body1),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      print("Error booking parcel: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Network error. Please check your connection.", 
              style: AppTextStyles.body1),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _currentPosition == null
          ? Container(
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
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Loading map...",
                      style: AppTextStyles.body1,
                    ),
                  ],
                ),
              ),
            )
          : Stack(
              children: [
                GoogleMap(
                  onMapCreated: _onMapCreated,
                  initialCameraPosition: CameraPosition(
                    target: _currentPosition!,
                    zoom: 14,
                  ),
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  style: '''
                    [
                      {
                        "elementType": "geometry",
                        "stylers": [{"color": "#242f3e"}]
                      },
                      {
                        "elementType": "labels.text.fill",
                        "stylers": [{"color": "#746855"}]
                      },
                      {
                        "elementType": "labels.text.stroke",
                        "stylers": [{"color": "#242f3e"}]
                      }
                    ]
                  ''',
                ),
                Positioned(
                  top: 50,
                  left: 24,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.arrow_back, 
                        color: AppColors.onSurface, size: 24),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SlideTransition(
                    position: _cardSlideAnimation,
                    child: _isWaitingForDriver 
                        ? _buildWaitingCard()
                        : _showDetailsCard
                            ? _buildDropDetailsCard()
                            : _showFareCard
                                ? _buildFareCard()
                                : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildWaitingCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2A38), Color(0xFF1A1A24)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
          const SizedBox(height: 20),
          Text(
            "Looking for nearby drivers...",
            style: AppTextStyles.heading3.copyWith(fontSize: 18),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            "Trip ID: $_currentTripId",
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }

  Widget _buildDropDetailsCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2A38), Color(0xFF1A1A24)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Parcel Details", 
              style: AppTextStyles.heading3.copyWith(fontSize: 20)),
            const SizedBox(height: 20),

            _buildStyledTextField(
              controller: _nameController,
              hint: "Receiver Name*",
              icon: Icons.person,
            ),
            const SizedBox(height: 16),

            _buildStyledTextField(
              controller: _phoneController,
              hint: "Phone Number*",
              icon: Icons.phone,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),

            _buildStyledTextField(
              controller: _weightController,
              hint: "Parcel Weight (kg)*",
              icon: Icons.scale,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),

            GestureDetector(
              onTap: _pickParcelPhoto,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _parcelPhoto != null 
                      ? AppColors.success.withOpacity(0.1)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _parcelPhoto != null 
                        ? AppColors.success.withOpacity(0.5)
                        : AppColors.primary.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _parcelPhoto != null ? Icons.check_circle : Icons.photo_camera,
                      color: _parcelPhoto != null 
                          ? AppColors.success 
                          : AppColors.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _parcelPhoto != null 
                          ? "Photo Added ✓" 
                          : "Add Parcel Photo*",
                      style: AppTextStyles.body1.copyWith(
                        color: _parcelPhoto != null 
                            ? AppColors.success 
                            : AppColors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            Text("Quick Tags", style: AppTextStyles.body2),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildChip("Home", Icons.home),
                _buildChip("Work", Icons.work),
                _buildChip("Gym", Icons.fitness_center),
                _buildChip("College", Icons.school),
                _buildChip("Hostel", Icons.hotel),
              ],
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: allInputsFilled ? _fetchFare : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: allInputsFilled 
                      ? AppColors.primary 
                      : AppColors.surface,
                  disabledBackgroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: allInputsFilled ? 8 : 0,
                  shadowColor: AppColors.primary.withOpacity(0.3),
                ),
                child: Text(
                  "Confirm drop details",
                  style: AppTextStyles.button.copyWith(
                    color: allInputsFilled 
                        ? Colors.white 
                        : AppColors.onSurfaceTertiary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFareCard() {
    if (_fareData == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2A38), Color(0xFF1A1A24)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Parcel Fare", style: AppTextStyles.heading3.copyWith(fontSize: 18)),
          const SizedBox(height: 20),
          
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              "₹${_fareData!['cost'] ?? _fareData!['total'] ?? '0'}",
              style: AppTextStyles.heading1.copyWith(
                fontSize: 36,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: allInputsFilled && !_isSubmitting ? _bookParcel : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                disabledBackgroundColor: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 8,
                shadowColor: AppColors.success.withOpacity(0.3),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      "Confirm & Book",
                      style: AppTextStyles.button.copyWith(color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStyledTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: AppTextStyles.body1,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: AppColors.primary),
          hintText: hint,
          hintStyle: AppTextStyles.body1.copyWith(
            color: AppColors.onSurfaceTertiary,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildChip(String label, IconData icon) => Chip(
        label: Text(
          label,
          style: AppTextStyles.caption.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        avatar: Icon(icon, size: 16, color: AppColors.primary),
        backgroundColor: AppColors.surface,
        side: BorderSide(color: AppColors.primary.withOpacity(0.3)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      );

  // Map & Location Methods

  Future<void> _fetchCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;

      final currentPos = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentPosition = currentPos;
        _markers.add(
          Marker(
            markerId: const MarkerId("pickup"),
            position: currentPos,
            infoWindow: const InfoWindow(title: "Pickup"),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          ),
        );
      });

      if (widget.pickupText != null && widget.pickupText!.isNotEmpty) {
        await _getDropCoordinates(widget.pickupText!);
      }
    } catch (e) {
      print("🔥 Error in _fetchCurrentLocation: $e");
    }
  }

  Future<void> _getDropCoordinates(String address) async {
    try {
      final url = Uri.parse(
        "https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(address)}&key=$_apiKey",
      );
      final response = await http.get(url);
      final data = json.decode(response.body);

      if (data["status"] == "OK") {
        final loc = data["results"][0]["geometry"]["location"];
        final dropPos = LatLng(loc["lat"], loc["lng"]);

        setState(() {
          _dropPosition = dropPos;
          _markers.add(
            Marker(
              markerId: const MarkerId("drop"),
              position: dropPos,
              infoWindow: InfoWindow(title: address),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            ),
          );
        });

        await _drawRoute();
      }
    } catch (e) {
      print("🔥 Error in _getDropCoordinates: $e");
    }
  }

  Future<void> _drawRoute() async {
    if (_currentPosition == null || _dropPosition == null) return;

    final url = Uri.parse(
      "https://maps.googleapis.com/maps/api/directions/json"
      "?origin=${_currentPosition!.latitude},${_currentPosition!.longitude}"
      "&destination=${_dropPosition!.latitude},${_dropPosition!.longitude}"
      "&key=$_apiKey",
    );

    try {
      final response = await http.get(url);
      final data = json.decode(response.body);

      if (data["status"] == "OK" && data["routes"].isNotEmpty) {
        final points = _decodePolyline(data["routes"][0]["overview_polyline"]["points"]);

        setState(() {
          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: const PolylineId("route"),
              color: AppColors.primary,
              width: 5,
              points: points,
            ),
          );
        });

        LatLng sw = LatLng(
          (_currentPosition!.latitude <= _dropPosition!.latitude)
              ? _currentPosition!.latitude
              : _dropPosition!.latitude,
          (_currentPosition!.longitude <= _dropPosition!.longitude)
              ? _currentPosition!.longitude
              : _dropPosition!.longitude,
        );

        LatLng ne = LatLng(
          (_currentPosition!.latitude > _dropPosition!.latitude)
              ? _currentPosition!.latitude
              : _dropPosition!.latitude,
          (_currentPosition!.longitude > _dropPosition!.longitude)
              ? _currentPosition!.longitude
              : _dropPosition!.longitude,
        );

        final bounds = LatLngBounds(southwest: sw, northeast: ne);

        if (_mapController != null) {
          try {
            if (sw.latitude == ne.latitude || sw.longitude == ne.longitude) {
              await _mapController!.animateCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(target: _currentPosition!, zoom: 16),
                ),
              );
            } else {
              await _mapController!.animateCamera(
                CameraUpdate.newLatLngBounds(bounds, 60),
              );
            }
          } catch (e) {
            print("🔥 Camera update failed: $e");
          }
        }
      }
    } catch (e) {
      print("🔥 Error in _drawRoute: $e");
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> polyline = [];
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

      polyline.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return polyline;
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }}