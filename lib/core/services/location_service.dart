import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:ksrtc_smarttrack/core/constants/app_constants.dart';
import 'package:ksrtc_smarttrack/core/utils/location_utils.dart';

/// Provides a battery-efficient GPS position stream used by the conductor
/// during live tracking.
class LocationService {
  StreamSubscription<Position>? _positionSubscription;

  /// Starts listening to position updates and invokes [onUpdate] on every new
  /// position.
  ///
  /// Uses [AppConstants.gpsMinDisplacementMetres] to filter out small
  /// movements and avoid excessive Firestore writes.
  Future<void> startTracking({
    required void Function(Position position) onUpdate,
  }) async {
    await LocationUtils.ensurePermissions();

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: AppConstants.gpsMinDisplacementMetres,
    );

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen(onUpdate);
  }

  /// Stops the GPS stream and cleans up resources.
  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  /// Whether the service is currently tracking.
  bool get isTracking => _positionSubscription != null;
}
