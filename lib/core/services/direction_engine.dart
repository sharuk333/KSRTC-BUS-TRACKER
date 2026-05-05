import 'package:ksrtc_smarttrack/core/utils/distance_utils.dart';
import 'package:ksrtc_smarttrack/data/models/route_model.dart';
import 'package:ksrtc_smarttrack/data/models/stop_model.dart';

/// Automatically determines the direction a bus is travelling based on its
/// current GPS position and the ordered stop list.
///
/// **Algorithm**
/// 1.  The canonical route is: stops sorted by [StopModel.order] ascending.
///     - stop[0]   = forward-origin  (e.g. Thiruvananthapuram)
///     - stop[N-1] = forward-destination (e.g. Kasaragod)
///
/// 2.  On every GPS update call [detect].
///     - Find the *nearest* stop index in the sorted list.
///     - If the nearest stop index is in the **upper half** of the route
///       (index >= N/2) → the bus has reached / passed the midpoint towards
///       the destination → direction = **forward**.
///     - When the bus subsequently moves and the nearest stop index falls back
///       into the **lower half** (index < N/2) *and* the current direction was
///       previously forward → direction flips to **return_**.
///     - Additionally: if the bus is within [_terminalRadiusMetres] of the
///       forward-destination stop it is treated as "reached destination" and
///       direction flips to return_ on the *next* meaningful movement.
///
/// 3.  With fewer than 2 stops no determination is possible → [BusDirection.unknown].
class DirectionEngine {
  /// Radius (metres) around a terminal stop considered "arrived".
  static const double _terminalRadiusMetres = 150.0;

  /// Fraction of the route that must be travelled before a direction switch
  /// is considered.  50% = midpoint.
  static const double _midpointFraction = 0.5;

  BusDirection _current = BusDirection.unknown;
  bool _reachedDestination = false;

  BusDirection get current => _current;

  /// Call on every GPS update.
  ///
  /// [stops] must be the FORWARD-ordered stop list (sorted by [StopModel.order]).
  /// [lat] / [lng] is the current bus position.
  ///
  /// Returns the updated [BusDirection].
  BusDirection detect({
    required List<StopModel> stops,
    required double lat,
    required double lng,
  }) {
    if (stops.length < 2) return _current;

    final sorted = List<StopModel>.from(stops)
      ..sort((a, b) => a.order.compareTo(b.order));

    final n = sorted.length;
    final origin = sorted.first;
    final destination = sorted.last;

    // Distance to each terminal.
    final distToOrigin = DistanceUtils.haversine(
      lat, lng, origin.lat, origin.lng,
    );
    final distToDestination = DistanceUtils.haversine(
      lat, lng, destination.lat, destination.lng,
    );

    // Find nearest stop index.
    int nearestIdx = 0;
    double nearestDist = double.infinity;
    for (var i = 0; i < n; i++) {
      final d = DistanceUtils.haversine(
        lat, lng, sorted[i].lat, sorted[i].lng,
      );
      if (d < nearestDist) {
        nearestDist = d;
        nearestIdx = i;
      }
    }

    final midpointIdx = (n * _midpointFraction).floor();

    // ── Reached the forward-destination terminal ──────────────────────────
    if (distToDestination <= _terminalRadiusMetres) {
      _reachedDestination = true;
    }

    // ── Reached the forward-origin terminal after having been at destination
    if (_reachedDestination && distToOrigin <= _terminalRadiusMetres) {
      _reachedDestination = false;
    }

    // ── Determine direction based on nearest-stop position ────────────────
    if (_current == BusDirection.unknown) {
      // Bootstrap: use which terminal is closer.
      if (distToOrigin <= distToDestination) {
        _current = BusDirection.forward;
      } else {
        _current = BusDirection.return_;
      }
    } else if (_current == BusDirection.forward) {
      // Switch to return_ once we passed the midpoint AND are heading back.
      if (_reachedDestination && nearestIdx < midpointIdx) {
        _current = BusDirection.return_;
      }
    } else {
      // return_ → switch back to forward once we're back near the origin side.
      if (!_reachedDestination && nearestIdx <= midpointIdx) {
        _current = BusDirection.forward;
      }
    }

    return _current;
  }

  /// Force-reset the engine (e.g. when a new trip starts).
  void reset() {
    _current = BusDirection.unknown;
    _reachedDestination = false;
  }
}
