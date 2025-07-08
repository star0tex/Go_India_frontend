import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();

  TextEditingController nameCtrl = TextEditingController();
  TextEditingController emailCtrl = TextEditingController();
  TextEditingController genderCtrl = TextEditingController();
  TextEditingController dobCtrl = TextEditingController();
  TextEditingController emergencyCtrl = TextEditingController();

  String phone = '';
  String memberSince = '';

  @override
  void initState() {
    super.initState();
    phone = FirebaseAuth.instance.currentUser?.phoneNumber?.replaceAll('+91', '') ?? '';
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    final url = Uri.parse('http://192.168.43.236:5002/api/profile/$phone');
    final res = await http.get(url);

    if (res.statusCode == 200) {
      final user = json.decode(res.body)['user'];
      setState(() {
        nameCtrl.text = user['name'] ?? '';
        emailCtrl.text = user['email'] ?? '';
        genderCtrl.text = user['gender'] ?? '';
        dobCtrl.text = user['dateOfBirth'] ?? '';
        emergencyCtrl.text = user['emergencyContact'] ?? '';
        memberSince = user['memberSince'] ?? '';
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to load profile")),
      );
    }
  }

  Future<void> _updateProfile() async {
    final url = Uri.parse('http://192.168.43.236:5002/api/profile/$phone');
    final res = await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'name': nameCtrl.text.trim(),
        'email': emailCtrl.text.trim(),
        'gender': genderCtrl.text.trim(),
        'dateOfBirth': dobCtrl.text.trim(),
        'emergencyContact': emergencyCtrl.text.trim(),
      }),
    );

    if (res.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Profile Updated")));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to update")));
    }
  }

  Widget _buildInput(String label, TextEditingController ctrl, IconData icon, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: ctrl,
        decoration: InputDecoration(
          prefixIcon: Icon(icon),
          labelText: label,
          border: OutlineInputBorder(),
        ),
        validator: (value) {
          if (required && (value == null || value.trim().isEmpty)) {
            return '$label is required';
          }
          return null;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile"),
        backgroundColor: Colors.indigo[900],
        actions: [
          IconButton(icon: Icon(Icons.help_outline), onPressed: () {}),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              _buildInput("Name", nameCtrl, Icons.person, required: true),
              _buildInput("Email", emailCtrl, Icons.email),
              _buildInput("Gender", genderCtrl, Icons.wc),
              _buildInput("Date of Birth", dobCtrl, Icons.cake),
              _buildInput("Emergency Contact", emergencyCtrl, Icons.phone, required: true),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.phone),
                title: const Text("Phone Number"),
                subtitle: Text(phone),
              ),
              ListTile(
                leading: const Icon(Icons.star),
                title: const Text("Member Since"),
                subtitle: Text(memberSince.isNotEmpty ? memberSince : "Fetching..."),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) _updateProfile();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo[900],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text("Update Profile", style: TextStyle(fontSize: 16)),
              )
            ],
          ),
        ),
      ),
    );
  }
}
