import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ksrtc_smarttrack/core/constants/app_constants.dart';
import 'package:ksrtc_smarttrack/data/models/bus_model.dart';

/// CRUD operations for the `buses` Firestore collection.
///
/// Each conductor owns their own buses.  The repository enforces that a
/// conductor can only read/write their own documents (the security rule also
/// enforces this server-side).
class BusRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _buses =>
      _firestore.collection(AppConstants.busesCollection);

  CollectionReference get _routes =>
      _firestore.collection(AppConstants.routesCollection);

  CollectionReference get _trips =>
      _firestore.collection(AppConstants.tripsCollection);

  // ── Create ──────────────────────────────────────────────────────────────

  /// Returns `true` if a bus with [busNumber] already exists in the collection.
  ///
  /// The check is case-insensitive and trims whitespace.
  /// Pass [excludeBusId] when editing an existing bus so the bus being edited
  /// does not count as a duplicate of itself.
  Future<bool> busNumberExists(String busNumber, {String? excludeBusId}) async {
    final normalised = busNumber.trim().toUpperCase();
    final snap = await _buses
        .where('busNumber', isEqualTo: normalised)
        .limit(5)
        .get();
    if (snap.docs.isEmpty) return false;
    if (excludeBusId == null) return true;
    // Allow the match only if it is NOT the bus being edited.
    return snap.docs.any((d) => d.id != excludeBusId);
  }

  Future<String> addBus(BusModel bus) async {
    final doc = await _buses.add(bus.toMap());

    // Auto-create a route document so passengers can discover this bus
    // immediately via the routes collection — even before the conductor
    // sets up stops or starts a trip.
    final fromLower = bus.fromPlace.trim().toLowerCase();
    final toLower = bus.toPlace.trim().toLowerCase();
    await _routes.add({
      'busId': doc.id,
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
      'routePolyline': '',
      'stops': [],
      'activeTripId': '',
      'direction': 'unknown',
      'createdAt': FieldValue.serverTimestamp(),
    });

    return doc.id;
  }

  // ── Read ────────────────────────────────────────────────────────────────

  /// Real-time stream of all buses belonging to [conductorId].
  Stream<List<BusModel>> busesStream(String conductorId) {
    return _buses
        .where('conductorId', isEqualTo: conductorId)
        .snapshots()
        .map((snap) {
      final buses = snap.docs.map(BusModel.fromFirestore).toList();
      buses.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return buses;
    });
  }

  // ── Update ──────────────────────────────────────────────────────────────

  Future<void> updateBus(BusModel bus) async {
    await _buses.doc(bus.busId).update(bus.toMap());

    // Keep the route document in sync with bus metadata changes.
    final routeSnap = await _routes
        .where('busId', isEqualTo: bus.busId)
        .limit(1)
        .get();
    if (routeSnap.docs.isNotEmpty) {
      final fromLower = bus.fromPlace.trim().toLowerCase();
      final toLower = bus.toPlace.trim().toLowerCase();
      await _routes.doc(routeSnap.docs.first.id).update({
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
      });
    }
  }

  // ── Delete ──────────────────────────────────────────────────────────────

  /// Deletes a bus document and its associated route document (if any).
  ///
  /// Throws a [BusDeletionException] if the bus currently has an active trip.
  /// Completed historical trips are NOT deleted.
  Future<void> deleteBus(String busId) async {
    // Force-end any stale active trips for this bus (orphaned from
    // previous sessions that didn't end cleanly).
    final activeSnap = await _trips
        .where('busId', isEqualTo: busId)
        .where('status', isEqualTo: 'active')
        .get();

    for (final doc in activeSnap.docs) {
      await _trips.doc(doc.id).update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
      });
    }

    // Delete the bus document.
    await _buses.doc(busId).delete();

    // Delete the matching route document so passengers can no longer see it.
    final routeSnap = await _routes
        .where('busId', isEqualTo: busId)
        .get();
    for (final doc in routeSnap.docs) {
      await _routes.doc(doc.id).delete();
    }
  }

  // ── Active-trip guard ────────────────────────────────────────────────────

  /// Returns `true` if [busId] has at least one active trip right now.
  Future<bool> hasActiveTrip(String busId) async {
    final snap = await _trips
        .where('busId', isEqualTo: busId)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }
}

/// Thrown when a bus cannot be deleted because it has an active trip.
class BusDeletionException implements Exception {
  final String message;
  const BusDeletionException(this.message);

  @override
  String toString() => message;
}
