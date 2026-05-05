import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ksrtc_smarttrack/core/theme/app_theme.dart';
import 'package:ksrtc_smarttrack/data/models/bus_model.dart';
import 'package:ksrtc_smarttrack/data/models/stop_model.dart';
import 'package:ksrtc_smarttrack/data/models/trip_model.dart';
import 'package:ksrtc_smarttrack/presentation/conductor/live_tracking_screen.dart';
import 'package:ksrtc_smarttrack/presentation/widgets/map_widget.dart';
import 'package:ksrtc_smarttrack/providers/trip_provider.dart';

class RoutePreviewScreen extends ConsumerStatefulWidget {
  final TripModel trip;

  /// The bus that owns this trip.  Used for upsert-route logic.
  final BusModel bus;

  const RoutePreviewScreen({
    super.key,
    required this.trip,
    required this.bus,
  });

  @override
  ConsumerState<RoutePreviewScreen> createState() =>
      _RoutePreviewScreenState();
}

class _RoutePreviewScreenState extends ConsumerState<RoutePreviewScreen> {
  GoogleMapController? _mapController;
  bool _loading = false;

  /// Previously saved stops loaded from the existing route document.
  List<StopModel> _existingStops = [];
  bool _loadedExistingStops = false;

  @override
  void initState() {
    super.initState();
    _loadExistingStops();
  }

  /// Load any previously saved stops from the route doc so they show up on the
  /// preview map and are NOT lost when the conductor starts a new trip.
  Future<void> _loadExistingStops() async {
    try {
      final route = await ref
          .read(tripRepositoryProvider)
          .getRouteByBusId(widget.bus.busId);
      if (route != null && route.stops.isNotEmpty && mounted) {
        setState(() {
          _existingStops = route.stops;
          _loadedExistingStops = true;
        });
      } else if (mounted) {
        setState(() => _loadedExistingStops = true);
      }
    } catch (_) {
      if (mounted) setState(() => _loadedExistingStops = true);
    }
  }

  List<LatLng> get _routePoints {
    return PolylinePoints()
        .decodePolyline(widget.trip.routePolyline)
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();
  }

  Set<Polyline> get _polylines {
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: _routePoints,
        color: AppTheme.primaryColor,
        width: 5,
      ),
    };
  }

  Set<Marker> get _markers {
    return {
      Marker(
        markerId: const MarkerId('from'),
        position: LatLng(widget.trip.fromLat, widget.trip.fromLng),
        infoWindow:
            InfoWindow(title: 'From', snippet: widget.trip.fromPlace),
        icon:
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      Marker(
        markerId: const MarkerId('to'),
        position: LatLng(widget.trip.toLat, widget.trip.toLng),
        infoWindow:
            InfoWindow(title: 'To', snippet: widget.trip.toPlace),
        icon:
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
      // Show existing saved stops as orange markers.
      ..._existingStops.map(
        (s) => Marker(
          markerId: MarkerId('saved_stop_${s.order}'),
          position: LatLng(s.lat, s.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(title: s.name, snippet: 'Stop #${s.order}'),
        ),
      ),
    };
  }

  void _fitBounds() {
    if (_mapController == null || _routePoints.isEmpty) return;
    final bounds = _boundsFromLatLngList(_routePoints);
    _mapController!
        .animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
  }

  LatLngBounds _boundsFromLatLngList(List<LatLng> points) {
    double south = points.first.latitude;
    double north = points.first.latitude;
    double west = points.first.longitude;
    double east = points.first.longitude;
    for (final p in points) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
  }

  Future<void> _startTracking() async {
    setState(() => _loading = true);
    try {
      final tripRepo = ref.read(tripRepositoryProvider);

      // 1. Persist the trip document → get its ID.
      final tripId = await tripRepo.createTrip(widget.trip);

      // 2. Upsert the single permanent route document for this bus.
      //    This links activeTripId so passengers can find the live bus.
      //    Existing stops are PRESERVED — not overwritten.
      final routeId = await tripRepo.upsertRoute(
        bus: widget.bus,
        trip: widget.trip,
        tripId: tripId,
      );

      // 3. Stamp the routeId back into the trip document.
      await tripRepo.updateTripRouteId(tripId: tripId, routeId: routeId);

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LiveTrackingScreen(
            tripId: tripId,
            routeId: routeId,
            bus: widget.bus,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start trip: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Route Preview',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          MapWidget(
            initialTarget:
                LatLng(widget.trip.fromLat, widget.trip.fromLng),
            initialZoom: 10,
            polylines: _polylines,
            markers: _markers,
            onMapCreated: (controller) {
              _mapController = controller;
              Future.delayed(
                const Duration(milliseconds: 400),
                _fitBounds,
              );
            },
          ),

          // ── Glassmorphic bottom sheet ────────────────────────────────
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
                  padding: EdgeInsets.fromLTRB(
                      20, 18, 20, 16 + bottomPad),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Handle bar
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color:
                                AppTheme.textMuted.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(
                                AppTheme.radiusFull),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: AppTheme.primaryGradient,
                              borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMd),
                            ),
                            child: const Icon(
                                Icons.directions_bus_rounded,
                                color: Colors.white,
                                size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${widget.trip.busType} • ${widget.trip.busNumber}',
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${widget.trip.fromPlace} → ${widget.trip.toPlace}',
                                  style: GoogleFonts.inter(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Stop status pill
                      if (_existingStops.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(
                                AppTheme.radiusFull),
                            border: Border.all(
                              color: AppTheme.primaryColor
                                  .withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline,
                                  size: 14,
                                  color: AppTheme.primaryColor),
                              const SizedBox(width: 6),
                              Text(
                                '${_existingStops.length} stop${_existingStops.length == 1 ? '' : 's'} already saved',
                                style: GoogleFonts.inter(
                                  color: AppTheme.primaryDark,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_existingStops.isEmpty && _loadedExistingStops)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(
                                AppTheme.radiusFull),
                            border: Border.all(
                              color: AppTheme.secondaryColor
                                  .withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.info_outline,
                                  size: 14,
                                  color: AppTheme.secondaryColor),
                              const SizedBox(width: 6),
                              Text(
                                'No stops saved yet — mark them after starting',
                                style: GoogleFonts.inter(
                                  color: const Color(0xFF92400E),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 18),

                      // Gradient Start button
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: _loading
                              ? null
                              : AppTheme.primaryGradient,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusLg),
                          boxShadow:
                              _loading ? [] : AppTheme.shadowPrimary,
                        ),
                        child: ElevatedButton.icon(
                          onPressed:
                              _loading ? null : _startTracking,
                          icon: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white),
                                )
                              : const Icon(Icons.play_arrow_rounded),
                          label: Text('Start & Mark Stops',
                              style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
