import 'package:flutter/material.dart';

import '../design/pandora_tokens.dart';

class PandoraMark extends StatelessWidget {
  const PandoraMark({
    super.key,
    this.size = PandoraSize.compactMark,
    this.semanticLabel = "Pandora's Box",
    this.color,
  });

  static const assetPath = 'assets/brand/pandora-product-mark-ui-1024.png';
  static const canonicalAssetSha256 =
      '8a35b74baec47b960a42bb74587f9c531d6cbf8d45f16061836a9e63f00efcc5';

  final double size;
  final String semanticLabel;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ??
        (Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFFF7F6F3)
            : const Color(0xFF171717));
    return Semantics(
      image: true,
      label: semanticLabel,
      child: SizedBox.square(
        dimension: size,
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
          color: effectiveColor,
          colorBlendMode: BlendMode.srcIn,
          filterQuality: FilterQuality.high,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
