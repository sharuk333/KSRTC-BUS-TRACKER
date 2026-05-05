import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ksrtc_smarttrack/core/theme/app_theme.dart';
import 'package:ksrtc_smarttrack/data/models/stop_model.dart';

enum StopState { passed, upcoming, future }

/// A list tile that visually distinguishes passed, upcoming, and future stops
/// using a timeline design with gradient dots and connecting lines.
class StopListTile extends StatelessWidget {
  final StopModel stop;
  final StopState state;
  final VoidCallback? onTap;

  /// Whether this is the last stop in the list (hides the bottom connecting line).
  final bool isLast;

  const StopListTile({
    super.key,
    required this.stop,
    required this.state,
    this.onTap,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Timeline column ───────────────────────────────────
              SizedBox(
                width: 32,
                child: Column(
                  children: [
                    // Top connecting line
                    Expanded(
                      child: Container(
                        width: 2,
                        color: state == StopState.passed
                            ? AppTheme.textMuted.withValues(alpha: 0.25)
                            : state == StopState.upcoming
                                ? AppTheme.primaryColor.withValues(alpha: 0.4)
                                : AppTheme.border,
                      ),
                    ),
                    // Dot indicator
                    _buildDot(),
                    // Bottom connecting line
                    Expanded(
                      child: isLast
                          ? const SizedBox.shrink()
                          : Container(
                              width: 2,
                              color: state == StopState.passed
                                  ? AppTheme.textMuted
                                      .withValues(alpha: 0.25)
                                  : AppTheme.border,
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // ── Content ───────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              stop.name,
                              style: _nameStyle(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Stop #${stop.order}',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (state == StopState.upcoming) _buildNextChip(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDot() {
    switch (state) {
      case StopState.passed:
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: AppTheme.textMuted.withValues(alpha: 0.35),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, size: 8, color: Colors.white),
        );
      case StopState.upcoming:
        return Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(Icons.arrow_forward_rounded,
              size: 10, color: Colors.white),
        );
      case StopState.future:
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.border, width: 2),
          ),
        );
    }
  }

  TextStyle _nameStyle() {
    switch (state) {
      case StopState.passed:
        return GoogleFonts.inter(
          fontSize: 13,
          color: AppTheme.textMuted,
          decoration: TextDecoration.lineThrough,
          decorationColor: AppTheme.textMuted.withValues(alpha: 0.5),
        );
      case StopState.upcoming:
        return GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.primaryColor,
        );
      case StopState.future:
        return GoogleFonts.inter(
          fontSize: 13,
          color: AppTheme.textPrimary,
        );
    }
  }

  Widget _buildNextChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: AppTheme.accentGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        boxShadow: [
          BoxShadow(
            color: AppTheme.secondaryColor.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        'NEXT',
        style: GoogleFonts.outfit(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
