import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pandora_preview_contract.dart';

/// Android implementation of Pandora's exact in-memory preview host.
///
/// Project code never receives a JavaScript interface. Selection is transported
/// through the bounded native touch-probe method channel only.
class PandoraAndroidPreview extends StatefulWidget {
  const PandoraAndroidPreview({
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
  State<PandoraAndroidPreview> createState() => _PandoraAndroidPreviewState();
}

class _PandoraAndroidPreviewState extends State<PandoraAndroidPreview> {
  MethodChannel? _selectionChannel;

  @override
  void didUpdateWidget(covariant PandoraAndroidPreview oldWidget) {
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
    double number(String key) => (raw[key] as num?)?.toDouble() ?? 0;
    int? integer(String key) => (raw[key] as num?)?.toInt();
    final width = number('width');
    final height = number('height');
    final selection = PandoraPreviewSelection(
      tag: value('tag'),
      selector: value('selector'),
      text: value('text'),
      semanticId: value('semanticId'),
      role: value('role'),
      accessibleName: value('accessibleName'),
      route: value('route').isEmpty ? '/' : value('route'),
      sourceFile:
          value('sourceFile').isEmpty ? 'index.html' : value('sourceFile'),
      sourceLine: integer('sourceLine'),
      bounds: width > 0 && height > 0
          ? PandoraPreviewBounds(
              x: number('x'),
              y: number('y'),
              width: width,
              height: height,
            )
          : null,
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
    if (!PandoraAndroidPreview.isSupported ||
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
