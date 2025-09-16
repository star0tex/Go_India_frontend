import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
//import 'package:geolocator/geolocator.dart';

/* ─── config ─── */
const _BASE = 'http://192.168.1.12:5002';

class ParcelLiveTrackingPage extends StatefulWidget {
  final String customerId;
  const ParcelLiveTrackingPage({super.key, required this.customerId});

  @override
  State<ParcelLiveTrackingPage> createState() => _ParcelLiveTrackingPageState();
}

class _ParcelLiveTrackingPageState extends State<ParcelLiveTrackingPage> {
  GoogleMapController? mapController;
  LatLng? driverLocation;

  // Simulated trip status and driver data
  bool isTripActive = true; // Set to false to test "no trip" UI
  final driverData = {
    'name': 'Ravi Kumar',
    'phone': '+91 9876543210',
    'vehicle': 'TS09 AB 1234',
  };

  @override
  void initState() {
    super.initState();
    _fetchDriverLocation();
  }

  Future<void> _fetchDriverLocation() async {
    // Use customerId to fetch the driver's location from the server
    try {
      final response = await http.get(
        Uri.parse('$_BASE/api/parcels/tracking/${widget.customerId}'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] && data['location'] != null) {
          setState(() {
            driverLocation = LatLng(
                data['location']['latitude'], data['location']['longitude']);
          });
        } else {
          // Fallback to default location if no data available
          setState(() {
            driverLocation =
                const LatLng(17.385044, 78.486671); // Hyderabad example
          });
        }
      } else {
        // Fallback to default location on error
        setState(() {
          driverLocation =
              const LatLng(17.385044, 78.486671); // Hyderabad example
        });
      }
    } catch (e) {
      print('Error fetching driver location: $e');
      // Fallback to default location on error
      setState(() {
        driverLocation =
            const LatLng(17.385044, 78.486671); // Hyderabad example
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Parcel Live Tracking"),
        backgroundColor: const Color.fromRGBO(98, 205, 255, 1),
        foregroundColor: Colors.white,
      ),
      body: isTripActive
          ? (driverLocation == null
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    GoogleMap(
                      onMapCreated: (controller) => mapController = controller,
                      initialCameraPosition: CameraPosition(
                        target: driverLocation!,
                        zoom: 15,
                      ),
                      markers: {
                        Marker(
                          markerId: const MarkerId('driver'),
                          position: driverLocation!,
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueAzure),
                          infoWindow: InfoWindow(
                            title: driverData['name'],
                            snippet: driverData['vehicle'],
                          ),
                        ),
                      },
                      myLocationEnabled: true,
                      myLocationButtonEnabled: true,
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(24)),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black12,
                                blurRadius: 8,
                                offset: Offset(0, -3))
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Driver Details",
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            ListTile(
                              leading: const CircleAvatar(
                                  backgroundColor: Colors.teal,
                                  child:
                                      Icon(Icons.person, color: Colors.white)),
                              title: Text(driverData['name']!),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Phone: ${driverData['phone']}"),
                                  Text("Vehicle: ${driverData['vehicle']}"),
                                ],
                              ),
                              trailing: IconButton(
                                icon:
                                    const Icon(Icons.call, color: Colors.green),
                                onPressed: () {
                                  // You can launch call with url_launcher
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ))
          : _noTripWidget(),
    );
  }

  Widget _noTripWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/no_trip.png', height: 180),
            const SizedBox(height: 24),
            const Text(
              "No Parcel Trip Booked",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              "You have no active parcel trips right now. Book one to start tracking.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text("Go Back"),
            ),
          ],
        ),
      ),
    );
  }
}
