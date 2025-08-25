// lib/services/socket_service.dart
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:firebase_auth/firebase_auth.dart';

/// Singleton Socket service aligned to backend `socketHandler.js`
class SocketService {
  // ===== Singleton =====
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  String? _baseUrl;

  bool get isConnected => _socket?.connected ?? false;
  IO.Socket? get rawSocket => _socket;

  /// Connect to Socket.IO server (call once, app start or page open)
  void connect(String baseUrl) {
    if (_socket != null && _baseUrl == baseUrl && _socket!.connected) {
      return;
    }

    _baseUrl = baseUrl;

    try {
      _socket?.dispose();
    } catch (_) {}

    _socket = IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .build(),
    );

    _socket!.onConnect((_) {
      print('🟢 Socket connected -> $_baseUrl (id: ${_socket!.id})');
      _reRegisterCustomerIfPossible();
    });

    _socket!.onReconnect((_) {
      print('♻️ Socket reconnected');
      _reRegisterCustomerIfPossible();
    });

    _socket!.onReconnectAttempt((_) {
      print('… trying to reconnect to $_baseUrl');
    });

    _socket!.onDisconnect((_) {
      print('🔴 Socket disconnected');
    });

    _socket!.onError((err) {
      print('⚠️ Socket error: $err');
    });

    _socket!.connect();
  }

  /// Register this socket as a **customer** on the backend.
  Future<void> connectCustomer({String? customerId}) async {
    if (_socket == null) {
      print(
          '⚠️ connectCustomer called before connect(). Call connect(baseUrl) first.');
      return;
    }
    if (!isConnected) {
      print(
          'ℹ️ Socket not connected yet. Will still emit; Socket.IO buffers until connected.');
    }

    final user = FirebaseAuth.instance.currentUser;
    final String? phone = user?.phoneNumber;
    final String? uid = user?.uid;

    final idToUse = customerId?.trim().isNotEmpty == true
        ? customerId!.trim()
        : (phone?.trim().isNotEmpty == true
            ? phone!.trim()
            : (uid ?? '').trim());

    if (idToUse.isEmpty) {
      print(
          '❌ No Firebase user and no customerId provided; cannot register customer.');
      return;
    }

    _socket!.emit('customer:register', {'customerId': idToUse});
    print('📡 customer:register -> $idToUse');
  }

  void connectCustomerLegacy(String customerId) {
    connectCustomer(customerId: customerId);
  }

  /// Emit trip request with tripId
  void emitCustomerRequestTrip(String tripId) {
    if (_socket == null) {
      print('⚠️ emitCustomerRequestTrip before connect().');
      return;
    }
    _socket!.emit('customer:request_trip', {'tripId': tripId});
    print('📤 customer:request_trip -> $tripId');
  }

  /// Added for backward compatibility with pages using sendRideRequest()
  void sendRideRequest(Map<String, dynamic> rideData) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('customer:request_trip', rideData);
      print('📤 Ride request sent: $rideData');
    } else {
      print('⚠️ Socket not connected. Ride request not sent.');
    }
  }

  // ========= Listeners =========
  void onTripAccepted(void Function(Map<String, dynamic> data) handler) {
    _socket?.off('trip:accepted');
    _socket?.on('trip:accepted', (data) {
      final map = _toMap(data);
      print('✅ trip:accepted -> $map');
      handler(map);
    });
  }

  void onTripRejectedBySystem(
      void Function(Map<String, dynamic> data) handler) {
    _socket?.off('trip:rejected_by_system');
    _socket?.off('tripRejectedBySystem');

    _socket?.on('trip:rejected_by_system', (data) {
      final map = _toMap(data);
      print('🚫 trip:rejected_by_system -> $map');
      handler(map);
    });

    _socket?.on('tripRejectedBySystem', (data) {
      final map = _toMap(data);
      print('🚫 tripRejectedBySystem -> $map');
      handler(map);
    });
  }

  void onRideRejected(void Function(Map<String, dynamic> data) handler) {
    onTripRejectedBySystem(handler);
  }

  void onDriverLiveLocation(void Function(Map<String, dynamic> data) handler) {
    _socket?.off('driverLiveLocation');
    _socket?.on('driverLiveLocation', (data) {
      final map = _toMap(data);
      print('📍 driverLiveLocation -> $map');
      handler(map);
    });
  }

  void onRideConfirmed(void Function(Map<String, dynamic> data) handler) {
    _socket?.off('rideConfirmed');
    _socket?.on('rideConfirmed', (data) {
      final map = _toMap(data);
      print('✅ rideConfirmed -> $map');
      handler(map);
    });
  }

  // ========= Utilities =========
  void emit(String event, Map<String, dynamic> data) {
    _socket?.emit(event, data);
  }

  void on(String event, void Function(Map<String, dynamic> data) handler) {
    _socket?.off(event);
    _socket?.on(event, (data) => handler(_toMap(data)));
  }

  void off(String event) {
    _socket?.off(event);
  }

  void disconnect() {
    try {
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
    print('🔌 Socket disposed');
  }

  // ========= Private =========
  void _reRegisterCustomerIfPossible() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final idToUse = (user.phoneNumber != null && user.phoneNumber!.isNotEmpty)
        ? user.phoneNumber!
        : user.uid;

    _socket?.emit('customer:register', {'customerId': idToUse});
    print('↪️ Re-register on reconnect -> $idToUse');
  }

  Map<String, dynamic> _toMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    return {'data': data};
  }
}
