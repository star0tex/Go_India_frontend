import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
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

      final url = Uri.parse('https://b23b44ae0c5e.ngrok-free.app/api/user/id/$customerId');
      final res = await http.get(url);

      if (res.statusCode == 200) {
        final user = json.decode(res.body)['user'];
        final emergencyContact = user['emergencyContact'] ?? '';
        
        setState(() {
          phone = user['phone'] ?? phone;
          nameCtrl.text = user['name'] ?? '';
          emailCtrl.text = user['email'] ?? '';
          genderCtrl.text = user['gender'] ?? '';
          dobCtrl.text = user['dateOfBirth'] ?? '';
          emergencyCtrl.text = emergencyContact;
          memberSince = user['memberSince'] ?? '';
          _isLoading = false;
        });
        
        // ✅ FIXED: Save emergency contact immediately after fetching
        if (emergencyContact.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('emergency_contact', emergencyContact);
          debugPrint('✅ Emergency contact saved to SharedPreferences: $emergencyContact');
        }
      } else {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to load profile")),
          );
        }
      }
    } catch (e) {
      debugPrint("❌ Error fetching profile: $e");
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
      final emergencyContact = emergencyCtrl.text.trim();
      
      final url = Uri.parse('https://b23b44ae0c5e.ngrok-free.app/api/user/$phone');
      final res = await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': nameCtrl.text.trim(),
          'email': emailCtrl.text.trim(),
          'gender': genderCtrl.text.trim(),
          'dateOfBirth': dobCtrl.text.trim(),
          'emergencyContact': emergencyContact,
        }),
      );

      if (mounted) {
        if (res.statusCode == 200) {
          // ✅ FIXED: Save emergency contact to SharedPreferences after update
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('emergency_contact', emergencyContact);
          debugPrint('✅ Emergency contact updated in SharedPreferences: $emergencyContact');
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Profile Updated Successfully! 🎉"),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to update")),
          );
        }
      }
    } catch (e) {
      debugPrint("❌ Error updating profile: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  // ✅ SOS CALL FUNCTIONALITY
  Future<void> _makeSOSCall() async {
    final emergencyNumber = emergencyCtrl.text.trim();
    
    if (emergencyNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please add an emergency contact first'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.emergency, color: Colors.red, size: 32),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Emergency Call',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Call emergency contact?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.phone, color: Colors.red),
                  const SizedBox(width: 8),
                  Text(
                    emergencyNumber,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Call Now', style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final phoneUri = Uri(scheme: 'tel', path: emergencyNumber);
        
        if (await canLaunchUrl(phoneUri)) {
          HapticFeedback.heavyImpact();
          await launchUrl(phoneUri);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('📞 Calling emergency contact...'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Unable to make call. Please check your device.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint("❌ Error making SOS call: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildInput(String label, TextEditingController ctrl, IconData icon,
      {bool required = false, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: const Color.fromRGBO(98, 205, 255, 1)),
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color.fromRGBO(98, 205, 255, 1), width: 2),
          ),
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
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color.fromRGBO(98, 205, 255, 1)),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile"),
        backgroundColor: const Color.fromRGBO(98, 205, 255, 1),
        foregroundColor: Colors.white,
        elevation: 0,
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
              _buildInput("Email", emailCtrl, Icons.email, keyboardType: TextInputType.emailAddress),
              _buildInput("Gender", genderCtrl, Icons.wc),
              _buildInput("Date of Birth", dobCtrl, Icons.cake),
              _buildInput(
                "Emergency Contact",
                emergencyCtrl,
                Icons.phone,
                required: true,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.phone, color: Color.fromRGBO(98, 205, 255, 1)),
                title: const Text("Phone Number"),
                subtitle: Text(phone.isNotEmpty ? phone : "Not available"),
                tileColor: Colors.grey.shade100,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.star, color: Color.fromRGBO(98, 205, 255, 1)),
                title: const Text("Member Since"),
                subtitle: Text(memberSince.isNotEmpty ? memberSince : "Not available"),
                tileColor: Colors.grey.shade100,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) _updateProfile();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromRGBO(98, 205, 255, 1),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                child: const Text(
                  "Update Profile",
                  style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 100), // Space for floating button
            ],
          ),
        ),
      ),
      // ✅ SOS FLOATING BUTTON
      floatingActionButton: SOSButton(
        onPressed: _makeSOSCall,
        emergencyNumber: emergencyCtrl.text.trim(),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

// ✅ REUSABLE SOS BUTTON WIDGET
class SOSButton extends StatefulWidget {
  final VoidCallback onPressed;
  final String emergencyNumber;

  const SOSButton({
    Key? key,
    required this.onPressed,
    this.emergencyNumber = '',
  }) : super(key: key);

  @override
  State<SOSButton> createState() => _SOSButtonState();
}

class _SOSButtonState extends State<SOSButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _pulseAnimation = Tween<double>(begin: 0.0, end: 20.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Pulsing circle effect
            Container(
              width: 80 + _pulseAnimation.value,
              height: 80 + _pulseAnimation.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withOpacity(0.3 - (_pulseAnimation.value / 100)),
              ),
            ),
            // Main SOS button
            Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Colors.red, Colors.redAccent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.5),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.heavyImpact();
                      widget.onPressed();
                    },
                    borderRadius: BorderRadius.circular(40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.emergency, color: Colors.white, size: 32),
                        SizedBox(height: 2),
                        Text(
                          'SOS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}