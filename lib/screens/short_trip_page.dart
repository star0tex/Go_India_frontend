import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
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
import 'driver_en_route_page.dart'; // ✅ NEW: Import the new page
// TODO: Replace with project env var
const String googleMapsApiKey = 'AIzaSyCqfjktNhxjKfM-JmpSwBk9KtgY429QWY8';
const String apiBase = 'http://192.168.1.9:5002';

const Map<String, String> vehicleAssets = {
  'bike': 'assets/images/bike.png',
  'auto': 'assets/images/auto.png',
  'car': 'assets/images/car.png',
  'premium': 'assets/images/Primium.png',
  'xl': 'assets/images/xl.png',
};

const List<String> vehicleLabels = ['bike', 'auto', 'car', 'premium', 'xl'];
const List<String> invalidHistoryTerms = ['auto', 'bike', 'car'];

class ShortTripPage extends StatefulWidget {
  final String? vehicleType;
  final String customerId;
  final TripArgs args;
  final Map<String, dynamic>? initialPickup;
  final Map<String, dynamic>? initialDrop;
  final String? entryMode;

  // ignore: use_super_parameters
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

class _ShortTripPageState extends State<ShortTripPage> {
  // Screen management
  gmaps.LatLng? _driverPosition;
Set<gmaps.Marker> _markers = {};
Timer? _locationTimer;
 // ✅ NEW: State variables for waiting logic
  bool _isWaitingForDriver = false;
  String? _currentTripId;
  Timer? _rerequestTimer;
  int _screenIndex = 0; // 0: Search screen, 1: Map+Fare screen
  // Location data
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropController = TextEditingController();
  gmaps.LatLng? _pickupPoint;
  gmaps.LatLng? _dropPoint;
  String _pickupAddress = '';
  String _dropAddress = '';
  String _pickupState = '';
  String _pickupCity = '';
  String? _fare;
  late final SocketService _socketService; // <-- Add this

  // Map & route
  gmaps.GoogleMapController? _mapController;
  List<gmaps.LatLng> _routePoints = [];
  double? _distanceKm;
  double? _durationSec;

  // Speech
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

  // History & suggestions
  List<String> _history = [];
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounce;

  // Fare calculation
  Map<String, double> _fares = {};
  bool _loadingFares = false;
  String? _selectedVehicle;

  @override
  void initState() {
    super.initState();
    _selectedVehicle = widget.vehicleType;
    _initializeData();

    _socketService = SocketService(); // <-- Use a single instance

    _socketService.connect(apiBase);
  _socketService.connectCustomer(customerId: widget.customerId);

    _setupSocketListeners();
  }

  void _setupSocketListeners() {
    _socketService.on('trip:accepted', (data) {
      print("📢 Trip accepted: $data");
      // Defensive: check keys
      final driverDetails = data['driver'] ?? data['driverDetails'] ?? {};
      final tripDetails = data['trip'] ?? data['tripDetails'] ?? {};

      // If keys are missing, print the whole data for debugging
      if (driverDetails.isEmpty || tripDetails.isEmpty) {
        print("⚠️ Missing driver/trip details in event: $data");
      }

      // Defensive: check context
      if (!mounted) return;

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
  }

 
  
void _updateMarkers() {
  _markers.clear();

  // Pickup marker
  if (_pickupPoint != null) {
    _markers.add(gmaps.Marker(
      markerId: const gmaps.MarkerId("pickup"),
      position: _pickupPoint!,
      icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
        gmaps.BitmapDescriptor.hueGreen,
      ),
    ));
  }

  // Drop marker
  if (_dropPoint != null) {
    _markers.add(gmaps.Marker(
      markerId: const gmaps.MarkerId("drop"),
      position: _dropPoint!,
      icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
        gmaps.BitmapDescriptor.hueRed,
      ),
    ));
  }

  // Driver marker
  if (_driverPosition != null) {
    _markers.add(gmaps.Marker(
      markerId: const gmaps.MarkerId("driver"),
      position: _driverPosition!,
      icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
        gmaps.BitmapDescriptor.hueBlue,
      ),
    ));
  }

  // Trigger refresh on map
  setState(() {});
}


void _safeEmit(String event, dynamic data) {
  if (SocketService().isConnected) {
    SocketService().emit(event, data);
  } else {
    debugPrint("⚠️ Socket not connected. Event '$event' not sent immediately.");
  }
}
Future<void> _getFareEstimate() async {
try {
final response = await http.post(
Uri.parse("http://192.168.1.9:5002/api/fare/estimate"),
headers: {"Content-Type": "application/json"},
body: jsonEncode({
"pickup": _pickupController.text,
"dropoff": _dropController.text,
}),
);


if (response.statusCode == 200) {
final data = jsonDecode(response.body);
setState(() {
_fare = data['fare'].toString();
});
} else {
debugPrint("❌ Fare API failed: ${response.statusCode}");
}
} catch (e) {
debugPrint("⚠️ Fare fetch error: $e");
}
}


void _requestTrip() {
_safeEmit("customerRequestTripByType", {
"customerId": widget.customerId,
"pickup": _pickupController.text,
"dropoff": _dropController.text,
});
debugPrint("🚕 Trip request emitted safely");
}
  @override
  void dispose() {
        _rerequestTimer?.cancel(); 
SocketService().off('trip:accepted');
    SocketService().off('driver:locationUpdate');
    _pickupController.dispose();
    _dropController.dispose();
    _speech.stop();
    _debounce?.cancel();
    _mapController?.dispose();
    _pickupController.dispose();
_dropController.dispose();
    super.dispose();
    _locationTimer?.cancel();

  }

  Future<void> _initializeData() async {
    await _loadHistory();

    // Set initial pickup
    if (widget.initialPickup != null) {
      _pickupPoint = gmaps.LatLng(
        widget.initialPickup!['lat'],
        widget.initialPickup!['lng'],
      );
      _pickupAddress = widget.initialPickup!['address'] ?? 'Pickup location';
      _pickupController.text = _pickupAddress;

      // Get state/city from reverse geocoding
      final locationData = await _reverseGeocode(_pickupPoint!);
      _pickupState = locationData['state'] ?? '';
      _pickupCity = locationData['city'] ?? '';
    } else {
      await _getCurrentLocation();
    }

    // Set initial drop and screen
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

    // Direct to screen 2 if coming from search with drop
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
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting location: $e')),
      );
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
      // Fallback to Google Geocoding API
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
        // Ignore and return default
      }

      return {'displayName': 'Unknown Location', 'state': '', 'city': ''};
    }
  }

  void _showLocationServiceError() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Location Services Disabled'),
        content: Text('Please enable location services to use this feature.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Geolocator.openLocationSettings(),
            child: Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showLocationPermissionError() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Location Permission Required'),
        content:
            Text('This app needs location permission to find nearby rides.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Geolocator.openAppSettings(),
            child: Text('Open Settings'),
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
    // Don't save invalid terms
    final lowerAddress = address.toLowerCase();
    if (invalidHistoryTerms.any((term) => lowerAddress.contains(term))) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    final historyKey = 'location_history_${user?.phoneNumber ?? user?.uid}';

    // Remove if already exists and add to top
    _history.remove(address);
    _history.insert(0, address);

    // Keep only last 5 items
    if (_history.length > 5) {
      _history = _history.sublist(0, 5);
    }

    await prefs.setStringList(historyKey, _history);
  }

  Future<void> _fetchSuggestions(String query) async {
    if (query.trim().length < 2) {
      setState(() => _suggestions = []);
      return;
    }

    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        // Use Google Places API for autocomplete
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query'
          '&key=$googleMapsApiKey'
          '&location=${_pickupPoint?.latitude},${_pickupPoint?.longitude}'
          '&radius=20000',
        );

        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final predictions = data['predictions'] as List?;

          if (predictions != null) {
            setState(() {
              _suggestions =
                  predictions.map<Map<String, dynamic>>((prediction) {
                return {
                  'description': prediction['description'] as String,
                  'place_id': prediction['place_id'] as String,
                };
              }).toList();
            });
          }
        }
      } catch (e) {
        // Fallback to local history matches
        setState(() {
          _suggestions = _history
              .where((item) => item.toLowerCase().contains(query.toLowerCase()))
              .map((item) => {'description': item, 'place_id': ''})
              .toList();
        });
      }
    });
  }

  Future<void> _selectSuggestion(Map<String, dynamic> suggestion) async {
    final placeId = suggestion['place_id'] as String;
    final description = suggestion['description'] as String;

    if (placeId.isEmpty) {
      // History item selected
      _dropController.text = description;
      await _searchLocation(description);
      return;
    }

    try {
      // Get place details from Google Places API
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

          _dropPoint = gmaps.LatLng(lat, lng);
          _dropAddress = result['formatted_address'] ?? description;
          _dropController.text = _dropAddress;

          await _saveToHistory(_dropAddress);
          setState(() => _screenIndex = 1);
          await _drawRoute();
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to get location details: $e')),
      );
    }
  }

  Future<void> _searchLocation(String query) async {
    try {
      // Use Google Geocoding API to search for location
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to search location: $e')),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speech input unavailable, please type')),
        );
      },
    );

    if (!available) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speech recognition not available')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to calculate route: $e')),
      );
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
    if (_pickupPoint == null || _dropPoint == null || _mapController == null)
      return;

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
  if (_distanceKm == null || _durationSec == null) return;

  setState(() {
    _loadingFares = true;
    _fares.clear();
  });

  // ✅ Choose vehicles to fetch
  final vehiclesToFetch = (widget.vehicleType != null &&
          widget.vehicleType!.isNotEmpty)
      ? [widget.vehicleType!]
      : vehicleLabels.where((v) => v.isNotEmpty).toList();

  try {
    final results = await Future.wait(
      vehiclesToFetch.map((vehicleType) async {
        try {
          debugPrint('📡 Fetching fare for vehicleType="$vehicleType"...');

          final response = await http.post(
            Uri.parse('$apiBase/api/fares/calc'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'state': _pickupState,
              'city': _pickupCity,
              'vehicleType': vehicleType,
              'category': 'short',
              'distanceKm': _distanceKm,
              'durationMin': _durationSec! / 60,
            }),
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final total = (data['total'] as num).toDouble();
            debugPrint('✅ Fare for $vehicleType = $total');
            return MapEntry(vehicleType, total);
          } else if (response.statusCode == 404) {
            debugPrint('⚠️ Rate not found for $vehicleType');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Rate not found for $vehicleType')),
            );
            return null;
          } else {
            debugPrint(
                '❌ Failed response ${response.statusCode} for $vehicleType');
          }
        } catch (e) {
          debugPrint('❌ Error fetching fare for $vehicleType: $e');
        }
        return null;
      }),
    );

    // ✅ Apply results once
    setState(() {
      for (var entry in results) {
        if (entry != null) {
          _fares[entry.key] = entry.value;
        }
      }
    });
  } catch (e) {
    debugPrint('🔥 Unexpected error in _fetchFares: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to fetch fares: $e')),
    );
  } finally {
    setState(() => _loadingFares = false);
  }
}


Future<void> _confirmRide() async {
  // 1. Validate that all necessary data (user, vehicle, locations) is available before proceeding.
  final user = FirebaseAuth.instance.currentUser;
  if (user == null || _selectedVehicle == null || _pickupPoint == null || _dropPoint == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please ensure all details are correct.')),
    );
    return;
  }

  // 2. Build the data payload for the backend, ensuring coordinates are in [longitude, latitude] order.
  // ...existing code...
final rideData = {
  "customerId": widget.customerId, // <-- Use DB ID, not phone!
  "pickup": {
    "coordinates": [_pickupPoint!.longitude, _pickupPoint!.latitude],
    "address": _pickupAddress,
  },
  "drop": {
    "coordinates": [_dropPoint!.longitude, _dropPoint!.latitude],
    "address": _dropAddress,
  },
  "vehicleType": _selectedVehicle!.toLowerCase().trim(),
  "fare": _fares[_selectedVehicle],
  "timestamp": DateTime.now().toIso8601String(),
};
// ...existing code...
  debugPrint("🚨 Sending rideData: ${jsonEncode(rideData)}");

  try {
    // 3. Send the ride request to the server via an HTTP POST request.
    final response = await http.post(
      Uri.parse("$apiBase/api/trip/short"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(rideData),
    );

    // 4. Handle the successful response from the server.
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      debugPrint("✅ Trip created on server: $data");

      // 5. If a trip was created, start the 'waiting' UI and the 5-second re-request timer.
      if (data['tripId'] != null) {
        setState(() {
          _currentTripId = data['tripId'];
          // Show the waiting UI only if the backend found drivers to notify.
          _isWaitingForDriver = data['drivers'] > 0;
        });

        if (_isWaitingForDriver) {
          _rerequestTimer?.cancel(); // Cancel any old timer before starting a new one.
          _rerequestTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
            if (!mounted) {
              timer.cancel();
              return;
            }
            print("🔁 Re-requesting trip: $_currentTripId");
            // This event tells the backend to broadcast the request again to nearby drivers.
            SocketService().emit('trip:rerequest', {'tripId': _currentTripId});
          });
        }
      }

      await _saveToHistory(_dropAddress);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isWaitingForDriver ? 'Searching for nearby drivers...' : 'No drivers available right now.'),
        ),
      );
    } else {
      // Handle API errors (e.g., 400, 500).
      debugPrint("❌ Trip API failed: ${response.statusCode} ${response.body}");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ride request failed: ${response.body}')),
      );
    }
  } catch (e) {
    // Handle network errors (e.g., no internet connection).
    debugPrint("⚠️ Error calling trip API: $e");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to send ride request: $e')),
    );
  }
}

@override
Widget build(BuildContext context) {
  return Scaffold(
    body: Stack(
      children: [
        // This is your main content (the search screen or the map screen)
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: _screenIndex == 0 ? _buildSearchScreen() : _buildMapScreen(),
        ),

        // This is the overlay that shows ONLY when you are waiting for a driver
        if (_isWaitingForDriver)
          Container(
            color: Colors.black.withOpacity(0.7),
            child: Center(
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 20),
                      Text(
                        'Waiting for a driver to accept...',
                        style: GoogleFonts.poppins(fontSize: 16),
                      ),
                      const SizedBox(height: 10),
                      // Ensure _currentTripId is not null before displaying
                      if (_currentTripId != null)
                        Text(
                          'Trip ID: $_currentTripId',
                          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

  Widget _buildSearchScreen() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Book a Ride",
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 4),
            Text(
              "Where would you like to go?",
              style: GoogleFonts.poppins(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
            SizedBox(height: 16),
            _LocationInputBar(
              pickupController: _pickupController,
              dropController: _dropController,
              onPickupChanged: (value) => _fetchSuggestions(value),
              onDropChanged: (value) => _fetchSuggestions(value),
              onMicPressed: _toggleListening,
              isListening: _isListening,
              editable: true,
            ),
            SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  if (_suggestions.isNotEmpty)
                    _SuggestionList(
                      suggestions: _suggestions,
                      onSuggestionSelected: _selectSuggestion,
                    ),
                  if (_history.isNotEmpty)
                    _HistoryList(
                      history: _history,
                      onHistorySelected: _selectSuggestion,
                    ),
                ],
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
  onMapCreated: (controller) {
    _mapController = controller;
    _updateMarkers(); // initialize markers
  },
  initialCameraPosition: gmaps.CameraPosition(
    target: _pickupPoint ?? const gmaps.LatLng(0, 0),
    zoom: 15,
  ),
  markers: _markers, // ✅ use dynamic markers
  polylines: _routePoints.isNotEmpty
      ? {
          gmaps.Polyline(
            polylineId: const gmaps.PolylineId('route'),
            points: _routePoints,
            color: Colors.blue,
            width: 4,
          ),
        }
      : {},
  myLocationEnabled: true,
),

        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: _LocationInputBar(
            pickupController: _pickupController,
            dropController: _dropController,
            onPickupChanged: (value) {},
            onDropChanged: (value) {},
            onMicPressed: () {},
            isListening: false,
            editable: false,
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _FarePanel(
            fares: _fares,
            loading: _loadingFares,
            selectedVehicle: _selectedVehicle,
            durationSec: _durationSec,
            onVehicleSelected: (vehicle) =>
                setState(() => _selectedVehicle = vehicle),
            onConfirmRide: _confirmRide,
            showAll: widget.vehicleType == null,
          ),
        ),
      ],
    );
  }
}

class _LocationInputBar extends StatelessWidget {
  final TextEditingController pickupController;
  final TextEditingController dropController;
  final ValueChanged<String> onPickupChanged;
  final ValueChanged<String> onDropChanged;
  final VoidCallback onMicPressed;
  final bool isListening;
  final bool editable;

  const _LocationInputBar({
    required this.pickupController,
    required this.dropController,
    required this.onPickupChanged,
    required this.onDropChanged,
    required this.onMicPressed,
    required this.isListening,
    required this.editable,
  });

  @override
  Widget build(BuildContext context) {
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: pickupController,
            enabled: editable,
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.radio_button_checked, color: Colors.black),
              hintText: 'Pickup location',
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onChanged: onPickupChanged,
          ),
          Divider(height: 1),
          TextField(
            controller: dropController,
            enabled: editable,
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.location_on_outlined, color: Colors.black),
              suffixIcon: IconButton(
                icon: Icon(isListening ? Icons.mic : Icons.mic_none,
                    color: Colors.black),
                onPressed: onMicPressed,
              ),
              hintText: 'Drop location',
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onChanged: onDropChanged,
          ),
        ],
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  final List<String> history;
  final ValueChanged<Map<String, dynamic>> onHistorySelected;

  const _HistoryList({
    required this.history,
    required this.onHistorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Recent Rides',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...history.map((item) => ListTile(
              leading: Icon(Icons.history, color: Colors.grey),
              title: Text(item),
              onTap: () =>
                  onHistorySelected({'description': item, 'place_id': ''}),
            )),
      ],
    );
  }
}

class _SuggestionList extends StatelessWidget {
  final List<Map<String, dynamic>> suggestions;
  final ValueChanged<Map<String, dynamic>> onSuggestionSelected;

  const _SuggestionList({
    required this.suggestions,
    required this.onSuggestionSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: suggestions
          .map((suggestion) => ListTile(
                leading: Icon(Icons.location_on, color: Colors.blue),
                title: Text(suggestion['description']),
                onTap: () => onSuggestionSelected(suggestion),
              ))
          .toList(),
    );
  }
}

class _FarePanel extends StatelessWidget {
  final Map<String, double> fares;
  final bool loading;
  final String? selectedVehicle;
  final double? durationSec;
  final ValueChanged<String> onVehicleSelected;
  final VoidCallback onConfirmRide;
  final bool showAll;

  const _FarePanel({
    required this.fares,
    required this.loading,
    required this.selectedVehicle,
    required this.durationSec,
    required this.onVehicleSelected,
    required this.onConfirmRide,
    required this.showAll,
  });

  String _formatDuration(double seconds) {
    final duration = Duration(seconds: seconds.round());
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    }
    return '${duration.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (fares.isEmpty) {
      return SizedBox.shrink();
    }

final vehiclesToShow = showAll
    ? vehicleLabels
    : (selectedVehicle != null ? [selectedVehicle!] : [vehicleLabels.first]);

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: vehiclesToShow.map((vehicle) {
                final fare = fares[vehicle];
                return _FareCard(
                  vehicle: vehicle,
                  fare: fare,
                  selected: selectedVehicle == vehicle,
                  onTap: () => onVehicleSelected(vehicle),
                );
              }).toList(),
            ),
          ),
          SizedBox(height: 16),
          if (durationSec != null)
            Text(
              'Duration: ${_formatDuration(durationSec!)}',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
          SizedBox(height: 16),
          //... inside _FarePanel widget
ElevatedButton(
  // The button is disabled (onPressed is null) if no vehicle is selected.
  // Otherwise, it's enabled with the onConfirmRide function.
  onPressed: selectedVehicle != null ? onConfirmRide : null,
  style: ElevatedButton.styleFrom(
    // You can also change the color based on the state for a clearer visual cue
    backgroundColor: selectedVehicle != null ? Colors.blue[900] : Colors.grey,
    minimumSize: Size(double.infinity, 50),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(25),
    ),
  ),
  child: Text(
    'Confirm Ride',
    style: GoogleFonts.poppins(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: Colors.white,
    ),
  ),
),
        ],
      ),
    );
  }
}

class _FareCard extends StatelessWidget {
  final String vehicle;
  final double? fare;
  final bool selected;
  final VoidCallback onTap;

  const _FareCard({
    required this.vehicle,
    required this.fare,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        margin: EdgeInsets.only(right: 12),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? Colors.blue[50] : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: selected ? Border.all(color: Colors.blue, width: 2) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              vehicleAssets[vehicle]!,
              height: 60,
              width: 60,
              fit: BoxFit.contain,
            ),
            SizedBox(height: 8),
            Text(
              vehicle.toUpperCase(),
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              fare != null ? '₹${fare!.toStringAsFixed(0)}' : '--',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
