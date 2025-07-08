import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  /* ---------------- API base ---------------- */
  final String _baseUrl =
      'http://192.168.183.12:5002/api/help'; // change if your IP/port differs

  /* ---------------- FAQs -------------------- */
  List<dynamic> _faqs = [];
  bool _loadingFaqs = true;

  /* ------------- Report-Issue form ---------- */
  final _issueTypes = [
    'Driver was rude',
    'Vehicle not clean',
    'Overcharged',
    'Safety concern',
    'Other'
  ];
  String _selectedIssue = 'Driver was rude';
  final _rideIdController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _submitting = false;

  /* ------------ Contact options ------------- */
  final String supportPhone = '+919876543210';
  final String supportEmail = 'support@goindia.com';

  /* ---------------- Init -------------------- */
  @override
  void initState() {
    super.initState();
    _fetchFaqs();
  }

  Future<void> _fetchFaqs() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/faqs'));
      if (res.statusCode == 200) {
        setState(() {
          _faqs = json.decode(res.body)['faqs'];
          _loadingFaqs = false;
        });
      } else {
        setState(() => _loadingFaqs = false);
      }
    } catch (_) {
      setState(() => _loadingFaqs = false);
    }
  }

  /* -------------- Submit Issue -------------- */
  Future<void> _submitIssue() async {
    final payload = {
      'phone':
          FirebaseAuth.instance.currentUser?.phoneNumber?.replaceAll('+91', '') ??
              '',
      'issueType': _selectedIssue,
      'rideId': _rideIdController.text.trim(),
      'description': _descriptionController.text.trim(),
    };

    try {
      final res = await http.post(Uri.parse('$_baseUrl/issue'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(payload));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(res.statusCode == 201 ? 'Issue submitted!' : 'Submission failed'),
        ),
      );
    } catch (_) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Server error')));
    } finally {
      _rideIdController.clear();
      _descriptionController.clear();
    }
  }

  /* -------------- Bottom sheet -------------- */
  void _openIssueSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (ctx, setModal) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Report an Issue',
                  style: GoogleFonts.poppins(
                      fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedIssue,
                decoration: const InputDecoration(labelText: 'Issue Type'),
                items: _issueTypes
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setModal(() => _selectedIssue = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _rideIdController,
                decoration:
                    const InputDecoration(labelText: 'Ride ID (optional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                decoration:
                    const InputDecoration(labelText: 'Describe the issue'),
                maxLines: 3,
              ),
              const SizedBox(height: 20),
              _submitting
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: () async {
                        setModal(() => _submitting = true);
                        await _submitIssue();
                        if (mounted) Navigator.pop(context);
                      },
                      child: const Text('Submit'),
                    ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  /* --------- Call / email helpers ---------- */
  Future<void> _callSupport() async {
    final uri = Uri.parse('tel:$supportPhone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _emailSupport() async {
    final uri = Uri.parse('mailto:$supportEmail');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  /* ----------------  UI  ------------------- */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---------- FAQs ----------
          Text('FAQs',
              style:
                  GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _loadingFaqs
              ? const Center(child: CircularProgressIndicator())
              : _faqs.isEmpty
                  ? const Text('No FAQs available')
                  : ExpansionPanelList.radio(
                      children: _faqs
                          .map<ExpansionPanelRadio>(
                            (f) => ExpansionPanelRadio(
                              value: f['q'],
                              headerBuilder: (_, __) => ListTile(title: Text(f['q'])),
                              body: ListTile(title: Text(f['a'])),
                            ),
                          )
                          .toList(),
                    ),
          const SizedBox(height: 24),

          // ----- Report an Issue -----
          ListTile(
            leading:
                const Icon(Icons.report_problem_outlined, color: Colors.redAccent),
            title: const Text('Report a Ride / App Issue'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _openIssueSheet,
          ),

          const Divider(height: 40),

          // -------- Contact Us -------
          Text('Contact Us',
              style:
                  GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.call, color: Colors.green),
            title: Text('Call $supportPhone'),
            onTap: _callSupport,
          ),
          ListTile(
            leading: const Icon(Icons.email, color: Colors.blue),
            title: Text('Email $supportEmail'),
            onTap: _emailSupport,
          ),
        ],
      ),
    );
  }
}