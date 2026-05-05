import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ksrtc_smarttrack/data/models/route_model.dart';
import 'package:ksrtc_smarttrack/data/models/trip_model.dart';
import 'package:ksrtc_smarttrack/data/repositories/trip_repository.dart';

// ── Repository singleton ─────────────────────────────────────────────────
final tripRepositoryProvider = Provider<TripRepository>((ref) {
  return TripRepository();
});

// ── All active trips (real-time) ─────────────────────────────────────────
final activeTripsProvider = StreamProvider<List<TripModel>>((ref) {
  return ref.watch(tripRepositoryProvider).activeTripsStream();
});

// ── Single trip stream (real-time) ───────────────────────────────────────
final tripStreamProvider =
    StreamProvider.family<TripModel, String>((ref, tripId) {
  return ref.watch(tripRepositoryProvider).tripStream(tripId);
});

// ── Search parameters (kept for compatibility) ────────────────────────────
/// Holds the current search parameters set by the passenger.
final searchQueryProvider = StateProvider<({String from, String to})>((ref) {
  return (from: '', to: '');
});

// ── Search results — family variant (PREFERRED) ───────────────────────────
/// Takes ({from, to}) as the family key so the stream is created immediately
/// with the correct query — no microtask timing issues.
final routeSearchProvider = StreamProvider.family<List<RouteModel>,
    ({String from, String to})>((ref, query) {
  return ref.watch(tripRepositoryProvider).searchRoutesStream(
        from: query.from,
        to: query.to,
      );
});

// ── Search results from permanent routes collection ──────────────────────
/// Returns saved routes from the permanent `routes` collection.
/// Always works regardless of whether a conductor is active.
final searchResultsProvider = StreamProvider<List<RouteModel>>((ref) {
  final query = ref.watch(searchQueryProvider);
  return ref.watch(tripRepositoryProvider).searchRoutesStream(
        from: query.from,
        to: query.to,
      );
});

// ── Single route by ID (one-shot fetch) ─────────────────────────────────
final routeByIdProvider =
    FutureProvider.family<RouteModel?, String>((ref, routeId) {
  return ref.watch(tripRepositoryProvider).getRoute(routeId);
});

// ── Single route by ID (real-time stream) ───────────────────────────────
/// Used by [BusTrackingScreen] so GPS callbacks always have the latest route.
final routeStreamProvider =
    StreamProvider.family<RouteModel?, String>((ref, routeId) {
  return ref
      .watch(tripRepositoryProvider)
      .routeStream(routeId);
});
