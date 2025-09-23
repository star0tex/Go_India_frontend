import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import '../services/socket_service.dart';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
// ─────────────────────────────
// Screen 1 → Pickup
// ─────────────────────────────
class PickupScreen extends StatefulWidget {
  final String customerId;
  const PickupScreen({super.key, required this.customerId});

  @override
  State<PickupScreen> createState() => _PickupScreenState();
}

class _PickupScreenState extends State<PickupScreen> {
  String _pickupAddress = "Fetching current location...";
  String _dropAddress = "Search drop address";
  final bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        setState(() {
          _pickupAddress = "Location permission denied";
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;

        // Build full address safely
        final address = [
          place.name,                       // house/building number
          place.street,                     // street / road
          place.subLocality,                // area / colony
          place.locality,                   // city
          place.subAdministrativeArea,      // district
          place.administrativeArea,         // state
          place.postalCode,                 // pincode
        ].where((e) => e != null && e.isNotEmpty).join(", ");

        setState(() => _pickupAddress = address);
      } else {
        setState(() => _pickupAddress = "Unable to fetch address");
      }
    } catch (e) {
      setState(() => _pickupAddress = "Error fetching location: $e");
    }
  }

  void _swapLocations() {
    setState(() {
      final temp = _pickupAddress;
      _pickupAddress = _dropAddress;
      _dropAddress = temp;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ───────── Header tagline ─────────
            Center(
              child: Column(
                children: const [
                  Text(
                    "Send Anything, Anytime",
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    "Parcel Delivery",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ───────── Pickup card ─────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.15),
                    spreadRadius: 1,
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.location_on, color: Colors.green, size: 20),
                      SizedBox(width: 6),
                      Text(
                        "Pickup from current location",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Current location with loader
                  _isLoading
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Text(
                          _pickupAddress,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                  const SizedBox(height: 8),

                  // Switch button
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: _swapLocations,
                      icon: const Icon(Icons.swap_vert, color: Colors.black),
                      label: const Text(
                        "Switch",
                        style: TextStyle(color: Colors.black),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Colors.black12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 18),
                      ),
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ───────── Drop Section ─────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.15),
                    spreadRadius: 1,
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.circle, size: 12, color: Colors.red),
                      SizedBox(width: 6),
                      Text(
                        "Drop to",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  GestureDetector(
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => DropScreen(customerId: widget.customerId)),
                      );

                      if (result != null && result is String) {
                        setState(() => _dropAddress = result);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue, width: 1),
                        color: Colors.white,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search, color: Colors.black54),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _dropAddress,
                              style: const TextStyle(
                                fontSize: 15,
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // ───────── Terms footer ─────────
            Center(
              child: Column(
                children: [
                  const Text(
                    "Learn more about prohibited items",
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  RichText(
                    text: const TextSpan(
                      text: "By using our service, you agree to our ",
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                      children: [
                        TextSpan(
                          text: "Terms & Conditions",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue,
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

// ─────────────────────────────
// Screen 2 → Drop
// ─────────────────────────────

class DropScreen extends StatefulWidget {
  final String customerId;
  const DropScreen({super.key, required this.customerId});

  @override
  State<DropScreen> createState() => _DropScreenState();
}

class _DropScreenState extends State<DropScreen> {
  final TextEditingController dropCtl = TextEditingController();
  List<String> _recentSearches = [];
  final List<String> _suggestions = [];
  late GoogleMapsPlaces _places;

  @override
  void initState() {
    super.initState();
    _places = GoogleMapsPlaces(
      apiKey: "AIzaSyCqfjktNhxjKfM-JmpSwBk9KtgY429QWY8",
    );
    _loadSearchHistory();
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
        _suggestions
          ..clear()
          ..addAll(response.predictions
              .map((p) => p.description ?? "")
              .where((d) => d.isNotEmpty));
      });
    } else {
      setState(() => _suggestions.clear());
    }
  }

  void _selectLocation(String? location) async {
    if (location == null || location.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    // Save in history (max 10)
    if (!_recentSearches.contains(location)) {
      _recentSearches.insert(0, location);
      if (_recentSearches.length > 10) {
        _recentSearches.removeLast();
      }
      await _saveSearchHistory();
    }

    Navigator.pop(context); // close loader before navigation
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          "Drop to",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // ───────── Search input ─────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: dropCtl,
              onChanged: _getSuggestions,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.location_on, color: Colors.red),
                hintText: "Search drop location",
                hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // ───────── Suggestions / History ─────────
          Expanded(
            child: ListView.builder(
              itemCount: isTyping ? _suggestions.length : _recentSearches.length,
              itemBuilder: (context, index) {
                final location =
                    isTyping ? _suggestions[index] : _recentSearches[index];

                return InkWell(
                  onTap: () => _selectLocation(location),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          isTyping ? Icons.place : Icons.history,
                          color: Colors.black54,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            location,
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.favorite_border,
                            color: Colors.black38, size: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
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

class _ParcelLocationPageState extends State<ParcelLocationPage> {
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

  // socket state
  String? _currentTripId;
  bool _isWaitingForDriver = false;

  bool get allInputsFilled {
    return _nameController.text.isNotEmpty &&
        _phoneController.text.isNotEmpty &&
        _weightController.text.isNotEmpty &&
        _parcelPhoto != null;
  }

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
    _setupSocketListeners();
  }

  @override
  void dispose() {
    SocketService().disconnect();
    super.dispose();
  }
  void _setupSocketListeners() {
    final socketService = SocketService();
    
    // Connect to socket
    socketService.connect("http://192.168.1.28:5002");
    socketService.connectCustomer(customerId: widget.customerId);

    // Listen for trip acceptance
    socketService.onTripAccepted((data) {
      print("Driver accepted parcel: $data");
      setState(() {
        _isWaitingForDriver = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Driver accepted your parcel delivery!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    });

    // Listen for rejections/reassignments
    socketService.onTripRejectedBySystem((data) {
      print("Trip rejected: $data");
      if (data['tripId'] == _currentTripId && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Looking for another driver..."),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });
  }

  Future<void> _pickParcelPhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
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
    double finalDistance = 0.1; // default fallback min distance

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

    final url = Uri.parse("http://192.168.1.28:5002/api/parcels/estimate");

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

    setState(() => _isSubmitting = true);

    try {
      // Use trip controller for socket broadcasting
      final url = Uri.parse("http://192.168.1.28:5002/api/trip/parcel");
      
      // Calculate distance
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
        
        // Store trip ID for socket listening
        _currentTripId = responseData['tripId'];
        
        setState(() {
          _isWaitingForDriver = responseData['drivers'] > 0;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(responseData['drivers'] > 0 
                ? "Searching for nearby drivers..."
                : "No drivers available right now"),
            ),
          );
        }
      } else {
        print("Booking failed: ${response.statusCode} - ${response.body}");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Failed to book parcel. Please try again."),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print("Error booking parcel: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Network error. Please check your connection."),
            backgroundColor: Colors.red,
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
      body: _currentPosition == null
          ? const Center(child: CircularProgressIndicator())
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
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _isWaitingForDriver 
                      ? _buildWaitingCard()
                      : _showDetailsCard
                          ? _buildDropDetailsCard()
                          : _showFareCard
                              ? _buildFareCard()
                              : const SizedBox.shrink(),
                ),
              ],
            ),
    );
  }

  Widget _buildWaitingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
      decoration: _cardDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          const Text(
            "Looking for nearby drivers...",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "Trip ID: $_currentTripId",
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildDropDetailsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
      decoration: _cardDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: _inputStyle("Name*", Icons.person).copyWith(
              errorText: _nameController.text.isEmpty ? null : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: _inputStyle("Phone Number*", Icons.phone).copyWith(
              errorText: _phoneController.text.isEmpty ? null : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _pickParcelPhoto,
                icon: const Icon(Icons.photo_camera),
                label: const Text("Add Parcel Photo"),
              ),
              const SizedBox(width: 10),
              if (_parcelPhoto != null)
                const Icon(Icons.check_circle, color: Colors.green),
              if (_parcelPhoto == null)
                const Text("Required", style: TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _weightController,
            keyboardType: TextInputType.number,
            decoration: _inputStyle("Parcel Weight (kg)", Icons.scale).copyWith(
              errorText: _weightController.text.isEmpty ? null : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildChip("Home", Icons.home),
              _buildChip("Work", Icons.work),
              _buildChip("Gym", Icons.fitness_center),
              _buildChip("College", Icons.school),
              _buildChip("Hostel", Icons.hotel),
              _buildAddNewChip(),
            ],
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: allInputsFilled ? _fetchFare : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: allInputsFilled ? Colors.black : Colors.grey,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                "Confirm drop details",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFareCard() {
    if (_fareData == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
      decoration: _cardDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Parcel Fare",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Text("₹${_fareData!['cost'] ?? _fareData!['total'] ?? '0'}",
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: allInputsFilled ? _bookParcel : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: allInputsFilled ? Colors.black : Colors.grey,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSubmitting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      "Confirm & Book",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      );

  InputDecoration _inputStyle(String hint, IconData icon) => InputDecoration(
        prefixIcon: Icon(icon, color: Colors.black87),
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: Colors.grey[100],
      );

  Widget _buildChip(String label, IconData icon) => Chip(
        label: Text(label),
        avatar: Icon(icon, size: 18, color: Colors.black87),
        backgroundColor: Colors.grey[200],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      );

  Widget _buildAddNewChip() => Chip(
        label: const Text("+ Add New",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        backgroundColor: Colors.redAccent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      );

  // -----------------------------
  // Map + Location
  // -----------------------------

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

      // auto set drop if pickup text given
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
              color: Colors.black,
              width: 5,
              points: points,
            ),
          );
        });

        // bounds calc
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
              // pickup == drop
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
      } else {
        print("⚠️ Directions API failed: ${data["status"]}");
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
  }
}