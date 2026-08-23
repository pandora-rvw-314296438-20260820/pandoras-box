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

  final double size;
  final String semanticLabel;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).round();

    return Semantics(
      image: true,
      label: semanticLabel,
      child: SizedBox.square(
        dimension: size,
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          cacheWidth: cacheSize,
          cacheHeight: cacheSize,
          color: resolvedColor,
          colorBlendMode: BlendMode.srcIn,
          gaplessPlayback: true,
          isAntiAlias: true,
          excludeFromSemantics: true,
          errorBuilder: (context, error, stackTrace) => DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.transparent,
              border: Border.all(color: Theme.of(context).colorScheme.error),
              borderRadius: PandoraRadius.controlBorder,
            ),
            child: Icon(
              Icons.broken_image_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      ),
    );
  }
}
