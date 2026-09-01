import 'package:flutter/material.dart';

import 'pandora_preview_contract.dart';

class PandoraWebPreview extends StatelessWidget {
  const PandoraWebPreview({
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

  static bool get isSupported => false;

  @override
  Widget build(BuildContext context) => fallback;
}
