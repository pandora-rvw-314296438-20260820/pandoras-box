import 'package:flutter/material.dart';

import 'pandora_android_preview.dart';

export 'pandora_preview_contract.dart';

/// Platform-neutral entry point for Pandora exact preview rendering.
///
/// Experience code depends on this host and the shared preview contract only.
/// Platform implementations remain isolated behind the host and must fail closed
/// to [fallback] when an exact renderer is unavailable.
class PandoraPreviewHost extends StatelessWidget {
  const PandoraPreviewHost({
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

  static bool get isSupported => PandoraAndroidPreview.isSupported;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty || versionId.trim().isEmpty) return fallback;

    if (PandoraAndroidPreview.isSupported) {
      return PandoraAndroidPreview(
        files: files,
        versionId: versionId,
        fallback: fallback,
        selectionEnabled: selectionEnabled,
        selectedSelector: selectedSelector,
        onSelection: onSelection,
      );
    }

    return fallback;
  }
}
