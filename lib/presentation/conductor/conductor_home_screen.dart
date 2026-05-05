import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ksrtc_smarttrack/core/theme/app_theme.dart';
import 'package:ksrtc_smarttrack/data/models/bus_model.dart';
import 'package:ksrtc_smarttrack/data/repositories/bus_repository.dart';
import 'package:ksrtc_smarttrack/presentation/auth/login_screen.dart';
import 'package:ksrtc_smarttrack/presentation/conductor/add_edit_bus_screen.dart';
import 'package:ksrtc_smarttrack/presentation/conductor/trip_form_screen.dart';
import 'package:ksrtc_smarttrack/providers/auth_provider.dart';
import 'package:ksrtc_smarttrack/providers/bus_provider.dart';

class ConductorHomeScreen extends ConsumerWidget {
  const ConductorHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authRepositoryProvider).currentUser;
    if (user == null) return const LoginScreen();

    final busesAsync = ref.watch(conductorBusesProvider(user.uid));

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
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 20),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        ),
                        child: const Icon(Icons.directions_bus_rounded,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'My Buses',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                          ),
                          child: const Icon(Icons.logout_rounded,
                              color: Colors.white, size: 20),
                        ),
                        tooltip: 'Logout',
                        onPressed: () async {
                          await ref.read(authRepositoryProvider).signOut();
                          if (context.mounted) {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (_) => const LoginScreen()),
                              (r) => false,
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Body ──────────────────────────────────────────────
            Expanded(
              child: busesAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.primaryColor, strokeWidth: 3),
                ),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (buses) {
                  if (buses.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                            ),
                            child: Icon(Icons.directions_bus_outlined,
                                size: 36, color: AppTheme.textMuted),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No buses yet',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tap + to register your first bus.',
                            style: GoogleFonts.inter(
                              color: AppTheme.textMuted, fontSize: 14),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: buses.length,
                    itemBuilder: (ctx, i) =>
                        _BusCard(bus: buses[i], conductorId: user.uid),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          boxShadow: AppTheme.shadowPrimary,
        ),
        child: FloatingActionButton.extended(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AddEditBusScreen()),
          ),
          icon: const Icon(Icons.add_rounded),
          label: Text('Add Bus', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bus card
// ─────────────────────────────────────────────────────────────────────────────

class _BusCard extends ConsumerWidget {
  final BusModel bus;
  final String conductorId;

  const _BusCard({required this.bus, required this.conductorId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TripFormScreen(bus: bus),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
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
                        bus.busNumber,
                        style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w600, fontSize: 15,
                            color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${bus.busType} • ${bus.shift} shift',
                        style: GoogleFonts.inter(
                            fontSize: 12, color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${bus.fromPlace} → ${bus.toPlace}',
                        style: GoogleFonts.inter(
                            fontSize: 13, color: AppTheme.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Actions
                PopupMenuButton<_BusAction>(
                  onSelected: (action) =>
                      _handleAction(context, ref, action),
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(
                      value: _BusAction.edit,
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _BusAction.delete,
                      child: ListTile(
                        leading: Icon(Icons.delete_outline, color: Colors.red),
                        title: Text('Delete',
                            style: TextStyle(color: Colors.red)),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleAction(
      BuildContext context, WidgetRef ref, _BusAction action) async {
    switch (action) {
      case _BusAction.edit:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AddEditBusScreen(existingBus: bus),
          ),
        );

      case _BusAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Bus?'),
            content: Text(
                'Remove bus ${bus.busNumber}? Completed trip history will NOT be deleted.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );

        if (confirmed != true || !context.mounted) return;

        try {
          await ref.read(busRepositoryProvider).deleteBus(bus.busId);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('Bus ${bus.busNumber} deleted.')),
            );
          }
        } on BusDeletionException catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.message)),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e')),
            );
          }
        }
    }
  }
}

enum _BusAction { edit, delete }
