import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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
  String customerId = '';
  String memberSince = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      customerId = prefs.getString('customerId') ?? '';
      phone = prefs.getString('phoneNumber') ?? '';

      if (customerId.isEmpty) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("User not logged in")),
          );
        }
        return;
      }

      await _fetchProfile();
    } catch (e) {
      debugPrint("Error loading user data: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchProfile() async {
    try {
      setState(() => _isLoading = true);

      final url = Uri.parse('https://7668d252ef1d.ngrok-free.app/api/user/id/$customerId');
      final res = await http.get(url);

      if (res.statusCode == 200) {
        final user = json.decode(res.body)['user'];
        setState(() {
          phone = user['phone'] ?? phone;
          nameCtrl.text = user['name'] ?? '';
          emailCtrl.text = user['email'] ?? '';
          genderCtrl.text = user['gender'] ?? '';
          dobCtrl.text = user['dateOfBirth'] ?? '';
          emergencyCtrl.text = user['emergencyContact'] ?? '';
          memberSince = user['memberSince'] ?? '';
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to load profile")),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  Future<void> _updateProfile() async {
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Phone number not available")),
      );
      return;
    }

    try {
      final url = Uri.parse('https://7668d252ef1d.ngrok-free.app/api/user/$phone');
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

      if (mounted) {
        if (res.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Profile Updated")),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to update")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  Widget _buildInput(String label, TextEditingController ctrl, IconData icon,
      {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: ctrl,
        decoration: InputDecoration(
          prefixIcon: Icon(icon),
          labelText: label,
          border: const OutlineInputBorder(),
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
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile"),
        backgroundColor: const Color.fromRGBO(98, 205, 255, 1),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.help_outline), onPressed: () {}),
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
              _buildInput("Emergency Contact", emergencyCtrl, Icons.phone,
                  required: true),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.phone),
                title: const Text("Phone Number"),
                subtitle: Text(phone.isNotEmpty ? phone : "Not available"),
              ),
              ListTile(
                leading: const Icon(Icons.star),
                title: const Text("Member Since"),
                subtitle: Text(memberSince.isNotEmpty ? memberSince : "Not available"),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) _updateProfile();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromRGBO(98, 205, 255, 1),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text("Update Profile",
                    style: TextStyle(fontSize: 16)),
              )
            ],
          ),
        ),
      ),
    );
  }
}