import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/socket_service.dart'; // Make sure the import path is correct

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
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  BitmapDescriptor? _bikeIcon;

  late LatLng _driverPosition;
  late LatLng _pickupPosition;
  late LatLng _dropPosition;

  @override
  void initState() {
    super.initState();

    // Extract initial locations from the passed details
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
  }

  @override
  void dispose() {
    // Clean up listeners to prevent memory leaks
    SocketService().off('driver:locationUpdate');
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadCustomMarkers() async {
    _bikeIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/images/bike.png', // Ensure you have this bike icon in your assets
    );
    _updateMarkers();
  }

  void _setupSocketListeners() {
    SocketService().on('driver:locationUpdate', (data) {
      if (!mounted) return;

      final lat = data['latitude'];
      final lng = data['longitude'];

      if (lat is num && lng is num) {
        setState(() {
          _driverPosition = LatLng(lat.toDouble(), lng.toDouble());
          _updateMarkers();
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(_driverPosition),
          );
        });
      }
    });
  }

  void _updateMarkers() {
    setState(() {
      _markers.clear();
      // Driver Marker with custom bike icon
      _markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: _driverPosition,
          icon: _bikeIcon ?? BitmapDescriptor.defaultMarker,
          anchor: const Offset(0.5, 0.5),
          flat: true,
        ),
      );
      // Pickup Marker
      _markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: _pickupPosition,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
      // Drop Marker
      _markers.add(
        Marker(
          markerId: const MarkerId('drop'),
          position: _dropPosition,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    // Fit map to show both driver and pickup
    Future.delayed(const Duration(milliseconds: 500), () {
      controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(
              _driverPosition.latitude <= _pickupPosition.latitude ? _driverPosition.latitude : _pickupPosition.latitude,
              _driverPosition.longitude <= _pickupPosition.longitude ? _driverPosition.longitude : _pickupPosition.longitude,
            ),
            northeast: LatLng(
              _driverPosition.latitude > _pickupPosition.latitude ? _driverPosition.latitude : _pickupPosition.latitude,
              _driverPosition.longitude > _pickupPosition.longitude ? _driverPosition.longitude : _pickupPosition.longitude,
            ),
          ),
          100.0, // Padding
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver is on the way'),
        backgroundColor: Colors.white,
        elevation: 1,
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
            myLocationButtonEnabled: false,
          ),
          // Bottom Driver Details Card
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
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: NetworkImage(
                    driver['photoUrl'] ?? 'https://via.placeholder.com/150',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driver['name'] ?? 'Driver',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${driver['vehicleBrand'] ?? 'Bike'} • ${driver['vehicleNumber'] ?? 'TS00AB0000'}',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 20),
                    Text(
                      (driver['rating'] ?? 4.8).toString(),
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                )
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () { /* TODO: Implement call logic */ },
                  icon: const Icon(Icons.call),
                  label: const Text('Call'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () { /* TODO: Implement cancel logic */ },
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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