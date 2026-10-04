import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

@immutable
class PandoraChatViewportItem {
  const PandoraChatViewportItem({required this.id, required this.child});

  /// Stable logical message/turn identity; never an index or display text.
  final String id;
  final Widget child;
}

@immutable
class PandoraChatReadingAnchor {
  const PandoraChatReadingAnchor({
    required this.messageId,
    required this.offset,
  });

  final String messageId;
  final double offset;
}

class _SavedReading {
  const _SavedReading(this.followingLatest, this.anchors, this.scrollOffset);

  final bool followingLatest;
  final List<PandoraChatReadingAnchor> anchors;
  final double scrollOffset;
}

/// Retain this alongside the retained conversation to preserve reading state
/// when its presentation is temporarily detached from the widget tree.
class PandoraChatViewportController extends ChangeNotifier {
  _PandoraChatViewportState? _state;
  final Map<String, _SavedReading> _saved = {};
  bool _followingLatest = true;
  bool _hasNewContent = false;
  bool _requestedLatest = false;

  bool get followingLatest => _followingLatest;
  bool get hasNewContent => _hasNewContent;
  PandoraChatReadingAnchor? get anchor => _state?._currentAnchor;

  /// Explicit participation/return intent. Do not call this for a token event,
  /// keyboard resize, overlay dismissal, or successful retry of an older turn.
  void returnToLatest() {
    _requestedLatest = true;
    _state?._returnToLatest();
  }

  void captureAnchor() => _state?._captureReading();

  void _update(bool followingLatest, bool hasNewContent) {
    if (_followingLatest == followingLatest &&
        _hasNewContent == hasNewContent) {
      return;
    }
    _followingLatest = followingLatest;
    _hasNewContent = hasNewContent;
    notifyListeners();
  }
}

/// Owns reading intent and stable message/offset anchoring. Layout is based on
/// this widget's actual resized constraints, not an inferred screen/IME size.
class PandoraChatViewport extends StatefulWidget {
  PandoraChatViewport({
    super.key,
    required this.threadIdentity,
    required this.revision,
    required List<PandoraChatViewportItem> items,
    this.padding = EdgeInsets.zero,
    this.controller,
    this.onReadingModeChanged,
    this.onViewportChanged,
    this.itemSpacing = 14,
  }) : items = List<PandoraChatViewportItem>.unmodifiable(items) {
    assert(
      items.map((item) => item.id).toSet().length == items.length,
      'Conversation viewport items require unique stable identities.',
    );
  }

  final String threadIdentity;

  /// Changes for every rendered content/lifecycle change, including streamed
  /// text growth that does not change the number of messages.
  final int revision;
  final List<PandoraChatViewportItem> items;
  final EdgeInsets padding;
  final PandoraChatViewportController? controller;
  final ValueChanged<bool>? onReadingModeChanged;
  final ValueChanged<Size>? onViewportChanged;
  final double itemSpacing;

  @override
  State<PandoraChatViewport> createState() => _PandoraChatViewportState();
}

class _PandoraChatViewportState extends State<PandoraChatViewport> {
  late final ScrollController _scroll;
  final GlobalKey _viewportKey = GlobalKey();
  final Map<String, GlobalKey> _itemKeys = {};
  late PandoraChatViewportController _controller;
  bool _ownsController = false;
  bool _followingLatest = true;
  bool _hasNewContent = false;
  bool _userScrolling = false;
  bool _reconcileScheduled = false;
  bool _correcting = false;
  int _readingRevision = 0;
  bool _captureScheduled = false;
  Size _viewportSize = Size.zero;
  List<PandoraChatReadingAnchor> _anchors = const [];
  double? _restoreScrollOffset;
  double _lastScrollOffset = 0;

  PandoraChatReadingAnchor? get _currentAnchor =>
      _anchors.isEmpty ? null : _anchors.first;

  @override
  void initState() {
    super.initState();
    _attachController();
    _restoreReading(widget.threadIdentity);
    _scroll = ScrollController(initialScrollOffset: _restoreScrollOffset ?? 0);
    _lastScrollOffset = _restoreScrollOffset ?? 0;
    _scroll.addListener(_rememberScrollOffset);
    _restoreScrollOffset = null;
    _scheduleReconcile();
  }

  void _attachController() {
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? PandoraChatViewportController();
    assert(
      _controller._state == null || identical(_controller._state, this),
      'A viewport controller may only be attached to one conversation view.',
    );
    _controller._state = this;
  }

  void _saveReading(String thread) {
    _captureReading();
    _controller._saved[thread] = _SavedReading(
      _followingLatest,
      _anchors,
      _scroll.hasClients ? _scroll.offset : _lastScrollOffset,
    );
  }

  void _rememberScrollOffset() {
    if (_scroll.hasClients) _lastScrollOffset = _scroll.offset;
  }

  void _restoreReading(String thread) {
    final saved = _controller._saved[thread];
    _followingLatest =
        _controller._requestedLatest || saved == null || saved.followingLatest;
    _anchors = _followingLatest ? const [] : saved!.anchors;
    _restoreScrollOffset = _followingLatest ? null : saved?.scrollOffset;
    _hasNewContent = false;
    _controller._requestedLatest = false;
    // Attachment happens in build; publish after layout via reconciliation.
  }

  @override
  void didUpdateWidget(PandoraChatViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    final threadChanged = oldWidget.threadIdentity != widget.threadIdentity;
    if (oldWidget.controller != widget.controller) {
      _saveReading(oldWidget.threadIdentity);
      _controller._state = null;
      if (_ownsController) _controller.dispose();
      _attachController();
      _restoreReading(widget.threadIdentity);
    } else if (threadChanged) {
      _saveReading(oldWidget.threadIdentity);
      _readingRevision += 1;
      _userScrolling = false;
      _restoreReading(widget.threadIdentity);
    } else {
      // These are old render objects, before the new message/IME layout. Their
      // visible stable identities are the anchor for the incoming projection.
      _captureReading();
      if (oldWidget.revision != widget.revision && !_followingLatest) {
        _hasNewContent = true;
      }
    }
    final ids = widget.items.map((item) => item.id).toSet();
    _itemKeys.removeWhere((id, _) => !ids.contains(id));
    if (threadChanged ||
        oldWidget.revision != widget.revision ||
        oldWidget.padding != widget.padding ||
        !listEquals(
          oldWidget.items.map((item) => item.id).toList(),
          widget.items.map((item) => item.id).toList(),
        )) {
      _scheduleReconcile();
    }
  }

  RenderBox? get _viewportBox {
    final render = _viewportKey.currentContext?.findRenderObject();
    return render is RenderBox && render.hasSize ? render : null;
  }

  void _captureReading() {
    if (_followingLatest || _correcting) return;
    final viewport = _viewportBox;
    if (viewport == null) return;
    final readableTop = math.min(widget.padding.top, viewport.size.height);
    final readableBottom = math.max(
      readableTop,
      viewport.size.height - widget.padding.bottom,
    );
    final visible = <PandoraChatReadingAnchor>[];
    for (final item in widget.items) {
      final render = _itemKeys[item.id]?.currentContext?.findRenderObject();
      if (render is! RenderBox || !render.hasSize || !render.attached) continue;
      final top = render.localToGlobal(Offset.zero, ancestor: viewport).dy;
      final bottom = top + render.size.height;
      if (bottom <= readableTop || top >= readableBottom) continue;
      visible.add(PandoraChatReadingAnchor(messageId: item.id, offset: top));
    }
    // Retain several visible identities, so removing a compact error row cannot
    // destroy the anchor of an unrelated exchange underneath it.
    if (visible.isNotEmpty) _anchors = List.unmodifiable(visible);
  }

  void _captureAfterUserLayout() {
    if (_captureScheduled) return;
    _captureScheduled = true;
    final thread = widget.threadIdentity;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _captureScheduled = false;
      if (!mounted || thread != widget.threadIdentity) return;
      _captureReading();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _scheduleReconcile() {
    if (_reconcileScheduled) return;
    _reconcileScheduled = true;
    final readingRevision = _readingRevision;
    final thread = widget.threadIdentity;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reconcileScheduled = false;
      if (!mounted || !_scroll.hasClients) return;
      // A gesture or thread switch since scheduling invalidates the old intent.
      if (readingRevision != _readingRevision ||
          thread != widget.threadIdentity ||
          _userScrolling) {
        _captureReading();
        _publish();
        if (!_userScrolling &&
            (thread != widget.threadIdentity || _followingLatest)) {
          _scheduleReconcile();
        }
        return;
      }
      if (_followingLatest) {
        _jumpTo(_scroll.position.maxScrollExtent);
      } else {
        _restoreAnchor();
      }
      _publish();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _restoreAnchor() {
    final viewport = _viewportBox;
    if (viewport == null || !_scroll.hasClients) return;
    final savedOffset = _restoreScrollOffset;
    if (savedOffset != null) {
      _restoreScrollOffset = null;
      _jumpTo(savedOffset);
      _scheduleReconcile();
      return;
    }
    for (final anchor in _anchors) {
      final render =
          _itemKeys[anchor.messageId]?.currentContext?.findRenderObject();
      if (render is! RenderBox || !render.hasSize || !render.attached) continue;
      final offset = render.localToGlobal(Offset.zero, ancestor: viewport).dy;
      final delta = offset - anchor.offset;
      if (delta.abs() > .5) _jumpTo(_scroll.offset + delta);
      return;
    }
    // All anchored messages may have been intentionally removed. Preserve the
    // remaining scroll position instead of guessing a different active turn.
    _jumpTo(_scroll.offset);
  }

  void _jumpTo(double offset) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final target = offset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((position.pixels - target).abs() <= .5) return;
    _correcting = true;
    try {
      _scroll.jumpTo(target);
    } finally {
      _correcting = false;
    }
  }

  void _returnToLatest() {
    if (!mounted) return;
    _readingRevision += 1;
    _userScrolling = false;
    _followingLatest = true;
    _hasNewContent = false;
    _anchors = const [];
    _restoreScrollOffset = null;
    _controller._requestedLatest = false;
    _scheduleReconcile();
    _publish();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || _correcting) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _readingRevision += 1;
      _userScrolling = true;
      _followingLatest = false;
      _captureAfterUserLayout();
      _publish();
    } else if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle &&
        !_userScrolling) {
      // Also includes mouse wheel, trackpad and accessibility scrolling.
      _readingRevision += 1;
      _userScrolling = true;
      _followingLatest = false;
      _captureAfterUserLayout();
      _publish();
    } else if (_userScrolling && notification is ScrollUpdateNotification) {
      _captureAfterUserLayout();
    } else if (_userScrolling && notification is ScrollEndNotification) {
      _userScrolling = false;
      _followingLatest = notification.metrics.extentAfter <= 48;
      if (_followingLatest) {
        _anchors = const [];
        _hasNewContent = false;
      } else {
        _captureAfterUserLayout();
      }
      _publish();
    }
    return false;
  }

  void _publish() {
    if (!mounted) return;
    final changed = _controller.followingLatest != _followingLatest;
    _controller._update(_followingLatest, _hasNewContent);
    if (changed) widget.onReadingModeChanged?.call(_followingLatest);
    // Only changes control visibility; scrolling and token frames do not force
    // an extra rebuild when the reading projection is already identical.
    if (_showLatest != !_followingLatest) {
      setState(() => _showLatest = !_followingLatest);
    }
  }

  bool _showLatest = false;

  @override
  void dispose() {
    _saveReading(widget.threadIdentity);
    _controller._state = null;
    if (_ownsController) _controller.dispose();
    _scroll
      ..removeListener(_rememberScrollOffset)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final nextSize = Size(constraints.maxWidth, constraints.maxHeight);
          if (nextSize != _viewportSize) {
            _viewportSize = nextSize;
            _scheduleReconcile();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _viewportSize == nextSize) {
                widget.onViewportChanged?.call(nextSize);
              }
            });
          }
          final indexById = <String, int>{
            for (var i = 0; i < widget.items.length; i++) widget.items[i].id: i,
          };
          return SizedBox.expand(
            key: _viewportKey,
            child: Stack(
              children: [
                Positioned.fill(
                  child: NotificationListener<ScrollMetricsNotification>(
                    onNotification: (_) {
                      if (!_userScrolling) _scheduleReconcile();
                      return false;
                    },
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScroll,
                      child: ListView.builder(
                        key: const ValueKey<String>('pandora-chat-transcript'),
                        controller: _scroll,
                        padding: widget.padding,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount: widget.items.length,
                        findChildIndexCallback: (key) => key is ValueKey<String>
                            ? indexById[key.value]
                            : null,
                        itemBuilder: (context, index) {
                          final item = widget.items[index];
                          return Padding(
                            key: ValueKey<String>(item.id),
                            padding: EdgeInsets.only(
                              bottom: index == widget.items.length - 1
                                  ? 0
                                  : widget.itemSpacing,
                            ),
                            child: RepaintBoundary(
                              key:
                                  _itemKeys.putIfAbsent(item.id, GlobalKey.new),
                              child: item.child,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                if (_showLatest)
                  Positioned(
                    right: 14,
                    bottom: math.min(
                      widget.padding.bottom + 10,
                      math.max(0, _viewportSize.height - 56),
                    ),
                    child: Semantics(
                      identifier: 'pandora.chat.latest',
                      label: 'Return to latest message',
                      button: true,
                      onTap: _returnToLatest,
                      excludeSemantics: true,
                      child: Material(
                        color: const Color(0xFF242424),
                        elevation: 4,
                        shape: const StadiumBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          key: const ValueKey<String>('pandora-chat-latest'),
                          onTap: _returnToLatest,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 15,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.arrow_downward_rounded,
                                  size: 18,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Latest',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );
}
