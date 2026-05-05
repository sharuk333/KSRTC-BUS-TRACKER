import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ksrtc_smarttrack/data/models/stop_model.dart';

/// Direction of the current / last known bus journey.
///
/// `forward`  = bus is travelling from [fromPlace] → [toPlace] (stop order 1,2,3…)
/// `return_`  = bus is travelling from [toPlace] → [fromPlace] (stop order reversed)
/// `unknown`  = not yet determined
enum BusDirection { forward, return_, unknown }

/// A permanently saved bus route stored in the `routes` Firestore collection.
///
/// One route document per bus — the same stops are used for both the forward
/// and return journeys. [direction] reflects what the conductor's device last
/// detected automatically; passengers use it to display the correct stop order.
class RouteModel {
  final String routeId;

  // Owning bus / conductor (set when the conductor creates / updates the route)
  final String busId;
  final String conductorId;

  final String busNumber;
  final String busType;
  final String shift;

  // Origin (canonical forward direction)
  final String fromPlace;
  final String fromPlaceLower;
  final double fromLat;
  final double fromLng;

  // Destination (canonical forward direction)
  final String toPlace;
  final String toPlaceLower;
  final double toLat;
  final double toLng;

  // Route
  final String routePolyline;

  // Ordered stops — always stored in FORWARD order (order 1, 2, 3 … N).
  // Reverse in memory when direction == return_.
  final List<StopModel> stops;

  // Auto-detected direction pushed by the conductor device.
  final BusDirection direction;

  // ID of the currently active trip document, or empty string when idle.
  final String activeTripId;

  final DateTime createdAt;

  const RouteModel({
    required this.routeId,
    this.busId = '',
    this.conductorId = '',
    required this.busNumber,
    required this.busType,
    required this.shift,
    required this.fromPlace,
    required this.fromPlaceLower,
    required this.fromLat,
    required this.fromLng,
    required this.toPlace,
    required this.toPlaceLower,
    required this.toLat,
    required this.toLng,
    required this.routePolyline,
    required this.stops,
    this.direction = BusDirection.unknown,
    this.activeTripId = '',
    required this.createdAt,
  });

  factory RouteModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final rawStops = data['stops'] as List<dynamic>? ?? [];

    final fromPlace = data['fromPlace'] as String? ?? '';
    final toPlace = data['toPlace'] as String? ?? '';

    BusDirection direction;
    switch (data['direction'] as String? ?? 'unknown') {
      case 'forward':
        direction = BusDirection.forward;
      case 'return':
        direction = BusDirection.return_;
      default:
        direction = BusDirection.unknown;
    }

    return RouteModel(
      routeId: doc.id,
      busId: data['busId'] as String? ?? '',
      conductorId: data['conductorId'] as String? ?? '',
      busNumber: data['busNumber'] as String? ?? '',
      busType: data['busType'] as String? ?? '',
      shift: data['shift'] as String? ?? '',
      fromPlace: fromPlace,
      fromPlaceLower: (data['fromPlaceLower'] as String?)?.trim().toLowerCase() ??
          fromPlace.trim().toLowerCase(),
      fromLat: (data['fromLat'] as num?)?.toDouble() ?? 0,
      fromLng: (data['fromLng'] as num?)?.toDouble() ?? 0,
      toPlace: toPlace,
      toPlaceLower: (data['toPlaceLower'] as String?)?.trim().toLowerCase() ??
          toPlace.trim().toLowerCase(),
      toLat: (data['toLat'] as num?)?.toDouble() ?? 0,
      toLng: (data['toLng'] as num?)?.toDouble() ?? 0,
      routePolyline: data['routePolyline'] as String? ?? '',
      stops: rawStops
          .map((s) => StopModel.fromMap(s as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order)),
      direction: direction,
      activeTripId: data['activeTripId'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
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
      'busId': busId,
      'conductorId': conductorId,
      'busNumber': busNumber,
      'busType': busType,
      'shift': shift,
      'fromPlace': fromPlace,
      'fromPlaceLower': fromPlaceLower,
      'fromLat': fromLat,
      'fromLng': fromLng,
      'toPlace': toPlace,
      'toPlaceLower': toPlaceLower,
      'toLat': toLat,
      'toLng': toLng,
      'routePolyline': routePolyline,
      'stops': stops.map((s) => s.toMap()).toList(),
      'direction': dirStr,
      'activeTripId': activeTripId,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  /// Returns stops sorted in the correct order for [dir].
  /// If [dir] is unknown, defaults to forward.
  List<StopModel> stopsForDirection(BusDirection dir) {
    final sorted = List<StopModel>.from(stops)
      ..sort((a, b) => a.order.compareTo(b.order));
    if (dir == BusDirection.return_) return sorted.reversed.toList();
    return sorted;
  }
}
