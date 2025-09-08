// models/trip_args.dart
class TripArgs {
  final double pickupLat;
  final double pickupLng;
  final String pickupAddress;

  final double? dropLat;
  final double? dropLng;
  final String? dropAddress;

  final String? vehicleType; // "bike", "auto", "car", "premium", "xl"
  final bool showAllFares; // true → show all fares, false → only vehicleType

  TripArgs({
    required this.pickupLat,
    required this.pickupLng,
    required this.pickupAddress,
    this.dropLat,
    this.dropLng,
    this.dropAddress,
    this.vehicleType,
    required this.showAllFares,
  });
}
