import 'package:flutter/material.dart';
import 'parcel_details_page.dart';

class ParcelLocationPage extends StatefulWidget {
  const ParcelLocationPage({super.key});

  @override
  State<ParcelLocationPage> createState() => _ParcelLocationPageState();
}

class _ParcelLocationPageState extends State<ParcelLocationPage> {
  final TextEditingController _pickup = TextEditingController();
  final TextEditingController _drop   = TextEditingController();

  void _next() {
    final from = _pickup.text.trim();
    final to   = _drop.text.trim();
    if (from.isEmpty || to.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter both pickup and drop locations')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ParcelDetailsPage(
          pickupLocation: from,
          dropLocation:   to,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send Parcel – Locations')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _pickup,
              decoration: const InputDecoration(
                labelText: 'Pickup location',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _drop,
              decoration: const InputDecoration(
                labelText: 'Drop location',
                border: OutlineInputBorder(),
              ),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _next,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              child: const Text('Next'),
            ),
          ],
        ),
      ),
    );
  }
}
