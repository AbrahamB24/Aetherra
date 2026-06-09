import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Reusable D20 icon (hexagonal dice shape with inner lines).
/// [number] = null → shows 'd10' label; non-null → shows the value.
/// [color] defaults to the app gold.
class D20Icon extends StatelessWidget {
  final int?   number;
  final Color  color;
  final double size;

  const D20Icon({
    super.key,
    this.number,
    required this.color,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size, size),
    painter: D20Painter(color: color, number: number));
}

class D20Painter extends CustomPainter {
  final Color color;
  final int?  number;
  const D20Painter({required this.color, this.number});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width  / 2;
    final cy = size.height / 2;
    final r  = size.width  * 0.45;

    const sides = 6;
    final path = Path();
    for (int i = 0; i < sides; i++) {
      final angle = (i * 2 * math.pi / sides) - math.pi / 2;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();

    // Inner lines
    final inner = r * 0.55;
    for (int i = 0; i < sides; i++) {
      final a1 = (i * 2 * math.pi / sides) - math.pi / 2;
      final a2 = ((i + 1) * 2 * math.pi / sides) - math.pi / 2;
      canvas.drawLine(
        Offset(cx + r * math.cos(a1), cy + r * math.sin(a1)),
        Offset(cx, cy),
        Paint()..color = color.withValues(alpha: 0.25)..strokeWidth = 0.8
          ..style = PaintingStyle.stroke);
      canvas.drawLine(
        Offset(cx + r * math.cos(a1), cy + r * math.sin(a1)),
        Offset(cx + inner * math.cos(a2), cy + inner * math.sin(a2)),
        Paint()..color = color.withValues(alpha: 0.15)..strokeWidth = 0.6
          ..style = PaintingStyle.stroke);
    }

    canvas.drawPath(path,
      Paint()..color = color.withValues(alpha: 0.15)..style = PaintingStyle.fill);
    canvas.drawPath(path,
      Paint()..color = color..strokeWidth = 1.5..style = PaintingStyle.stroke);

    // Center label
    final label = number != null ? '$number' : 'd10';
    final fontSize = number != null
        ? (number! >= 10 ? size.width * 0.30 : size.width * 0.36)
        : size.width * 0.25;
    final tp = TextPainter(
      text: TextSpan(text: label,
        style: TextStyle(
          color: number != null ? color : color.withValues(alpha: 0.7),
          fontSize: fontSize, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  @override
  bool shouldRepaint(D20Painter o) => o.number != number || o.color != color;
}
