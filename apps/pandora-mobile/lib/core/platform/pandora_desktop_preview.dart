import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'pandora_preview_contract.dart';

/// Explicit fail-closed host for desktop platforms without a governed exact
/// renderer yet.
///
/// Desktop must never silently substitute an external URL or stale preview for
/// the exact artifact requested by [versionId].
class PandoraDesktopPreview extends StatelessWidget {
  const PandoraDesktopPreview({
    super.key,
    required this.files,
    required this.versionId,
    required this.fallback,
    this.selectionEnabled = false,
    this.selectedSelector,
    this.onSelection,
  });

  final List<Map<String, Object?>> files;
  final String versionId;
  final Widget fallback;
  final bool selectionEnabled;
  final String? selectedSelector;
  final ValueChanged<PandoraPreviewSelection>? onSelection;

  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  static bool get isSupported => false;

  @override
  Widget build(BuildContext context) => fallback;
}
