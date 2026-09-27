import 'dart:math';
import 'constants.dart';

/// Haversine spatial calculations with road network tortuosity adjustments
class HaversineUtils {
  static const double earthRadiusMeters = 6371000.0;

  /// Direct great-circle distance between two GPS coordinates in meters
  static double directDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final rLat1 = _toRadians(lat1);
    final rLat2 = _toRadians(lat2);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(rLat1) * cos(rLat2) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadiusMeters * c;
  }

  /// Estimated road network driving distance in meters (adjusted by tortuosity)
  static double roadDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2, {
    double tortuosity = AppConstants.roadTortuosityFactor,
  }) {
    return directDistance(lat1, lon1, lat2, lon2) * tortuosity;
  }

  /// Estimated driving travel duration in seconds based on average urban speed
  static double travelDurationSeconds(
    double lat1,
    double lon1,
    double lat2,
    double lon2, {
    double tortuosity = AppConstants.roadTortuosityFactor,
    double speedMetersPerSec = AppConstants.averageUrbanSpeedMetersPerSec,
  }) {
    final dist = roadDistance(lat1, lon1, lat2, lon2, tortuosity: tortuosity);
    return dist / speedMetersPerSec;
  }

  static double _toRadians(double degrees) => degrees * (pi / 180.0);
}
