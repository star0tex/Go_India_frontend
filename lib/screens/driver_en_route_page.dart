import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:math';
import '../services/socket_service.dart';
import '../screens/chat_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  String rideStatus = 'driver_coming'; // 'driver_coming', 'ride_started', 'completed'
  
  late LatLng _driverPosition;
  late LatLng _pickupPosition;
  late LatLng _dropPosition;
  Timer? _locationTimer;
  double? _driverDistance;
  int? _estimatedMinutes;
  double? finalFare;

  @override
  void initState() {
    super.initState();

    rideCode = widget.tripDetails['rideCode']?.toString();
    print('🔍 Initial rideCode from tripDetails: $rideCode');
    
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
    _locationTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadCustomMarkers() async {
    _bikeIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/images/bikelive.png',
    );
    _updateMarkers();
  }

  void _setupSocketListeners() {
    // Listen for driver location updates
    SocketService().on('driver:locationUpdate', (data) {
      if (!mounted) return;
      print('📍 Driver location update: $data');
      
      final lat = data['latitude'];
      final lng = data['longitude'];
      if (lat is num && lng is num) {
        setState(() {
          _driverPosition = LatLng(lat.toDouble(), lng.toDouble());
          _updateMarkers();
          _drawPolyline();
          _updateDriverDistance();
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(_driverPosition),
          );
        });
      }
    });

    // Listen for ride code/OTP if not already received
    SocketService().on('trip:accepted', (data) {
      if (!mounted) return;
      print('🔔 Received trip:accepted event with data: $data');
      
      final receivedRideCode = data['rideCode']?.toString();
      if (receivedRideCode != null && receivedRideCode.isNotEmpty) {
        setState(() {
          rideCode = receivedRideCode;
        });
        print('✅ Ride code updated to: $rideCode');
      }
    });

    // Listen for ride started event
    SocketService().on('trip:ride_started', (data) {
      if (!mounted) return;
      print('🚗 Ride started: $data');
      
      setState(() {
        rideStatus = 'ride_started';
      });
      
      // Update polyline from driver to drop location
      _drawPolyline();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ride started! Heading to destination')),
      );
    });

    // Listen for ride completed event
    SocketService().on('trip:completed', (data) {
      if (!mounted) return;
      print('✅ Ride completed: $data');
      
      final fare = data['fare'];
      setState(() {
        rideStatus = 'completed';
        finalFare = fare is num ? fare.toDouble() : double.tryParse(fare?.toString() ?? '0');
      });
      
      // Show completion dialog
      _showCompletionDialog();
    });
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Ride Completed! 🎉'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            Text(
              'Total Fare: ₹${finalFare?.toStringAsFixed(2) ?? '0.00'}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Thank you for riding with us!'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Go back to home
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _updateMarkers() {
    setState(() {
      _markers.clear();
      
      // Driver marker with bike icon
      _markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: _driverPosition,
          icon: _bikeIcon ?? BitmapDescriptor.defaultMarker,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          rotation: _calculateBearing(),
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

  double _calculateBearing() {
    // Calculate bearing for bike icon rotation
    return 0.0; // You can implement bearing calculation if needed
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
            _driverPosition.latitude <= target.latitude
                ? _driverPosition.latitude
                : target.latitude,
            _driverPosition.longitude <= target.longitude
                ? _driverPosition.longitude
                : target.longitude,
          ),
          northeast: LatLng(
            _driverPosition.latitude > target.latitude
                ? _driverPosition.latitude
                : target.latitude,
            _driverPosition.longitude > target.longitude
                ? _driverPosition.longitude
                : target.longitude,
          ),
        ),
        100.0,
      ),
    );
  }

  Future<void> _fetchDriverLocation() async {
    // Socket updates handled in _setupSocketListeners
  }

  Future<void> _drawPolyline() async {
  _polylines.clear();
  
  if (rideStatus == 'driver_coming') {
    // Driver to pickup - simple straight line is fine
    _polylines.add(
      Polyline(
        polylineId: const PolylineId('driver_to_pickup'),
        color: const Color(0xFFFFA726),
        width: 5,
        points: [_driverPosition, _pickupPosition],
      ),
    );
    setState(() {});
  } else if (rideStatus == 'ride_started') {
    // Driver to drop - use Google Directions API for actual route
    await _drawRouteToDestination();
  }
}

Future<void> _drawRouteToDestination() async {
  print('🔄 Fetching route from Directions API...');
  
  try {
    final String apiKey = 'AIzaSyCqfjktNhxjKfM-JmpSwBk9KtgY429QWY8';
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${_driverPosition.latitude},${_driverPosition.longitude}'
      '&destination=${_dropPosition.latitude},${_dropPosition.longitude}'
      '&mode=driving'
      '&key=$apiKey'
    );
    
    final response = await http.get(uri);
    
    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      
      if (data['status'] == 'OK' && data['routes'] != null && (data['routes'] as List).isNotEmpty) {
        final route = data['routes'][0];
        final polylinePoints = route['overview_polyline']['points'] as String;
        final List<LatLng> routeCoordinates = _decodePolyline(polylinePoints);
        
        if (routeCoordinates.isNotEmpty) {
          setState(() {
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('driver_to_drop'),
                color: Colors.blue,
                width: 6,
                points: routeCoordinates,
                geodesic: true,
              ),
            );
          });
          
          print('✅ Route polyline drawn with ${routeCoordinates.length} points');
          return;
        }
      }
    }
  } catch (e) {
    print('❌ Error fetching route: $e');
  }
  
  // Fallback to straight line
  setState(() {
    _polylines.add(
      Polyline(
        polylineId: const PolylineId('driver_to_drop'),
        color: Colors.blue,
        width: 5,
        points: [_driverPosition, _dropPosition],
      ),
    );
  });
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
        ),
      ),
    );
  }

  void _cancelRide() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF2A2520)
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Cancel Ride?',
          style: GoogleFonts.poppins(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to cancel this ride?',
          style: GoogleFonts.poppins(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white70
                : Colors.black54,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'No',
              style: GoogleFonts.poppins(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ride cancelled')),
              );
            },
            child: Text(
              'Yes, Cancel',
              style: GoogleFonts.poppins(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      appBar: AppBar(
        title: Text(
          rideStatus == 'ride_started' ? 'On the way to destination' : 'Driver is on the way',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: _driverPosition,
              zoom: 16,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationButtonEnabled: false,
            myLocationEnabled: true,
          ),
          _buildDriverCard(isDark),
        ],
      ),
    );
  }

  Widget _buildDriverCard(bool isDark) {
    final driver = widget.driverDetails;
    final cardColor = isDark ? const Color(0xFF2A2520) : const Color(0xFFFFF8E1);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.white70 : Colors.black54;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.all(0),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, -5),
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
                color: isDark ? Colors.white24 : Colors.black26,
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
                            color: const Color(0xFFFFA726),
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
                              style: GoogleFonts.poppins(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.star,
                                  color: Color(0xFFFFA726),
                                  size: 18,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  (driver['rating'] ?? 4.8).toString(),
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: textColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF4A3820) : const Color(0xFF8B6914),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.call, color: Color(0xFFFFA726)),
                          iconSize: 28,
                          onPressed: () {
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
                          color: isDark ? const Color(0xFF4A3820) : const Color(0xFF8B6914),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFFFFA726)),
                          iconSize: 28,
                          onPressed: _openChat,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // Show OTP only when driver is coming and ride not started
                  if (rideCode != null && rideStatus == 'driver_coming')
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF3D2F1F) : Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade600, width: 1.5)
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Your OTP to start the ride',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: subtitleColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            rideCode!,
                            style: GoogleFonts.poppins(
                              fontSize: 36,
                              color: textColor,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  if (rideCode != null && rideStatus == 'driver_coming') 
                    const SizedBox(height: 20),

                  // Ride status indicator
                  if (rideStatus == 'ride_started')
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade600, width: 1.5)
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.directions_car, color: Colors.green, size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Ride in Progress\nHeading to destination',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  if (rideStatus == 'ride_started')
                    const SizedBox(height: 20),

                  Text(
                    'Bike No. ${driver['vehicleNumber'] ?? '1234'}',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      color: subtitleColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                 
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF3D2F1F) : const Color(0xFF8B6914),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rideStatus == 'ride_started' 
                                  ? 'Estimated Time to Destination'
                                  : 'Estimated Time of Arrival',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: isDark ? Colors.white70 : Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _estimatedMinutes != null
                                  ? '$_estimatedMinutes Mins'
                                  : 'Calculating...',
                              style: GoogleFonts.poppins(
                                fontSize: 24,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (rideStatus == 'driver_coming')
                          GestureDetector(
                            onTap: _cancelRide,
                            child: Text(
                              'Cancel Ride',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                color: const Color(0xFFFFA726),
                                fontWeight: FontWeight.bold,
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