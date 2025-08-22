import 'package:flutter/material.dart';

/// Centralized icon mapping for vehicles by their `car_type` string.
/// Keeps Firestore clean (no icon fields stored) and UI consistent.
class VehicleIcons {
  static IconData forType(String carType) {
    final t = carType.toLowerCase();

    // Common buckets
    if (t.contains('suv')) return Icons.airport_shuttle; // or Icons.directions_car_filled
    if (t.contains('hatchback')) return Icons.directions_car_filled;
    if (t.contains('sedan')) return Icons.directions_car;

    if (t.contains('motorcycle') || t.contains('bike')) return Icons.two_wheeler;
    if (t.contains('scooter')) return Icons.electric_scooter;

    // Fallback
    return Icons.directions_car;
  }
}
