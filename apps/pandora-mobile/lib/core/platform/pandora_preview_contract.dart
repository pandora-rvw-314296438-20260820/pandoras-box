import 'package:flutter/foundation.dart';

@immutable
class PandoraPreviewBounds {
  const PandoraPreviewBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;
}

@immutable
class PandoraPreviewSelection {
  const PandoraPreviewSelection({
    required this.tag,
    required this.selector,
    required this.text,
    this.semanticId = '',
    this.role = '',
    this.accessibleName = '',
    this.route = '/',
    this.sourceFile = 'index.html',
    this.sourceLine,
    this.bounds,
  });

  final String tag;
  final String selector;
  final String text;
  final String semanticId;
  final String role;
  final String accessibleName;
  final String route;
  final String sourceFile;
  final int? sourceLine;
  final PandoraPreviewBounds? bounds;

  String get label {
    final accessible = accessibleName.trim();
    if (accessible.isNotEmpty) return accessible;
    final visible = text.trim();
    if (visible.isNotEmpty) return visible;
    final target = selector.trim();
    if (target.isNotEmpty) return target;
    final element = tag.trim().toLowerCase();
    return element.isEmpty ? 'Selected element' : element;
  }
}
