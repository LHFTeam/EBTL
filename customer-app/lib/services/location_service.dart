import 'package:geolocator/geolocator.dart';

import '../models/common_models.dart';

class DevicePosition {
  final double latitude;
  final double longitude;

  const DevicePosition({required this.latitude, required this.longitude});
}

/// Best-effort device location and pure beach-cart distance helpers.
class LocationService {
  /// Hacienda and Marassi are about 20 km apart, while Cairo is roughly
  /// 250 km away. Thirty kilometres identifies someone at the beach without
  /// making the two carts compete with Cairo-distance customers.
  static const double maxAutoSelectMeters = 30000;

  static Future<DevicePosition?>? _pending;

  static Future<DevicePosition?> currentPosition() {
    return _pending ??= _resolvePosition();
  }

  static Future<DevicePosition?> refreshPosition() {
    _pending = null;
    return currentPosition();
  }

  static Future<DevicePosition?> _resolvePosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition().timeout(
        const Duration(seconds: 10),
      );
      return DevicePosition(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {
      // Location is an optional enhancement. Plugin, permission, service and
      // timeout failures all leave the app behaving as it did before GPS.
      return null;
    }
  }

  static double? distanceMetersTo(
    ServiceLocation cart,
    double latitude,
    double longitude,
  ) {
    final cartLatitude = cart.latitude;
    final cartLongitude = cart.longitude;
    if (cartLatitude == null || cartLongitude == null) return null;

    return Geolocator.distanceBetween(
      latitude,
      longitude,
      cartLatitude,
      cartLongitude,
    );
  }

  static Map<String, double> distancesById(
    List<ServiceLocation> carts,
    double latitude,
    double longitude,
  ) {
    final distances = <String, double>{};
    for (final cart in carts) {
      final distance = distanceMetersTo(cart, latitude, longitude);
      if (distance != null) distances[cart.id] = distance;
    }
    return distances;
  }

  static ServiceLocation? nearestWithin(
    List<ServiceLocation> carts,
    Map<String, double> distances,
  ) {
    ServiceLocation? nearest;
    var nearestDistance = double.infinity;
    for (final cart in carts) {
      final distance = distances[cart.id];
      if (distance != null &&
          distance <= maxAutoSelectMeters &&
          distance < nearestDistance) {
        nearest = cart;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  static List<ServiceLocation> sortedByDistance(
    List<ServiceLocation> carts,
    Map<String, double> distances,
  ) {
    final indexed = carts.indexed.toList();
    indexed.sort((left, right) {
      final leftDistance = distances[left.$2.id];
      final rightDistance = distances[right.$2.id];
      if (leftDistance == null && rightDistance == null) {
        return left.$1.compareTo(right.$1);
      }
      if (leftDistance == null) return 1;
      if (rightDistance == null) return -1;
      return leftDistance.compareTo(rightDistance);
    });
    return indexed.map((entry) => entry.$2).toList(growable: false);
  }
}
