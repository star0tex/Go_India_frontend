import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:math';
import 'dart:ui' as ui;
import '../services/socket_service.dart';
import '../screens/chat_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String apiBase = 'https://7668d252ef1d.ngrok-free.app';
const String googleMapsApiKey = 'AIzaSyB7VstS4RZlou2jyNgzkKePGqNbs2MyzYY'; // ✅ Your API key

// --- MATCHING COLOR PALETTE ---
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
  static const Color serviceCardBg = Color.fromARGB(255, 238, 216, 189);
}

// --- MATCHING TYPOGRAPHY ---
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

class DriverEnRoutePage extends StatefulWidget {
  final Map<String, dynamic> driverDetails;
  final Map<String, dynamic> tripDetails;

  const DriverEnRoutePage({
    Key? key,
    required this.driverDetails,
    required this.tripDetails,
  }) : super(key: key);

  @override
  _DriverEnRoutePageState createState() => _DriverEnRoutePageState();
}

class _DriverEnRoutePageState extends State<DriverEnRoutePage> {
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double p = 0.017453292519943295;
    final double a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * 1000 * asin(sqrt(a));
  }

  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  BitmapDescriptor? _bikeIcon;
  String? rideCode;
  String rideStatus = 'driver_coming';
  
  late LatLng _driverPosition;
  LatLng? _previousDriverPosition; // ✅ Track previous position for bearing
  late LatLng _pickupPosition;
  late LatLng _dropPosition;
  Timer? _locationTimer;
  double? _driverDistance;
  int? _estimatedMinutes;
  double? finalFare;
  double _currentBearing = 0.0; // ✅ Store bearing for rotation

  @override
  void initState() {
    super.initState();

    rideCode = widget.tripDetails['rideCode']?.toString();
    debugPrint('🔍 Initial rideCode from tripDetails: $rideCode');
    
    _driverPosition = LatLng(
      widget.driverDetails['location']['lat'],
      widget.driverDetails['location']['lng'],
    );
    _pickupPosition = LatLng(
      widget.tripDetails['pickup']['lat'],
      widget.tripDetails['pickup']['lng'],
    );
    _dropPosition = LatLng(
      widget.tripDetails['drop']['lat'],
      widget.tripDetails['drop']['lng'],
    );

    _loadCustomMarkers();
    _setupSocketListeners();

    _locationTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchDriverLocation();
    });
    _drawPolyline();
    _updateDriverDistance();
  }

  @override
  void dispose() {
    SocketService().off('driver:locationUpdate');
    SocketService().off('trip:accepted');
    SocketService().off('trip:ride_started');
    SocketService().off('trip:completed');
    SocketService().off('trip:cancelled');
    SocketService().off('trip:cash_collected');
    _locationTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // ✅ FIXED: Proper bike marker loading with custom size
  Future<void> _loadCustomMarkers() async {
    try {
      final ByteData data = await rootBundle.load('assets/images/bikelive.png');
      final ui.Codec codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: 120, // ✅ Increase size to 120px (was 64px)
        targetHeight: 120,
      );
      final ui.FrameInfo fi = await codec.getNextFrame();
      final ByteData? markerData = await fi.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      
      if (markerData != null) {
        _bikeIcon = BitmapDescriptor.fromBytes(markerData.buffer.asUint8List());
        debugPrint('✅ Bike marker loaded successfully (120x120)');
      }
    } catch (e) {
      debugPrint('❌ Error loading bike marker: $e');
      // Fallback to default marker
      _bikeIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    }
    _updateMarkers();
  }

  void _setupSocketListeners() {
    SocketService().on('driver:locationUpdate', (data) {
      if (!mounted) return;
      debugPrint('📍 Driver location update: $data');
      
      final lat = data['latitude'];
      final lng = data['longitude'];
      if (lat is num && lng is num) {
        setState(() {
          _previousDriverPosition = _driverPosition; // ✅ Store old position
          _driverPosition = LatLng(lat.toDouble(), lng.toDouble());
          
          // ✅ Calculate bearing for rotation
          if (_previousDriverPosition != null) {
            _currentBearing = _calculateBearing(
              _previousDriverPosition!.latitude,
              _previousDriverPosition!.longitude,
              _driverPosition.latitude,
              _driverPosition.longitude,
            );
          }
          
          _updateMarkers();
          _drawPolyline(); // ✅ Redraw route with new position
          _updateDriverDistance();
          
          // Smooth camera movement
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(_driverPosition),
          );
        });
      }
    });

    SocketService().on('trip:accepted', (data) {
      if (!mounted) return;
      debugPrint('🔔 Received trip:accepted event with data: $data');
      
      final receivedRideCode = data['rideCode']?.toString();
      if (receivedRideCode != null && receivedRideCode.isNotEmpty) {
        setState(() {
          rideCode = receivedRideCode;
        });
        debugPrint('✅ Ride code updated to: $rideCode');
      }
    });

    SocketService().on('trip:cancelled', (data) {
      if (!mounted) return;
      
      debugPrint('🚫 Trip cancelled: $data');
      
      final cancelledBy = data['cancelledBy'] ?? 'unknown';
      final message = cancelledBy == 'customer' 
          ? 'Customer cancelled the trip'
          : 'Trip has been cancelled';
      
      SharedPreferences.getInstance().then((prefs) {
        prefs.remove('active_trip_id');
        debugPrint('🗑️ Cleared cached trip ID');
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message, style: const TextStyle(color: AppColors.onPrimary)),
            backgroundColor: AppColors.warning,
            duration: const Duration(seconds: 3),
          ),
        );
        
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        });
      }
    });

    SocketService().on('trip:ride_started', (data) {
      if (!mounted) return;
      debugPrint('🚗 Ride started: $data');
      
      setState(() {
        rideStatus = 'ride_started';
      });
      
      _drawPolyline(); // ✅ Redraw to show route to destination
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Ride started! Heading to destination', 
            style: TextStyle(color: AppColors.onPrimary)),
          backgroundColor: AppColors.success,
        ),
      );
    });

    SocketService().on('trip:completed', (data) {
      if (!mounted) return;
      debugPrint('✅ Ride completed: $data');
      
      final fare = data['fare'];
      setState(() {
        rideStatus = 'completed';
        finalFare = fare is num ? fare.toDouble() : double.tryParse(fare?.toString() ?? '0');
      });
      
      _showCompletionDialog();
    });

    SocketService().on('trip:cash_collected', (data) async {
      if (!mounted) return;
      
      debugPrint('💰 Payment confirmed - clearing state');
      
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('active_trip_id');
        debugPrint('🗑️ Cleared cached trip ID');
      } catch (e) {
        debugPrint('❌ Error clearing trip ID: $e');
      }
      
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      Navigator.of(context).popUntil((route) => route.isFirst);
      
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? 'Payment confirmed. Thank you!',
                style: const TextStyle(color: AppColors.onPrimary)),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      });
    });
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          backgroundColor: AppColors.background,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Ride Completed! 🎉', style: AppTextStyles.heading3),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, color: AppColors.success, size: 64),
              ),
              const SizedBox(height: 16),
              Text(
                'Total Fare: ₹${finalFare?.toStringAsFixed(2) ?? '0.00'}',
                style: AppTextStyles.heading2,
              ),
              const SizedBox(height: 8),
              Text(
                'Waiting for driver to collect payment...',
                style: AppTextStyles.body2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ Calculate bearing between two points for marker rotation
  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = (lon2 - lon1) * pi / 180;
    final lat1Rad = lat1 * pi / 180;
    final lat2Rad = lat2 * pi / 180;
    
    final y = sin(dLon) * cos(lat2Rad);
    final x = cos(lat1Rad) * sin(lat2Rad) -
        sin(lat1Rad) * cos(lat2Rad) * cos(dLon);
    
    final bearing = atan2(y, x) * 180 / pi;
    return (bearing + 360) % 360; // Normalize to 0-360
  }

  void _updateMarkers() {
    setState(() {
      _markers.clear();
      
      // ✅ Driver marker with proper size and rotation
      _markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: _driverPosition,
          icon: _bikeIcon ?? BitmapDescriptor.defaultMarker,
          anchor: const Offset(0.5, 0.5), // Center the marker
          flat: true, // Keep flat on map for smooth rotation
          rotation: _currentBearing, // ✅ Rotate based on direction
          zIndex: 10, // ✅ Keep on top
        ),
      );
      
      // Pickup marker (only show if ride not started)
      if (rideStatus == 'driver_coming') {
        _markers.add(
          Marker(
            markerId: const MarkerId('pickup'),
            position: _pickupPosition,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: const InfoWindow(title: 'Pickup Location'),
          ),
        );
      }
      
      // Drop marker
      _markers.add(
        Marker(
          markerId: const MarkerId('drop'),
          position: _dropPosition,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Drop Location'),
        ),
      );
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    Future.delayed(const Duration(milliseconds: 500), () {
      _fitMapBounds();
    });
  }

  void _fitMapBounds() {
    if (_mapController == null) return;
    
    LatLng target = rideStatus == 'ride_started' ? _dropPosition : _pickupPosition;
    
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            min(_driverPosition.latitude, target.latitude) - 0.005,
            min(_driverPosition.longitude, target.longitude) - 0.005,
          ),
          northeast: LatLng(
            max(_driverPosition.latitude, target.latitude) + 0.005,
            max(_driverPosition.longitude, target.longitude) + 0.005,
          ),
        ),
        100.0, // Padding
      ),
    );
  }

  Future<void> _fetchDriverLocation() async {
    // Socket updates handled in _setupSocketListeners
  }

  // ✅ FIXED: Now fetches REAL routes from Google Directions API
  Future<void> _drawPolyline() async {
    _polylines.clear();
    
    LatLng destination;
    String routeId;
    Color routeColor;
    
    if (rideStatus == 'driver_coming') {
      // Driver to pickup - REAL route (not straight line)
      destination = _pickupPosition;
      routeId = 'driver_to_pickup';
      routeColor = AppColors.primary;
    } else {
      // Driver to drop - REAL route
      destination = _dropPosition;
      routeId = 'driver_to_drop';
      routeColor = AppColors.success;
    }
    
    debugPrint('🔄 Fetching route from Directions API...');
    debugPrint('   From: ${_driverPosition.latitude}, ${_driverPosition.longitude}');
    debugPrint('   To: ${destination.latitude}, ${destination.longitude}');
    
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${_driverPosition.latitude},${_driverPosition.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&mode=driving'
        '&key=$googleMapsApiKey'
      );
      
      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('⏱️ Directions API timeout');
          throw TimeoutException('Request timeout');
        },
      );
      
      debugPrint('📥 Directions API response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        
        debugPrint('   Status: ${data['status']}');
        
        if (data['status'] == 'OK' && data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final polylinePoints = route['overview_polyline']['points'] as String;
          final List<LatLng> routeCoordinates = _decodePolyline(polylinePoints);
          
          if (routeCoordinates.isNotEmpty) {
            debugPrint('✅ Route decoded: ${routeCoordinates.length} points');
            
            setState(() {
              _polylines.add(
                Polyline(
                  polylineId: PolylineId(routeId),
                  color: routeColor,
                  width: 6,
                  points: routeCoordinates,
                  geodesic: true, // ✅ Follow earth's curvature
                  startCap: Cap.roundCap,
                  endCap: Cap.roundCap,
                  jointType: JointType.round,
                ),
              );
            });
            
            // ✅ Update distance and time from route data
            if (route['legs'] != null && (route['legs'] as List).isNotEmpty) {
              final leg = route['legs'][0];
              final distanceMeters = leg['distance']['value'] as num;
              final durationSeconds = leg['duration']['value'] as num;
              
              setState(() {
                _driverDistance = distanceMeters / 1000;
                _estimatedMinutes = (durationSeconds / 60).round();
                if (_estimatedMinutes! < 1) _estimatedMinutes = 1;
              });
              
              debugPrint('   Distance: ${_driverDistance!.toStringAsFixed(2)} km');
              debugPrint('   Duration: $_estimatedMinutes min');
            }
            
            return;
          }
        } else if (data['status'] == 'ZERO_RESULTS') {
          debugPrint('⚠️ No route found between points');
        } else if (data['status'] == 'REQUEST_DENIED') {
          debugPrint('❌ API key issue: ${data['error_message']}');
        } else {
          debugPrint('⚠️ Unexpected status: ${data['status']}');
        }
      } else {
        debugPrint('❌ HTTP error: ${response.statusCode}');
        debugPrint('   Body: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Error fetching route: $e');
    }
    
    // ✅ Fallback to straight line if API fails
    debugPrint('⚠️ Using fallback straight line');
    setState(() {
      _polylines.add(
        Polyline(
          polylineId: PolylineId(routeId),
          color: routeColor,
          width: 5,
          points: [_driverPosition, destination],
          geodesic: true,
          patterns: [
            PatternItem.dash(20),
            PatternItem.gap(10),
          ], // Dashed to indicate fallback
        ),
      );
    });
    
    // Calculate straight-line distance for fallback
    _updateDriverDistance();
  }

  // ✅ Decode Google's encoded polyline format
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

  void _updateDriverDistance() {
    LatLng targetLocation = rideStatus == 'ride_started' ? _dropPosition : _pickupPosition;
    
    final double distanceMeters = _calculateDistance(
      _driverPosition.latitude,
      _driverPosition.longitude,
      targetLocation.latitude,
      targetLocation.longitude,
    );
    
    setState(() {
      _driverDistance = distanceMeters / 1000;
      _estimatedMinutes = ((distanceMeters / 1000) / 30 * 60).round();
      if (_estimatedMinutes! < 1) _estimatedMinutes = 1;
    });
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch phone dialer')),
        );
      }
    }
  }

  void _openChat() async {
    final prefs = await SharedPreferences.getInstance();
    final currentCustomerId = prefs.getString('customerId') ?? '';
    
    final String? tripId = widget.tripDetails['tripId']?.toString();
    final String? driverId = widget.driverDetails['id']?.toString();
    
    if (tripId == null || driverId == null || currentCustomerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open chat. Missing details.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          tripId: tripId,
          senderId: currentCustomerId,
          receiverId: driverId,
          receiverName: widget.driverDetails['name'] ?? 'Driver',
          isDriver: false,
        ),
      ),
    );
  }

  void _cancelRide() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Cancel Ride?', style: AppTextStyles.heading3),
        content: Text(
          'Are you sure you want to cancel this ride?',
          style: AppTextStyles.body1,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'No',
              style: AppTextStyles.body1.copyWith(color: AppColors.onSurfaceSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              
              try {
                final prefs = await SharedPreferences.getInstance();
                final customerId = prefs.getString('customerId') ?? '';
                final tripId = widget.tripDetails['tripId']?.toString();
                
                if (tripId != null && customerId.isNotEmpty) {
                  final response = await http.post(
                    Uri.parse('$apiBase/api/trip/cancel'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({
                      'tripId': tripId,
                      'cancelledBy': customerId,
                    }),
                  );
                  
                  if (response.statusCode == 200) {
                    debugPrint('✅ Trip cancelled successfully');
                    
                    await prefs.remove('active_trip_id');
                    
                    Navigator.of(context).popUntil((route) => route.isFirst);
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Ride cancelled successfully',
                          style: TextStyle(color: AppColors.onPrimary)),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  } else {
                    debugPrint('❌ Failed to cancel trip: ${response.statusCode}');
                    throw Exception('Failed to cancel trip');
                  }
                }
              } catch (e) {
                debugPrint('❌ Error cancelling trip: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to cancel trip: $e'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
            child: Text(
              'Yes, Cancel',
              style: AppTextStyles.button.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          rideStatus == 'ride_started' ? 'On the way to destination' : 'Driver is on the way',
          style: AppTextStyles.heading3,
        ),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: _driverPosition,
              zoom: 15,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationButtonEnabled: false,
            myLocationEnabled: true,
            compassEnabled: true,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
            rotateGesturesEnabled: true,
            scrollGesturesEnabled: true,
            tiltGesturesEnabled: false,
            zoomGesturesEnabled: true,
          ),
          _buildDriverCard(),
        ],
      ),
    );
  }

  Widget _buildDriverCard() {
    final driver = widget.driverDetails;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.all(0),
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
          mainAxisSize: MainAxisSize.min,
          children: [
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
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primary,
                            width: 3,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 35,
                          backgroundImage: NetworkImage(
                            driver['photoUrl'] ?? 'https://via.placeholder.com/150',
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              driver['name'] ?? 'Driver',
                              style: AppTextStyles.heading2.copyWith(fontSize: 20),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.star,
                                  color: AppColors.primary,
                                  size: 18,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  (driver['rating'] ?? 4.8).toString(),
                                  style: AppTextStyles.body1.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.call, color: AppColors.onPrimary),
                          iconSize: 24,
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            final phone = driver['phone'] ?? driver['phoneNumber'];
                            if (phone != null && phone.toString().isNotEmpty) {
                              _makePhoneCall(phone.toString());
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Phone number not available'),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.chat_bubble_outline, 
                            color: AppColors.onPrimary),
                          iconSize: 24,
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            _openChat();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  if (rideCode != null && rideStatus == 'driver_coming')
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: AppColors.serviceCardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.primary, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Your OTP to start the ride',
                            style: AppTextStyles.body2,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            rideCode!,
                            style: AppTextStyles.heading1.copyWith(
                              fontSize: 36,
                              letterSpacing: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  if (rideCode != null && rideStatus == 'driver_coming') 
                    const SizedBox(height: 20),

                  if (rideStatus == 'ride_started')
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.success, width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.directions_car, 
                              color: AppColors.success, 
                              size: 28
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ride in Progress',
                                  style: AppTextStyles.body1.copyWith(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Heading to destination',
                                  style: AppTextStyles.body2.copyWith(
                                    color: AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  if (rideStatus == 'ride_started')
                    const SizedBox(height: 20),

                  Text(
                    'Bike No. ${driver['vehicleNumber'] ?? '1234'}',
                    style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w600),
                  ),
                 
                  const SizedBox(height: 24),
                  
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                rideStatus == 'ride_started' 
                                    ? 'Time to Destination'
                                    : 'Driver Arriving In',
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.onPrimary.withOpacity(0.9),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _estimatedMinutes != null
                                    ? '$_estimatedMinutes min'
                                    : 'Calculating...',
                                style: AppTextStyles.heading2.copyWith(
                                  color: AppColors.onPrimary,
                                  fontSize: 28,
                                ),
                              ),
                              if (_driverDistance != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${_driverDistance!.toStringAsFixed(1)} km away',
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.onPrimary.withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (rideStatus == 'driver_coming')
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              _cancelRide();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.onPrimary.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.onPrimary,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                'Cancel',
                                style: AppTextStyles.button.copyWith(
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}