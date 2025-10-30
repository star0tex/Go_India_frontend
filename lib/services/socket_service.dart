// lib/services/socket_service.dart
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';

enum TripType { short, parcel, long }

class SocketService {
  // Singleton Setup
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();
  final String baseUrl = 'https://b23b44ae0c5e.ngrok-free.app'; // ✅ Replace with your server URL

  // Private State
  IO.Socket? _socket;
  String? _baseUrl;
  String? _lastUsedCustomerId;

  // Event handler references for rebinding
  void Function(Map<String, dynamic>)? _onTripAcceptedHandler;
  void Function(Map<String, dynamic>)? _onTripRejectedBySystemHandler;
  void Function(Map<String, dynamic>)? _onDriverLiveLocationHandler;
  void Function(Map<String, dynamic>)? _onRideConfirmedHandler;
  void Function(Map<String, dynamic>)? _onLongTripStandbyHandler;

  // Public Getters
  bool get isConnected => _socket?.connected ?? false;
  IO.Socket? get rawSocket => _socket;

  // Core Methods

  void connect(String baseUrl) {
    if (_socket != null && _baseUrl == baseUrl && _socket!.connected) {
      print('Socket already connected to $baseUrl.');
      return;
    }

    _baseUrl = baseUrl;
    _cleanupSocket();

    _socket = IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setReconnectionAttempts(5)
          .build(),
    );

    _socket!.onConnect((_) {
      print('Socket connected: ${_socket!.id}');
      _reRegisterCustomerAndListeners();
    });

    _socket!.onReconnect((_) {
      print('Socket reconnected: ${_socket!.id}');
      _reRegisterCustomerAndListeners();
    });

    _socket!.onDisconnect((_) => print('Socket disconnected'));
    _socket!.onConnectError((error) => print('Socket connection error: $error'));
    _socket!.onError((error) => print('Socket error: $error'));

    _socket!.connect();
  }

  /// Registers the customer using MongoDB _id from SharedPreferences or login response
  Future<void> connectCustomer({String? customerId}) async {
    if (_socket == null || !_socket!.connected) {
      print('Cannot connect customer: socket is not connected.');
      return;
    }

    final idToUse = await _resolveCustomerId(explicitId: customerId);
    if (idToUse == null || idToUse.isEmpty) {
      print('Could not resolve a customer ID. Cannot register.');
      return;
    }
    
    _lastUsedCustomerId = idToUse;

    print('Registering customer with ID: $idToUse');
    _socket!.emit('customer:register', {'customerId': idToUse});

    // Listen for registration confirmation
    _socket!.once('customer:registered', (data) {
      final response = _toMap(data);
      if (response['success'] == true) {
        print('Customer registration successful:');
        print('  MongoDB ID: ${response['mongoId']}');
        print('  Socket ID: ${response['socketId']}');
        print('  Phone: ${response['phone']}');
      } else {
        print('Customer registration failed: ${response['error']}');
        print('  Provided ID: ${response['providedId']}');
        print('  Hint: ${response['hint']}');
      }
    });
  }

  void disconnect() {
    _lastUsedCustomerId = null;
    _cleanupSocket();
    print('Socket disconnected and disposed by client.');
  }

  // Event Emitters

  void emitCustomerRequestTripByType(TripType type, Map<String, dynamic> rideData) {
    if (!isConnected) {
      print('Socket not connected. Cannot send trip request.');
      return;
    }
    
    final payload = {
      'type': type.name,
      ...rideData, // Merge ride data directly
    };
    
    print('Emitting [${type.name}] trip request: $payload');
    _socket!.emit('customer:request_trip', payload);
  }

  void sendRideRequest(Map<String, dynamic> rideData) {
    if (!isConnected) {
      print('Socket not connected. Ride request not sent.');
      return;
    }
    _socket!.emit('customer:request_trip', rideData);
    print('Sending ride request: $rideData');
  }

  // Event Listeners

  void onTripAccepted(void Function(Map<String, dynamic> data) handler) {
    _onTripAcceptedHandler = handler;
    _socket?.off('trip:accepted');
    _socket?.on('trip:accepted', (data) {
      final map = _toMap(data);
      print('Received [trip:accepted]: ${map.keys}');
      handler(map);
    });
  }

  void onTripRejectedBySystem(void Function(Map<String, dynamic> data) handler) {
    _onTripRejectedBySystemHandler = handler;
    const eventName = 'trip:rejected_by_system';
    _socket?.off(eventName);
    _socket?.on(eventName, (data) {
      final map = _toMap(data);
      print('Received [$eventName]: $map');
      handler(map);
    });
  }

  void onDriverLiveLocation(void Function(Map<String, dynamic> data) handler) {
    _onDriverLiveLocationHandler = handler;
    const eventName = 'driverLiveLocation';
    _socket?.off(eventName);
    _socket?.on(eventName, (data) {
      final map = _toMap(data);
      handler(map);
    });
  }

  void onRideConfirmed(void Function(Map<String, dynamic> data) handler) {
    _onRideConfirmedHandler = handler;
    const eventName = 'rideConfirmed';
    _socket?.off(eventName);
    _socket?.on(eventName, (data) {
      final map = _toMap(data);
      print('Received [$eventName]: $map');
      handler(map);
    });
  }

  void onLongTripStandby(void Function(Map<String, dynamic> data) handler) {
    _onLongTripStandbyHandler = handler;
    const eventName = 'longTrip:standby';
    _socket?.off(eventName);
    _socket?.on(eventName, (data) {
      final map = _toMap(data);
      print('Received [$eventName]: $map');
      handler(map);
    });
  }

  // Generic Utilities

  void emit(String event, dynamic data) {
    _socket?.emit(event, data);
  }

  void on(String event, Function(dynamic) handler) {
    _socket?.on(event, handler);
  }
  
  void off(String event) {
    _socket?.off(event);
  }

  // Private Helpers

  Future<void> _reRegisterCustomerAndListeners() async {
    if (_lastUsedCustomerId != null) {
      await connectCustomer(customerId: _lastUsedCustomerId);
    } else {
      await connectCustomer();
    }

    print('Re-binding event listeners...');
    if (_onTripAcceptedHandler != null) onTripAccepted(_onTripAcceptedHandler!);
    if (_onTripRejectedBySystemHandler != null) onTripRejectedBySystem(_onTripRejectedBySystemHandler!);
    if (_onDriverLiveLocationHandler != null) onDriverLiveLocation(_onDriverLiveLocationHandler!);
    if (_onRideConfirmedHandler != null) onRideConfirmed(_onRideConfirmedHandler!);
    if (_onLongTripStandbyHandler != null) onLongTripStandby(_onLongTripStandbyHandler!);
  }

  /// Resolves customer ID with priority:
  /// 1. Explicitly provided ID (should be MongoDB _id)
  /// 2. Stored customerId from SharedPreferences (from login)
  /// 3. Stored phone number as fallback
  Future<String?> _resolveCustomerId({String? explicitId}) async {
    if (explicitId != null && explicitId.trim().isNotEmpty) {
      print('Using explicit customer ID: $explicitId');
      return explicitId.trim();
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      
      // First try to get the MongoDB _id stored during login
      final storedCustomerId = prefs.getString('customerId');
      if (storedCustomerId != null && storedCustomerId.trim().isNotEmpty) {
        print('Using stored customerId: $storedCustomerId');
        return storedCustomerId.trim();
      }

      // Fallback to phone number
      final storedPhone = prefs.getString('phoneNumber');
      if (storedPhone != null && storedPhone.trim().isNotEmpty) {
        print('Using stored phone as customer ID: $storedPhone');
        return storedPhone.trim();
      }

      print('No customer ID found in SharedPreferences');
      return null;
    } catch (e) {
      print('Error resolving customer ID: $e');
      return null;
    }
  }

  void _cleanupSocket() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
  
  Map<String, dynamic> _toMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    return {'data': data};
  }
}