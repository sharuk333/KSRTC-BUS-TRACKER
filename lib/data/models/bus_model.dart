import 'package:cloud_firestore/cloud_firestore.dart';

/// A bus registered by a conductor and stored in the `buses` Firestore collection.
///
/// A bus has a single canonical route: [fromPlace] → [toPlace].
/// The same stop list is used for both the forward and return journeys.
/// Direction is determined automatically at runtime — it is NOT stored here.
class BusModel {
  final String busId;
  final String conductorId;
  final String busNumber;
  final String busType;
  final String shift;

  // Canonical route endpoints
  final String fromPlace;
  final double fromLat;
  final double fromLng;

  final String toPlace;
  final double toLat;
  final double toLng;

  final DateTime createdAt;

  const BusModel({
    required this.busId,
    required this.conductorId,
    required this.busNumber,
    required this.busType,
    required this.shift,
    required this.fromPlace,
    required this.fromLat,
    required this.fromLng,
    required this.toPlace,
    required this.toLat,
    required this.toLng,
    required this.createdAt,
  });

  factory BusModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return BusModel(
      busId: doc.id,
      conductorId: d['conductorId'] as String? ?? '',
      busNumber: d['busNumber'] as String? ?? '',
      busType: d['busType'] as String? ?? '',
      shift: d['shift'] as String? ?? '',
      fromPlace: d['fromPlace'] as String? ?? '',
      fromLat: (d['fromLat'] as num?)?.toDouble() ?? 0,
      fromLng: (d['fromLng'] as num?)?.toDouble() ?? 0,
      toPlace: d['toPlace'] as String? ?? '',
      toLat: (d['toLat'] as num?)?.toDouble() ?? 0,
      toLng: (d['toLng'] as num?)?.toDouble() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'conductorId': conductorId,
        'busNumber': busNumber,
        'busType': busType,
        'shift': shift,
        'fromPlace': fromPlace,
        'fromLat': fromLat,
        'fromLng': fromLng,
        'toPlace': toPlace,
        'toLat': toLat,
        'toLng': toLng,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  BusModel copyWith({
    String? busId,
    String? conductorId,
    String? busNumber,
    String? busType,
    String? shift,
    String? fromPlace,
    double? fromLat,
    double? fromLng,
    String? toPlace,
    double? toLat,
    double? toLng,
    DateTime? createdAt,
  }) =>
      BusModel(
        busId: busId ?? this.busId,
        conductorId: conductorId ?? this.conductorId,
        busNumber: busNumber ?? this.busNumber,
        busType: busType ?? this.busType,
        shift: shift ?? this.shift,
        fromPlace: fromPlace ?? this.fromPlace,
        fromLat: fromLat ?? this.fromLat,
        fromLng: fromLng ?? this.fromLng,
        toPlace: toPlace ?? this.toPlace,
        toLat: toLat ?? this.toLat,
        toLng: toLng ?? this.toLng,
        createdAt: createdAt ?? this.createdAt,
      );
}
