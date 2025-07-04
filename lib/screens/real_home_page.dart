import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'OpenStreetLocationPage.dart';
import 'profile_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class RealHomePage extends StatefulWidget {
  const RealHomePage({super.key});
  

  @override
  State<RealHomePage> createState() => _RealHomePageState();
}

class _RealHomePageState extends State<RealHomePage>
    with TickerProviderStateMixin {
  final services = [
    {'label': 'Bike', 'image': 'assets/images/bike.png'},
    {'label': 'Auto', 'image': 'assets/images/auto.png'},
    {'label': 'Car', 'image': 'assets/images/car.png'},
    {'label': 'Parcel', 'image': 'assets/images/parcel.png'},
  ];

  late List<AnimationController> _controllers;
  late List<Animation<Offset>> _animations;

  // ──────────────────  NEW: search + voice  ──────────────────
  final TextEditingController _searchController = TextEditingController();
  late final stt.SpeechToText _speech;
  
  bool _isListening = false;

String? selectedVehicle; // ✅ NEW: stores last tapped vehicle

  String name = '';
  String phone = '';
  String rating = '';

  @override
  void initState() {
    super.initState();

    _speech = stt.SpeechToText();

    _controllers = List.generate(
      services.length,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 800),
      ),
    );

    _animations = List.generate(
      services.length,
      (i) {
        final fromLeft = i % 2 == 0;
        return Tween<Offset>(
          begin: Offset(fromLeft ? -1.5 : 1.5, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: _controllers[i],
          curve: Curves.easeOut,
        ));
      },
    );

    Future.forEach<int>(List.generate(services.length, (i) => i), (i) async {
      await Future.delayed(Duration(milliseconds: i * 300));
      _controllers[i].forward();
    });

    phone = FirebaseAuth.instance.currentUser?.phoneNumber?.replaceAll('+91', '') ?? '';
    _fetchUserProfile();
  }

  Future<void> _fetchUserProfile() async {
    try {
      final res = await http.get(Uri.parse('http://192.168.43.236:5002/api/profile/$phone'));
      if (res.statusCode == 200) {
        final user = json.decode(res.body)['user'];
        setState(() {
          name = user['name'] ?? '';
          phone = user['phone'] ?? phone;
        });
      }
    } catch (e) {
      debugPrint("Failed to fetch profile: $e");
    }
  }

  // ──────────────────  NEW: voice helpers  ──────────────────
  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    final ok = await _speech.initialize(onStatus: (s) {
      if (s == 'done') _toggleListening();
    }, onError: (e) {
      debugPrint('Speech error: $e');
      _toggleListening();
    });

    if (!ok) return;

    setState(() => _isListening = true);
    _speech.listen(onResult: (r) {
      if (r.finalResult) {
        _searchController.text = r.recognizedWords.trim();
        _openLocationPage(_searchController.text);
      }
    });
  }

 void _openLocationPage(String destination) {
  if (destination.isEmpty) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => OpenStreetLocationPage(
  initialDrop: destination,
  selectedVehicle: selectedVehicle, // ✅ Add this
),

    ),
  ).then((_) => _fetchUserProfile());
  _searchController.clear();
}




  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    _speech.stop();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final halfWidth = screenWidth / 2;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      drawer: _buildDrawer(context),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ──────────────────  MENU + SEARCH BAR  ──────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Builder(
                    builder: (ctx) => IconButton(
                      icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                      onPressed: () {
                        Scaffold.of(ctx).openDrawer();
                        _fetchUserProfile();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Icon(Icons.search, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: const TextStyle(color: Colors.black87),
                              decoration: const InputDecoration(
                                hintText: "Where are you going?",
                                hintStyle: TextStyle(color: Colors.grey),
                                border: InputBorder.none,
                              ),
                              onSubmitted: _openLocationPage,
                            ),
                          ),
                          IconButton(
                            icon: Icon(_isListening ? Icons.mic : Icons.mic_none, color: Colors.grey),
                            onPressed: _toggleListening,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ──────────────────  EXPLORE SECTION  ──────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Explore",
                      style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
                  Text("View all",
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.yellow)),
                ],
              ),
            ),
            const SizedBox(height: 25),

            // ──────────────────  SERVICE CARDS  ──────────────────
            Expanded(
              child: Stack(
                children: [
                  Transform.translate(
                    offset: const Offset(0, 80),
                    child: Align(
                      child: Opacity(
                        opacity: 0.18,
                        child: Image.asset('assets/images/charminar_white.png', height: 600, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                  ListView.builder(
                    padding: const EdgeInsets.only(bottom: 25),
                    itemCount: services.length,
                    itemBuilder: (ctx, idx) {
                      return AnimatedBuilder(
                        animation: _animations[idx],
                        builder: (ctx, child) {
                          final dx = _animations[idx].value.dx;
                          final fromLeft = idx % 2 == 0;
                          return Transform.translate(
                            offset: Offset(dx * halfWidth, 0),
                            child: Align(
                              alignment: fromLeft ? Alignment.centerLeft : Alignment.centerRight,
                              child: _buildHalfCard(
                                services[idx]['label']!,
                                services[idx]['image']!,
                                halfWidth,
                                fromLeft,
                                ctx,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /* ------------------------------------------------------------- */
  Widget _buildHalfCard(String label, String imagePath, double width, bool fromLeft, BuildContext ctx) {
    const double cardHeight = 55;
    return GestureDetector(
     onTap: () {
        selectedVehicle = label;
  Navigator.push(
    ctx,
    MaterialPageRoute(
      builder: (_) => OpenStreetLocationPage(
        selectedVehicle: label, // Pass selected vehicle
      ),
    ),
  ).then((_) => _fetchUserProfile());
},

      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: width,
            height: cardHeight,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: fromLeft
                  ? const BorderRadius.only(topRight: Radius.circular(20), bottomRight: Radius.circular(20))
                  : const BorderRadius.only(topLeft: Radius.circular(20), bottomLeft: Radius.circular(20)),
              boxShadow: const [
                BoxShadow(color: Color.fromRGBO(13, 27, 42, 0.3), blurRadius: 12, offset: Offset(0, 5)),
              ],
            ),
            alignment: Alignment.center,
            child: Text(label,
                textAlign: TextAlign.center,
                style: GoogleFonts.roboto(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.black87, letterSpacing: 0.8)),
          ),
          Positioned(
            top: -20,
            left: fromLeft ? width - 75 : null,
            right: fromLeft ? null : width - 45,
            child: Container(
              width: 130,
              height: 130,
              alignment: Alignment.center,
              child: Image.asset(imagePath, width: 130, height: 130, fit: BoxFit.contain),
            ),
          ),
        ],
      ),
    );
  }

  /* ------------------------------------------------------------- */
  Widget _buildDrawer(BuildContext ctx) {
    return Drawer(
      backgroundColor: Colors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GestureDetector(
              onTap: () async {
                Navigator.pop(ctx);
                await Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ProfilePage()));
                _fetchUserProfile();
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(radius: 26, backgroundColor: Colors.white, child: Icon(Icons.person, size: 30, color: Colors.black)),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name.isNotEmpty ? name : 'Guest', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(phone, style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(children: [const Icon(Icons.star, color: Colors.amber), const SizedBox(width: 8), Text("$rating My Rating", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))])
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _drawerTile(Icons.help_outline, "Help"),
          _drawerTile(Icons.local_shipping_outlined, "Parcel - Send Items"),
          _drawerTile(Icons.payment, "Payment"),
          _drawerTile(Icons.history, "My Rides"),
          _drawerTile(Icons.shield_outlined, "Safety"),
          _drawerTile(Icons.card_giftcard_outlined, "Refer and Earn", subtitle: "Get ₹50"),
          _drawerTile(Icons.emoji_events_outlined, "My Rewards"),
          _drawerTile(Icons.notifications_none, "Notifications"),
          _drawerTile(Icons.policy_outlined, "Claims"),
          _drawerTile(Icons.settings_outlined, "Settings"),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _drawerTile(IconData icon, String title, {String? subtitle}) {
    return ListTile(
      leading: Icon(icon, color: Colors.black87),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: subtitle != null ? Text(subtitle, style: TextStyle(color: Colors.grey[600])) : null,
      onTap: () {},
    );
  }
}
