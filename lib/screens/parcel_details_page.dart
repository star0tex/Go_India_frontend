import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ParcelDetailsPage extends StatefulWidget {
  final String pickupLocation;
  final String dropLocation;

  const ParcelDetailsPage({
    super.key,
    required this.pickupLocation,
    required this.dropLocation,
  });

  @override
  State<ParcelDetailsPage> createState() => _ParcelDetailsPageState();
}

class _ParcelDetailsPageState extends State<ParcelDetailsPage> {
  File? _image;
  final _picker = ImagePicker();
  final TextEditingController _weight = TextEditingController();
  String _vehicle = 'Bike';            // Bike • LCV • ICV

  Future<void> _pick(ImageSource src) async {
    final picked = await _picker.pickImage(source: src, imageQuality: 80);
    if (picked != null) setState(() => _image = File(picked.path));
  }

  void _submit() {
    if (_image == null || _weight.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add photo and weight')),
      );
      return;
    }

    // TODO: Send multipart request to backend here

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Parcel sent to nearby $_vehicle drivers!')),
    );
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  Widget _vehCard(String label, String img) {
    final sel = _vehicle == label;
    return GestureDetector(
      onTap: () => setState(() => _vehicle = label),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? Colors.blue : Colors.grey),
              color: sel ? Colors.blue.shade50 : Colors.grey.shade100,
            ),
            child: Image.asset(img, height: 60),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parcel Details')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Package photo', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade400),
              ),
              child: _image != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(_image!, fit: BoxFit.cover),
                    )
                  : const Center(child: Text('No image selected')),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Camera'),
                    onPressed: () => _pick(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                    onPressed: () => _pick(ImageSource.gallery),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _weight,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Weight (kg)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.scale),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Select vehicle', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _vehCard('Bike', 'assets/images/bike.png'),
                _vehCard('LCV',  'assets/images/lcv.png'),
                _vehCard('ICV',  'assets/images/icv.png'),
              ],
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              child: const Text('Confirm & Send'),
            ),
          ],
        ),
      ),
    );
  }
}
