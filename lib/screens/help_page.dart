import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  // You can change this to your real support email or phone
  final String supportPhone = "tel:+919999999999";
  final String supportEmail =
      "mailto:support@yourapp.com?subject=Support%20Request";

  void _callSupport() async {
    if (await canLaunchUrl(Uri.parse(supportPhone))) {
      await launchUrl(Uri.parse(supportPhone));
    }
  }

  void _emailSupport() async {
    if (await canLaunchUrl(Uri.parse(supportEmail))) {
      await launchUrl(Uri.parse(supportEmail));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
        backgroundColor: const Color.fromRGBO(98, 205, 255, 1),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Quick Help',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _helpTile(Icons.directions_bike, 'Problem with my ride'),
          _helpTile(Icons.local_shipping, 'Parcel delivery delayed'),
          _helpTile(Icons.payments_outlined, 'Payment or refund issue'),
          _helpTile(Icons.account_circle_outlined, 'Update my phone number'),
          _helpTile(Icons.card_giftcard, 'Refer and Earn not working'),
          const SizedBox(height: 24),
          const Text(
            'FAQs',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _faqTile('How do I cancel a ride?',
              'Go to “My Rides”, select the ride and tap “Cancel Ride”.'),
          _faqTile('When will I receive a refund?',
              'Refunds are usually processed within 5–7 working days.'),
          _faqTile('What if my parcel is not delivered?',
              'You can contact support and track it from the Parcel Tracking screen.'),
          _faqTile('Can I change my drop location?',
              'Yes, before the ride starts. Tap on the location and update it.'),
          const SizedBox(height: 30),
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.phone_in_talk),
              label: const Text('Contact Support'),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (_) => _contactSupportBottomSheet(context),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  Widget _helpTile(IconData icon, String title) {
    return ListTile(
      leading: Icon(icon, color: Colors.blueAccent),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () {
        // You can navigate to detailed issue screens here
      },
    );
  }

  Widget _faqTile(String question, String answer) {
    return ExpansionTile(
      title:
          Text(question, style: const TextStyle(fontWeight: FontWeight.w500)),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
          child: Text(answer),
        ),
      ],
    );
  }

  Widget _contactSupportBottomSheet(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Contact Support',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.phone, color: Colors.green),
            title: const Text('Call Us'),
            onTap: () {
              Navigator.pop(context);
              _callSupport();
            },
          ),
          ListTile(
            leading: const Icon(Icons.email_outlined, color: Colors.orange),
            title: const Text('Email Us'),
            onTap: () {
              Navigator.pop(context);
              _emailSupport();
            },
          ),
        ],
      ),
    );
  }
}
