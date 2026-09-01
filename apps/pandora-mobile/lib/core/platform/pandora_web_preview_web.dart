// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import 'pandora_preview_contract.dart';

const int _maxFileCount = 1000;
const int _maxFileBytes = 10 * 1024 * 1024;
const int _maxBundleBytes = 12 * 1024 * 1024;

class PandoraWebPreview extends StatefulWidget {
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

  static bool get isSupported => true;

  @override
  State<PandoraWebPreview> createState() => _PandoraWebPreviewState();
}

class _PandoraWebPreviewState extends State<PandoraWebPreview> {
  static int _nextViewId = 0;

  late final String _viewType;
  html.IFrameElement? _frame;
  html.MessagePort? _port;
  StreamSubscription<html.Event>? _loadSubscription;
  StreamSubscription<html.MessageEvent>? _portSubscription;
  Map<String, _PreviewFile>? _bundle;
  String? _srcdoc;

  @override
  void initState() {
    super.initState();
    _viewType = 'pandora-exact-preview-web-${_nextViewId++}';
    _materialize();
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _createFrame(),
    );
  }

  @override
  void didUpdateWidget(covariant PandoraWebPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bundleChanged = oldWidget.versionId != widget.versionId ||
        !identical(oldWidget.files, widget.files);
    if (bundleChanged) {
      _materialize();
      _reloadFrame();
      return;
    }
    if (oldWidget.selectionEnabled != widget.selectionEnabled ||
        oldWidget.selectedSelector != widget.selectedSelector) {
      _sendState();
    }
  }

  @override
  void dispose() {
    _loadSubscription?.cancel();
    _portSubscription?.cancel();
    _port?.close();
    _loadSubscription = null;
    _portSubscription = null;
    _port = null;
    _frame = null;
    super.dispose();
  }

  void _materialize() {
    final versionId = widget.versionId.trim();
    final parsed = _parseBundle(widget.files);
    if (versionId.isEmpty || parsed == null) {
      _bundle = null;
      _srcdoc = null;
      return;
    }
    _bundle = parsed;
    _srcdoc = _buildSrcdoc(parsed, versionId);
  }

  html.IFrameElement _createFrame() {
    final frame = html.IFrameElement()
      ..setAttribute('sandbox', 'allow-scripts')
      ..setAttribute('referrerpolicy', 'no-referrer')
      ..setAttribute('aria-label', 'Pandora exact preview')
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.display = 'block';
    _frame = frame;
    _loadSubscription?.cancel();
    _loadSubscription = frame.onLoad.listen((_) => _attachPort());
    frame.srcdoc = _srcdoc ?? _unavailableDocument;
    return frame;
  }

  void _reloadFrame() {
    final frame = _frame;
    if (frame == null) return;
    _portSubscription?.cancel();
    _port?.close();
    _portSubscription = null;
    _port = null;
    frame.srcdoc = _srcdoc ?? _unavailableDocument;
  }

  void _attachPort() {
    final frame = _frame;
    final target = frame?.contentWindow;
    final versionId = widget.versionId.trim();
    if (frame == null ||
        target == null ||
        _bundle == null ||
        versionId.isEmpty) {
      return;
    }

    _portSubscription?.cancel();
    _port?.close();

    final channel = html.MessageChannel();
    _port = channel.port1;
    _portSubscription = channel.port1.onMessage.listen(_handlePortMessage);
    target.postMessage(
      <String, Object?>{
        'type': 'pandora-preview-init',
        'versionId': versionId,
      },
      '*',
      <html.MessagePort>[channel.port2],
    );
  }

  void _handlePortMessage(html.MessageEvent event) {
    final raw = event.data;
    if (raw is! String || !mounted) return;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    final message = decoded;
    if (message is! Map) return;

    String value(String key) => (message[key] as String? ?? '').trim();
    if (value('versionId') != widget.versionId.trim()) return;
    final type = value('type');
    if (type == 'ready') {
      _sendState();
      return;
    }
    if (type != 'selection') return;

    double number(String key) => (message[key] as num?)?.toDouble() ?? 0;
    int? integer(String key) => (message[key] as num?)?.toInt();
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

  void _sendState() {
    final port = _port;
    if (port == null) return;
    port.postMessage(
      jsonEncode(<String, Object?>{
        'type': 'state',
        'versionId': widget.versionId.trim(),
        'selectionEnabled': widget.selectionEnabled,
        'selectedSelector': widget.selectedSelector?.trim() ?? '',
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_bundle == null || _srcdoc == null) return widget.fallback;
    return HtmlElementView(viewType: _viewType);
  }
}

class _PreviewFile {
  const _PreviewFile({
    required this.path,
    required this.mimeType,
    required this.dataBase64,
    required this.bytes,
  });

  final String path;
  final String mimeType;
  final String dataBase64;
  final List<int> bytes;
}

Map<String, _PreviewFile>? _parseBundle(List<Map<String, Object?>> rawFiles) {
  if (rawFiles.isEmpty || rawFiles.length > _maxFileCount) return null;
  final files = <String, _PreviewFile>{};
  var totalBytes = 0;
  try {
    for (final raw in rawFiles) {
      final path = (raw['file'] as String? ?? '').trim();
      final mimeType = (raw['mimeType'] as String? ?? '').trim();
      final dataBase64 = (raw['dataBase64'] as String? ?? '').trim();
      if (!_isSafePath(path) ||
          mimeType.isEmpty ||
          dataBase64.isEmpty ||
          files.containsKey(path)) {
        return null;
      }
      final bytes = base64Decode(dataBase64);
      if (bytes.length > _maxFileBytes) return null;
      totalBytes += bytes.length;
      if (totalBytes > _maxBundleBytes) return null;
      files[path] = _PreviewFile(
        path: path,
        mimeType: mimeType,
        dataBase64: dataBase64,
        bytes: bytes,
      );
    }
  } catch (_) {
    return null;
  }
  return files.containsKey('index.html') ? files : null;
}

bool _isSafePath(String path) {
  if (path.isEmpty ||
      path.length > 512 ||
      path.startsWith('/') ||
      path.endsWith('/') ||
      path.contains(r'\') ||
      path.contains('\u0000') ||
      path.contains('?') ||
      path.contains('#')) {
    return false;
  }
  return path.split('/').every(
        (part) =>
            part.isNotEmpty &&
            part != '.' &&
            part != '..' &&
            part.length <= 255,
      );
}

String _buildSrcdoc(Map<String, _PreviewFile> files, String versionId) {
  final index = files['index.html']!;
  final htmlText = utf8.decode(index.bytes, allowMalformed: false);
  final cache = <String, String>{};
  final rewritten = _rewriteHtml(htmlText, files, cache, 'index.html');
  final bootstrap = _bootstrapScript(versionId);
  const csp = "default-src 'none'; "
      "script-src 'unsafe-inline' data: blob:; "
      "style-src 'unsafe-inline' data: blob:; "
      "img-src data: blob:; "
      "font-src data: blob:; "
      "media-src data: blob:; "
      "connect-src 'none'; "
      "frame-src 'none'; "
      "child-src 'none'; "
      "worker-src 'none'; "
      "object-src 'none'; "
      "form-action 'none'; "
      "base-uri 'none'; "
      "navigate-to 'none'";

  final securityHead =
      '<meta http-equiv="Content-Security-Policy" content="${htmlEscape.convert(csp)}">'
      '<meta name="referrer" content="no-referrer">'
      '<script>$bootstrap</script>';

  final withoutBase = rewritten.replaceAll(
    RegExp(r'<base\b[^>]*>', caseSensitive: false),
    '',
  );
  final head = RegExp(r'<head\b[^>]*>', caseSensitive: false);
  final match = head.firstMatch(withoutBase);
  if (match != null) {
    return withoutBase.replaceRange(match.end, match.end, securityHead);
  }
  final htmlTag = RegExp(r'<html\b[^>]*>', caseSensitive: false);
  final htmlMatch = htmlTag.firstMatch(withoutBase);
  if (htmlMatch != null) {
    return withoutBase.replaceRange(
      htmlMatch.end,
      htmlMatch.end,
      '<head>$securityHead</head>',
    );
  }
  return '<!doctype html><html><head>$securityHead</head><body>$withoutBase</body></html>';
}

String _rewriteHtml(
  String source,
  Map<String, _PreviewFile> files,
  Map<String, String> cache,
  String basePath,
) {
  var output = source.replaceAllMapped(
    RegExp(r'''(\b(?:src|href|poster)\s*=\s*["'])([^"']+)(["'])''',
        caseSensitive: false),
    (match) {
      final ref = match.group(2)!;
      final path = _resolvePath(basePath, ref, files);
      if (path == null) return match.group(0)!;
      return '${match.group(1)}${_materializeUri(path, files, cache, <String>{})}${match.group(3)}';
    },
  );
  output = output.replaceAllMapped(
    RegExp(r'''url\(\s*(["']?)([^)"']+)\1\s*\)''', caseSensitive: false),
    (match) {
      final ref = match.group(2)!;
      final path = _resolvePath(basePath, ref, files);
      if (path == null) return match.group(0)!;
      return 'url("${_materializeUri(path, files, cache, <String>{})}")';
    },
  );
  return output;
}

String _materializeUri(
  String path,
  Map<String, _PreviewFile> files,
  Map<String, String> cache,
  Set<String> visiting,
) {
  final cached = cache[path];
  if (cached != null) return cached;
  final file = files[path];
  if (file == null) return '';
  if (!visiting.add(path)) return _rawDataUri(file);

  var bytes = file.bytes;
  final mime = file.mimeType.toLowerCase();
  if (mime.contains('css') ||
      mime.contains('javascript') ||
      mime.endsWith('/json') ||
      mime.startsWith('text/')) {
    try {
      var text = utf8.decode(bytes, allowMalformed: false);
      if (mime.contains('css')) {
        text = text.replaceAllMapped(
          RegExp(r'''url\(\s*(["']?)([^)"']+)\1\s*\)''', caseSensitive: false),
          (match) {
            final nested = _resolvePath(path, match.group(2)!, files);
            if (nested == null) return match.group(0)!;
            return 'url("${_materializeUri(nested, files, cache, visiting)}")';
          },
        );
      } else if (mime.contains('javascript')) {
        text = _rewriteModuleSpecifiers(text, path, files, cache, visiting);
      }
      bytes = utf8.encode(text);
    } catch (_) {
      visiting.remove(path);
      return _rawDataUri(file);
    }
  }

  final uri = 'data:${file.mimeType};base64,${base64Encode(bytes)}';
  cache[path] = uri;
  visiting.remove(path);
  return uri;
}

String _rewriteModuleSpecifiers(
  String source,
  String basePath,
  Map<String, _PreviewFile> files,
  Map<String, String> cache,
  Set<String> visiting,
) {
  var output = source.replaceAllMapped(
    RegExp(r'''(\bfrom\s*["'])([^"']+)(["'])'''),
    (match) {
      final nested = _resolvePath(basePath, match.group(2)!, files);
      if (nested == null) return match.group(0)!;
      return '${match.group(1)}${_materializeUri(nested, files, cache, visiting)}${match.group(3)}';
    },
  );
  output = output.replaceAllMapped(
    RegExp(r'''(\bimport\s*["'])([^"']+)(["'])'''),
    (match) {
      final nested = _resolvePath(basePath, match.group(2)!, files);
      if (nested == null) return match.group(0)!;
      return '${match.group(1)}${_materializeUri(nested, files, cache, visiting)}${match.group(3)}';
    },
  );
  output = output.replaceAllMapped(
    RegExp(r'''(\bimport\s*\(\s*["'])([^"']+)(["']\s*\))'''),
    (match) {
      final nested = _resolvePath(basePath, match.group(2)!, files);
      if (nested == null) return match.group(0)!;
      return '${match.group(1)}${_materializeUri(nested, files, cache, visiting)}${match.group(3)}';
    },
  );
  return output;
}

String? _resolvePath(
  String basePath,
  String rawRef,
  Map<String, _PreviewFile> files,
) {
  final ref = rawRef.trim();
  if (ref.isEmpty ||
      ref.startsWith('#') ||
      ref.startsWith('data:') ||
      ref.startsWith('blob:') ||
      ref.startsWith('javascript:') ||
      ref.startsWith('mailto:') ||
      ref.startsWith('tel:') ||
      ref.startsWith('//') ||
      RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(ref)) {
    return null;
  }
  final clean = ref.split('#').first.split('?').first;
  if (clean.isEmpty) return null;
  final parts = <String>[];
  if (!clean.startsWith('/')) {
    final base = basePath.split('/');
    if (base.isNotEmpty) base.removeLast();
    parts.addAll(base);
  }
  for (final segment in clean.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (parts.isEmpty) return null;
      parts.removeLast();
      continue;
    }
    parts.add(segment);
  }
  final path = parts.join('/');
  return files.containsKey(path) ? path : null;
}

String _rawDataUri(_PreviewFile file) =>
    'data:${file.mimeType};base64,${file.dataBase64}';

String _bootstrapScript(String versionId) {
  final encodedVersion = jsonEncode(versionId);
  return '''
(() => {
  'use strict';
  const expectedVersionId = $encodedVersion;
  let privilegedPort = null;
  let selectionEnabled = false;
  let selectedSelector = '';

  const escapeSelector = value =>
    (window.CSS && CSS.escape)
      ? CSS.escape(value)
      : String(value).replace(/[^a-zA-Z0-9_-]/g, ch => '\\\\' + ch);

  const clearSelection = () => {
    document.querySelectorAll('[data-pandora-preview-selected="true"]')
      .forEach(node => node.removeAttribute('data-pandora-preview-selected'));
  };

  const ensureSelectionStyle = () => {
    if (document.getElementById('pandora-preview-selection-style')) return;
    const style = document.createElement('style');
    style.id = 'pandora-preview-selection-style';
    style.textContent =
      '[data-pandora-preview-selected="true"]{outline:2px solid rgba(25,25,25,.72)!important;outline-offset:2px!important}';
    document.head.appendChild(style);
  };

  const applySelectedSelector = () => {
    clearSelection();
    if (!selectedSelector) return;
    try {
      const node = document.querySelector(selectedSelector);
      if (node) {
        ensureSelectionStyle();
        node.setAttribute('data-pandora-preview-selected', 'true');
      }
    } catch (_) {}
  };

  const selectorFor = node => {
    const semanticId = node.getAttribute('data-pandora-id');
    if (semanticId) return '[data-pandora-id="' + escapeSelector(semanticId) + '"]';
    if (node.id) return '#' + escapeSelector(node.id);
    const parts = [];
    let current = node;
    while (current && current.nodeType === 1 && current !== document.documentElement) {
      let part = current.tagName.toLowerCase();
      const owner = current.parentElement;
      if (owner) {
        const peers = Array.from(owner.children)
          .filter(child => child.tagName === current.tagName);
        if (peers.length > 1) {
          part += ':nth-of-type(' + (peers.indexOf(current) + 1) + ')';
        }
      }
      parts.unshift(part);
      current = owner;
      if (parts.length >= 8) break;
    }
    return parts.join(' > ');
  };

  window.addEventListener('message', (event) => {
    if (!event.isTrusted || event.ports.length !== 1) return;
    const message = event.data;
    if (!message ||
        message.type !== 'pandora-preview-init' ||
        message.versionId !== expectedVersionId ||
        privilegedPort !== null) {
      return;
    }
    event.stopImmediatePropagation();
    const port = event.ports[0];
    privilegedPort = port;
    port.onmessage = portEvent => {
      if (typeof portEvent.data !== 'string') return;
      let command;
      try { command = JSON.parse(portEvent.data); } catch (_) { return; }
      if (!command || command.versionId !== expectedVersionId || command.type !== 'state') return;
      selectionEnabled = command.selectionEnabled === true;
      selectedSelector = typeof command.selectedSelector === 'string'
        ? command.selectedSelector
        : '';
      applySelectedSelector();
    };
    port.postMessage(JSON.stringify({
      type: 'ready',
      versionId: expectedVersionId
    }));
  }, true);

  document.addEventListener('click', (event) => {
    const anchor = event.target && event.target.closest
      ? event.target.closest('a[href]')
      : null;
    if (anchor) {
      const href = String(anchor.getAttribute('href') || '').trim();
      if (/^(?:[a-zA-Z][a-zA-Z0-9+.-]*:|\\/\\/)/.test(href) &&
          !href.startsWith('data:') &&
          !href.startsWith('blob:')) {
        event.preventDefault();
        event.stopImmediatePropagation();
        return;
      }
    }

    if (!selectionEnabled || !privilegedPort) return;
    const element = document.elementFromPoint(event.clientX, event.clientY);
    if (!element || element === document.documentElement || element === document.body) return;

    event.preventDefault();
    event.stopImmediatePropagation();
    clearSelection();
    ensureSelectionStyle();
    element.setAttribute('data-pandora-preview-selected', 'true');
    selectedSelector = selectorFor(element);

    const rect = element.getBoundingClientRect();
    const lineRaw = element.getAttribute('data-pandora-source-line');
    const sourceLine = lineRaw && /^\\d+\$/.test(lineRaw) ? Number(lineRaw) : null;
    const hashRoute = location.hash && location.hash.startsWith('#/')
      ? location.hash.substring(1)
      : '';

    privilegedPort.postMessage(JSON.stringify({
      type: 'selection',
      versionId: expectedVersionId,
      tag: element.tagName ? element.tagName.toLowerCase() : '',
      selector: selectedSelector,
      text: String(element.textContent || '').trim().slice(0, 500),
      semanticId: String(element.getAttribute('data-pandora-id') || ''),
      role: String(element.getAttribute('role') || ''),
      accessibleName: String(
        element.getAttribute('aria-label') ||
        element.getAttribute('title') ||
        ''
      ),
      route: hashRoute || '/',
      sourceFile: String(
        element.getAttribute('data-pandora-source-file') || 'index.html'
      ),
      sourceLine,
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height
    }));
  }, true);
})();
''';
}

const String _unavailableDocument = '<!doctype html><html><head>'
    '<meta http-equiv="Content-Security-Policy" '
    'content="default-src &#39;none&#39;; connect-src &#39;none&#39;; '
    'frame-src &#39;none&#39;; form-action &#39;none&#39;">'
    '</head><body></body></html>';
