import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

@immutable
class PandoraPreviewSelection {
  const PandoraPreviewSelection({
    required this.tag,
    required this.selector,
    required this.text,
  });

  final String tag;
  final String selector;
  final String text;

  String get label {
    final visible = text.trim();
    if (visible.isNotEmpty) return visible;
    final target = selector.trim();
    if (target.isNotEmpty) return target;
    final element = tag.trim().toLowerCase();
    return element.isEmpty ? 'Selected element' : element;
  }

  String get intentContext {
    final target = selector.trim();
    final element = tag.trim().toLowerCase();
    final parts = <String>[
      'Selected project element:',
      if (target.isNotEmpty) 'selector=$target',
      if (element.isNotEmpty) 'tag=$element',
    ];
    return '${parts.join(' ')}. Apply the owner change specifically to this selected element.';
  }
}

/// Renders an exact Pandora preview bundle inside the owner workspace.
///
/// Android uses the app's bounded in-memory WebView renderer. Other platforms
/// fail closed to [fallback] rather than silently showing a stale or unrelated
/// project URL. Selection uses a native touch probe and never exposes a
/// JavaScript interface to project code.
class PandoraEmbeddedPreview extends StatefulWidget {
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

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  State<PandoraEmbeddedPreview> createState() => _PandoraEmbeddedPreviewState();
}

class _PandoraEmbeddedPreviewState extends State<PandoraEmbeddedPreview> {
  MethodChannel? _selectionChannel;

  @override
  void didUpdateWidget(covariant PandoraEmbeddedPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionEnabled != widget.selectionEnabled) {
      _syncSelectionMode();
    }
    if (oldWidget.selectedSelector != widget.selectedSelector &&
        widget.selectedSelector == null) {
      _clearNativeSelection();
    }
  }

  @override
  void dispose() {
    _selectionChannel?.setMethodCallHandler(null);
    _selectionChannel = null;
    super.dispose();
  }

  void _onPlatformViewCreated(int viewId) {
    final previous = _selectionChannel;
    previous?.setMethodCallHandler(null);
    final channel = MethodChannel('pandora/exact_preview_selection_$viewId');
    _selectionChannel = channel;
    channel.setMethodCallHandler(_handleNativeSelection);
    _syncSelectionMode();
  }

  Future<void> _handleNativeSelection(MethodCall call) async {
    if (call.method != 'selection' || !mounted) return;
    final raw = call.arguments;
    if (raw is! Map) return;
    String value(String key) => (raw[key] as String? ?? '').trim();
    final selection = PandoraPreviewSelection(
      tag: value('tag'),
      selector: value('selector'),
      text: value('text'),
    );
    if (selection.selector.isEmpty && selection.tag.isEmpty) return;
    widget.onSelection?.call(selection);
  }

  void _syncSelectionMode() {
    final channel = _selectionChannel;
    if (channel == null) return;
    channel.invokeMethod<void>(
      'setSelectionMode',
      <String, Object?>{'enabled': widget.selectionEnabled},
    ).catchError((_) {});
  }

  void _clearNativeSelection() {
    final channel = _selectionChannel;
    if (channel == null) return;
    channel.invokeMethod<void>('clearSelection').catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (!PandoraEmbeddedPreview.isSupported ||
        widget.files.isEmpty ||
        widget.versionId.trim().isEmpty) {
      return widget.fallback;
    }
    return AndroidView(
      viewType: 'pandora/exact_preview',
      layoutDirection: TextDirection.ltr,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _onPlatformViewCreated,
      creationParams: <String, Object?>{
        'versionId': widget.versionId.trim(),
        'files': widget.files,
      },
    );
  }
}
