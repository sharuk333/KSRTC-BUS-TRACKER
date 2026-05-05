import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ksrtc_smarttrack/core/theme/app_theme.dart';
import 'package:ksrtc_smarttrack/data/models/route_model.dart';
import 'package:ksrtc_smarttrack/presentation/passenger/bus_tracking_screen.dart';
import 'package:ksrtc_smarttrack/providers/trip_provider.dart';

class BusResultsScreen extends ConsumerWidget {
  final String from;
  final String to;

  const BusResultsScreen({super.key, required this.from, required this.to});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Pass (from, to) directly to the family provider — stream is created
    // immediately with the correct query; no microtask timing race.
    final query = (from: from.trim(), to: to.trim());

    debugPrint('[BusResultsScreen] Searching from="${query.from}" to="${query.to}"');

    final resultsAsync = ref.watch(routeSearchProvider(query));

    return Scaffold(
      body: Container(
        color: AppTheme.surfaceColor,
        child: Column(
          children: [
            // ── Gradient App Bar ─────────────────────────────────
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(AppTheme.radiusXl),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 16, 20),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Available Buses',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$from → $to',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Results ──────────────────────────────────────────
            Expanded(
              child: resultsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.primaryColor,
                    strokeWidth: 3,
                  ),
                ),
                error: (e, _) => Center(
                  child: Text('Error: $e',
                      style: GoogleFonts.inter(color: AppTheme.errorColor)),
                ),
                data: (routes) {
                  debugPrint('[BusResultsScreen] Results count: ${routes.length}');

                  if (routes.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(
                                  AppTheme.radiusXl),
                            ),
                            child: Icon(Icons.bus_alert_rounded,
                                size: 36,
                                color: AppTheme.textMuted),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No buses found',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Try a different route.',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: routes.length,
                    itemBuilder: (context, index) {
                      final route = routes[index];
                      return _AnimatedBusCard(
                        route: route,
                        index: index,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                          builder: (_) => BusTrackingScreen(
                                    routeId: route.routeId,
                                    from: from,
                                    to: to,
                                  ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bus card with staggered entrance animation.
class _AnimatedBusCard extends StatefulWidget {
  final RouteModel route;
  final int index;
  final VoidCallback onTap;

  const _AnimatedBusCard({
    required this.route,
    required this.index,
    required this.onTap,
  });

  @override
  State<_AnimatedBusCard> createState() => _AnimatedBusCardState();
}

class _AnimatedBusCardState extends State<_AnimatedBusCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    Future.delayed(Duration(milliseconds: 80 * widget.index), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            boxShadow: AppTheme.shadowSm,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Bus icon
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusMd),
                      ),
                      child: const Icon(Icons.directions_bus_rounded,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),

                    // Info
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
                            const SizedBox(height: 4),
                            Text(
                              '${route.fromPlace} → ${route.toPlace}',
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                _InfoChip(
                                  icon: Icons.pin_drop_outlined,
                                  text: '${route.stops.length} stops',
                                ),
                                if (route.shift.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  _InfoChip(
                                    icon: Icons.schedule_outlined,
                                    text: route.shift,
                                  ),
                                ],
                              ],
                            ),
                        ],
                      ),
                    ),

                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(
                            AppTheme.radiusFull),
                      ),
                      child: const Icon(Icons.arrow_forward_ios_rounded,
                          size: 14, color: AppTheme.primaryColor),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.textMuted),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
