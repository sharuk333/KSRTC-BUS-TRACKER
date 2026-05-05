import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ksrtc_smarttrack/core/constants/app_constants.dart';
import 'package:ksrtc_smarttrack/core/theme/app_theme.dart';
import 'package:ksrtc_smarttrack/core/utils/distance_utils.dart';
import 'package:ksrtc_smarttrack/core/utils/navigation_arrow_marker.dart';
import 'package:ksrtc_smarttrack/data/models/route_model.dart';
import 'package:ksrtc_smarttrack/data/models/stop_model.dart';
import 'package:ksrtc_smarttrack/presentation/widgets/stop_list_tile.dart';
import 'package:ksrtc_smarttrack/providers/location_provider.dart';
import 'package:ksrtc_smarttrack/providers/trip_provider.dart';

/// Passenger bus-tracking screen.
///
/// [routeId]  — Firestore document ID of the route to track.
/// [from]     — passenger's selected departure (free-text, may match either
///              a route terminal or an intermediate stop name).
/// [to]       — passenger's selected destination (same).
class BusTrackingScreen extends ConsumerStatefulWidget {
  final String routeId;
  final String from;
  final String to;

  const BusTrackingScreen({
    super.key,
    required this.routeId,
    this.from = '',
    this.to   = '',
  });

  @override
  ConsumerState<BusTrackingScreen> createState() => _BusTrackingScreenState();
}

class _BusTrackingScreenState extends ConsumerState<BusTrackingScreen> {
  GoogleMapController? _mapController;

  // ── Bus live position (from conductor's Firebase data) ────────────────────
  LatLng?               _busLatLng;
  LatLng?               _prevBusLatLng;
  double                _busBearing   = 0;
  double                _busSpeedKmh  = 0;
  BitmapDescriptor?     _arrowIcon;

  // ── Trip state ────────────────────────────────────────────────────────────
  bool                  _tripActive       = false;
  bool                  _signalLost       = false;
  String?               _activeTripId;

  // ── Route / direction state ───────────────────────────────────────────────
  bool                  _directionResolved = false;
  bool                  _routeListenerRegistered = false;
  bool                  _tripListenerRegistered  = false;

  // ── Direction-resolved state (set once per screen open by _resolveDirection)
  List<StopModel>       _orderedStops = [];

  // ORIGIN — always widget.from, resolved to a LatLng.
  double                _originLat  = 0;
  double                _originLng  = 0;
  String                _originName = '';

  // DESTINATION — always widget.to, resolved to a LatLng.
  double                _destLat  = 0;
  double                _destLng  = 0;
  String                _destName = '';

  // ── ETA state ─────────────────────────────────────────────────────────────
  String                _etaText = '';

  // ── Voice announcement state ─────────────────────────────────────────────
  final Set<int>        _announcedArrival = {};
  final Set<int>        _announcedNext    = {};
  bool                  _destinationReached = false;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    ref.read(ttsServiceProvider).stop();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // ── Route listener: resolves direction + destination once ──────────────
    if (!_routeListenerRegistered) {
      _routeListenerRegistered = true;

      ref.listenManual(routeStreamProvider(widget.routeId), (_, next) {
        next.whenData((route) {
          if (route == null || !mounted) return;

          // Grab activeTripId from the route so we can listen to the trip.
          final tripId = route.activeTripId;
          if (tripId.isNotEmpty && _activeTripId != tripId) {
            _activeTripId = tripId;
            _registerTripListener(tripId);
          }

          if (!_directionResolved) {
            _directionResolved = true;
            _resolveDirection(route);
          } else {
            setState(() {});
          }
        });
      });
    }
  }

  /// Registers a real-time listener on the active trip document to read
  /// the conductor's live GPS coordinates, speed, and trip status.
  void _registerTripListener(String tripId) {
    if (_tripListenerRegistered) return;
    _tripListenerRegistered = true;

    ref.listenManual(tripStreamProvider(tripId), (_, next) {
      next.whenData((trip) {
        if (!mounted) return;

        // ── Sync passed stops from Firebase (critical for mid-trip join) ────
        // Pre-populate _announcedArrival so already-passed stops are shown
        // correctly and voice announcements are silently skipped for them.
        if (trip.passedStopOrders.isNotEmpty) {
          for (final order in trip.passedStopOrders) {
            _announcedArrival.add(order);
            _announcedNext.add(order);
          }
        }

        // ── Trip ended ──────────────────────────────────────────────────────
        if (!trip.isActive) {
          setState(() {
            _tripActive  = false;
            _busLatLng   = null;
            _busSpeedKmh = 0;
            _etaText     = '';
          });
          return;
        }

        // ── Trip active — update bus position ───────────────────────────────
        final newBusLatLng = LatLng(trip.currentLat, trip.currentLng);

        // Check for signal loss: if lastUpdated is >30s old
        final secsSinceUpdate =
            DateTime.now().difference(trip.lastUpdated).inSeconds;
        final signalLost = secsSinceUpdate > 30;

        // Compute bearing from previous to current position
        double newBearing = _busBearing;
        if (_prevBusLatLng != null) {
          final d = DistanceUtils.haversine(
            _prevBusLatLng!.latitude, _prevBusLatLng!.longitude,
            newBusLatLng.latitude,    newBusLatLng.longitude,
          );
          if (d > 3) {
            newBearing = DistanceUtils.bearing(
              _prevBusLatLng!.latitude, _prevBusLatLng!.longitude,
              newBusLatLng.latitude,    newBusLatLng.longitude,
            );
          }
        }

        setState(() {
          _prevBusLatLng = _busLatLng;
          _busLatLng     = newBusLatLng;
          _busBearing    = newBearing;
          _busSpeedKmh   = trip.currentSpeed;
          _tripActive    = true;
          _signalLost    = signalLost;
        });

        _refreshArrowIcon(newBearing);

        // Camera follows bus
        _mapController?.animateCamera(CameraUpdate.newLatLng(newBusLatLng));

        // Voice announcements triggered by BUS location
        if (_directionResolved) {
          _checkStopAnnouncements(trip.currentLat, trip.currentLng);
          _updateEta(trip.currentLat, trip.currentLng, trip.currentSpeed);
        }
      });
    });
  }

  Future<void> _refreshArrowIcon(double bearing) async {
    final icon = await buildNavigationArrow(
      bearingDegrees: bearing,
      arrowColor: Colors.blue.shade700,
    );
    if (mounted) setState(() => _arrowIcon = icon);
  }

  // ── Direction + destination resolution ───────────────────────────────────

  /// Called exactly once when the first Firestore emission arrives.
  void _resolveDirection(RouteModel route) {
    final fq = widget.from.trim().toLowerCase();
    final tq = widget.to.trim().toLowerCase();

    // ── Step 1: determine journey direction ──────────────────────────────
    bool tokenMatch(String query, String target) {
      if (query.isEmpty) return false;
      final tokens = query.split(RegExp(r'\s+'));
      return tokens.every((t) => target.toLowerCase().contains(t));
    }

    final forwardScore =
        (tokenMatch(fq, route.fromPlace) ? 1 : 0) +
        (tokenMatch(tq, route.toPlace)   ? 1 : 0);
    final reverseScore =
        (tokenMatch(fq, route.toPlace)   ? 1 : 0) +
        (tokenMatch(tq, route.fromPlace) ? 1 : 0);

    final bool isReturn = reverseScore > forwardScore;

    // ── Step 2: build ordered stop list ──────────────────────────────────
    final sorted = List<StopModel>.from(route.stops)
      ..sort((a, b) => a.order.compareTo(b.order));
    final ordered = isReturn ? sorted.reversed.toList() : sorted;

    // ── Step 3: resolve ORIGIN coords ────────────────────────────────────
    final double oLat  = isReturn ? route.toLat   : route.fromLat;
    final double oLng  = isReturn ? route.toLng   : route.fromLng;
    final String oName = isReturn ? route.toPlace : route.fromPlace;

    // ── Step 4: resolve DESTINATION coords ───────────────────────────────
    double dLat;
    double dLng;
    String dName;
      final terminalDestLat  = isReturn ? route.fromLat   : route.toLat;
      final terminalDestLng  = isReturn ? route.fromLng   : route.toLng;
      final terminalDestName = isReturn ? route.fromPlace : route.toPlace;

      final toMatchesTerminal = tokenMatch(tq, terminalDestName);

      if (toMatchesTerminal || tq.isEmpty) {
        dLat  = terminalDestLat;
        dLng  = terminalDestLng;
        dName = terminalDestName;
      } else {
        double? matchLat;
        double? matchLng;
        String? matchName;

        final tqTokens = tq.split(RegExp(r'\s+'));
        for (var i = 0; i < ordered.length; i++) {
          final nameLower = ordered[i].name.trim().toLowerCase();
          if (tqTokens.every((t) => nameLower.contains(t))) {
            matchLat  = ordered[i].lat;
            matchLng  = ordered[i].lng;
            matchName = ordered[i].name;
            break;
          }
        }

        if (matchLat != null) {
          dLat  = matchLat;
          dLng  = matchLng!;
          dName = matchName!;
        } else {
          dLat  = terminalDestLat;
          dLng  = terminalDestLng;
          dName = terminalDestName;
        }
      }

      // ── Step 5: commit to state ───────────────────────────────────────────
      setState(() {
        _orderedStops       = ordered;
        _originLat          = oLat;
        _originLng          = oLng;
        _originName         = oName;
        _destLat            = dLat;
        _destLng            = dLng;
        _destName           = dName;
        _announcedArrival.clear();
        _announcedNext.clear();
        _announcedProximity.clear();
        _announced500m = false;
        _destinationReached = false;
      });
  }

  // ── ETA calculation ──────────────────────────────────────────────────────

  void _updateEta(double busLat, double busLng, double speedKmh) {
    if (_destLat == 0 && _destLng == 0) return;
    if (_orderedStops.isEmpty) return;

    // Use bus speed if available, otherwise default 30 km/h
    final effectiveSpeed = speedKmh > 1 ? speedKmh : 30.0;

    // Calculate distance from bus to destination through remaining stops
    double totalDistanceMetres = 0;

    // Find the closest upcoming stop to the bus
    int busStopIdx = 0;
    double minDist = double.infinity;
    for (var i = 0; i < _orderedStops.length; i++) {
      final d = DistanceUtils.haversine(
        busLat, busLng, _orderedStops[i].lat, _orderedStops[i].lng,
      );
      if (d < minDist) {
        minDist = d;
        busStopIdx = i;
      }
    }

    // Distance from bus to nearest stop
    totalDistanceMetres += minDist;

    // Check if destination is a terminal or matches a stop
    int destStopIdx = -1;
    for (var i = busStopIdx; i < _orderedStops.length; i++) {
      if (_isPassengerDestination(_orderedStops[i].lat, _orderedStops[i].lng)) {
        destStopIdx = i;
        break;
      }
    }

    if (destStopIdx >= 0 && destStopIdx >= busStopIdx) {
      // Sum distances through intermediate stops
      for (var i = busStopIdx; i < destStopIdx; i++) {
        totalDistanceMetres += DistanceUtils.haversine(
          _orderedStops[i].lat, _orderedStops[i].lng,
          _orderedStops[i + 1].lat, _orderedStops[i + 1].lng,
        );
      }
    } else {
      // Destination is a terminal or past all stops — direct distance to dest
      // Sum through remaining stops then to terminal
      for (var i = busStopIdx; i < _orderedStops.length - 1; i++) {
        totalDistanceMetres += DistanceUtils.haversine(
          _orderedStops[i].lat, _orderedStops[i].lng,
          _orderedStops[i + 1].lat, _orderedStops[i + 1].lng,
        );
      }
      // Add distance from last stop to destination terminal
      if (_orderedStops.isNotEmpty) {
        totalDistanceMetres += DistanceUtils.haversine(
          _orderedStops.last.lat, _orderedStops.last.lng,
          _destLat, _destLng,
        );
      }
    }

    // Convert to minutes
    final distKm = totalDistanceMetres / 1000;
    final etaMinutes = (distKm / effectiveSpeed) * 60;

    setState(() {
      if (_destinationReached) {
        _etaText = 'Bus has arrived at your stop!';
      } else if (etaMinutes < 1) {
        _etaText = 'Bus is arriving now!';
      } else {
        _etaText = 'Bus reaches the stop in ~${etaMinutes.round()} min';
      }
    });
  }

  // ── Voice announcements ───────────────────────────────────────────────────
  //
  // Triggered by CONDUCTOR's GPS coordinates (bus location from Firebase).
  // Speech is queued via TtsService so messages never cut each other off.

  /// Tracks destination proximity alerts already spoken (keys: 'dest_2', 'dest_1').
  final Set<String> _announcedProximity = {};

  /// Whether the 500-metre GPS proximity alert has fired (once per trip).
  bool _announced500m = false;

  void _checkStopAnnouncements(double busLat, double busLng) {
    if (_destinationReached) return;

    // ── 500-metre destination proximity alert (GPS-based, fires ONCE) ────
    if (!_announced500m && _destLat != 0 && _destLng != 0) {
      final distToDest = DistanceUtils.haversine(
        busLat, busLng, _destLat, _destLng,
      );
      if (distToDest <= 500) {
        _announced500m = true;
        _speak('Your destination is reaching, please get ready.');
        _snack('Destination approaching — get ready!',
            color: Colors.deepPurple.shade600);
      }
    }

    // ── A. Intermediate stop announcements ───────────────────────────────
    for (var i = 0; i < _orderedStops.length; i++) {
      final stop = _orderedStops[i];

      final dist = DistanceUtils.haversine(
        busLat, busLng, stop.lat, stop.lng,
      );

      if (dist > AppConstants.stopAnnouncementMetres) continue;
      if (_announcedArrival.contains(stop.order)) continue;

      _announcedArrival.add(stop.order);

      final isThisDestination = _isPassengerDestination(stop.lat, stop.lng);

      if (isThisDestination) {
        _destinationReached = true;
        _speak('You have reached your destination, ${stop.name}.');
        _snack('You have reached your destination: ${stop.name}',
            color: Colors.green.shade700);
        return;
      }

      // Speak current stop name fully — queued, will not be interrupted.
      _speak('This stop is ${stop.name}.');
      _snack('This stop: ${stop.name}');

      // Queue the next-stop announcement — TTS queue ensures it plays
      // only after the current stop announcement finishes completely.
      if (i + 1 < _orderedStops.length &&
          !_announcedNext.contains(stop.order)) {
        _announcedNext.add(stop.order);
        final next = _orderedStops[i + 1];
        final isNextDestination =
            _isPassengerDestination(next.lat, next.lng);

        if (isNextDestination) {
          _speak('Next stop is your destination, ${next.name}. '
              'Please get ready.');
          _snack(
              'Next stop is your destination: ${next.name}. Get ready!',
              color: Colors.orange.shade700);
        } else {
          _speak('Next stop is ${next.name}.');
          _snack('Next stop: ${next.name}');
        }
      } else if (i + 1 >= _orderedStops.length &&
          !_announcedNext.contains(stop.order) &&
          _destLat != 0 && _destLng != 0) {
        // This is the LAST intermediate stop — destination is the terminal.
        _announcedNext.add(stop.order);
        _speak('Next stop is your destination, $_destName.');
        _snack('Next stop is your destination: $_destName',
            color: Colors.orange.shade700);
      }

      // ── Destination proximity alerts ─────────────────────────────────
      // Check if destination is 2 stops or 1 stop ahead from this stop.
      // IMPORTANT: only announce destination as "next stop" when there
      // are ZERO intermediate stops remaining between conductor and
      // destination. This prevents premature destination announcements.
      _checkDestinationProximity(i);

      break; // one stop per update
    }

    // ── B. Terminal destination arrival check ────────────────────────────
    if (_destinationReached) return;
    if (_destLat == 0 && _destLng == 0) return;

    final termDist = DistanceUtils.haversine(
      busLat, busLng, _destLat, _destLng,
    );
    if (termDist <= AppConstants.stopAnnouncementMetres) {
      _destinationReached = true;
      _speak('You have reached your destination, $_destName.');
      _snack('You have reached your destination: $_destName',
          color: Colors.green.shade700);
    }
  }

  /// Check if the passenger's destination is 1 or 2 stops ahead from the
  /// current stop at index [currentIdx] and announce accordingly.
  ///
  /// "stops away" means the number of REMAINING intermediate stops between
  /// the conductor and the destination — NOT counting the destination itself.
  /// The destination is only announced as "next stop" when there are ZERO
  /// intermediate stops remaining (i.e., the conductor has passed every stop
  /// before the destination).
  void _checkDestinationProximity(int currentIdx) {
    if (_destinationReached) return;

    // Find the destination stop index in _orderedStops.
    int destIdx = -1;
    for (var j = currentIdx + 1; j < _orderedStops.length; j++) {
      if (_isPassengerDestination(_orderedStops[j].lat, _orderedStops[j].lng)) {
        destIdx = j;
        break;
      }
    }

    // Also check if destination is the terminal (not an intermediate stop).
    final bool destIsTerminal = destIdx < 0 &&
        _destLat != 0 && _destLng != 0;

    if (destIdx >= 0) {
      // Number of intermediate stops between current and destination.
      final intermediateStops = destIdx - currentIdx - 1;

      if (intermediateStops == 1 && !_announcedProximity.contains('dest_2')) {
        // There is exactly 1 intermediate stop between us and destination,
        // meaning destination is effectively "2 stops ahead".
        _announcedProximity.add('dest_2');
        final destStopName = _orderedStops[destIdx].name;
        _speak('Your destination $destStopName is approaching, '
            'two stops ahead.');
        _snack('$destStopName is 2 stops away',
            color: Colors.blue.shade700);
      }
      // NOTE: "dest_1" (next stop is destination) is already handled in
      // the main loop above via isNextDestination — we do NOT duplicate it
      // here to avoid the premature announcement bug.
    } else if (destIsTerminal) {
      // Destination is the route terminal — count remaining intermediate
      // stops between current position and the end of the stop list.
      // The terminal itself is AFTER the last stop, so all stops in the
      // list are intermediate.
      final remainingStops = _orderedStops.length - 1 - currentIdx;

      if (remainingStops == 2 && !_announcedProximity.contains('dest_2')) {
        _announcedProximity.add('dest_2');
        _speak('Your destination $_destName is approaching, '
            'two stops ahead.');
        _snack('$_destName is 2 stops away',
            color: Colors.blue.shade700);
      }
      // NOTE: "dest_1" for terminal is handled by the isNextDestination
      // check in the main loop — it fires only when the conductor physically
      // reaches the LAST intermediate stop, ensuring the destination is
      // announced as "next stop" only when zero intermediate stops remain.
    }
  }

  bool _isPassengerDestination(double lat, double lng) {
    if (_destLat == 0 && _destLng == 0) return false;
    return DistanceUtils.haversine(lat, lng, _destLat, _destLng) <= 50;
  }

  void _speak(String text) => ref.read(ttsServiceProvider).speak(text);

  void _snack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color ?? AppTheme.primaryColor,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final routeAsync = ref.watch(routeStreamProvider(widget.routeId));

    return Scaffold(
      body: Column(
        children: [
          // ── Gradient App Bar ──────────────────────────────────
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: AppTheme.primaryGradient,
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 16, 14),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.from.isNotEmpty && widget.to.isNotEmpty
                            ? '${widget.from} → ${widget.to}'
                            : 'Track Bus',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: routeAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(
                  color: AppTheme.primaryColor, strokeWidth: 3),
              ),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (route) {
                if (route == null) {
                  return const Center(child: Text('Route not found.'));
                }
                return _buildTrackingView(route);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackingView(RouteModel route) {
    // ── Effective values ───────────────────────────────────────────────────
    final double originLat  = _directionResolved ? _originLat  : route.fromLat;
    final double originLng  = _directionResolved ? _originLng  : route.fromLng;
    final String originName = _directionResolved ? _originName : route.fromPlace;
    final double destLat    = _directionResolved ? _destLat    : route.toLat;
    final double destLng    = _directionResolved ? _destLng    : route.toLng;
    final String destName   = _directionResolved ? _destName   : route.toPlace;

    final displayStops = _directionResolved && _orderedStops.isNotEmpty
        ? _orderedStops
        : (List<StopModel>.from(route.stops)
          ..sort((a, b) => a.order.compareTo(b.order)));

    final rawPoints = PolylinePoints()
        .decodePolyline(route.routePolyline)
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();

    // ── Marker set ─────────────────────────────────────────────────────────
    final markers = <Marker>{
      // ── Green: passenger-selected origin ─────────────────────────────────
      Marker(
        markerId: const MarkerId('origin'),
        position: LatLng(originLat, originLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: 'From', snippet: originName),
        zIndexInt: 3,
      ),

      // ── Red: passenger-selected destination ──────────────────────────────
      Marker(
        markerId: const MarkerId('destination'),
        position: LatLng(destLat, destLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: 'Your destination', snippet: destName),
        zIndexInt: 3,
      ),

      // ── Blue arrow: BUS live location (from conductor Firebase) ──────────
      if (_busLatLng != null && _tripActive)
        Marker(
          markerId: const MarkerId('bus'),
          position: _busLatLng!,
          icon: _arrowIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          flat: true,
          anchor: const Offset(0.5, 0.5),
          infoWindow: const InfoWindow(title: 'Bus'),
          zIndexInt: 4,
        ),

      // ── Orange: intermediate stops ──────────────────────────────────────
      ...displayStops.map((s) {
        final isPassed = _announcedArrival.contains(s.order);
        return Marker(
          markerId: MarkerId('stop_${s.order}'),
          position: LatLng(s.lat, s.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isPassed
                ? BitmapDescriptor.hueViolet
                : BitmapDescriptor.hueOrange,
          ),
          infoWindow: InfoWindow(title: s.name, snippet: 'Stop #${s.order}'),
          zIndexInt: 1,
        );
      }),
    };

    final initialTarget = _busLatLng ?? LatLng(originLat, originLng);

    // ── Speed label ────────────────────────────────────────────────────────
    final String speedText;
    if (!_tripActive) {
      speedText = '';
    } else if (_busSpeedKmh < 1) {
      speedText = 'Bus is stopped';
    } else {
      speedText = 'Speed: ${_busSpeedKmh.round()} km/h';
    }

    // ── Status banner text ─────────────────────────────────────────────────
    String? bannerText;
    Color? bannerColor;
    IconData? bannerIcon;
    if (!_tripActive && _activeTripId == null) {
      bannerText  = 'Bus not started yet';
      bannerColor = Colors.orange.shade100;
      bannerIcon  = Icons.schedule;
    } else if (!_tripActive && _activeTripId != null) {
      bannerText  = 'Trip has ended';
      bannerColor = Colors.grey.shade200;
      bannerIcon  = Icons.check_circle_outline;
    } else if (_signalLost) {
      bannerText  = 'Signal lost — showing last known position';
      bannerColor = Colors.red.shade50;
      bannerIcon  = Icons.signal_wifi_off;
    }

    return Column(
      children: [
        // ── Direction strip ──────────────────────────────────────────────
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.06),
            border: Border(bottom: BorderSide(color: AppTheme.border.withValues(alpha: 0.5))),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.route_rounded, size: 14, color: AppTheme.primaryColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${widget.from} → ${widget.to}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        // ── Status banner ────────────────────────────────────────────────
        if (bannerText != null)
          Container(
            width: double.infinity,
            color: bannerColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(bannerIcon, size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 8),
                Text(
                  bannerText,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),

        // ── ETA + Speed info strip ───────────────────────────────────────
        if (_tripActive && (_etaText.isNotEmpty || speedText.isNotEmpty))
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primaryColor.withValues(alpha: 0.08), AppTheme.primaryLight.withValues(alpha: 0.04)],
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                if (_etaText.isNotEmpty) ...[
                  Icon(Icons.access_time_rounded, size: 15, color: AppTheme.primaryColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _etaText,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryDark,
                      ),
                    ),
                  ),
                ],
                if (speedText.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.speed_rounded, size: 15, color: AppTheme.primaryColor),
                  const SizedBox(width: 4),
                  Text(
                    speedText,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ],
              ],
            ),
          ),

        // ── Map ──────────────────────────────────────────────────────────
        Expanded(
          flex: 3,
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: initialTarget,
              zoom: 14,
            ),
            polylines: {
              if (rawPoints.isNotEmpty)
                Polyline(
                  polylineId: const PolylineId('route'),
                  points: rawPoints,
                  color: AppTheme.primaryColor,
                  width: 5,
                ),
            },
            markers: markers,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (c) => _mapController = c,
          ),
        ),

        // ── Stop list ────────────────────────────────────────────────────
        Expanded(
          flex: 2,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, -4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Drag handle ───────────────────────────────
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        ),
                        child: const Icon(Icons.directions_bus_rounded,
                            color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${route.busType} • ${route.busNumber}',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            if (route.shift.isNotEmpty)
                              Text(
                                '${route.shift} shift',
                                style: GoogleFonts.inter(
                                    fontSize: 12, color: AppTheme.textMuted),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                        ),
                        child: Text(
                          '${displayStops.length} stops',
                          style: GoogleFonts.inter(
                              fontSize: 12, fontWeight: FontWeight.w500,
                              color: AppTheme.primaryColor),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 8),
                Expanded(
                  child: displayStops.isEmpty
                      ? Center(
                          child: Text(
                            'No stops on this route.',
                            style: GoogleFonts.inter(color: AppTheme.textMuted),
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: displayStops.length,
                          itemBuilder: (context, i) {
                            final stop = displayStops[i];
                            final isPassed =
                                _announcedArrival.contains(stop.order);

                            final isDest = _directionResolved &&
                                _isPassengerDestination(stop.lat, stop.lng);

                            final StopState state;
                            if (isDest && _destinationReached) {
                              state = StopState.passed;
                            } else if (isPassed) {
                              state = StopState.passed;
                            } else {
                              final firstUnpassed = displayStops.firstWhere(
                                (s) => !_announcedArrival.contains(s.order),
                                orElse: () => displayStops.last,
                              );
                              state = stop.order == firstUnpassed.order
                                  ? StopState.upcoming
                                  : StopState.future;
                            }

                            return StopListTile(
                              stop: stop,
                              state: state,
                              onTap: isDest
                                  ? () {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                        content: Text(
                                            'Your destination: ${stop.name}'),
                                      ));
                                    }
                                  : null,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
