import 'package:cloud_firestore/cloud_firestore.dart';

/// A single marked stop along a trip route.
class StopModel {
  final String name;
  final double lat;
  final double lng;
  final int order;
  final DateTime timestamp;

  const StopModel({
    required this.name,
    required this.lat,
    required this.lng,
    required this.order,
    required this.timestamp,
  });

  factory StopModel.fromMap(Map<String, dynamic> map) {
    return StopModel(
      name: map['name'] as String? ?? '',
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      order: map['order'] as int? ?? 0,
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'lat': lat,
      'lng': lng,
      'order': order,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }

  StopModel copyWith({
    String? name,
    double? lat,
    double? lng,
    int? order,
    DateTime? timestamp,
  }) {
    return StopModel(
      name: name ?? this.name,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      order: order ?? this.order,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
