import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Generates a navigation-arrow [BitmapDescriptor] rotated to [bearingDegrees].
///
/// The arrow is drawn entirely on a Canvas — no image assets required.
/// [size]          — canvas size in logical pixels (default 80).
/// [bearingDegrees] — clockwise rotation from north (0 = pointing up/north).
Future<BitmapDescriptor> buildNavigationArrow({
  double bearingDegrees = 0,
  double size = 80,
  Color arrowColor = Colors.blue,
  Color borderColor = Colors.white,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final cx = size / 2;
  final cy = size / 2;
  final r = size / 2 - 4; // leave a small margin for the shadow/border

  // ── Rotate around centre by bearing ──────────────────────────────────────
  canvas.translate(cx, cy);
  canvas.rotate((bearingDegrees - 0) * math.pi / 180);
  canvas.translate(-cx, -cy);

  // ── Draw outer white circle (border / halo) ───────────────────────────────
  canvas.drawCircle(
    Offset(cx, cy),
    r,
    Paint()
      ..color = borderColor
      ..style = PaintingStyle.fill,
  );

  // ── Draw inner filled circle ──────────────────────────────────────────────
  canvas.drawCircle(
    Offset(cx, cy),
    r - 4,
    Paint()
      ..color = arrowColor
      ..style = PaintingStyle.fill,
  );

  // ── Draw the navigation chevron / arrow ───────────────────────────────────
  // Coordinates are in a [0, size] space, centred at (cx, cy).
  // The arrow points UP (north) in local space; rotation above handles bearing.
  final arrowPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;

  final path = Path();
  // Tip — top centre
  path.moveTo(cx, cy - r * 0.55);
  // Right wing
  path.lineTo(cx + r * 0.38, cy + r * 0.40);
  // Tail notch — right of centre-bottom
  path.lineTo(cx + r * 0.12, cy + r * 0.18);
  // Tail notch — left of centre-bottom
  path.lineTo(cx - r * 0.12, cy + r * 0.18);
  // Left wing
  path.lineTo(cx - r * 0.38, cy + r * 0.40);
  path.close();

  canvas.drawPath(path, arrowPaint);

  // ── Finalise ──────────────────────────────────────────────────────────────
  final picture = recorder.endRecording();
  final img = await picture.toImage(size.toInt(), size.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);

  return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
}
