// lib/services/socket_service.dart
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:firebase_auth/firebase_auth.dart';

/// Customer app Socket.IO service (singleton)
/// - Handles connect/reconnect
/// - Registers customer identity (phone -> uid fallback)
/// - Supports trip types: short | parcel | long
/// - Exposes typed emit helpers + listeners
// Optionally use an enum for safety when emitting trip by type
enum TripType { short, parcel, long }

class SocketService {
  // ===== Singleton =====
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  String? _baseUrl;

  // Keep references to handlers so we can rebind after reconnect
  void Function(Map<String, dynamic>)? _onTripAcceptedHandler;
  void Function(Map<String, dynamic>)? _onTripRejectedBySystemHandler;
  void Function(Map<String, dynamic>)? _onDriverLiveLocationHandler;
  void Function(Map<String, dynamic>)? _onRideConfirmedHandler;
  void Function(Map<String, dynamic>)? _onLongTripStandbyHandler;

  bool get isConnected => _socket?.connected ?? false;
  IO.Socket? get rawSocket => _socket;

  /// Connect to Socket.IO server.
  /// Call once per app session (or page open) with the base URL, e.g. http://192.168.1.16:5002
  void connect(String baseUrl) {
    if (_socket != null && _baseUrl == baseUrl && _socket!.connected) {
      return;
    }

    _baseUrl = baseUrl;

    // Clean up any previous socket instance
    try {
      _socket?.disconnect();
      // Some versions have close()/dispose(); wrap in try to avoid runtime errors
      // ignore: empty_catches
      try {
        _socket?.close();
      } catch (_) {}
      // ignore: empty_catches
      try {
        _socket?.dispose();
      } catch (_) {}
    } catch (_) {}

    _socket = IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(double.infinity.toInt()) // keep trying
          .setReconnectionDelay(1000)
          .build(),
    );

    // ---- Lifecycle ----
    _socket!.onConnect((_) {
      print('🟢 Socket connected -> $_baseUrl (id: ${_socket!.id})');
      _reRegisterCustomerIfPossible();
    });

    _socket!.onReconnect((_) {
      print('♻️ Socket reconnected (id: ${_socket!.id})');
      _reRegisterCustomerIfPossible();
    });

    _socket!.onReconnectAttempt((attempt) {
      print('… reconnecting to $_baseUrl (attempt $attempt)');
    });

    _socket!.onDisconnect((_) {
      print('🔴 Socket disconnected');
    });

    _socket!.onError((err) {
      print('⚠️ Socket error: $err');
    });

    _socket!.connect();
  }

  /// Registers this connection as a Customer on the backend.
  /// If [customerId] is omitted, it tries Firebase phoneNumber, then uid.
  Future<void> connectCustomer({String? customerId}) async {
    if (_socket == null) {
      print(
          '⚠️ connectCustomer called before connect(). Call connect(baseUrl) first.');
      return;
    }

    final idToUse = await _resolveCustomerId(explicitId: customerId);
    if (idToUse == null || idToUse.isEmpty) {
      print(
          '❌ No Firebase user and no customerId provided; cannot register customer.');
      return;
    }

    _socket!.emit('customer:register', {'customerId': idToUse});
    print('📡 customer:register -> $idToUse');
  }

  /// Legacy alias
  void connectCustomerLegacy(String customerId) {
    connectCustomer(customerId: customerId);
  }

  /// Emit a trip request with only a tripId (legacy/back-compat).
  void emitCustomerRequestTrip(String tripId) {
    if (_socket == null) {
      print('⚠️ emitCustomerRequestTrip before connect().');
      return;
    }
    _socket!.emit('customer:request_trip', {'tripId': tripId});
    print('📤 customer:request_trip -> $tripId');
  }

  /// Legacy helper used by older pages expecting to send the whole rideData map.
  void sendRideRequest(Map<String, dynamic> rideData) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('customer:request_trip', rideData);
      print('📤 Ride request sent: $rideData');
    } else {
      print('⚠️ Socket not connected. Ride request not sent.');
    }
  }

  /// Emit a trip request specifying the category:
  /// - TripType.short   -> short trip (auto + bike + car as per backend rules)
  /// - TripType.parcel  -> parcel (bike only)
  /// - TripType.long    -> long trip (car only)
  void emitCustomerRequestTripByType(
      TripType type, Map<String, dynamic> rideData) {
    if (_socket == null) {
      print('⚠️ emitCustomerRequestTripByType before connect().');
      return;
    }
    final payload = {
      'type': type.name, // "short" | "parcel" | "long"
      'data': rideData,
    };
    _socket!.emit('customer:request_trip', payload);
    print('📤 ${type.name}_trip request sent: $payload');
  }

  // ========= Event Listeners (with rebind support) =========

  void onTripAccepted(void Function(Map<String, dynamic> data) handler) {
    _onTripAcceptedHandler = handler;
    _socket?.off('trip:accepted');
    _socket?.on('trip:accepted', (data) {
      final map = _toMap(data);
      print('✅ trip:accepted -> $map');
      handler(map);
    });
  }

  void onTripRejectedBySystem(
      void Function(Map<String, dynamic> data) handler) {
    _onTripRejectedBySystemHandler = handler;

    // New canonical name
    _socket?.off('trip:rejected_by_system');
    _socket?.on('trip:rejected_by_system', (data) {
      final map = _toMap(data);
      print('🚫 trip:rejected_by_system -> $map');
      handler(map);
    });

    // Backward-compatible legacy name
    _socket?.off('tripRejectedBySystem');
    _socket?.on('tripRejectedBySystem', (data) {
      final map = _toMap(data);
      print('🚫 tripRejectedBySystem -> $map');
      handler(map);
    });
  }

  // Alias kept for your existing code that expects "ride rejected"
  void onRideRejected(void Function(Map<String, dynamic> data) handler) {
    onTripRejectedBySystem(handler);
  }

  void onDriverLiveLocation(void Function(Map<String, dynamic> data) handler) {
    _onDriverLiveLocationHandler = handler;
    _socket?.off('driverLiveLocation');
    _socket?.on('driverLiveLocation', (data) {
      final map = _toMap(data);
      print('📍 driverLiveLocation -> $map');
      handler(map);
    });
  }

  void onRideConfirmed(void Function(Map<String, dynamic> data) handler) {
    _onRideConfirmedHandler = handler;
    _socket?.off('rideConfirmed');
    _socket?.on('rideConfirmed', (data) {
      final map = _toMap(data);
      print('✅ rideConfirmed -> $map');
      handler(map);
    });
  }

  /// Long trip standby (e.g., waiting room/queue before manual/auto assign)
  void onLongTripStandby(void Function(Map<String, dynamic> data) handler) {
    _onLongTripStandbyHandler = handler;
    _socket?.off('longTrip:standby');
    _socket?.on('longTrip:standby', (data) {
      final map = _toMap(data);
      print('🟡 longTrip:standby -> $map');
      handler(map);
    });
  }

  // ========= Generic Utilities =========

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
      _socket?.disconnect();
      // ignore: empty_catches
      try {
        _socket?.close();
      } catch (_) {}
      // ignore: empty_catches
      try {
        _socket?.dispose();
      } catch (_) {}
    } catch (_) {}
    _socket = null;
    print('🔌 Socket disposed');
  }

  // ========= Private Helpers =========

  /// Resolve a customer id using priority: explicitId > phoneNumber > uid
  Future<String?> _resolveCustomerId({String? explicitId}) async {
    if (explicitId != null && explicitId.trim().isNotEmpty) {
      return explicitId.trim();
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final phone = user.phoneNumber;
    if (phone != null && phone.trim().isNotEmpty) return phone.trim();
    return user.uid;
  }

  /// Re-register & rebind listeners on connect/reconnect
  Future<void> _reRegisterCustomerIfPossible() async {
    final idToUse = await _resolveCustomerId();
    if (idToUse == null || idToUse.isEmpty) return;

    _socket?.emit('customer:register', {'customerId': idToUse});
    print('↪️ Re-register on (re)connect -> $idToUse');

    // Re-bind listeners if handlers were set previously
    if (_onTripAcceptedHandler != null) {
      onTripAccepted(_onTripAcceptedHandler!);
    }
    if (_onTripRejectedBySystemHandler != null) {
      onTripRejectedBySystem(_onTripRejectedBySystemHandler!);
    }
    if (_onDriverLiveLocationHandler != null) {
      onDriverLiveLocation(_onDriverLiveLocationHandler!);
    }
    if (_onRideConfirmedHandler != null) {
      onRideConfirmed(_onRideConfirmedHandler!);
    }
    if (_onLongTripStandbyHandler != null) {
      onLongTripStandby(_onLongTripStandbyHandler!);
    }
  }

  Map<String, dynamic> _toMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    return {'data': data};
  }
}
