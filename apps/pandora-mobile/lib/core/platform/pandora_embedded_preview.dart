import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Renders an exact Pandora preview bundle inside the owner workspace.
///
/// Android uses the app's bounded in-memory WebView renderer. Other platforms
/// fail closed to [fallback] rather than silently showing a stale or unrelated
/// project URL.
class PandoraEmbeddedPreview extends StatelessWidget {
  const PandoraEmbeddedPreview({
    super.key,
    required this.files,
    required this.versionId,
    required this.fallback,
  });

  final List<Map<String, Object?>> files;
  final String versionId;
  final Widget fallback;

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Widget build(BuildContext context) {
    if (!isSupported || files.isEmpty || versionId.trim().isEmpty) {
      return fallback;
    }
    return AndroidView(
      viewType: 'pandora/exact_preview',
      layoutDirection: TextDirection.ltr,
      creationParamsCodec: const StandardMessageCodec(),
      creationParams: <String, Object?>{
        'versionId': versionId.trim(),
        'files': files,
      },
    );
  }
}
