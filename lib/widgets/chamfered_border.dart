import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Paints a chamfered (beveled-corner) rectangle border where the diagonal
/// corner segments are the same VISUAL thickness as the straight edges.
///
/// A normal stroked path at 45Â° appears thinner than horizontal/vertical
/// strokes of the same width. This painter instead draws a filled ring
/// (outer chamfered shape minus inner chamfered shape) where the inner
/// shape is computed so the perpendicular distance at each diagonal equals
/// [width] â€” matching the straight-edge thickness exactly.
///
/// [squareBottom] â€” when true the two bottom corners are right-angle (not
/// chamfered), useful when the widget merges visually with content below it.
class ChamferedBorderPainter extends CustomPainter {
  final Color  color;
  final double width;        // visual border thickness
  final double bevel;        // corner cut size
  final bool   squareBottom; // square bottom-left / bottom-right corners

  const ChamferedBorderPainter({
    required this.color,
    required this.width,
    required this.bevel,
    this.squareBottom = false,
  });

  // Bi = B - width*(2-âˆš2) gives perpendicular corner thickness == width
  static const double _k = 2.0 - math.sqrt2;

  static Path _chamferedRect(
      double l, double t, double r, double b, double bv,
      {bool squareBottom = false}) {
    final bvB = squareBottom ? 0.0 : bv;
    if (bv <= 0 && bvB <= 0) return Path()..addRect(Rect.fromLTRB(l, t, r, b));
    return Path()
      ..moveTo(l + bv, t)
      ..lineTo(r - bv, t)
      ..lineTo(r, t + bv)
      ..lineTo(r, b - bvB)
      ..lineTo(r - bvB, b)
      ..lineTo(l + bvB, b)
      ..lineTo(l, b - bvB)
      ..lineTo(l, t + bv)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w  = size.width;
    final h  = size.height;
    final sw = width;
    final B  = bevel;
    final innerBevel  = (B - sw * _k).clamp(0.0, B);

    final outer = _chamferedRect(0,  0,  w,      h,      B,      squareBottom: squareBottom);
    final inner = _chamferedRect(sw, sw, w - sw, h - sw, innerBevel, squareBottom: squareBottom);

    canvas.drawPath(
      Path.combine(PathOperation.difference, outer, inner),
      Paint()
        ..color       = color
        ..style       = PaintingStyle.fill
        ..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(ChamferedBorderPainter o) =>
    o.color != color || o.width != width || o.bevel != bevel ||
    o.squareBottom != squareBottom;
}
