import 'package:flutter/material.dart';
import 'car_trip_booking_page.dart';

/// A modal sheet that explains the long‑trip rules.
/// Call it with  showModalBottomSheet(context:…, builder: (_) => CarTripAgreementSheet());
class CarTripAgreementSheet extends StatelessWidget {
  const CarTripAgreementSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text('Go India — Long‑Trip (Car Trip) Agreement',
                style: textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 12),

            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  '''
• This service is meant for round‑trip sightseeing *within the same state* for family & friends.  
• Driver charge (example):  
  • Normal Car   → ₹1 500 first day  
  • Premium Car → ₹1 800 first day  
  • XL / SUV      → ₹2 000 first day  
  • For every **additional day** the driver charge is ₹1 500 (all classes).  
• If the ride is **one‑way** (driver returns alone) you pay **½ of first‑day driver charge** + return‑fuel.  
• Fuel, tolls, parking & driver meals are paid *by the rider*.  
• Trips **must be booked ≥ 2 days in advance**. Same‑day bookings are allowed, but confirmation may take up to 30 min.  
• After you confirm below you’ll pick pickup & destination, trip dates and see prices by vehicle class.

By tapping *Accept* you agree to these terms.
''',
                  style: textTheme.bodyMedium,
                ),
              ),
            ),

            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);          // close sheet
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CarTripBookingPage()),
                      );
                    },
                    child: const Text('Accept'),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
