import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http_parser/http_parser.dart'; // Add this import
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';

/* ─── config ─── */
const _BASE = 'http://192.168.190.33:5002';
const _HEAD = {'User-Agent': 'GoIndiaApp'}; // Nominatim politeness

/* ─── tiny model ─── */
class _Loc {
  _Loc(this.name, this.lat, this.lon);
  final String name;
  final double lat;
  final double lon;
}

/* ─── page ─── */
class ParcelLocationPage extends StatefulWidget {
  final String customerId;
  const ParcelLocationPage({super.key, required this.customerId});

  @override
  State<ParcelLocationPage> createState() => _ParcelLocationPageState();
}

class _ParcelLocationPageState extends State<ParcelLocationPage> {
  /* text controllers */
  final pickupCtl = TextEditingController();
  final dropCtl = TextEditingController();
  final houseCtl = TextEditingController();
  final nameCtl = TextEditingController();
  final phoneCtl = TextEditingController();
  final weightCtl = TextEditingController();
  final notesCtl = TextEditingController();

  /* map */
  final MapController _map = MapController();
  LatLng mapCenter = const LatLng(20.5937, 78.9629);
  LatLng? pickup, drop;
  List<LatLng> routePts = [];

  /* state */
  double? _km, _cost;
  bool _loading = false; // ← single flag
  File? _photo;
  String _payment = 'Prepaid';
  bool _useMyContact = false;

  /* favourites */
  final favs = <String, _Loc>{};

  /* ───────── init ───────── */
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initGPS());
  }

  Future<void> _initGPS() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.medium)
          .timeout(const Duration(seconds: 3));
      pickup = LatLng(pos.latitude, pos.longitude);
      mapCenter = pickup!;
      pickupCtl.text = 'Current location';
      if (mounted) {
        _map.move(mapCenter, 15);
        setState(() {});
      }
    } catch (_) {}
  }

  /* ───────── search helpers ───────── */
  Future<List<_Loc>> _suggest(String q) async {
    if (q.length < 2) return [];
    final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&q=$q&limit=8');
    final res = await http.get(uri, headers: _HEAD);
    if (res.statusCode != 200) return [];
    return (jsonDecode(res.body) as List)
        .map((e) => _Loc(
            e['display_name'], double.parse(e['lat']), double.parse(e['lon'])))
        .toList();
  }

  Future<void> _choose(_Loc l, {required bool isPickup}) async {
    setState(() {
      if (isPickup) {
        pickup = LatLng(l.lat, l.lon);
      } else {
        drop = LatLng(l.lat, l.lon);
      }
    });
    _route();
  }

  Future<void> postParcelTrip({
    required String customerId,
    required Map<String, dynamic> pickup,
    required Map<String, dynamic> drop,
    required String vehicleType,
    required Map<String, dynamic> parcelDetails,
  }) async {
    final url = Uri.parse('$_BASE/api/parcels/create');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        "customerId": widget.customerId,
        "pickup": pickup,
        "drop": drop,
        "vehicleType": vehicleType,
        "parcelDetails": parcelDetails,
      }),
    );

    final data = jsonDecode(response.body);
    print('📦 Parcel Trip Response: $data');

    if (response.statusCode == 200 && data["success"]) {
      // success
    } else {
      // handle error
    }
  }

  /* ───────── routing + estimate ───────── */
  Future<void> _route() async {
    if (pickup == null || drop == null) return;
    setState(() => _loading = true);

    final uri = Uri.parse('https://router.project-osrm.org/route/v1/driving/'
        '${pickup!.longitude},${pickup!.latitude};'
        '${drop!.longitude},${drop!.latitude}?overview=full&geometries=geojson');

    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final geo = jsonDecode(res.body);
        final coords = geo['routes'][0]['geometry']['coordinates'] as List;
        routePts = coords.map((c) => LatLng(c[1], c[0])).toList();
        _km = (geo['routes'][0]['distance'] as num) / 1000.0;

        _map.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(routePts),
            padding: const EdgeInsets.all(80),
            maxZoom: 17,
          ),
        );

        await _estimate();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _estimate() async {
    if (_km == null) return;
    setState(() => _loading = true);

    // Reverse geocode pickup to get state/city
    String state = '', city = '';
    try {
      final rev = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${pickup!.latitude}&lon=${pickup!.longitude}&addressdetails=1');
      final res = await http.get(rev, headers: _HEAD);
      if (res.statusCode == 200) {
        final addr = jsonDecode(res.body)['address'];
        state = addr['state'] ?? '';
        city = addr['city'] ?? addr['town'] ?? addr['village'] ?? '';
      }
    } catch (_) {}

    final body = {
      'state': state,
      'city': city,
      'vehicleType': 'bike',
      'category': 'parcel',
      'distanceKm': _km,
      'weight': double.tryParse(weightCtl.text) ?? 0,
    };

    try {
      final res = await http.post(
        Uri.parse('$_BASE/api/parcels/estimate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (res.statusCode == 200) {
        _cost = (jsonDecode(res.body)['cost'] as num).toDouble();
      }
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  /* ───────── confirm ───────── */
  String? _error() {
    if (pickup == null || drop == null) return 'Select pickup & drop';
    if (_photo == null) return 'Attach parcel photo';
    if (nameCtl.text.trim().isEmpty) return 'Receiver name required';
    if (phoneCtl.text.length != 10) return 'Phone must be 10 digits';
    return null;
  }

  Future<void> _confirm() async {
    final err = _error();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }

    setState(() => _loading = true);

    // Use values from `_estimate()` for state and city
    String state = '', city = '';
    try {
      final rev = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${pickup!.latitude}&lon=${pickup!.longitude}&addressdetails=1');
      final res = await http.get(rev, headers: _HEAD);
      if (res.statusCode == 200) {
        final addr = jsonDecode(res.body)['address'];
        state = addr['state'] ?? '';
        city = addr['city'] ?? addr['town'] ?? addr['village'] ?? '';
      }
    } catch (_) {}

    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$_BASE/api/parcels/create'),
    )
      ..fields.addAll({
        'state': state,
        'city': city,
        'vehicleType': 'bike',
        'category': 'parcel',
        'distanceKm': _km.toString(),
        'weight': weightCtl.text,
        'pickupLat': pickup!.latitude.toString(),
        'pickupLng': pickup!.longitude.toString(),
        'dropLat': drop!.latitude.toString(),
        'dropLng': drop!.longitude.toString(),
        'receiverName': nameCtl.text.trim(),
        'receiverPhone': phoneCtl.text.trim(),
        'notes': notesCtl.text,
        'payment': _payment,
      })
      ..files.add(await http.MultipartFile.fromPath(
        'parcelPhoto',
        _photo!.path,
        contentType:
            MediaType('image', 'jpeg'), // or 'png' if your image is PNG
      ));
    http.StreamedResponse res;
    try {
      res = await req.send();
    } catch (_) {
      res = http.StreamedResponse(Stream.empty(), 500);
    }

    setState(() => _loading = false);

    if (res.statusCode == 201) {
      final data = jsonDecode(await res.stream.bytesToString());

      _slip(data);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Booking failed')));
    }
  }

  void _slip(Map data) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Parcel Confirmed'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _kv('Pickup', pickupCtl.text),
          _kv('Drop', dropCtl.text),
          _kv('Receiver', nameCtl.text),
          _kv('Phone', phoneCtl.text),
          const Divider(),
          _kv('Cost', '₹ ${data['cost'] ?? _cost ?? '--'}'),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK'))
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k),
            Text(v, style: const TextStyle(fontWeight: FontWeight.bold))
          ],
        ),
      );

  /* ───────── UI ───────── */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SlidingUpPanel(
        minHeight: 300,
        maxHeight: 560,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        panelBuilder: _sheet,
        body: Stack(
          children: [
            _mapWidget(),
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 12,
              right: 12,
              child: _addressCard(),
            ),
          ],
        ),
      ),
    );
  }

  /* ── map ── */
  Widget _mapWidget() => FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: mapCenter, // ← new names
          initialZoom: 5,
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
                width: 32,
                height: 32,
                child: const Icon(Icons.my_location, color: Colors.green),
              ),
            ]),
          if (drop != null)
            MarkerLayer(markers: [
              Marker(
                point: drop!,
                width: 32,
                height: 32,
                child: const Icon(Icons.flag, color: Colors.red),
              ),
            ]),
          if (routePts.isNotEmpty)
            PolylineLayer(polylines: [
              Polyline(points: routePts, strokeWidth: 4, color: Colors.blue),
            ]),
        ],
      );

  /* ── top address card ── */
  Widget _addressCard() => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.circle, size: 10, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dropCtl.text.isEmpty ? 'Select drop location' : dropCtl.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: _editLocations,
                child: const Text('Edit'),
              )
            ],
          ),
        ),
      );

  Future<void> _editLocations() async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Set location'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _typeAhead(pickupCtl, 'Pickup', isPickup: true),
            const SizedBox(height: 8),
            _typeAhead(dropCtl, 'Drop', isPickup: false),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _typeAhead(TextEditingController c, String hint,
          {required bool isPickup}) =>
      TypeAheadField<_Loc>(
        suggestionsCallback: _suggest,
        itemBuilder: (_, l) => ListTile(
            title: Text(l.name, maxLines: 2, overflow: TextOverflow.ellipsis)),
        onSelected: (l) {
          c.text = l.name;
          _choose(l, isPickup: isPickup);
        },
        builder: (_, tf, f) {
          tf.text = c.text;
          return TextField(
            controller: tf,
            focusNode: f,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: hint,
              prefixIcon: Icon(
                  isPickup ? Icons.my_location : Icons.location_on_outlined),
            ),
          );
        },
      );

  /* ── bottom sheet ── */
  Widget _sheet(ScrollController sc) => ListView(
        controller: sc,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(3)))),
          const SizedBox(height: 12),
          TextField(
            controller: houseCtl,
            decoration: const InputDecoration(
              labelText: 'House / Building (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('Add contact details',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: nameCtl,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.person),
              labelText: 'Name *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _useMyContact,
            onChanged: (v) => setState(() => _useMyContact = v!),
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Use my contact for this booking'),
          ),
          TextField(
            controller: phoneCtl,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.phone),
              labelText: 'Phone number *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          _photoPicker(),
          const SizedBox(height: 8),
          TextField(
            controller: weightCtl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Weight (kg, ≤10) optional',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: notesCtl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: ['Prepaid', 'COD']
                .map((m) => Expanded(
                      child: RadioListTile<String>(
                        title: Text(m),
                        value: m,
                        groupValue: _payment,
                        onChanged: (v) => setState(() => _payment = v!),
                      ),
                    ))
                .toList(),
          ),
          if (_cost != null)
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: ListTile(
                leading: const Icon(Icons.receipt_long),
                title: const Text('Estimated cost'),
                trailing: Text('₹ ${_cost!.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _loading ? null : _confirm,
              child: _loading
                  ? const CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)
                  : const Text('Confirm parcel details'),
            ),
          ),
        ],
      );

  Widget _photoPicker() => GestureDetector(
        onTap: () async {
          final x = await ImagePicker()
              .pickImage(source: ImageSource.gallery, imageQuality: 80);
          if (x != null) setState(() => _photo = File(x.path));
        },
        child: Container(
          height: 140,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey),
          ),
          alignment: Alignment.center,
          child: _photo == null
              ? const Icon(Icons.camera_alt, size: 40, color: Colors.grey)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(_photo!, fit: BoxFit.cover)),
        ),
      );
}
