import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:firebase_auth/firebase_auth.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;

  /// ✅ Connect Customer to Socket
  void connectCustomer() {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? 'test_user';

    _socket = IO.io(
      'http://192.168.210.12:5002', // Your backend IP
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      print('🟢 Connected to Socket Server');

      _socket!.emit('registerUser', {'userId': userId});
    });

    _socket!.onDisconnect((_) => print('🔴 Disconnected from socket'));
  }

  /// ✅ Send Ride Request to Backend
  void sendRideRequest(Map<String, dynamic> data) {
    if (_socket != null) {
      _socket!.emit('rideRequest', data);
      print('📩 Ride request sent: $data');
    }
  }

  /// ✅ Listen for Ride Accepted by Driver
  void onRideAccepted(Function(Map<String, dynamic>) callback) {
    _socket?.on('rideAccepted', (data) {
      print('✅ Ride Accepted: $data');
      callback(Map<String, dynamic>.from(data));
    });
  }

  /// ✅ Listen for Ride Rejected by Driver
  void onRideRejected(Function(Map<String, dynamic>) callback) {
    _socket?.on('rideRejected', (data) {
      print('❌ Ride Rejected: $data');
      callback(Map<String, dynamic>.from(data));
    });
  }

  /// ✅ Disconnect Socket
  void disconnect() {
    _socket?.disconnect();
    print('🔴 Socket disconnected');
  }
}
