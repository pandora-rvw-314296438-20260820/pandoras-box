import 'package:flutter/material.dart';

import 'plp_editorial_surfaces.dart';

/// Lightweight outline glyphs (Lucide-style, 24-unit grid, 1.5 stroke) for
/// PLP surfaces that must not fall back to filled Material icons.
enum PlpLineGlyph { chevronRight }

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
    }
  }

  @override
  bool shouldRepaint(_PlpLineIconPainter old) =>
      old.glyph != glyph ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
