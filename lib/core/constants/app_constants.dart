/// Central configuration for the KSRTC SmartTrack application.
class AppConstants {
  AppConstants._();

  // ── Google Maps API Keys ──────────────────────────────────────────────
  /// Maps SDK key – used in AndroidManifest.xml & AppDelegate.swift for
  /// rendering the map, and by the geocoding package for reverse-geocoding.
  static const String mapsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY';

  /// Directions API key – used to fetch route polylines.
  static const String directionsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY';

  /// Places API key – used for autocomplete and place detail lookups.
  static const String placesApiKey = 'YOUR_GOOGLE_MAPS_API_KEY';

  // ── Bus metadata ─────────────────────────────────────────────────────
  static const List<String> busTypes = [
    'Ordinary',
    'Fast Passenger',
    'Super Fast',
    'Deluxe',
    'AC Deluxe',
  ];

  static const List<String> shifts = [
    'Morning',
    'Afternoon',
    'Night',
  ];

  // ── GPS tuning ───────────────────────────────────────────────────────
  /// Interval (in seconds) between GPS updates while the app is in the
  /// foreground.
  static const int gpsIntervalForegroundSec = 10;

  /// Interval (in seconds) between GPS updates when the app is in the
  /// background.
  static const int gpsIntervalBackgroundSec = 30;

  /// Minimum displacement (in metres) before a location update is fired.
  static const int gpsMinDisplacementMetres = 10;

  // ── Alerts ───────────────────────────────────────────────────────────
  /// Distance (in metres) at which the passenger receives a destination
  /// alert.
  static const double destinationAlertMetres = 100.0;

  // ── Firestore collection names ───────────────────────────────────────
  static const String usersCollection = 'users';
  static const String tripsCollection = 'trips';

  /// Permanent bus routes saved when a conductor ends a trip.
  static const String routesCollection = 'routes';

  /// Buses registered by conductors.
  static const String busesCollection = 'buses';

  /// Distance (in metres) at which a stop announcement is triggered.
  static const double stopAnnouncementMetres = 100.0;
}
