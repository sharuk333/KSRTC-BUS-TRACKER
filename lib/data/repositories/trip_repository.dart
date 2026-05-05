import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ksrtc_smarttrack/core/constants/app_constants.dart';
import 'package:ksrtc_smarttrack/data/models/bus_model.dart';
import 'package:ksrtc_smarttrack/data/models/route_model.dart';
import 'package:ksrtc_smarttrack/data/models/stop_model.dart';
import 'package:ksrtc_smarttrack/data/models/trip_model.dart';

/// Data-access layer for trip and route documents in Firestore.
class TripRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _trips =>
      _firestore.collection(AppConstants.tripsCollection);

  CollectionReference get _routes =>
      _firestore.collection(AppConstants.routesCollection);

  // ── Create ──────────────────────────────────────────────────────────────

  /// Creates a new active trip and returns its Firestore document ID.
  Future<String> createTrip(TripModel trip) async {
    final doc = await _trips.add(trip.toMap());
    return doc.id;
  }

  // ── Read ────────────────────────────────────────────────────────────────

  /// Real-time stream of a single trip document.
  Stream<TripModel> tripStream(String tripId) {
    return _trips.doc(tripId).snapshots().map(
          (snap) => TripModel.fromFirestore(snap),
        );
  }

  /// Real-time stream of all **active** trips.
  Stream<List<TripModel>> activeTripsStream() {
    return _trips
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snap) => snap.docs.map(TripModel.fromFirestore).toList());
  }

  // ── Update – live GPS ──────────────────────────────────────────────────

  /// Pushes the conductor's latest GPS position and speed to Firestore.
  Future<void> updateLiveLocation({
    required String tripId,
    required double lat,
    required double lng,
    double speed = 0,
  }) async {
    await _trips.doc(tripId).update({
      'currentLat': lat,
      'currentLng': lng,
      'currentSpeed': speed,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  /// Mark a stop as PASSED by the conductor.
  ///
  /// Uses [FieldValue.arrayUnion] so the call is idempotent — calling it
  /// multiple times for the same [stopOrder] is harmless.
  Future<void> markStopPassed({
    required String tripId,
    required int stopOrder,
  }) async {
    await _trips.doc(tripId).update({
      'passedStopOrders': FieldValue.arrayUnion([stopOrder]),
    });
  }

  // ── Update – direction ─────────────────────────────────────────────────

  /// Auto-detected direction pushed to both the trip doc and its route doc.
  Future<void> updateDirection({
    required String tripId,
    required String routeId,
    required BusDirection direction,
  }) async {
    final dirStr = _dirToString(direction);
    final futures = <Future>[
      _trips.doc(tripId).update({'direction': dirStr}),
    ];
    if (routeId.isNotEmpty) {
      futures.add(_routes.doc(routeId).update({'direction': dirStr}));
    }
    await Future.wait(futures);
  }

  // ── Update – stops ─────────────────────────────────────────────────────

  /// Appends a marked stop to both the trip and its route document.
  Future<void> addStop({
    required String tripId,
    required String routeId,
    required StopModel stop,
  }) async {
    final futures = <Future>[
      _trips.doc(tripId).update({
        'stops': FieldValue.arrayUnion([stop.toMap()]),
      }),
    ];
    if (routeId.isNotEmpty) {
      futures.add(
        _routes.doc(routeId).update({
          'stops': FieldValue.arrayUnion([stop.toMap()]),
        }),
      );
    }
    await Future.wait(futures);
  }

  // ── Update – end trip ──────────────────────────────────────────────────

  /// Marks the trip as completed and clears [activeTripId] on the route.
  Future<void> endTrip(String tripId, {String routeId = ''}) async {
    final futures = <Future>[
      _trips.doc(tripId).update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
      }),
    ];
    if (routeId.isNotEmpty) {
      futures.add(
        _routes.doc(routeId).update({'activeTripId': ''}),
      );
    }
    await Future.wait(futures);
  }

  // ── Upsert permanent route ─────────────────────────────────────────────

  /// Creates or updates the **single** permanent route for [bus].
  ///
  /// • One route document per bus (matched by [BusModel.busId]).
  /// • If no route exists, a new document is created with empty stops.
  /// • If one already exists its metadata is merged but **stops are NEVER
  ///   overwritten** — they are only modified via [addStop] / [removeStop].
  /// • Sets [activeTripId] so passengers can find live trips.
  ///
  /// Returns the route document ID.
  Future<String> upsertRoute({
    required BusModel bus,
    required TripModel trip,
    required String tripId,
  }) async {
    final fromLower = bus.fromPlace.trim().toLowerCase();
    final toLower = bus.toPlace.trim().toLowerCase();

    final existing = await _routes
        .where('busId', isEqualTo: bus.busId)
        .limit(1)
        .get();

    // Base metadata — shared between create and update.
    final routeData = <String, dynamic>{
      'busId': bus.busId,
      'conductorId': bus.conductorId,
      'busNumber': bus.busNumber,
      'busType': bus.busType,
      'shift': bus.shift,
      'fromPlace': bus.fromPlace.trim(),
      'fromPlaceLower': fromLower,
      'fromLat': bus.fromLat,
      'fromLng': bus.fromLng,
      'toPlace': bus.toPlace.trim(),
      'toPlaceLower': toLower,
      'toLat': bus.toLat,
      'toLng': bus.toLng,
      'routePolyline': trip.routePolyline,
      'activeTripId': tripId,
      'direction': 'unknown',
    };

    if (existing.docs.isEmpty) {
      // Brand-new route — start with whatever stops the trip has (usually []).
      final sortedStops = List<StopModel>.from(trip.stops)
        ..sort((a, b) => a.order.compareTo(b.order));
      routeData['stops'] = sortedStops.map((s) => s.toMap()).toList();
      routeData['createdAt'] = FieldValue.serverTimestamp();
      final doc = await _routes.add(routeData);
      debugPrint('[upsertRoute] Created route ${doc.id} for bus ${bus.busId}');
      return doc.id;
    } else {
      // Existing route — update metadata but PRESERVE existing stops.
      // Stops are only modified via addStop() / removeStop().
      final docId = existing.docs.first.id;
      await _routes.doc(docId).update(routeData);
      debugPrint('[upsertRoute] Updated route $docId for bus ${bus.busId} (stops preserved)');
      return docId;
    }
  }

  // ── Fetch route by bus ID ──────────────────────────────────────────────

  /// Returns the permanent route document for [busId], or `null` if none.
  Future<RouteModel?> getRouteByBusId(String busId) async {
    final snap = await _routes
        .where('busId', isEqualTo: busId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return RouteModel.fromFirestore(snap.docs.first);
  }

  // ── Remove a single stop ──────────────────────────────────────────────

  /// Removes a stop from both the trip and route documents by its map value.
  Future<void> removeStop({
    required String tripId,
    required String routeId,
    required StopModel stop,
  }) async {
    final futures = <Future>[
      if (tripId.isNotEmpty)
        _trips.doc(tripId).update({
          'stops': FieldValue.arrayRemove([stop.toMap()]),
        }),
      if (routeId.isNotEmpty)
        _routes.doc(routeId).update({
          'stops': FieldValue.arrayRemove([stop.toMap()]),
        }),
    ];
    await Future.wait(futures);
  }

  // ── Start trip from existing route (tracking-only) ────────────────────

  /// Creates a new active trip and links it to the existing [route].
  /// Copies route stops into the trip doc (read-only snapshot).
  /// Sets [activeTripId] on the route so passengers can find the live bus.
  /// Returns `({String tripId, String routeId})`.
  Future<({String tripId, String routeId})> startTripFromExistingRoute({
    required BusModel bus,
    required RouteModel route,
    required String conductorId,
  }) async {
    final trip = TripModel(
      tripId: '',
      conductorId: conductorId,
      busId: bus.busId,
      routeId: route.routeId,
      busNumber: bus.busNumber,
      busType: bus.busType,
      shift: bus.shift,
      fromPlace: bus.fromPlace,
      fromLat: bus.fromLat,
      fromLng: bus.fromLng,
      toPlace: bus.toPlace,
      toLat: bus.toLat,
      toLng: bus.toLng,
      routePolyline: route.routePolyline,
      status: TripStatus.active,
      currentLat: bus.fromLat,
      currentLng: bus.fromLng,
      lastUpdated: DateTime.now(),
      startedAt: DateTime.now(),
      direction: BusDirection.unknown,
      stops: route.stops, // snapshot of saved stops
    );

    final tripId = await createTrip(trip);

    // Link activeTripId on the route doc.
    await _routes.doc(route.routeId).update({
      'activeTripId': tripId,
      'direction': 'unknown',
    });

    // Stamp routeId on the trip doc.
    await updateTripRouteId(tripId: tripId, routeId: route.routeId);

    debugPrint('[startTripFromExistingRoute] trip=$tripId route=${route.routeId}');
    return (tripId: tripId, routeId: route.routeId);
  }

  // ── Search permanent routes ────────────────────────────────────────────

  /// Queries the `routes` collection.
  ///
  /// Matches BOTH forward AND reverse passenger searches:
  ///   forward : fromPlaceLower contains [from]  &&  toPlaceLower contains [to]
  ///   reverse : toPlaceLower contains [from]    &&  fromPlaceLower contains [to]
  Stream<List<RouteModel>> searchRoutesStream({
    required String from,
    required String to,
  }) {
    final fq = from.trim().toLowerCase();
    final tq = to.trim().toLowerCase();

    return _routes.snapshots().map((snap) {
      return snap.docs
          .map((doc) => RouteModel.fromFirestore(doc))
          .where((r) {
            final fwd = (fq.isEmpty || r.fromPlaceLower.contains(fq)) &&
                (tq.isEmpty || r.toPlaceLower.contains(tq));
            final rev = (fq.isEmpty || r.toPlaceLower.contains(fq)) &&
                (tq.isEmpty || r.fromPlaceLower.contains(tq));
            return fwd || rev;
          })
          .toList();
    });
  }

  /// One-shot version of [searchRoutesStream].
  Future<List<RouteModel>> searchRoutes({
    required String from,
    required String to,
  }) async {
    final fq = from.trim().toLowerCase();
    final tq = to.trim().toLowerCase();

    final snapshot = await _routes.get();
    return snapshot.docs
        .map((doc) => RouteModel.fromFirestore(doc))
        .where((r) {
          final fwd = (fq.isEmpty || r.fromPlaceLower.contains(fq)) &&
              (tq.isEmpty || r.toPlaceLower.contains(tq));
          final rev = (fq.isEmpty || r.toPlaceLower.contains(fq)) &&
              (tq.isEmpty || r.fromPlaceLower.contains(tq));
          return fwd || rev;
        })
        .toList();
  }

  /// Fetch a single route by its document ID.
  Future<RouteModel?> getRoute(String routeId) async {
    final doc = await _routes.doc(routeId).get();
    if (!doc.exists) return null;
    return RouteModel.fromFirestore(doc);
  }

  /// Real-time stream of a single route document.
  Stream<RouteModel?> routeStream(String routeId) {
    return _routes.doc(routeId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return RouteModel.fromFirestore(snap);
    });
  }

  // ── Directions API ─────────────────────────────────────────────────────

  Future<String> fetchRoutePolyline({
    required String originLat,
    required String originLng,
    required String destLat,
    required String destLng,
  }) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=$originLat,$originLng'
      '&destination=$destLat,$destLng'
      '&key=${AppConstants.directionsApiKey}',
    );

    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw 'Failed to fetch directions (HTTP ${response.statusCode}).';
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final routes = data['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) {
      throw 'No route found between the selected locations.';
    }

    return routes[0]['overview_polyline']['points'] as String;
  }

  // ── Places Autocomplete ────────────────────────────────────────────────

  Future<List<Map<String, String>>> placesAutocomplete(String input) async {
    if (input.isEmpty) return [];

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json'
      '?input=${Uri.encodeComponent(input)}'
      '&components=country:in'
      '&key=${AppConstants.placesApiKey}',
    );

    final response = await http.get(url);
    if (response.statusCode != 200) return [];

    final data = json.decode(response.body) as Map<String, dynamic>;
    final predictions = data['predictions'] as List<dynamic>? ?? [];

    return predictions.map((p) {
      final pred = p as Map<String, dynamic>;
      return {
        'description': pred['description'] as String,
        'place_id': pred['place_id'] as String,
      };
    }).toList();
  }

  Future<Map<String, double>> placeDetails(String placeId) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json'
      '?place_id=$placeId'
      '&fields=geometry'
      '&key=${AppConstants.placesApiKey}',
    );

    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw 'Failed to fetch place details.';
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final location =
        data['result']['geometry']['location'] as Map<String, dynamic>;

    return {
      'lat': (location['lat'] as num).toDouble(),
      'lng': (location['lng'] as num).toDouble(),
    };
  }

  // ── Update – routeId stamp ─────────────────────────────────────────────

  /// Stamps [routeId] on the trip document after upsert-route returns.
  Future<void> updateTripRouteId({
    required String tripId,
    required String routeId,
  }) async {
    await _trips.doc(tripId).update({'routeId': routeId});
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  static String _dirToString(BusDirection d) {
    switch (d) {
      case BusDirection.forward:
        return 'forward';
      case BusDirection.return_:
        return 'return';
      case BusDirection.unknown:
        return 'unknown';
    }
  }
}
