import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ksrtc_smarttrack/core/constants/app_constants.dart';
import 'package:ksrtc_smarttrack/core/services/direction_engine.dart';
import 'package:ksrtc_smarttrack/core/services/location_service.dart';
import 'package:ksrtc_smarttrack/core/theme/app_theme.dart';
import 'package:ksrtc_smarttrack/core/utils/distance_utils.dart';
import 'package:ksrtc_smarttrack/data/models/bus_model.dart';
import 'package:ksrtc_smarttrack/data/models/route_model.dart';
import 'package:ksrtc_smarttrack/data/models/stop_model.dart';
import 'package:ksrtc_smarttrack/data/models/trip_model.dart';
import 'package:ksrtc_smarttrack/presentation/conductor/conductor_home_screen.dart';
import 'package:ksrtc_smarttrack/providers/location_provider.dart';
import 'package:ksrtc_smarttrack/providers/trip_provider.dart';

/// Live tracking screen with stop-marking abilities.
///
/// This is used when the conductor goes through the "Setup Route & Stops" flow.
/// It allows marking new stops and deleting existing ones.
class LiveTrackingScreen extends ConsumerStatefulWidget {
  final String tripId;
  final String routeId;
  final BusModel bus;

  const LiveTrackingScreen({
    super.key,
    required this.tripId,
    required this.routeId,
    required this.bus,
  });

  @override
  ConsumerState<LiveTrackingScreen> createState() =>
      _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends ConsumerState<LiveTrackingScreen> {
  GoogleMapController? _mapController;
  LatLng? _currentLatLng;
  int _stopCounter = 0;

  /// Direction engine — auto-detects forward / return_ from GPS.
  final DirectionEngine _dirEngine = DirectionEngine();
  BusDirection _lastPushedDirection = BusDirection.unknown;

  /// Stop orders already pushed to Firebase as "passed" — avoids duplicate writes.
  final Set<int> _localPassedStops = {};

  late final LocationService _locationService;

  @override
  void initState() {
    super.initState();
    _locationService = ref.read(locationServiceProvider);
    _initStopCounter();
    _startLocationUpdates();
  }

  /// Initialize stop counter from existing stops so new stops get the correct
  /// order number (not starting from 0 every time).
  void _initStopCounter() {
    final tripAsync = ref.read(tripStreamProvider(widget.tripId));
    tripAsync.whenData((trip) {
      if (trip.stops.isNotEmpty) {
        final maxOrder = trip.stops
            .map((s) => s.order)
            .reduce((a, b) => a > b ? a : b);
        _stopCounter = maxOrder;
      }
    });

    // Also try loading from the route doc (in case trip was just created with
    // an empty stops list but the route has saved stops).
    ref
        .read(tripRepositoryProvider)
        .getRouteByBusId(widget.bus.busId)
        .then((route) {
      if (route != null && route.stops.isNotEmpty && mounted) {
        final maxOrder = route.stops
            .map((s) => s.order)
            .reduce((a, b) => a > b ? a : b);
        if (maxOrder > _stopCounter) {
          _stopCounter = maxOrder;
        }
      }
    });
  }

  void _startLocationUpdates() {
    final tripRepo = ref.read(tripRepositoryProvider);

    _locationService.startTracking(
      onUpdate: (Position pos) {
        setState(() => _currentLatLng = LatLng(pos.latitude, pos.longitude));

        // Push GPS to Firestore.
        tripRepo.updateLiveLocation(
          tripId: widget.tripId,
          lat: pos.latitude,
          lng: pos.longitude,
          speed: pos.speed * 3.6, // m/s → km/h
        );

        // Keep camera centred on the bus.
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
        );

        // ── Auto-detect direction ─────────────────────────────────────────
        _updateDirection(pos, tripRepo);

        // Detect when bus passes a stop and write to Firebase.
        _checkPassedStops(pos, tripRepo);
      },
    );
  }

  /// Check if the conductor is within proximity of any stop and mark it as
  /// passed in Firebase so passengers joining mid-trip see correct status.
  void _checkPassedStops(Position pos, dynamic tripRepo) {
    final tripAsync = ref.read(tripStreamProvider(widget.tripId));
    tripAsync.whenData((trip) {
      for (final stop in trip.stops) {
        if (_localPassedStops.contains(stop.order)) continue;

        final dist = DistanceUtils.haversine(
          pos.latitude,
          pos.longitude,
          stop.lat,
          stop.lng,
        );

        if (dist <= AppConstants.stopAnnouncementMetres) {
          _localPassedStops.add(stop.order);
          tripRepo.markStopPassed(
            tripId: widget.tripId,
            stopOrder: stop.order,
          );
          debugPrint(
              '[PassedStop] Marked stop #${stop.order} (${stop.name}) as passed');
        }
      }
    });
  }

  /// Reads the latest stop list from the trip stream, runs the direction engine,
  /// and pushes any change to Firestore (only when it changes — avoids spam).
  void _updateDirection(Position pos, dynamic tripRepo) {
    final tripAsync = ref.read(tripStreamProvider(widget.tripId));
    tripAsync.whenData((trip) {
      if (trip.stops.length < 2) return; // need at least 2 stops to detect

      final newDir = _dirEngine.detect(
        stops: trip.stops,
        lat: pos.latitude,
        lng: pos.longitude,
      );

      if (newDir != _lastPushedDirection) {
        _lastPushedDirection = newDir;
        tripRepo.updateDirection(
          tripId: widget.tripId,
          routeId: widget.routeId,
          direction: newDir,
        );
        debugPrint('[Direction] Auto-detected: $newDir');
      }
    });
  }

  Future<void> _markStop() async {
    if (_currentLatLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waiting for GPS fix…')),
      );
      return;
    }

    _stopCounter++;

    String stopName = 'Stop $_stopCounter';
    try {
      final placemarks = await geocoding.placemarkFromCoordinates(
        _currentLatLng!.latitude,
        _currentLatLng!.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;

        // Build a name from geocoding parts, but EXCLUDE the route's
        // source/destination place names so a stop near the endpoint
        // does not get named after it.
        final routeEndpoints = {
          widget.bus.fromPlace.trim().toLowerCase(),
          widget.bus.toPlace.trim().toLowerCase(),
        };

        // Prefer street/POI name + subLocality over locality (city name).
        // p.locality often returns the broad city/town name which matches
        // the route destination — causing Bug #1.
        final candidates = <String>[
          if (p.name != null && p.name!.isNotEmpty) p.name!,
          if (p.subLocality != null && p.subLocality!.isNotEmpty)
            p.subLocality!,
          if (p.thoroughfare != null && p.thoroughfare!.isNotEmpty)
            p.thoroughfare!,
        ];

        // Filter out any part that matches a route endpoint name.
        final filtered = candidates
            .where(
                (c) => !routeEndpoints.contains(c.trim().toLowerCase()))
            .toList();

        if (filtered.isNotEmpty) {
          stopName = filtered.join(', ');
        } else if (candidates.isNotEmpty) {
          // All candidates matched endpoints — use locality as last resort
          // but prefix with "Stop" to make it distinguishable.
          stopName = 'Stop $_stopCounter';
        }

        if (stopName.isEmpty) stopName = 'Stop $_stopCounter';
      }
    } catch (_) {
      // Use fallback name.
    }

    final stop = StopModel(
      name: stopName,
      lat: _currentLatLng!.latitude,
      lng: _currentLatLng!.longitude,
      order: _stopCounter,
      timestamp: DateTime.now(),
    );

    try {
      await ref.read(tripRepositoryProvider).addStop(
            tripId: widget.tripId,
            routeId: widget.routeId,
            stop: stop,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Marked: $stopName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to mark stop: $e')),
        );
      }
    }
  }

  /// Delete a stop after confirmation.
  Future<void> _deleteStop(StopModel stop) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Stop?'),
        content: Text('Remove "${stop.name}" from the route?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(tripRepositoryProvider).removeStop(
            tripId: widget.tripId,
            routeId: widget.routeId,
            stop: stop,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted: ${stop.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete stop: $e')),
        );
      }
    }
  }

  Future<void> _endTrip() async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Trip?'),
        content: const Text(
            'This will stop tracking and save the route permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End Trip'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      _locationService.stopTracking();
      final tripRepo = ref.read(tripRepositoryProvider);

      // End the trip doc and clear activeTripId on the route.
      await tripRepo.endTrip(widget.tripId, routeId: widget.routeId);

      messenger.showSnackBar(
        const SnackBar(
            content: Text('Trip ended. Route saved successfully.')),
      );

      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ConductorHomeScreen()),
        (route) => false,
      );
    } catch (e) {
      debugPrint('[EndTrip] Error: $e');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Error ending trip: $e')),
      );
    }
  }

  @override
  void dispose() {
    _locationService.stopTracking();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tripAsync = ref.watch(tripStreamProvider(widget.tripId));

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Setup Stops',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: tripAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
              color: AppTheme.primaryColor, strokeWidth: 3),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (trip) => _buildBody(trip),
      ),
    );
  }

  Widget _buildBody(TripModel trip) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final routePoints = PolylinePoints()
        .decodePolyline(trip.routePolyline)
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();

    final polylines = <Polyline>{
      Polyline(
        polylineId: const PolylineId('route'),
        points: routePoints,
        color: AppTheme.primaryColor,
        width: 5,
      ),
    };

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('from'),
        position: LatLng(trip.fromLat, trip.fromLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: 'Start', snippet: trip.fromPlace),
      ),
      Marker(
        markerId: const MarkerId('to'),
        position: LatLng(trip.toLat, trip.toLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: 'End', snippet: trip.toPlace),
      ),
      if (_currentLatLng != null)
        Marker(
          markerId: const MarkerId('bus'),
          position: _currentLatLng!,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Bus'),
        ),
      ...trip.stops.map(
        (s) => Marker(
          markerId: MarkerId('stop_${s.order}'),
          position: LatLng(s.lat, s.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(title: s.name, snippet: 'Stop #${s.order}'),
        ),
      ),
    };

    // Direction badge label
    final dirLabel = switch (trip.direction) {
      BusDirection.forward => '${trip.fromPlace} → ${trip.toPlace}',
      BusDirection.return_ => '${trip.toPlace} → ${trip.fromPlace}',
      BusDirection.unknown => 'Detecting direction…',
    };

    final isUnknown = trip.direction == BusDirection.unknown;

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target:
                _currentLatLng ?? LatLng(trip.currentLat, trip.currentLng),
            zoom: 15,
          ),
          polylines: polylines,
          markers: markers,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          onMapCreated: (c) => _mapController = c,
        ),

        // ── Glassmorphic Direction badge ─────────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 56,
          left: 14,
          right: 14,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isUnknown
                      ? Colors.amber.shade100.withValues(alpha: 0.85)
                      : AppTheme.primaryDark.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  border: Border.all(
                    color: isUnknown
                        ? Colors.amber.shade300.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isUnknown
                            ? Colors.amber.shade300.withValues(alpha: 0.4)
                            : Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        trip.direction == BusDirection.return_
                            ? Icons.arrow_back_rounded
                            : Icons.arrow_forward_rounded,
                        size: 14,
                        color:
                            isUnknown ? Colors.amber.shade800 : Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        dirLabel,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isUnknown
                              ? Colors.amber.shade900
                              : Colors.white,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Glassmorphic Bottom controls ─────────────────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding:
                    EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomPad),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.88),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24)),
                  border: Border(
                    top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.6),
                        width: 1),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle bar
                    Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.textMuted.withValues(alpha: 0.3),
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusFull),
                      ),
                    ),
                    Text(
                      '${trip.busType} • ${trip.busNumber}',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Stops marked: ${trip.stops.length}',
                      style: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    // ── Refined mini stop list ────────────────────────────
                    if (trip.stops.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 130),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: trip.stops.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: AppTheme.divider,
                            indent: 40,
                          ),
                          itemBuilder: (ctx, i) {
                            final s = trip.stops[i];
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  gradient: AppTheme.accentGradient,
                                  borderRadius: BorderRadius.circular(
                                      AppTheme.radiusSm),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${s.order}',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              title: Text(s.name,
                                  style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: AppTheme.textPrimary)),
                              trailing: IconButton(
                                icon: Icon(Icons.delete_outline,
                                    size: 18,
                                    color: AppTheme.errorColor
                                        .withValues(alpha: 0.7)),
                                onPressed: () => _deleteStop(s),
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),
                    Row(
                      children: [
                        // Mark Stop button — outlined with gradient-style
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _markStop,
                            icon:
                                const Icon(Icons.add_location_alt_rounded),
                            label: Text('Mark Stop',
                                style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w600)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primaryColor,
                              side: const BorderSide(
                                  color: AppTheme.primaryColor, width: 1.5),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Gradient End Trip button
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFEF4444),
                                  Color(0xFFDC2626)
                                ],
                              ),
                              borderRadius: BorderRadius.circular(
                                  AppTheme.radiusLg),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.errorColor
                                      .withValues(alpha: 0.25),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              onPressed: _endTrip,
                              icon: const Icon(
                                  Icons.stop_circle_rounded),
                              label: Text('End Trip',
                                  style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.w600)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
