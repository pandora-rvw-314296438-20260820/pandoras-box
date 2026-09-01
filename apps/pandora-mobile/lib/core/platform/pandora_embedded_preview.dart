import 'package:flutter/material.dart';

import 'pandora_preview_host.dart';

export 'pandora_preview_contract.dart';

/// Compatibility wrapper for callers that still use the former embedded name.
///
/// New Experience code must depend on [PandoraPreviewHost] so platform-specific
/// rendering remains isolated behind one cross-platform boundary.
@Deprecated('Use PandoraPreviewHost instead.')
class PandoraEmbeddedPreview extends StatelessWidget {
  const PandoraEmbeddedPreview({
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

  static bool get isSupported => PandoraPreviewHost.isSupported;

  @override
  Widget build(BuildContext context) => PandoraPreviewHost(
    files: files,
    versionId: versionId,
    fallback: fallback,
    selectionEnabled: selectionEnabled,
    selectedSelector: selectedSelector,
    onSelection: onSelection,
  );
}
