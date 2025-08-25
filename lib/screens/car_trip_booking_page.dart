// lib/pages/car_trip_booking_page.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;

class LongTripPage extends StatefulWidget {
  final String customerId;
  const LongTripPage({super.key, required this.customerId});

  @override
  State<LongTripPage> createState() => _CarTripBookingPageState();
}

class _CarTripBookingPageState extends State<LongTripPage> {
  final pickupCtl = TextEditingController();
  final dropCtl = TextEditingController();
  final dateCtl = TextEditingController();
  final daysCtl = TextEditingController(text: '1');

  final MapController mapCtl = MapController();
  LatLng? pickup, drop;
  final List<LatLng> routePts = [];
  LatLng mapCenter = const LatLng(20.5937, 78.9629);

  static const vehicles = ['car', 'premium', 'xl'];
  String selectedVehicle = 'car';
  bool _oneWay = false;
  double? _distanceKm, _durationMin;

  bool _routing = false;
  bool _loadingFare = false;

  final String apiBase = 'http://192.168.43.3:5002';
  late io.Socket _socket;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _initSocket();
  }

  void _initSocket() {
    try {
      _socket = io.io(
        apiBase,
        <String, dynamic>{
          'transports': ['websocket'],
          'autoConnect': true,
        },
      );

     _socket.onConnect((_) {
    print('🟢 Customer socket connected');
    if (widget.customerId.isNotEmpty) {
      _socket.emit('customer:register', {'customerId': widget.customerId});
    }});

      _socket.onDisconnect((_) {
        print('🔴 Customer socket disconnected');
      });

      _socket.onError((err) {
        print('⚠️ Customer socket error: $err');
      });
    } catch (e) {
      print('⚠️ Failed to init socket: $e');
    }
  }

  Future<void> _initLocation() async {
    Position? pos = await Geolocator.getLastKnownPosition();
    pos ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    pickup = LatLng(pos.latitude, pos.longitude);
    mapCenter = pickup!;
    pickupCtl.text = 'Current location';
    setState(() {});
    mapCtl.move(mapCenter, 15);
  }

  Future<List<_Loc>> _suggest(String q) async {
    if (q.trim().length < 2) return [];
    final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&q=$q&limit=8');
    final res = await http.get(uri, headers: {'User-Agent': 'GoIndiaApp'});
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body) as List;
    return data
        .map((e) => _Loc(
              e['display_name'],
              double.parse(e['lat']),
              double.parse(e['lon']),
            ))
        .toList();
  }

  Future<void> _selectLoc(_Loc loc, {required bool isPickup}) async {
    if (isPickup) {
      pickup = LatLng(loc.lat, loc.lon);
    } else {
      drop = LatLng(loc.lat, loc.lon);
    }
    await _updateRoute();
  }

  Future<void> _updateRoute() async {
    if (pickup == null || drop == null) return;
    setState(() => _routing = true);

    final start = '${pickup!.longitude},${pickup!.latitude}';
    final end = '${drop!.longitude},${drop!.latitude}';
    final uri = Uri.parse('https://router.project-osrm.org/route/v1/driving/'
        '$start;$end?overview=full&geometries=geojson');

    final res = await http.get(uri);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final coords = data['routes'][0]['geometry']['coordinates'] as List;
      routePts
        ..clear()
        ..addAll(coords.map((c) => LatLng(c[1], c[0])));
      _distanceKm = (data['routes'][0]['distance'] as num) / 1000.0;
      _durationMin = (data['routes'][0]['duration'] as num) / 60.0;
    }

    setState(() => _routing = false);
    _fitBounds();
  }

  void _fitBounds() {
    if (routePts.isEmpty) return;
    final bounds = LatLngBounds.fromPoints(routePts);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      mapCtl.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(80),
          maxZoom: 17,
        ),
      );
    });
  }

  Future<void> _fetchAndShowFare(String vehicle) async {
    if (_distanceKm == null || _durationMin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select both points first')));
      return;
    }

    setState(() => _loadingFare = true);
    try {
      final uri = Uri.parse('$apiBase/api/fares/calc');
      final body = {
        'state': 'telangana',
        'city': 'hyderabad',
        'vehicleType': vehicle.toLowerCase(),
        'category': 'long',
        'distanceKm': _distanceKm,
        'durationMin': _durationMin,
        'tripDays': int.tryParse(daysCtl.text) ?? 1,
        'returnTrip': !_oneWay,
        'surge': null,
        'weight': null,
      };

      final res = await http.post(uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (!mounted) return;
        _showFareSheet(vehicle.toLowerCase(), data);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Backend error ${res.statusCode}')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loadingFare = false);
    }
  }

  Future<void> postLongTrip({
    required String customerId,
    required Map<String, dynamic> pickup,
    required Map<String, dynamic> drop,
    required String vehicleType,
    required bool isSameDay,
    required int tripDays,
    required bool returnTrip,
  }) async {
    final url = Uri.parse('$apiBase/api/trips/long');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        "customerId": customerId,
        "pickup": pickup,
        "drop": drop,
        "vehicleType": vehicleType.toLowerCase(),
        "isSameDay": isSameDay,
        "tripDays": tripDays,
        "returnTrip": returnTrip,
        "tripDate": dateCtl.text, // Or ISO format
      }),
    );

    final data = jsonDecode(response.body);
    print('🔁 Long Trip Response: $data');

    if (response.statusCode == 200 &&
        data["success"] &&
        data['tripId'] != null) {
      final tripId = data['tripId'];
      print('📤 Trip created ($tripId) — emitting customer:request_trip');
      try {
        _socket.emit('customer:request_trip', {'tripId': tripId});
      } catch (e) {
        print('⚠️ Socket emit failed: $e');
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to create trip. Please try again.')),
      );
    }
  }

  void _showFareSheet(String vehicle, Map data) {
    final total = data['total'] ?? data['fare'] ?? '--';
    final driver = data['driver'] ?? data['driverFare'] ?? '--';
    final fuel = data['fuel'] ?? data['fuelFare'] ?? '--';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 12),
              Text('Fare Estimate',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              _pair('Vehicle', vehicle),
              _pair('Distance', '${_distanceKm!.toStringAsFixed(1)} km'),
              _pair('Duration', '${_durationMin!.round()} min'),
              _pair('Days', daysCtl.text),
              _pair('Trip type', _oneWay ? 'One Way' : 'Return'),
              const Divider(height: 32),
              _pair('Driver Charge', '₹$driver'),
              _pair('Fuel Estimate', '₹$fuel'),
              const SizedBox(height: 8),
              Text('Total   ₹$total',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    if (pickup == null || drop == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'Please select both pickup and drop locations.')));
                      return;
                    }
                    if (widget.customerId.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Login required. Please re-login.')));
                      return;
                    }

                    final pickupData = {
                      "address": pickupCtl.text,
                      "coordinates": [
                        pickup!.latitude,
                        pickup!.longitude
                      ], // ✅ Correct order
                    };
                    final dropData = {
                      "address": dropCtl.text,
                      "coordinates": [
                        drop!.latitude,
                        drop!.longitude
                      ], // ✅ Correct order
                    };

                    await postLongTrip(
                      customerId: widget.customerId,
                      pickup: pickupData,
                      drop: dropData,
                      vehicleType: selectedVehicle,
                      isSameDay: true,
                      tripDays: int.tryParse(daysCtl.text) ?? 1,
                      returnTrip: !_oneWay,
                    );

                    if (!mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Trip confirmed and sent to backend.')));
                  },
                  child: const Text('Confirm Trip'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pair(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Book Car Trip')),
      body: Column(
        children: [
          _topForm(),
          _map(),
          _vehicleRow(),
          if (_loadingFare) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }

  Widget _topForm() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          children: [
            _typeAhead(pickupCtl, 'Pickup location', isPickup: true),
            const SizedBox(height: 8),
            _typeAhead(dropCtl, 'Destination', isPickup: false),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 5,
                  child: TextField(
                    controller: dateCtl,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Trip Date',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.date_range),
                    ),
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: now,
                        lastDate: now.add(const Duration(days: 365)),
                        initialDate: now.add(const Duration(days: 2)),
                      );
                      if (picked != null) {
                        dateCtl.text =
                            '${picked.day}/${picked.month}/${picked.year}';
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: daysCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Days',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('Return Trip'),
                  selected: !_oneWay,
                  onSelected: (v) => setState(() => _oneWay = !v),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('One Way'),
                  selected: _oneWay,
                  onSelected: (v) => setState(() => _oneWay = v),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _map() => Expanded(
        child: Stack(
          children: [
            FlutterMap(
              mapController: mapCtl,
              options: MapOptions(
                initialCenter: mapCenter,
                initialZoom: 15,
                maxZoom: 19,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.goindia.app',
                ),
                if (pickup != null)
                  MarkerLayer(markers: [
                    Marker(
                        point: pickup!,
                        width: 28,
                        height: 28,
                        child:
                            const Icon(Icons.location_on, color: Colors.green)),
                  ]),
                if (drop != null)
                  MarkerLayer(markers: [
                    Marker(
                        point: drop!,
                        width: 28,
                        height: 28,
                        child: const Icon(Icons.flag, color: Colors.red)),
                  ]),
                if (routePts.isNotEmpty)
                  PolylineLayer(polylines: [
                    Polyline(
                        points: routePts, strokeWidth: 4, color: Colors.blue),
                  ]),
              ],
            ),
            if (_routing)
              const Positioned.fill(
                  child: Center(child: CircularProgressIndicator())),
          ],
        ),
      );

  Widget _vehicleRow() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.white,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: vehicles.map((v) {
            final sel = v == selectedVehicle;
            String asset = v == 'xl'
                ? 'assets/images/xl.png'
                : v == 'premium'
                    ? 'assets/images/Primium.png'
                    : 'assets/images/car.png';
            return GestureDetector(
              onTap: () {
                setState(() => selectedVehicle = v);
                _fetchAndShowFare(v);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: sel ? Colors.blue[50] : Colors.grey[200],
                          borderRadius: BorderRadius.circular(16),
                          border: sel
                              ? Border.all(color: Colors.blue, width: 2)
                              : null),
                      child: Image.asset(asset, height: 40, width: 40)),
                  const SizedBox(height: 4),
                  Text(v, style: const TextStyle(fontSize: 12)),
                ],
              ),
            );
          }).toList(),
        ),
      );

  Widget _typeAhead(TextEditingController ctl, String hint,
          {required bool isPickup}) =>
      TypeAheadField<_Loc>(
        suggestionsCallback: _suggest,
        itemBuilder: (_, s) => ListTile(
            title: Text(s.name, maxLines: 2, overflow: TextOverflow.ellipsis)),
        onSelected: (s) {
          ctl.text = s.name;
          _selectLoc(s, isPickup: isPickup);
        },
        hideOnLoading: true,
        builder: (context, tfCtl, focus) {
          tfCtl.text = ctl.text;
          return TextField(
            controller: tfCtl,
            focusNode: focus,
            decoration: InputDecoration(
              prefixIcon: Icon(
                  isPickup ? Icons.my_location : Icons.location_on_outlined),
              hintText: hint,
              border: const OutlineInputBorder(),
            ),
          );
        },
      );

  @override
  void dispose() {
    try {
      _socket.dispose();
    } catch (_) {}
    pickupCtl.dispose();
    dropCtl.dispose();
    dateCtl.dispose();
    daysCtl.dispose();
    super.dispose();
  }
}

class _Loc {
  _Loc(this.name, this.lat, this.lon);
  final String name;
  final double lat;
  final double lon;
}
