import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

const String googleMapsApiKey = 'AIzaSyB7VstS4RZlou2jyNgzkKePGqNbs2MyzYY';

class AppColors {
  static const Color primary = Color.fromARGB(255, 212, 120, 0);
  static const Color background = Colors.white;
  static const Color onSurface = Colors.black;
  static const Color surface = Color(0xFFF5F5F5);
  static const Color onPrimary = Colors.white;
  static const Color onSurfaceSecondary = Colors.black54;
  static const Color onSurfaceTertiary = Colors.black38;
  static const Color divider = Color(0xFFEEEEEE);
  static const Color success = Color.fromARGB(255, 0, 66, 3);
  static const Color warning = Color(0xFFFFA000);
  static const Color error = Color(0xFFD32F2F);
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
        color: AppColors.onPrimary,
      );
}

class ManualPickupLocationPage extends StatefulWidget {
  final gmaps.LatLng initialLocation;
  final String initialAddress;

  const ManualPickupLocationPage({
    Key? key,
    required this.initialLocation,
    required this.initialAddress,
  }) : super(key: key);

  @override
  State<ManualPickupLocationPage> createState() => _ManualPickupLocationPageState();
}

class _ManualPickupLocationPageState extends State<ManualPickupLocationPage>
    with SingleTickerProviderStateMixin {
  late gmaps.GoogleMapController _mapController;
  late gmaps.LatLng _currentLocation;
  String _currentAddress = '';
  bool _isLoadingAddress = false;
  bool _isDragging = false;
  Timer? _debounceTimer;
  
  late AnimationController _pinAnimationController;
  late Animation<double> _pinAnimation;

  @override
  void initState() {
    super.initState();
    _currentLocation = widget.initialLocation;
    _currentAddress = widget.initialAddress;
    
    // Pin drop animation
    _pinAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    
    _pinAnimation = Tween<double>(begin: -50, end: 0).animate(
      CurvedAnimation(
        parent: _pinAnimationController,
        curve: Curves.elasticOut,
      ),
    );
    
    _pinAnimationController.forward();
  }

  @override
  void dispose() {
    _pinAnimationController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onCameraMove(gmaps.CameraPosition position) {
    if (!_isDragging) {
      setState(() {
        _isDragging = true;
      });
    }
    
    _currentLocation = position.target;
    
    // Cancel previous timer
    _debounceTimer?.cancel();
  }

  void _onCameraIdle() {
    setState(() {
      _isDragging = false;
    });
    
    // Debounce address lookup - wait 500ms after user stops moving map
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _updateAddress(_currentLocation);
    });
    
    // Animate pin drop
    _pinAnimationController.reset();
    _pinAnimationController.forward();
  }

  Future<void> _updateAddress(gmaps.LatLng location) async {
    setState(() {
      _isLoadingAddress = true;
    });

    try {
      // Try geocoding package first
      List<Placemark> placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      ).timeout(const Duration(seconds: 3));

      if (placemarks.isNotEmpty) {
        Placemark placemark = placemarks.first;
        setState(() {
          _currentAddress = '${placemark.street}, ${placemark.locality}, ${placemark.administrativeArea}';
          _isLoadingAddress = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('Geocoding package failed: $e');
    }

    // Fallback to Google Maps API
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=${location.latitude},${location.longitude}&key=$googleMapsApiKey',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List?;

        if (results != null && results.isNotEmpty) {
          setState(() {
            _currentAddress = results[0]['formatted_address'] as String;
            _isLoadingAddress = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('Google Maps API failed: $e');
    }

    setState(() {
      _currentAddress = 'Unable to fetch address';
      _isLoadingAddress = false;
    });
  }

  Future<void> _getCurrentLocation() async {
    try {
      HapticFeedback.selectionClick();
      
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showLocationError('Location services are disabled');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showLocationError('Location permission denied');
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final newLocation = gmaps.LatLng(position.latitude, position.longitude);

      _mapController.animateCamera(
        gmaps.CameraUpdate.newLatLngZoom(newLocation, 16),
      );
    } catch (e) {
      _showLocationError('Failed to get location: $e');
    }
  }

  void _showLocationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _confirmLocation() {
    HapticFeedback.mediumImpact();
    
    Navigator.pop(context, {
      'location': _currentLocation,
      'address': _currentAddress,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Google Map
          gmaps.GoogleMap(
            onMapCreated: (controller) {
              _mapController = controller;
              // Set map style for better visibility
              controller.setMapStyle('''
                [
                  {
                    "featureType": "poi",
                    "elementType": "labels",
                    "stylers": [{"visibility": "off"}]
                  }
                ]
              ''');
            },
            initialCameraPosition: gmaps.CameraPosition(
              target: _currentLocation,
              zoom: 16,
              tilt: 0,
            ),
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            minMaxZoomPreference: const gmaps.MinMaxZoomPreference(10, 20),
          ),

          // Center Pin Marker (moves with map)
          Center(
            child: AnimatedBuilder(
              animation: _pinAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, _isDragging ? -20 : _pinAnimation.value),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Shadow below pin
                      AnimatedOpacity(
                        opacity: _isDragging ? 0.3 : 0.6,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          width: _isDragging ? 50 : 30,
                          height: _isDragging ? 50 : 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Pin Icon
                      Transform.translate(
                        offset: const Offset(0, -40),
                        child: AnimatedScale(
                          scale: _isDragging ? 1.2 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            Icons.location_on,
                            size: 50,
                            color: AppColors.primary,
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Top Header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.5),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Back Button
                      Material(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        elevation: 4,
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            Navigator.pop(context);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            child: const Icon(
                              Icons.arrow_back,
                              color: AppColors.onSurface,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Title
                      Expanded(
                        child: Material(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                          elevation: 4,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Set Pickup Location',
                                  style: AppTextStyles.body1.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Move map to adjust',
                                  style: AppTextStyles.caption,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // My Location Button
          Positioned(
            right: 16,
            top: MediaQuery.of(context).padding.top + 140,
            child: Material(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              elevation: 4,
              child: InkWell(
                onTap: _getCurrentLocation,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: const Icon(
                    Icons.my_location,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),

          // Bottom Address Card & Confirm Button
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag Handle
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title
                          Text(
                            'Pickup Location',
                            style: AppTextStyles.heading3.copyWith(fontSize: 20),
                          ),
                          const SizedBox(height: 16),
                          
                          // Address Card
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: AppColors.success.withOpacity(0.3),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.location_on,
                                    color: AppColors.success,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _isLoadingAddress
                                      ? Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              height: 16,
                                              width: double.infinity,
                                              decoration: BoxDecoration(
                                                color: AppColors.divider,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Container(
                                              height: 14,
                                              width: 150,
                                              decoration: BoxDecoration(
                                                color: AppColors.divider,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                            ),
                                          ],
                                        )
                                      : Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _currentAddress,
                                              style: AppTextStyles.body1.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Lat: ${_currentLocation.latitude.toStringAsFixed(6)}, '
                                              'Lng: ${_currentLocation.longitude.toStringAsFixed(6)}',
                                              style: AppTextStyles.caption,
                                            ),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 20),
                          
                          // Confirm Button
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: _isLoadingAddress ? null : _confirmLocation,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.onPrimary,
                                elevation: 8,
                                shadowColor: AppColors.primary.withOpacity(0.3),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                disabledBackgroundColor: AppColors.surface,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (!_isLoadingAddress) ...[
                                    const Icon(
                                      Icons.check_circle,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  Text(
                                    _isLoadingAddress
                                        ? 'Loading address...'
                                        : 'Confirm Pickup Location',
                                    style: AppTextStyles.button.copyWith(
                                      fontSize: 16,
                                    ),
                                  ),
                                  if (!_isLoadingAddress) ...[
                                    const SizedBox(width: 12),
                                    const Icon(
                                      Icons.arrow_forward,
                                      size: 24,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 8),
                          
                          // Hint Text
                          Center(
                            child: Text(
                              'Drag the map to adjust your exact location',
                              style: AppTextStyles.caption.copyWith(fontSize: 11),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Loading Indicator when dragging
          if (_isDragging)
            Positioned(
              top: MediaQuery.of(context).padding.top + 100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
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
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.onPrimary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Updating location...',
                        style: AppTextStyles.body2.copyWith(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
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
}