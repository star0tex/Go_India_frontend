import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';

class OpenStreetLocationPage extends StatefulWidget {
  const OpenStreetLocationPage({super.key, this.initialDrop = '',this.selectedVehicle});
  final String initialDrop;
  final String? selectedVehicle;

  @override
  State<OpenStreetLocationPage> createState() => _OpenStreetLocationPageState();
}

class _OpenStreetLocationPageState extends State<OpenStreetLocationPage> {
  final pickupController = TextEditingController();
  final dropController = TextEditingController();
  late final stt.SpeechToText _speech;
  bool _isListening = false;

  LatLng? pickupPoint;
  LatLng? dropPoint;
  LatLng mapCenter = const LatLng(17.3850, 78.4867);

  final MapController _mapController = MapController();
  final List<Marker> _markers = [];
  final List<LatLng> _routePoints = [];
  double? _distanceKm;
  double? _durationSec;

  static const _historyKey = 'location_history';
  List<String> _history = [];

  final String apiBase = 'http://192.168.43.236:5002/api/fares/calc';
  final List<String> vehicles = ['bike', 'Auto', 'Car','Premium Car','Parcel','Car XL'];
  final Map<String, double> _vehicleFares = {};
  // ignore: unused_field
  bool _loadingFares = false;
String? selectedVehicle;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    selectedVehicle = widget.selectedVehicle;
    _bootstrap();
  }
Future<void> _bootstrap() async {
  await _setCurrentLocation();
  await _loadHistory();
  await _clearBadHistory();

  // If user came from search bar
  if (widget.initialDrop.isNotEmpty) {
    dropController.text = widget.initialDrop;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchLocation(widget.initialDrop, isPickup: false);
      
      // If user came from search bar, show all fares
      setState(() {
        selectedVehicle = null; // 🔁 Show ALL vehicles
      });
    });
  } else if (widget.selectedVehicle != null) {
    // If user came from vehicle tap, show only that vehicle fare
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
      final current = LatLng(pos.latitude, pos.longitude);
      final name = await _reverseGeocode(current);

      setState(() {
        pickupPoint = current;
        mapCenter = current;
        pickupController.text = name;
        _markers.add(_buildMarker(current, isPickup: true));
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(current, 15);
      });
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  Future<String> _reverseGeocode(LatLng latLng) async {
    final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=${latLng.latitude}&lon=${latLng.longitude}&format=json');
    final res = await http.get(url, headers: const {'User-Agent': 'FlutterApp'});
    if (res.statusCode != 200) return 'Current Location';
    return (jsonDecode(res.body) as Map)["display_name"] ?? 'Current Location';
  }

  void _searchLocation(String query, {required bool isPickup}) async {
    if (query.trim().isEmpty) return;
    final loc = await NominatimHelper.search(query.trim());
    if (loc == null) return;
    final point = LatLng(loc.latitude, loc.longitude);

    setState(() {
      mapCenter = point;
      _markers.removeWhere((m) {
        final icon = m.child as Icon;
        return isPickup ? icon.color == Colors.black : icon.color == Colors.red;
      });
      _markers.add(_buildMarker(point, isPickup: isPickup));

      if (isPickup) {
        pickupPoint = point;
      } else {
        dropPoint = point;
      }

      _addToHistory(loc.displayName);
    });

    if (pickupPoint != null && dropPoint != null) {
      await _drawRoute();
    } else {
      _mapController.move(point, 15);
    }
  }

  Marker _buildMarker(LatLng p, {required bool isPickup}) {
    return Marker(
      point: p,
      width: 60,
      height: 60,
      child: Icon(
        isPickup ? Icons.location_on : Icons.flag,
        size: 38,
        color: isPickup ? Colors.black : Colors.red,
      ),
    );
  }

  Future<void> _drawRoute() async {
    if (pickupPoint == null || dropPoint == null) return;
    final start = '${pickupPoint!.longitude},${pickupPoint!.latitude}';
    final end = '${dropPoint!.longitude},${dropPoint!.latitude}';

    final url = Uri.parse(
        'https://routing.openstreetmap.de/routed-bike/route/v1/driving/$start;$end?overview=full&geometries=geojson');
    final res = await http.get(url);
    if (res.statusCode != 200) return;

    final data = jsonDecode(res.body);
    final coords = data['routes'][0]['geometry']['coordinates'] as List;
    final distance = (data['routes'][0]['distance'] as num).toDouble() / 1000.0;
    final duration = (data['routes'][0]['duration'] as num).toDouble();

    setState(() {
      _routePoints
        ..clear()
        ..addAll(coords.map<LatLng>((c) => LatLng(c[1], c[0])));
      _distanceKm = distance;
      _durationSec = duration;
    });

    _fetchFares();
    _fitMapToBounds();
  }

  void _fitMapToBounds() {
    if (pickupPoint == null || dropPoint == null) return;
    final sw = LatLng(
      [pickupPoint!.latitude, dropPoint!.latitude].reduce((a, b) => a < b ? a : b),
      [pickupPoint!.longitude, dropPoint!.longitude].reduce((a, b) => a < b ? a : b),
    );
    final ne = LatLng(
      [pickupPoint!.latitude, dropPoint!.latitude].reduce((a, b) => a > b ? a : b),
      [pickupPoint!.longitude, dropPoint!.longitude].reduce((a, b) => a > b ? a : b),
    );
    _mapController.fitBounds(
      LatLngBounds(sw, ne),
      options: const FitBoundsOptions(padding: EdgeInsets.all(80)),
    );
  }

  Future<void> _fetchFares() async {
    if (_distanceKm == null || _durationSec == null) return;
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
            'state': 'telangana',
            'city': 'hyderabad',
            'vehicleType': v,
            'distanceKm': _distanceKm,
            'durationMin': _durationSec! / 60.0,
          }),
        );
        if (res.statusCode == 200) {
          final total = (jsonDecode(res.body)['total'] as num).toDouble();
          setState(() => _vehicleFares[v] = total);
        }
      } catch (e) {
        debugPrint('Fare API error: $e');
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
    return lower.contains('auto') || lower.contains('bike') || lower.contains('car');
  });
  await sp.setStringList(_historyKey, _history);
}



void _addToHistory(String place) {
  final lower = place.toLowerCase();
  if (['auto', 'bike', 'car'].contains(lower)) return; // ✅ prevent pollution

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
    final invalid = ['auto', 'bike', 'car'];
    if (!invalid.contains(txt.toLowerCase()) && txt.length > 3) {
      dropController.text = txt;
      _searchLocation(txt, isPickup: false);
    }
  }
});

  }

  Future<List<LocationResult>> _suggestions(String pattern) async {
    if (pattern.trim().length < 2) return [];

    final nearby = pickupPoint ?? dropPoint ?? mapCenter;
    final remote = await NominatimHelper.autocomplete(pattern, center: nearby);
    final hist = _history
    .where((h) {
      final lower = h.toLowerCase();
      return !['auto', 'bike', 'car'].contains(lower) &&
             h.toLowerCase().startsWith(pattern.toLowerCase());
    })
    .map((h) => LocationResult(latitude: 0, longitude: 0, displayName: h))
    .toList();


    final merged = <String, LocationResult>{};
    for (var r in [...hist, ...remote]) {
      merged[r.displayName] = r;
    }
    return merged.values.toList();
  }

  Widget _buildSearchField({
    required TextEditingController controller,
    required String hint,
    required bool isPickup,
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
        onSelected: (s) {
          controller.text = s.displayName;
          _searchLocation(s.displayName, isPickup: isPickup);
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
                      onPressed: () => _searchLocation(
                          controller.text.trim(),
                          isPickup: true),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon:
                              Icon(_isListening ? Icons.mic : Icons.mic_none),
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
    return selectedVehicle == null || selectedVehicle == v;
  }).map((v) {
    String asset = 'assets/images/$v.png';
    if (v == 'Bike') asset = 'assets/images/bike.png';
    if (v == 'Auto') asset = 'assets/images/auto.png';
    if (v == 'Car') asset = 'assets/images/car.png';
    if (v == 'Primer Car') asset = 'assets/images/Primium.png';
    if (v == 'Car XL') asset = 'assets/images/Primium.png';
    if (v == 'Parcel') asset = 'assets/images/parcel.png';
    if (v == 'Car Trip') asset = 'assets/images/Primium.png';
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedVehicle = v;
        });
      },
      child: _fareCard(
        v,
        asset,
        _vehicleFares[v],
        labelBelow: v == 'Bike' ? 'Quick Bike' : null,
      ),
    );
  }).toList(),
)

        ),
        const SizedBox(height: 20),
        if (_durationSec != null)
          Text(
            'Duration: ${_prettyDuration(_durationSec!)}',
            style: TextStyle(fontSize: 14, color: Colors.grey[800]),
          ),
        const SizedBox(height: 10),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[900],
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          onPressed: () {
            if (selectedVehicle != null && _vehicleFares[selectedVehicle!] != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Confirmed ${selectedVehicle!} Ride!')),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please select a vehicle first')),
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


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
  mapController: _mapController,
  options: MapOptions(center: mapCenter, zoom: 15, maxZoom: 19),
  children: [
    TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.example.app',
    ),
    MarkerLayer(markers: _markers),
    if (_routePoints.isNotEmpty)
      PolylineLayer(polylines: [
        Polyline(points: _routePoints, strokeWidth: 4, color: Colors.blue),
      ]),
  ],
),
              Positioned(
      top: 40,
      left: 20,
      right: 20,
      child: Column(
        children: [
          _buildSearchField(
            controller: pickupController,
            hint: 'Enter pickup location',
            isPickup: true,
          ),
          const SizedBox(height: 10),
          _buildSearchField(
            controller: dropController,
            hint: 'Enter drop location',
            isPickup: false,
          ),
        ],
      ),
    ),

    // 🟢 Bottom Panel
    Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: _bottomPanel(),
          ),
       ],
      ),
    );
  }
}
Widget _fareCard(String label, String assetPath, double? fare, {String? labelBelow}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 300,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Image.asset(assetPath, height: 150, width: 150),
      ),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      Text(fare != null ? '₹${fare.toStringAsFixed(0)}' : '₹--'),
      if (labelBelow != null)
        Text(labelBelow, style: const TextStyle(fontSize: 10, color: Colors.blue)),
    ],
  );
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

class NominatimHelper {
  static const _headers = {'User-Agent': 'FlutterApp'};

  static Future<LocationResult?> search(String q) async {
    final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=$q&format=json&limit=1');
    final res = await http.get(url, headers: _headers);
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as List;
    if (data.isEmpty) return null;
    final item = data[0];
    return LocationResult(
      latitude: double.parse(item['lat']),
      longitude: double.parse(item['lon']),
      displayName: item['display_name'],
    );
  }

  static Future<List<LocationResult>> autocomplete(String q,
      {LatLng? center}) async {
    if (q.trim().isEmpty) return [];
    const limit = 10;
    final baseUrl =
        'https://nominatim.openstreetmap.org/search?format=json&addressdetails=1&limit=$limit&q=$q';

    String urlStr;
    if (center != null) {
      const box = 0.2;
      final west = center.longitude - box;
      final east = center.longitude + box;
      final north = center.latitude + box;
      final south = center.latitude - box;
      urlStr =
          '$baseUrl&viewbox=$west,$north,$east,$south&bounded=1';
    } else {
      urlStr = baseUrl;
    }

    final res = await http.get(Uri.parse(urlStr), headers: _headers);
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body) as List;
    return data
        .map((item) => LocationResult(
              latitude: double.parse(item['lat']),
              longitude: double.parse(item['lon']),
              displayName: item['display_name'],
            ))
        .toList();
  }
}
