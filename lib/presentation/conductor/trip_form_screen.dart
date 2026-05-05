import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ksrtc_smarttrack/core/theme/app_theme.dart';
import 'package:ksrtc_smarttrack/data/models/bus_model.dart';
import 'package:ksrtc_smarttrack/data/models/route_model.dart';
import 'package:ksrtc_smarttrack/data/models/trip_model.dart';
import 'package:ksrtc_smarttrack/presentation/conductor/route_preview_screen.dart';
import 'package:ksrtc_smarttrack/presentation/conductor/trip_tracking_screen.dart';
import 'package:ksrtc_smarttrack/providers/auth_provider.dart';
import 'package:ksrtc_smarttrack/providers/trip_provider.dart';

/// Shows a brief route-summary for the selected [bus] and lets the conductor
/// either set up route stops OR start trip tracking.
class TripFormScreen extends ConsumerStatefulWidget {
  final BusModel bus;

  const TripFormScreen({super.key, required this.bus});

  @override
  ConsumerState<TripFormScreen> createState() => _TripFormScreenState();
}

class _TripFormScreenState extends ConsumerState<TripFormScreen> {
  bool _loadingSetup = false;
  bool _loadingTrack = false;
  RouteModel? _existingRoute;
  bool _checkedRoute = false;

  @override
  void initState() {
    super.initState();
    _checkExistingRoute();
  }

  /// Look up whether a permanent route already exists for this bus.
  Future<void> _checkExistingRoute() async {
    final route = await ref
        .read(tripRepositoryProvider)
        .getRouteByBusId(widget.bus.busId);
    if (mounted) {
      setState(() {
        _existingRoute = route;
        _checkedRoute = true;
      });
    }
  }

  // ── Button 1: Setup Route & Mark Stops ─────────────────────────────────

  Future<void> _setupRouteAndStops() async {
    setState(() => _loadingSetup = true);
    try {
      final tripRepo = ref.read(tripRepositoryProvider);
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user == null) throw 'Not authenticated.';

      final polyline = await tripRepo.fetchRoutePolyline(
        originLat: widget.bus.fromLat.toString(),
        originLng: widget.bus.fromLng.toString(),
        destLat: widget.bus.toLat.toString(),
        destLng: widget.bus.toLng.toString(),
      );

      final trip = TripModel(
        tripId: '',
        conductorId: user.uid,
        busId: widget.bus.busId,
        busNumber: widget.bus.busNumber,
        busType: widget.bus.busType,
        shift: widget.bus.shift,
        fromPlace: widget.bus.fromPlace,
        fromLat: widget.bus.fromLat,
        fromLng: widget.bus.fromLng,
        toPlace: widget.bus.toPlace,
        toLat: widget.bus.toLat,
        toLng: widget.bus.toLng,
        routePolyline: polyline,
        status: TripStatus.active,
        currentLat: widget.bus.fromLat,
        currentLng: widget.bus.fromLng,
        lastUpdated: DateTime.now(),
        startedAt: DateTime.now(),
        direction: BusDirection.unknown,
      );

      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RoutePreviewScreen(trip: trip, bus: widget.bus),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingSetup = false);
    }
  }

  // ── Button 2: Start Trip Tracking ──────────────────────────────────────

  Future<void> _startTripTracking() async {
    if (_existingRoute == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please set up the route and mark stops first '
            'using the "Setup Route & Stops" button.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    if (_existingRoute!.stops.isEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No Stops Saved'),
          content: const Text(
            'This route has no stops marked yet. '
            'Passengers won\'t see any stops on the map.\n\n'
            'Do you want to start tracking anyway, or set up stops first?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Set Up Stops First'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Start Anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _loadingTrack = true);
    try {
      final tripRepo = ref.read(tripRepositoryProvider);
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user == null) throw 'Not authenticated.';

      final result = await tripRepo.startTripFromExistingRoute(
        bus: widget.bus,
        route: _existingRoute!,
        conductorId: user.uid,
      );

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TripTrackingScreen(
            tripId: result.tripId,
            routeId: result.routeId,
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
      if (mounted) setState(() => _loadingTrack = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bus = widget.bus;
    final hasRoute = _existingRoute != null;
    final stopCount = _existingRoute?.stops.length ?? 0;

    return Scaffold(
      body: Container(
        color: AppTheme.surfaceColor,
        child: Column(
          children: [
            // ── Gradient App Bar ──────────────────────────────────
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
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
                      Text('Bus Options',
                        style: GoogleFonts.outfit(
                          fontSize: 18, fontWeight: FontWeight.w600,
                          color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppResponsive.horizontalPadding(context),
                    vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Bus summary card ─────────────────────────
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                          boxShadow: AppTheme.shadowSm,
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 44, height: 44,
                                  decoration: BoxDecoration(
                                    gradient: AppTheme.primaryGradient,
                                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                                  ),
                                  child: const Icon(Icons.directions_bus_rounded,
                                      color: Colors.white, size: 24),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(bus.busNumber,
                                    style: GoogleFonts.outfit(
                                        fontSize: 20, fontWeight: FontWeight.w700,
                                        color: AppTheme.textPrimary)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _InfoRow(icon: Icons.category_outlined, label: 'Type', value: bus.busType),
                            const SizedBox(height: 8),
                            _InfoRow(icon: Icons.schedule, label: 'Shift', value: bus.shift),
                            const SizedBox(height: 8),
                            _InfoRow(icon: Icons.trip_origin, label: 'From', value: bus.fromPlace),
                            const SizedBox(height: 8),
                            _InfoRow(icon: Icons.place, label: 'To', value: bus.toPlace),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Route status ─────────────────────────────
                      if (!_checkedRoute)
                        const Center(child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.primaryColor),
                        ))
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: hasRoute ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                            border: Border.all(color: hasRoute
                                ? AppTheme.primaryColor.withValues(alpha: 0.3)
                                : AppTheme.secondaryColor.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(hasRoute ? Icons.check_circle_outline : Icons.info_outline,
                                color: hasRoute ? AppTheme.primaryColor : AppTheme.secondaryColor, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text(
                                hasRoute
                                    ? 'Route ready — $stopCount stop${stopCount == 1 ? '' : 's'} saved'
                                    : 'No route set up yet. Tap below to begin.',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500,
                                    color: hasRoute ? AppTheme.primaryDark : const Color(0xFF92400E)),
                              )),
                            ],
                          ),
                        ),

                      const Spacer(),

                      // ── Setup Route button ───────────────────────
                      OutlinedButton.icon(
                        onPressed: _loadingSetup ? null : _setupRouteAndStops,
                        icon: _loadingSetup
                            ? const SizedBox(height: 20, width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor))
                            : Icon(hasRoute ? Icons.edit_location_alt : Icons.add_location),
                        label: Text(hasRoute ? 'Edit Route & Stops' : 'Setup Route & Stops'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryColor,
                          side: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Start Trip button ────────────────────────
                      Container(
                        decoration: BoxDecoration(
                          gradient: (_loadingTrack || !_checkedRoute) ? null : AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                          boxShadow: (_loadingTrack || !_checkedRoute) ? [] : AppTheme.shadowPrimary,
                        ),
                        child: ElevatedButton.icon(
                          onPressed: (_loadingTrack || !_checkedRoute) ? null : _startTripTracking,
                          icon: _loadingTrack
                              ? const SizedBox(height: 20, width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.play_arrow_rounded),
                          label: const Text('Start Trip Tracking'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            textStyle: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}




class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppTheme.textMuted),
        const SizedBox(width: 8),
        Text('$label: ',
            style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500)),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textPrimary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
