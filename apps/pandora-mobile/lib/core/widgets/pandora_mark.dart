import 'package:flutter/material.dart';

import '../design/pandora_tokens.dart';

class PandoraMark extends StatelessWidget {
  const PandoraMark({
    super.key,
    this.size = PandoraSize.compactMark,
    this.semanticLabel = "Pandora's Box",
    this.color,
  });

  // Kept for source-chain compatibility with the pinned historical brand asset.
  // Customer-facing UI now renders the Pandora app icon directly.
  static const assetPath = 'assets/brand/pandora-product-mark-ui-1024.png';

  final double size;
  final String semanticLabel;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final monochrome = color == Colors.white ? color : null;

    return Semantics(
      image: true,
      label: semanticLabel,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _PandoraAppIconPainter(monochrome: monochrome),
        ),
      ),
    );
  }
}

class _PandoraAppIconPainter extends CustomPainter {
  const _PandoraAppIconPainter({this.monochrome});

  final Color? monochrome;

  @override
  void paint(Canvas canva, Size size) {
    final w = size.width;
    final h = size.height;

    final mark = Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(w * 0.18, h * 0.91)
      ..lineTo(w * 0.34, h * 0.18)
      ..cubicTo(
        w * 0.37,
        h * 0.07,
        w * 0.47,
        h * 0.02,
        w * 0.60,
        h * 0.04,
      )
      ..cubicTo(
        w * 0.79,
        h * 0.05,
        w * 0.92,
        h * 0.17,
        w * 0.92,
        h * 0.32,
      )
      ..cubicTo(
        w * 0.92,
        h * 0.49,
        w * 0.80,
        h * 0.59,
        w * 0.61,
        h * 0.60,
      )
      ..lineTo(w * 0.55, h * 0.60)
      ..lineTo(w * 0.49, h * 0.86)
      ..cubicTo(
        w * 0.47,
        h * 0.94,
        w * 0.38,
        h * 0.97,
        w * 0.30,
        h * 0.94,
      )
      ..close()
      ..moveTo(w * 0.54, h * 0.23)
      ..cubicTo(
        w * 0.62,
        h * 0.19,
        w * 0.73,
        h * 0.20,
        w * 0.77,
        h * 0.27,
      )
      ..cubicTo(
        w * 0.82,
        h * 0.35,
        w * 0.75,
        h * 0.43,
        w * 0.66,
        h * 0.44,
      )
      ..lineTo(w * 0.58, h * 0.44)
      ..close();

    final bounds = Offset.zero & size;
    final gradient = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[
        Color(0xFF8A56FF),
        Color(0xFFB84DEB),
        Color(0xFFD94FC9),
        Color(0xFF2F6BFF),
      ],
      stops: <double>[0.0, 0.33, 0.58, 1.0],
    );

    final paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill
      ..shader = monochrome == null ? gradient.createShader(bounds) : null
      ..color = monochrome ?? Colors.white;

    canva.drawPath(mark, paint);
    canva.drawPath(tail, paint);
  }

  @override
  bool shouldRepaint(covariant _PandoraAppIconPainter oldDelegate) =>
      oldDelegate.monochrome != monochrome;
}
