import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:http/http.dart' as http;
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_place/google_place.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/socket_service.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

// ✅ Centralized constants
const String googleApiKey = 'AIzaSyCqfjktNhxjKfM-JmpSwBk9KtgY429QWY8';
const List<String> invalidHistoryTerms = ['auto', 'bike', 'car'];
const Map<String, String> vehicleAssets = {
  'bike': 'assets/images/bike.png',
  'auto': 'assets/images/auto.png',
  'car': 'assets/images/car.png',
  'premium': 'assets/images/Primium.png',
  'xl': 'assets/images/xl.png',
};

class OpenStreetLocationPage extends StatefulWidget {
  const OpenStreetLocationPage(
      {super.key, this.initialDrop = '', this.selectedVehicle});

  final String initialDrop;
  final String? selectedVehicle;

  @override
  State<OpenStreetLocationPage> createState() => _OpenStreetLocationPageState();
}

class _OpenStreetLocationPageState extends State<OpenStreetLocationPage> {
  double? _distanceKm;
  double? _durationSec;
  final pickupController = TextEditingController();
  final dropController = TextEditingController();
  late final stt.SpeechToText _speech;
  bool _isListening = false;
  gmaps.LatLng? pickupPoint;
  gmaps.LatLng? dropPoint;
  gmaps.LatLng mapCenter = const gmaps.LatLng(17.3850, 78.4867);

  // Add these at the top of _OpenStreetLocationPageState:

  // ✅ ADDED: Google Maps controller
  gmaps.GoogleMapController? _googleMapController;
  final Set<gmaps.Marker> _markers = {};
  final List<gmaps.LatLng> _routePoints = [];

  // 🔁 REPLACED: flutter_map markers

  static const _historyKey = 'location_history';
  List<String> _history = [];

  final String apiBase = 'http://192.168.210.12:5002'; // Your backend IP
  final List<String> vehicles = ['bike', 'auto', 'car', 'premium', 'xl'];
  final Map<String, double> _vehicleFares = {};
  bool _loadingFares = false;
  String? selectedVehicle;
  String _pickupState = '';
  String _pickupCity = '';
  Timer? _debounce;
  int _currentScreen = 1; // 1 = Booking Screen, 2 = Map Screen
  final FocusNode pickupFocusNode = FocusNode();
  final FocusNode dropFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();

    final socketService = SocketService();
    socketService
        .connect('http://192.168.210.12:5002'); // your backend socket URL
    socketService.connectCustomer(); // auto uses Firebase phone/UID

    _speech = stt.SpeechToText();
    selectedVehicle = widget.selectedVehicle;
    _setCurrentLocation();
    _bootstrap();

    socketService.onTripAccepted((data) {
      print('✅ Driver accepted ride: $data');
      // navigate to ride tracking if needed
    });

    socketService.onRideRejected((data) {
      print('❌ Driver rejected ride: $data');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No drivers accepted your ride')),
      );
    });
  }

  Future<void> _bootstrap() async {
    await _loadHistory();
    await _clearBadHistory();
    await _setCurrentLocation();

    if (widget.initialDrop.isNotEmpty) {
      dropController.text = widget.initialDrop;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchLocation(widget.initialDrop, isPickup: false);
        setState(() {
          selectedVehicle = null;
        });
      });
    } else if (widget.selectedVehicle != null) {
      setState(() {
        selectedVehicle = widget.selectedVehicle;
      });
    }
  }

  @override
  void dispose() {
    pickupController.dispose();
    dropController.dispose();
    _speech.stop();
    _googleMapController?.dispose();
    super.dispose();
  }

  Future<void> _setCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final current = gmaps.LatLng(pos.latitude, pos.longitude);
      final locData = await _reverseGeocode(current);

      setState(() {
        pickupPoint = current;
        mapCenter = current;
        pickupController.text = locData['displayName']!;
        _pickupState = locData['state']!;
        _pickupCity = locData['city']!;
        _markers.add(_buildMarker(current, isPickup: true));
      });

      // ✅ Updated to use GoogleMapController
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _googleMapController?.animateCamera(
          gmaps.CameraUpdate.newLatLngZoom(current, 15),
        );
      });
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  Future<Map<String, String>> _reverseGeocode(gmaps.LatLng latLng) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json'
      '?latlng=${latLng.latitude},${latLng.longitude}'
      '&key=$googleApiKey', // ✅ Updated
    );

    final res = await http.get(url);
    if (res.statusCode != 200) {
      return {'displayName': 'Current Location', 'state': '', 'city': ''};
    }

    final data = jsonDecode(res.body);
    final results = data['results'];
    if (results == null || results.isEmpty) {
      return {'displayName': 'Current Location', 'state': '', 'city': ''};
    }

    String state = '';
    String city = '';
    final components = results[0]['address_components'] as List;

    for (var c in components) {
      final types = List<String>.from(c['types']);
      if (types.contains('administrative_area_level_1')) state = c['long_name'];
      if (types.contains('locality') || types.contains('sublocality')) {
        city = c['long_name'];
      }
    }

    return {
      'displayName': results[0]['formatted_address'],
      'state': state,
      'city': city,
    };
  }

  void _searchLocationFromCoordinates(LocationResult loc,
      {required bool isPickup}) async {
    final point = gmaps.LatLng(loc.latitude, loc.longitude);
    final locData = await _reverseGeocode(point);

    setState(() {
      mapCenter = point;
      _markers.removeWhere(
          (m) => m.markerId.value == (isPickup ? 'pickup' : 'drop'));
      _markers.add(_buildMarker(point, isPickup: isPickup));

      if (isPickup) {
        pickupPoint = point;
        _pickupState = locData['state']!;
        _pickupCity = locData['city']!;
        pickupController.text = locData['displayName']!;
      } else {
        dropPoint = point;
        dropController.text = locData['displayName']!;
      }

      _addToHistory(loc.displayName);
    });

    if (pickupPoint != null && dropPoint != null) {
      await _drawRoute();
    } else {
      _googleMapController?.animateCamera(gmaps.CameraUpdate.newLatLng(point));
    }
  }

  void _searchLocation(String query, {required bool isPickup}) async {
    if (query.trim().isEmpty) return;

    final loc = await GooglePlaceHelper.search(query.trim());
    if (loc == null) return;

    final point = gmaps.LatLng(loc.latitude, loc.longitude);
    final locData = await _reverseGeocode(point);

    setState(() {
      mapCenter = point;
      _markers.removeWhere(
          (m) => m.markerId.value == (isPickup ? 'pickup' : 'drop'));
      _markers.add(_buildMarker(point, isPickup: isPickup));

      if (isPickup) {
        pickupPoint = point;
        _pickupState = locData['state']!;
        _pickupCity = locData['city']!;
        pickupController.text = locData['displayName']!;
      } else {
        dropPoint = point;
      }

      _addToHistory(loc.displayName);
    });

    if (pickupPoint != null && dropPoint != null) {
      await _drawRoute();
    } else {
      _googleMapController?.animateCamera(gmaps.CameraUpdate.newLatLng(point));
    }
    if (!isPickup) {
      setState(() => _currentScreen = 2);
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
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(gmaps.LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  Future<void> _drawRoute() async {
    if (pickupPoint == null || dropPoint == null) return;

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${pickupPoint!.latitude},${pickupPoint!.longitude}'
      '&destination=${dropPoint!.latitude},${dropPoint!.longitude}'
      '&key=$googleApiKey',
    );

    final res = await http.get(url);
    if (res.statusCode != 200) return;

    final data = jsonDecode(res.body);

    // ✅ Add this check BEFORE accessing routes[0]
    if (data['routes'] == null || data['routes'].isEmpty) {
      debugPrint('⚠ No routes found');
      return;
    }

    final route = data['routes'][0];
    final overviewPolyline = route['overview_polyline']['points'];
    final distance = route['legs'][0]['distance']['value'] / 1000.0;
    final duration = route['legs'][0]['duration']['value'].toDouble();

    setState(() {
      _routePoints.clear();
      _routePoints.addAll(_decodePolyline(overviewPolyline));
      _distanceKm = distance;
      _durationSec = duration;
    });

    await _fetchFares(apiBase);
    _fitMapToBounds();
  }

  Future<List<gmaps.LatLng>> fetchRoutePolyline(
      gmaps.LatLng start, gmaps.LatLng end) async {
    // TODO: integrate with your existing route API or Google Directions
    return [start, end]; // temporary straight line until proper implementation
  }

  void _fitMapToBounds() {
    if (pickupPoint == null || dropPoint == null) return;

    final sw = gmaps.LatLng(
      [pickupPoint!.latitude, dropPoint!.latitude]
          .reduce((a, b) => a < b ? a : b),
      [pickupPoint!.longitude, dropPoint!.longitude]
          .reduce((a, b) => a < b ? a : b),
    );
    final ne = gmaps.LatLng(
      [pickupPoint!.latitude, dropPoint!.latitude]
          .reduce((a, b) => a > b ? a : b),
      [pickupPoint!.longitude, dropPoint!.longitude]
          .reduce((a, b) => a > b ? a : b),
    );

    final bounds = gmaps.LatLngBounds(southwest: sw, northeast: ne);
    _googleMapController?.animateCamera(
      gmaps.CameraUpdate.newLatLngBounds(bounds, 80),
    );
  }

  Future<void> _fetchFares(dynamic apiBase) async {
    if (_distanceKm == null || _durationSec == null) return;
    if (_pickupState.isEmpty || _pickupCity.isEmpty) {
      debugPrint('⚠ Skipping fare fetch: missing state or city');
      return;
    }

    setState(() {
      _vehicleFares.clear();
      _loadingFares = true;
    });

    for (final v in vehicles) {
      try {
        final res = await http.post(
          Uri.parse('$apiBase/api/fares/calc'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'state': _pickupState,
            'city': _pickupCity,
            'vehicleType': v,
            'category': 'short',
            'distanceKm': _distanceKm,
            'durationMin': _durationSec! / 60.0,
          }),
        );

        if (kDebugMode) {
          debugPrint('🚕 Fetching fare for: $v');
          debugPrint(
              'Request: state=$_pickupState, city=$_pickupCity, distance=$_distanceKm, duration=${_durationSec! / 60.0}');
          debugPrint('Response Status: ${res.statusCode}');
          debugPrint('Response Body: ${res.body}');
        }

        if (res.statusCode == 200) {
          final json = jsonDecode(res.body);
          final total = (json['total'] as num).toDouble();
          setState(() => _vehicleFares[v] = total);
        } else {
          debugPrint(
              '❌ Failed to fetch fare for $v. Status: ${res.statusCode}');
        }
      } catch (e) {
        debugPrint('Fare API error for $v: $e');
      }
    }

    setState(() => _loadingFares = false);
  }

  Future<void> _loadHistory() async {
    final sp = await SharedPreferences.getInstance();
    _history = sp.getStringList(_historyKey) ?? [];
  }

  Future<void> _saveHistory() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_historyKey, _history);
  }

  Future<void> _clearBadHistory() async {
    final sp = await SharedPreferences.getInstance();
    _history.removeWhere((h) {
      final lower = h.toLowerCase();
      return invalidHistoryTerms.contains(lower);
    });
    await sp.setStringList(_historyKey, _history);
  }

  void _addToHistory(String place) {
    final lower = place.toLowerCase();
    if (invalidHistoryTerms.contains(lower)) return; // ✅ Cleaned

    if (_history.contains(place)) _history.remove(place);
    _history.insert(0, place);
    if (_history.length > 15) _history.removeLast();
    _saveHistory();
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }
    final ok = await _speech.initialize(
      onStatus: (s) {
        if (s == 'done') _toggleListening();
      },
      onError: (e) {
        debugPrint('Speech error: $e');
        _toggleListening();
      },
    );
    if (!ok) return;
    setState(() => _isListening = true);
    _speech.listen(onResult: (r) {
      if (r.finalResult) {
        final txt = r.recognizedWords.trim();
        if (!invalidHistoryTerms.contains(txt.toLowerCase()) &&
            txt.length > 3) {
          dropController.text = txt;
          _searchLocation(txt, isPickup: false);
          setState(() => _currentScreen = 2);
        }
      }
    });
  }

  Future<List<LocationResult>> _suggestions(String pattern) async {
    if (pattern.trim().length < 2) return [];

    // Debounce API calls
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    final completer = Completer<List<LocationResult>>();

    _debounce = Timer(const Duration(milliseconds: 200), () async {
      try {
        final nearby = pickupPoint ?? dropPoint ?? mapCenter;

        // Show history first
        final localMatches = _history
            .where((h) => h.toLowerCase().contains(pattern.toLowerCase()))
            .map((h) =>
                LocationResult(latitude: 0, longitude: 0, displayName: h))
            .toList();

        // Fetch Google suggestions in parallel
        final results =
            await GooglePlaceHelper.autocomplete(pattern, center: nearby);

        // Merge history + API results (no duplicates)
        final merged = [
          ...localMatches,
          ...results.where(
              (r) => !localMatches.any((h) => h.displayName == r.displayName)),
        ];

        completer.complete(merged);
      } catch (e) {
        debugPrint("❌ Suggestions error: $e");
        completer.complete([]);
      }
    });

    return completer.future;
  }

  Widget _buildSearchField({
    required TextEditingController controller,
    required String hint,
    required bool isPickup,
    FocusNode? focusNode, // ✅ added
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TypeAheadField<LocationResult>(
        suggestionsCallback: _suggestions,
        animationDuration: const Duration(milliseconds: 200),
        itemBuilder: (_, s) => ListTile(
          title: Text(s.displayName, style: const TextStyle(fontSize: 14)),
        ),
        onSelected: (s) async {
          controller.text = s.displayName;
          // ✅ Fetch full details only on selection
          final loc = await GooglePlaceHelper.search(s.displayName);
          if (loc != null) {
            _searchLocationFromCoordinates(loc, isPickup: isPickup);
            if (!isPickup) {
              setState(() {
                _currentScreen = 2;
              });
              _drawRoute(); // ✅ New method to redraw route
            }
          }
        },
        emptyBuilder: (_) => const Padding(
          padding: EdgeInsets.all(8),
          child: Text('No locations found'),
        ),
        builder: (context, textFieldController, focusNode) {
          textFieldController.text = controller.text;
          return TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: InputDecoration(
              prefixIcon: Icon(
                  isPickup
                      ? Icons.radio_button_checked
                      : Icons.location_on_outlined,
                  color: Colors.black),
              suffixIcon: isPickup
                  ? IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () => _searchLocation(controller.text.trim(),
                          isPickup: true),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                          onPressed: _toggleListening,
                        ),
                        IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: () => _searchLocation(
                              controller.text.trim(),
                              isPickup: false),
                        ),
                      ],
                    ),
              hintText: hint,
              border: InputBorder.none,
            ),
          );
        },
      ),
    );
  }

  String _prettyDuration(double secs) {
    final d = Duration(seconds: secs.round());
    return d.inHours > 0
        ? '${d.inHours}h ${d.inMinutes.remainder(60)}m'
        : '${d.inMinutes}m';
  }

  Widget _bottomPanel() {
    if (_loadingFares) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_vehicleFares.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, -2),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: vehicles.where((v) {
                return selectedVehicle == null ||
                    selectedVehicle!.toLowerCase() == v.toLowerCase();
              }).map((v) {
                if (!_vehicleFares.containsKey(v)) return const SizedBox();

                String asset = vehicleAssets[v]!;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedVehicle = v;
                    });
                  },
                  child: _fareCard(v, asset, _vehicleFares[v],
                      labelBelow: v == 'bike' ? 'Quick bike' : null),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),
          if (_durationSec != null)
            Text('Duration: ${_prettyDuration(_durationSec!)}',
                style: TextStyle(fontSize: 14, color: Colors.grey[800])),
          const SizedBox(height: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[900],
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
            ),
            onPressed: () async {
              if (selectedVehicle != null &&
                  _vehicleFares[selectedVehicle!] != null) {
                final pickup = pickupController.text.trim();
                final drop = dropController.text.trim();

                if (pickup.isEmpty || drop.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Pickup and Drop are required')),
                  );
                  return;
                }

                // ✅ Send ride request to drivers via SocketService
                final userId = FirebaseAuth.instance.currentUser?.uid;
                if (userId == null ||
                    pickupPoint == null ||
                    dropPoint == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Missing ride details')),
                  );
                  return;
                }

                SocketService().sendRideRequest({
                  'userId': userId,
                  'pickupLat': pickupPoint!.latitude,
                  'pickupLng': pickupPoint!.longitude,
                  'dropLat': dropPoint!.latitude,
                  'dropLng': dropPoint!.longitude,
                  'pickupName': pickupController.text.trim(),
                  'dropName': dropController.text.trim(),
                  'vehicleType': selectedVehicle,
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Ride sent to nearby drivers 🚗')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Please select a vehicle first')),
                );
              }
            },
            child: const Text(
              'Confirm Ride',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  gmaps.Marker _buildMarker(gmaps.LatLng p, {required bool isPickup}) {
    return gmaps.Marker(
      markerId: gmaps.MarkerId(isPickup ? 'pickup' : 'drop'),
      position: p,
      icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
        isPickup
            ? gmaps.BitmapDescriptor.hueGreen
            : gmaps.BitmapDescriptor.hueRed,
      ),
    );
  }

  void _onMapCreated(gmaps.GoogleMapController controller) {
    _googleMapController = controller;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentScreen == 1 ? 0 : 1,
        children: [
          _buildBookingScreen(),
          _buildMapScreen(),
        ],
      ),
    );
  }

  Widget _buildBookingScreen() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Book a Ride",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text("Where would you like to go?",
                style: TextStyle(color: Colors.grey)),

            const SizedBox(height: 16),

            // Pickup and Drop Fields
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
              ),
              child: Column(
                children: [
                  _buildSearchField(
                    controller: pickupController,
                    hint: "Current location",
                    isPickup: true,
                  ),
                  const SizedBox(height: 8),
                  _buildSearchField(
                    controller: dropController,
                    hint: "Where to?",
                    isPickup: false,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            const Text("Recent Rides",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),

            const SizedBox(height: 8),

            Expanded(
              child: _history.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.history, size: 40, color: Colors.grey),
                          SizedBox(height: 8),
                          Text("No recent rides",
                              style: TextStyle(color: Colors.grey)),
                          Text("Your ride history will appear here",
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        final place = _history[index];
                        return ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(place),
                          onTap: () {
                            dropController.text = place;
                            setState(() => _currentScreen = 2);
                            _searchLocation(place, isPickup: false);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapScreen() {
    return Stack(
      children: [
        gmaps.GoogleMap(
          onMapCreated: _onMapCreated,
          initialCameraPosition: gmaps.CameraPosition(
            target: mapCenter,
            zoom: 15,
          ),
          markers: Set<gmaps.Marker>.of(_markers),
          polylines: _routePoints.isNotEmpty
              ? {
                  gmaps.Polyline(
                    polylineId: const gmaps.PolylineId('route'),
                    points: _routePoints,
                    width: 4,
                    color: Colors.blue,
                  )
                }
              : {},
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
        ),

        // Pickup and Drop bars
        Positioned(
          top: 40,
          left: 20,
          right: 20,
          child: Column(
            children: [
              GestureDetector(
                onTap: () {
                  setState(() => _currentScreen = 1);
                  Future.delayed(const Duration(milliseconds: 100), () {
                    FocusScope.of(context).requestFocus(pickupFocusNode);
                  });
                },
                child: _buildSearchField(
                  controller: pickupController,
                  focusNode: pickupFocusNode, // ✅ add this
                  hint: "Pickup location",
                  isPickup: true,
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () {
                  setState(() => _currentScreen = 1);
                  Future.delayed(const Duration(milliseconds: 100), () {
                    FocusScope.of(context).requestFocus(dropFocusNode);
                  });
                },
                child: _buildSearchField(
                  controller: dropController,
                  focusNode: dropFocusNode, // ✅ add this
                  hint: "Drop location",
                  isPickup: false,
                ),
              ),
            ],
          ),
        ),

        // Fare Panel
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _bottomPanel(),
        ),
      ],
    );
  }

  Widget _buildLocalHistory() {
    if (_history.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _history.length,
        itemBuilder: (context, index) {
          final place = _history[index];
          return ListTile(
            dense: true,
            leading: const Icon(Icons.history, size: 20),
            title: Text(place, style: const TextStyle(fontSize: 14)),
            trailing: IconButton(
              icon: const Icon(Icons.favorite_border, size: 20),
              onPressed: () {},
            ),
            onTap: () {
              dropController.text = place;
              _searchLocation(place, isPickup: false);
            },
          );
        },
      ),
    );
  }

  Widget _fareCard(String label, String assetPath, double? fare,
      {String? labelBelow}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 150,
          height: 150,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Image.asset(assetPath, fit: BoxFit.contain),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(fare != null ? '₹${fare.toStringAsFixed(0)}' : 'Loading...'),
        if (labelBelow != null)
          Text(labelBelow,
              style: const TextStyle(fontSize: 10, color: Colors.blue)),
      ],
    );
  }
}

class LocationResult {
  LocationResult({
    required this.latitude,
    required this.longitude,
    required this.displayName,
  });
  final double latitude;
  final double longitude;
  final String displayName;
}

class GooglePlaceHelper {
  static final _place = GooglePlace('AIzaSyCqfjktNhxjKfM-JmpSwBk9KtgY429QWY8');

  static Future<LocationResult?> search(String input) async {
    final predictions = await _place.autocomplete.get(input);
    if (predictions == null || predictions.predictions == null) return null;

    final first = predictions.predictions!.first;
    final details = await _place.details.get(first.placeId!);
    if (details == null || details.result == null) return null;

    final loc = details.result!.geometry?.location;
    return LocationResult(
      latitude: loc?.lat ?? 0.0,
      longitude: loc?.lng ?? 0.0,
      displayName: details.result!.formattedAddress ?? first.description ?? '',
    );
  }

  static Future<List<LocationResult>> autocomplete(String input,
      {gmaps.LatLng? center}) async {
    final predictions = await _place.autocomplete.get(
      input,
      location:
          center != null ? LatLon(center.latitude, center.longitude) : null,
      radius: 20000,
    );

    if (predictions?.predictions == null) return [];

    // ✅ Only use predictions first (faster, no details call yet)
    return predictions!.predictions!.map((p) {
      return LocationResult(
        latitude: 0, // Will fetch later on selection
        longitude: 0,
        displayName: p.description ?? '',
      );
    }).toList();
  }
}
