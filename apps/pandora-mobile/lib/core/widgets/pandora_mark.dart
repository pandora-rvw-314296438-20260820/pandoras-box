
import 'package:flutter/material.dart';

import '../design/pandora_tokens.dart';

class PandoraMark extends StatelessWidget {
  const PandoraMark({
    super.key,
    this.size = PandoraSize.compactMark,
    this.semanticLabel = "Pandora's Box",
    this.color,
  });

  // Historical source-chain asset retained in the repository, but customer UI
  // renders the canonical Pandora gradient apple directly so Home, sign-in,
  // navigation, and Android launcher identity share one shape definition.
  static const assetPath = 'assets/brand/pandora-product-mark-ui-1024.png';

  final double size;
  final String semanticLabel;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final monochrome = color == Colors.white ? Colors.white : null;
    return Semantics(
      image: true,
      label: semanticLabel,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _PandoraApplePainter(monochrome: monochrome),
        ),
      ),
    );
  }
}

class _PandoraApplePainter extends CustomPainter {
  const _PandoraApplePainter({this.monochrome});

  final Color? monochrome;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final body = Path()
      ..moveTo(w * 0.499, h * 0.318)
      ..cubicTo(
        w * 0.447,
        h * 0.281,
        w * 0.392,
        h * 0.261,
        w * 0.340,
        h * 0.262,
      )
      ..cubicTo(
        w * 0.238,
        h * 0.265,
        w * 0.166,
        h * 0.346,
        w * 0.160,
        h * 0.461,
      )
      ..cubicTo(
        w * 0.153,
        h * 0.598,
        w * 0.220,
        h * 0.732,
        w * 0.329,
        h * 0.830,
      )
      ..cubicTo(
        w * 0.388,
        h * 0.883,
        w * 0.435,
        h * 0.913,
        w * 0.476,
        h * 0.910,
      )
      ..cubicTo(
        w * 0.500,
        h * 0.909,
        w * 0.518,
        h * 0.895,
        w * 0.538,
        h * 0.895,
      )
      ..cubicTo(
        w * 0.563,
        h * 0.895,
        w * 0.581,
        h * 0.910,
        w * 0.605,
        h * 0.911,
      )
      ..cubicTo(
        w * 0.651,
        h * 0.913,
        w * 0.697,
        h * 0.885,
        w * 0.752,
        h * 0.832,
      )
      ..cubicTo(
        w * 0.858,
        h * 0.734,
        w * 0.919,
        h * 0.600,
        w * 0.910,
        h * 0.467,
      )
      ..cubicTo(
        w * 0.902,
        h * 0.353,
        w * 0.832,
        h * 0.275,
        w * 0.737,
        h * 0.263,
      )
      ..cubicTo(
        w * 0.673,
        h * 0.254,
        w * 0.617,
        h * 0.274,
        w * 0.560,
        h * 0.314,
      )
      ..cubicTo(
        w * 0.539,
        h * 0.329,
        w * 0.519,
        h * 0.332,
        w * 0.499,
        h * 0.318,
      )
      ..close();

    final bite = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(w * 0.858, h * 0.373),
          radius: w * 0.105,
        ),
      );
    final apple = Path.combine(PathOperation.difference, body, bite);

    final leaf = Path()
      ..moveTo(w * 0.553, h * 0.242)
      ..cubicTo(
        w * 0.570,
        h * 0.171,
        w * 0.629,
        h * 0.118,
        w * 0.699,
        h * 0.104,
      )
      ..cubicTo(
        w * 0.696,
        h * 0.171,
        w * 0.661,
        h * 0.225,
        w * 0.604,
        h * 0.256,
      )
      ..cubicTo(
        w * 0.581,
        h * 0.269,
        w * 0.563,
        h * 0.264,
        w * 0.553,
        h * 0.242,
      )
      ..close();

    final bounds = Offset.zero & size;
    final gradient = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[
        Color(0xFFB72DFF),
        Color(0xFFD32BE8),
        Color(0xFF7046FF),
        Color(0xFF2063FF),
      ],
      stops: <double>[0.0, 0.36, 0.70, 1.0],
    );
    final paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill
      ..shader = monochrome == null ? gradient.createShader(bounds) : null
      ..color = monochrome ?? Colors.white;

    canvas.drawPath(apple, paint);
    canvas.drawPath(leaf, paint);
  }

  @override
  bool shouldRepaint(covariant _PandoraApplePainter oldDelegate) =>
      oldDelegate.monochrome != monochrome;
}
