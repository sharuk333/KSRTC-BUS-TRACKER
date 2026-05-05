import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ksrtc_smarttrack/data/models/route_model.dart';
import 'package:ksrtc_smarttrack/data/models/stop_model.dart';

enum TripStatus { active, completed }

/// Represents a single bus trip stored in the `trips` Firestore collection.
class TripModel {
  final String tripId;
  final String conductorId;

  /// ID of the [BusModel] document this trip belongs to.
  final String busId;

  /// ID of the permanent [RouteModel] document that was upserted when the trip
  /// was started.  Empty string for legacy trips that predate this field.
  final String routeId;

  final String busNumber;
  final String busType;
  final String shift;

  // Origin (canonical forward direction)
  final String fromPlace;
  final double fromLat;
  final double fromLng;

  // Destination (canonical forward direction)
  final String toPlace;
  final double toLat;
  final double toLng;

  // Route
  final String routePolyline;

  // Live state
  final TripStatus status;
  final double currentLat;
  final double currentLng;
  final double currentSpeed;
  final DateTime lastUpdated;
  final DateTime startedAt;
  final DateTime? completedAt;

  // Stops (always stored in FORWARD order)
  final List<StopModel> stops;

  /// Stop order numbers that the conductor has ALREADY passed.
  /// Written by the conductor, read by passengers for mid-trip join.
  final List<int> passedStopOrders;

  // Auto-detected direction
  final BusDirection direction;

  const TripModel({
    required this.tripId,
    required this.conductorId,
    this.busId = '',
    this.routeId = '',
    required this.busNumber,
    required this.busType,
    required this.shift,
    required this.fromPlace,
    required this.fromLat,
    required this.fromLng,
    required this.toPlace,
    required this.toLat,
    required this.toLng,
    required this.routePolyline,
    required this.status,
    required this.currentLat,
    required this.currentLng,
    this.currentSpeed = 0,
    required this.lastUpdated,
    required this.startedAt,
    this.completedAt,
    this.stops = const [],
    this.passedStopOrders = const [],
    this.direction = BusDirection.unknown,
  });

  factory TripModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final rawStops = data['stops'] as List<dynamic>? ?? [];

    BusDirection direction;
    switch (data['direction'] as String? ?? 'unknown') {
      case 'forward':
        direction = BusDirection.forward;
      case 'return':
        direction = BusDirection.return_;
      default:
        direction = BusDirection.unknown;
    }

    return TripModel(
      tripId: doc.id,
      conductorId: data['conductorId'] as String? ?? '',
      busId: data['busId'] as String? ?? '',
      routeId: data['routeId'] as String? ?? '',
      busNumber: data['busNumber'] as String? ?? '',
      busType: data['busType'] as String? ?? '',
      shift: data['shift'] as String? ?? '',
      fromPlace: data['fromPlace'] as String? ?? '',
      fromLat: (data['fromLat'] as num?)?.toDouble() ?? 0,
      fromLng: (data['fromLng'] as num?)?.toDouble() ?? 0,
      toPlace: data['toPlace'] as String? ?? '',
      toLat: (data['toLat'] as num?)?.toDouble() ?? 0,
      toLng: (data['toLng'] as num?)?.toDouble() ?? 0,
      routePolyline: data['routePolyline'] as String? ?? '',
      status: data['status'] == 'completed'
          ? TripStatus.completed
          : TripStatus.active,
      currentLat: (data['currentLat'] as num?)?.toDouble() ?? 0,
      currentLng: (data['currentLng'] as num?)?.toDouble() ?? 0,
      currentSpeed: (data['currentSpeed'] as num?)?.toDouble() ?? 0,
      lastUpdated:
          (data['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now(),
      startedAt:
          (data['startedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      stops: rawStops
          .map((s) => StopModel.fromMap(s as Map<String, dynamic>))
          .toList(),
      passedStopOrders: (data['passedStopOrders'] as List<dynamic>? ?? [])
          .map((e) => (e as num).toInt())
          .toList(),
      direction: direction,
    );
  }

  Map<String, dynamic> toMap() {
    String dirStr;
    switch (direction) {
      case BusDirection.forward:
        dirStr = 'forward';
      case BusDirection.return_:
        dirStr = 'return';
      case BusDirection.unknown:
        dirStr = 'unknown';
    }

    return {
      'conductorId': conductorId,
      'busId': busId,
      'routeId': routeId,
      'busNumber': busNumber,
      'busType': busType,
      'shift': shift,
      'fromPlace': fromPlace,
      'fromLat': fromLat,
      'fromLng': fromLng,
      'toPlace': toPlace,
      'toLat': toLat,
      'toLng': toLng,
      'routePolyline': routePolyline,
      'status': status == TripStatus.completed ? 'completed' : 'active',
      'currentLat': currentLat,
      'currentLng': currentLng,
      'currentSpeed': currentSpeed,
      'lastUpdated': Timestamp.fromDate(lastUpdated),
      'startedAt': Timestamp.fromDate(startedAt),
      'completedAt':
          completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'stops': stops.map((s) => s.toMap()).toList(),
      'passedStopOrders': passedStopOrders,
      'direction': dirStr,
    };
  }

  TripModel copyWith({
    String? tripId,
    String? conductorId,
    String? busId,
    String? routeId,
    String? busNumber,
    String? busType,
    String? shift,
    String? fromPlace,
    double? fromLat,
    double? fromLng,
    String? toPlace,
    double? toLat,
    double? toLng,
    String? routePolyline,
    TripStatus? status,
    double? currentLat,
    double? currentLng,
    double? currentSpeed,
    DateTime? lastUpdated,
    DateTime? startedAt,
    DateTime? completedAt,
    List<StopModel>? stops,
    BusDirection? direction,
  }) {
    return TripModel(
      tripId: tripId ?? this.tripId,
      conductorId: conductorId ?? this.conductorId,
      busId: busId ?? this.busId,
      routeId: routeId ?? this.routeId,
      busNumber: busNumber ?? this.busNumber,
      busType: busType ?? this.busType,
      shift: shift ?? this.shift,
      fromPlace: fromPlace ?? this.fromPlace,
      fromLat: fromLat ?? this.fromLat,
      fromLng: fromLng ?? this.fromLng,
      toPlace: toPlace ?? this.toPlace,
      toLat: toLat ?? this.toLat,
      toLng: toLng ?? this.toLng,
      routePolyline: routePolyline ?? this.routePolyline,
      status: status ?? this.status,
      currentLat: currentLat ?? this.currentLat,
      currentLng: currentLng ?? this.currentLng,
      currentSpeed: currentSpeed ?? this.currentSpeed,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      stops: stops ?? this.stops,
      direction: direction ?? this.direction,
    );
  }

  bool get isActive => status == TripStatus.active;
}
