import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_china1/screens/login_page.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';

// ✅ UPDATED COLOR PALETTE (matching ride history)
class AppColors {
  static const Color primary = Color.fromARGB(255, 212, 120, 0);
  static const Color background = Colors.white;
  static const Color onSurface = Colors.black;
  static const Color surface = Color(0xFFF5F5F5);
  static const Color onPrimary = Colors.white;
  static const Color onSurfaceSecondary = Colors.black54;
  static const Color onSurfaceTertiary = Colors.black38;
  static const Color divider = Color(0xFFEEEEEE);
  static const Color success = Color.fromARGB(255, 0, 66, 3);
  static const Color warning = Color(0xFFFFA000);
  static const Color error = Color(0xFFD32F2F);
}

// ✅ UPDATED TYPOGRAPHY (matching ride history)
class AppTextStyles {
  static TextStyle get heading1 => GoogleFonts.plusJakartaSans(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: AppColors.onSurface,
        letterSpacing: -0.5,
      );

  static TextStyle get heading2 => GoogleFonts.plusJakartaSans(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.onSurface,
        letterSpacing: -0.3,
      );

  static TextStyle get heading3 => GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
      );

  static TextStyle get body1 => GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurface,
      );

  static TextStyle get body2 => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurfaceSecondary,
      );

  static TextStyle get caption => GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurfaceTertiary,
        letterSpacing: 0.5,
      );

  static TextStyle get button => GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.onPrimary,
      );
}

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
            SnackBar(
              content: Text("User not logged in", style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary)),
              backgroundColor: AppColors.error,
            ),
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
        
        if (emergencyContact.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('emergency_contact', emergencyContact);
          debugPrint('✅ Emergency contact saved to SharedPreferences: $emergencyContact');
        }
      } else {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Failed to load profile", style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary)),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("❌ Error fetching profile: $e");
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e", style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _updateProfile() async {
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Phone number not available", style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary)),
          backgroundColor: AppColors.warning,
        ),
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
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('emergency_contact', emergencyContact);
          debugPrint('✅ Emergency contact updated in SharedPreferences: $emergencyContact');
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: AppColors.onPrimary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Profile Updated Successfully! 🎉",
                      style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary),
                    ),
                  ),
                ],
              ),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Failed to update", style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary)),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("❌ Error updating profile: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e", style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.logout, color: AppColors.primary, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Logout', style: AppTextStyles.heading3),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to logout?',
          style: AppTextStyles.body1,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: AppTextStyles.body1.copyWith(color: AppColors.onSurfaceSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Logout', style: AppTextStyles.button),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                    const SizedBox(height: 16),
                    Text("Logging out...", style: AppTextStyles.body1),
                  ],
                ),
              ),
            ),
          );
        }

        await FirebaseAuth.instance.signOut();
        debugPrint('✅ Firebase sign-out successful');
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        debugPrint('✅ SharedPreferences cleared');
        
        if (mounted) Navigator.pop(context);
        
        debugPrint('✅ User logged out successfully');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: AppColors.onPrimary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Logged out successfully! 👋',
                      style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary),
                    ),
                  ),
                ],
              ),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
          
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) Navigator.pop(context);
        
        debugPrint("❌ Error during logout: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error logging out: $e', style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary)),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _makeSOSCall() async {
    final emergencyNumber = emergencyCtrl.text.trim();
    
    if (emergencyNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.warning, color: AppColors.onPrimary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '⚠️ Please add an emergency contact first',
                  style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.emergency, color: AppColors.error, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Emergency Call',
                style: AppTextStyles.heading3.copyWith(color: AppColors.error),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Call emergency contact?',
              style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error),
              ),
              child: Row(
                children: [
                  Icon(Icons.phone, color: AppColors.error),
                  const SizedBox(width: 8),
                  Text(
                    emergencyNumber,
                    style: AppTextStyles.heading3.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.bold,
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
            child: Text('Cancel', style: AppTextStyles.body1.copyWith(color: AppColors.onSurfaceSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Call Now', style: AppTextStyles.button),
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
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.phone, color: AppColors.onPrimary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '📞 Calling emergency contact...',
                        style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary),
                      ),
                    ),
                  ],
                ),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Unable to make call. Please check your device.',
                  style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary),
                ),
                backgroundColor: AppColors.error,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint("❌ Error making SOS call: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e', style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary)),
              backgroundColor: AppColors.error,
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
        style: AppTextStyles.body1,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: AppColors.primary),
          labelText: label,
          labelStyle: AppTextStyles.body2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.error),
          ),
          filled: true,
          fillColor: AppColors.background,
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
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
              const SizedBox(height: 16),
              Text('Loading profile...', style: AppTextStyles.body2),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text("Profile", style: AppTextStyles.heading3.copyWith(color: AppColors.onPrimary)),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
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
              
              // Phone Number Card
              Container(
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: ListTile(
                  leading: Icon(Icons.phone, color: AppColors.primary),
                  title: Text("Phone Number", style: AppTextStyles.body1),
                  subtitle: Text(
                    phone.isNotEmpty ? phone : "Not available",
                    style: AppTextStyles.body2,
                  ),
                ),
              ),
              
              const SizedBox(height: 8),
              
              // Member Since Card
              Container(
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: ListTile(
                  leading: Icon(Icons.star, color: AppColors.primary),
                  title: Text("Member Since", style: AppTextStyles.body1),
                  subtitle: Text(
                    memberSince.isNotEmpty ? memberSince : "Not available",
                    style: AppTextStyles.body2,
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Update Profile Button
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) _updateProfile();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                child: Text("Update Profile", style: AppTextStyles.button),
              ),
              
              const SizedBox(height: 16),
              
              // Logout Button
              OutlinedButton.icon(
                onPressed: _logout,
                icon: Icon(Icons.logout, color: AppColors.error),
                label: Text("Logout", style: AppTextStyles.button.copyWith(color: AppColors.error)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: AppColors.error, width: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              
              const SizedBox(height: 100), // Space for floating button
            ],
          ),
        ),
      ),
      floatingActionButton: SOSButton(
        onPressed: _makeSOSCall,
        emergencyNumber: emergencyCtrl.text.trim(),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

// ✅ SOS BUTTON WIDGET (Updated colors)
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
                color: AppColors.error.withOpacity(0.3 - (_pulseAnimation.value / 100)),
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
                  gradient: LinearGradient(
                    colors: [AppColors.error, AppColors.error.withOpacity(0.8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.error.withOpacity(0.5),
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
                      children: [
                        Icon(Icons.emergency, color: AppColors.onPrimary, size: 32),
                        const SizedBox(height: 2),
                        Text(
                          'SOS',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.onPrimary,
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