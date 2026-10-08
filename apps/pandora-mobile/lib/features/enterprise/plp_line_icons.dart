import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'plp_editorial_surfaces.dart';

/// Lightweight outline glyphs (Lucide-style, 24-unit grid, 1.5 stroke) for
/// PLP surfaces that must not fall back to filled Material icons.
enum PlpLineGlyph { chevronRight, externalLink, seal, sealPlain, rotateCcw }

class PlpLineIcon extends StatelessWidget {
  const PlpLineIcon(
    this.glyph, {
    super.key,
    this.size = 18,
    this.color = plpInk,
    this.strokeWidth = 1.5,
  });

  final PlpLineGlyph glyph;
  final double size;
  final Color color;

  /// Stroke in 24-unit grid space, so it scales with [size].
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _PlpLineIconPainter(glyph, color, strokeWidth),
          ),
        ),
      );
}

class _PlpLineIconPainter extends CustomPainter {
  const _PlpLineIconPainter(this.glyph, this.color, this.strokeWidth);

  final PlpLineGlyph glyph;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (glyph) {
      case PlpLineGlyph.chevronRight:
        canvas.drawPath(
          Path()
            ..moveTo(9, 6)
            ..lineTo(15, 12)
            ..lineTo(9, 18),
          paint,
        );
      case PlpLineGlyph.externalLink:
        canvas.drawPath(
          Path()
            ..moveTo(15, 3)
            ..lineTo(21, 3)
            ..lineTo(21, 9)
            ..moveTo(10, 14)
            ..lineTo(21, 3)
            ..moveTo(18, 13)
            ..lineTo(18, 19)
            ..arcToPoint(const Offset(16, 21), radius: const Radius.circular(2))
            ..lineTo(5, 21)
            ..arcToPoint(const Offset(3, 19), radius: const Radius.circular(2))
            ..lineTo(3, 8)
            ..arcToPoint(const Offset(5, 6), radius: const Radius.circular(2))
            ..lineTo(11, 6),
          paint,
        );
      case PlpLineGlyph.seal:
      case PlpLineGlyph.sealPlain:
        final seal = Path();
        const samples = 96;
        for (var i = 0; i <= samples; i++) {
          final t = i / samples * 2 * math.pi;
          // Eight rounded lobes with soft inner cusps (badge outline).
          final r = 7.7 + 1.9 * math.sqrt(math.cos(4 * t).abs());
          final p = Offset(12 + r * math.cos(t), 12 + r * math.sin(t));
          i == 0 ? seal.moveTo(p.dx, p.dy) : seal.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(seal..close(), paint);
        if (glyph == PlpLineGlyph.seal) {
          canvas.drawPath(
            Path()
              ..moveTo(9, 12)
              ..lineTo(11, 14)
              ..lineTo(15, 10),
            paint,
          );
        }
      case PlpLineGlyph.rotateCcw:
        final arc = Path()
          ..addArc(
            Rect.fromCircle(center: const Offset(12, 12), radius: 9),
            math.pi,
            -1.75 * math.pi,
          )
          ..lineTo(3, 8)
          ..moveTo(3, 3)
          ..lineTo(3, 8)
          ..lineTo(8, 8);
        canvas.drawPath(arc, paint);
    }
  }

  @override
  bool shouldRepaint(_PlpLineIconPainter old) =>
      old.glyph != glyph ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
