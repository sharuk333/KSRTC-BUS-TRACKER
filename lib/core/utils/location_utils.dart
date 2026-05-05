import 'package:geolocator/geolocator.dart';

/// Helpers for location permission handling.
class LocationUtils {
  LocationUtils._();

  /// Ensures location services are enabled and permissions are granted.
  ///
  /// Throws a [String] message if something is wrong so callers can display
  /// a user-friendly dialog.
  static Future<void> ensurePermissions() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw 'Location services are disabled. Please enable them in Settings.';
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw 'Location permission denied. The app needs your location to work.';
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw 'Location permission permanently denied. '
          'Please enable it from app settings.';
    }
  }

  /// Returns the current device position with high accuracy.
  static Future<Position> getCurrentPosition() async {
    await ensurePermissions();
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }
}
