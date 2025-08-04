import 'package:flutter/material.dart';

class RideHistoryPage extends StatelessWidget {
  const RideHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ride History'),
          backgroundColor: Colors.teal,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'City Ride'),
              Tab(text: 'Intercity Ride'),
              Tab(text: 'Parcel'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            RideHistoryList(type: 'city'),
            RideHistoryList(type: 'intercity'),
            RideHistoryList(type: 'parcel'),
          ],
        ),
      ),
    );
  }
}

class RideHistoryList extends StatelessWidget {
  final String type;

  const RideHistoryList({super.key, required this.type});

  List<Map<String, dynamic>> getMockData() {
    if (type == 'city') {
      return [
        {
          'pickup': 'MG Road',
          'drop': 'Begumpet',
          'date': '2025-07-25 14:30',
          'fare': '₹85',
          'driver': 'Anil Kumar',
          'vehicle': 'TS09 AX 1234',
          'status': 'Completed'
        },
        {
          'pickup': 'Secunderabad',
          'drop': 'Kukatpally',
          'date': '2025-07-24 09:10',
          'fare': '₹120',
          'driver': 'Ramesh',
          'vehicle': 'TS10 CY 5678',
          'status': 'Cancelled'
        },
      ];
    } else if (type == 'intercity') {
      return [
        {
          'pickup': 'Hyderabad',
          'drop': 'Vijayawada',
          'date': '2025-07-20 06:00',
          'fare': '₹1200',
          'driver': 'Srinivas Rao',
          'vehicle': 'AP16 DZ 7788',
          'status': 'Completed'
        },
      ];
    } else {
      return [
        {
          'pickup': 'Charminar',
          'drop': 'Gachibowli',
          'date': '2025-07-26 17:00',
          'fare': '₹200',
          'driver': 'Kiran',
          'vehicle': 'TS12 AB 9999',
          'status': 'Completed'
        },
        {
          'pickup': 'LB Nagar',
          'drop': 'Jubilee Hills',
          'date': '2025-07-23 11:45',
          'fare': '₹180',
          'driver': 'Ajay',
          'vehicle': 'TS14 KM 3321',
          'status': 'Completed'
        },
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = getMockData();

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final item = history[index];
        return Card(
          elevation: 3,
          margin: const EdgeInsets.only(bottom: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item['pickup']} → ${item['drop']}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('Date: ${item['date']}'),
                Text('Fare: ${item['fare']}'),
                Text('Driver: ${item['driver']}'),
                Text('Vehicle: ${item['vehicle']}'),
                Text(
                  'Status: ${item['status']}',
                  style: TextStyle(
                    color: item['status'] == 'Completed'
                        ? Colors.green
                        : Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
