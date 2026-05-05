import 'dart:math';

/// Utility helpers for geospatial distance calculations.
class DistanceUtils {
  DistanceUtils._();

  static const double _earthRadiusMetres = 6371000;

  /// Returns the Haversine distance in **metres** between two coordinates.
  static double haversine(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return _earthRadiusMetres * c;
  }

  /// Returns the forward azimuth bearing in **degrees** (0–360, clockwise from north)
  /// from point 1 to point 2.
  static double bearing(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final lat1R = _toRadians(lat1);
    final lat2R = _toRadians(lat2);
    final dLng = _toRadians(lng2 - lng1);

    final y = sin(dLng) * cos(lat2R);
    final x =
        cos(lat1R) * sin(lat2R) - sin(lat1R) * cos(lat2R) * cos(dLng);

    return (_toDegrees(atan2(y, x)) + 360) % 360;
  }

  static double _toRadians(double degrees) => degrees * pi / 180;
  static double _toDegrees(double radians) => radians * 180 / pi;
}
