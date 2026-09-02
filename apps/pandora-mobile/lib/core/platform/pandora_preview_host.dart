import 'package:flutter/material.dart';

import '../models/project_preview_identity.dart';
import 'pandora_android_preview.dart';
import 'pandora_desktop_preview.dart';
import 'pandora_ios_preview.dart';
import 'pandora_preview_contract.dart';
import 'pandora_web_preview.dart';

export 'pandora_preview_contract.dart';

/// Platform-neutral entry point for Pandora exact preview rendering.
///
/// Experience code depends on this host and the shared preview contract only.
/// Platform implementations remain isolated behind the host and must fail closed
/// to [fallback] when an exact renderer is unavailable or identity mismatches.
class PandoraPreviewHost extends StatelessWidget {
  const PandoraPreviewHost({
    super.key,
    required this.files,
    required this.versionId,
    required this.fallback,
    this.identity,
    this.projectId,
    this.selectionEnabled = false,
    this.selectedSelector,
    this.onSelection,
  });

  final List<Map<String, Object?>> files;
  final String versionId;
  final Widget fallback;
  final ProjectPreviewIdentity? identity;
  final String? projectId;
  final bool selectionEnabled;
  final String? selectedSelector;
  final ValueChanged<PandoraPreviewSelection>? onSelection;

  static bool get isSupported =>
      PandoraAndroidPreview.isSupported ||
      PandoraIosPreview.isSupported ||
      PandoraWebPreview.isSupported;

  ProjectPreviewIdentity? resolveIdentity() {
    final parsed = ProjectPreviewIdentity.tryParse(
      files,
      expectedProjectId: projectId,
      expectedVersionId: versionId,
    );
    final explicit = identity;
    if (explicit == null) return parsed;
    if (parsed == null) return null;
    if (explicit.projectId != parsed.projectId ||
        explicit.versionId != parsed.versionId ||
        explicit.artifactDigest != parsed.artifactDigest ||
        explicit.deploymentId != parsed.deploymentId ||
        explicit.sourceSha256 != parsed.sourceSha256) {
      return null;
    }
    return explicit;
  }

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty || versionId.trim().isEmpty) return fallback;
    final resolved = resolveIdentity();
    if (resolved == null ||
        !resolved.matchesHost(versionId: versionId, projectId: projectId)) {
      return fallback;
    }

    if (PandoraAndroidPreview.isSupported) {
      return PandoraAndroidPreview(
        files: files,
        versionId: resolved.versionId,
        fallback: fallback,
        selectionEnabled: selectionEnabled,
        selectedSelector: selectedSelector,
        onSelection: onSelection,
      );
    }

    if (PandoraIosPreview.isSupported) {
      return PandoraIosPreview(
        files: files,
        versionId: resolved.versionId,
        fallback: fallback,
        selectionEnabled: selectionEnabled,
        selectedSelector: selectedSelector,
        onSelection: onSelection,
      );
    }

    if (PandoraWebPreview.isSupported) {
      return PandoraWebPreview(
        files: files,
        versionId: resolved.versionId,
        fallback: fallback,
        selectionEnabled: selectionEnabled,
        selectedSelector: selectedSelector,
        onSelection: onSelection,
      );
    }

    return PandoraDesktopPreview(
      files: files,
      versionId: resolved.versionId,
      fallback: fallback,
      selectionEnabled: selectionEnabled,
      selectedSelector: selectedSelector,
      onSelection: onSelection,
    );
  }
}
