import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ksrtc_smarttrack/core/services/location_service.dart';
import 'package:ksrtc_smarttrack/core/services/tts_service.dart';

/// Singleton [LocationService] used for conductor GPS tracking.
final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

/// Singleton [TtsService] used for passenger destination voice alerts.
final ttsServiceProvider = Provider<TtsService>((ref) {
  return TtsService();
});
