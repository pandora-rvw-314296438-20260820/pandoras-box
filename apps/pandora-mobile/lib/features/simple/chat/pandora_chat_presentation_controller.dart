import 'dart:async';
import 'dart:ui' show FlutterView, Size;

import 'package:flutter/widgets.dart';

/// Exactly one foreground surface can own the chat viewport.
enum PandoraChatSurface { none, picker, drawer, context }

enum PandoraChatDrawerKind { primary, recent }

@immutable
class PandoraChatPresentationState {
  const PandoraChatPresentationState({
    this.surface = PandoraChatSurface.none,
    this.pendingSurface,
    this.keyboardInset = 0,
    this.viewportSize = Size.zero,
    this.composerExtent = 0,
    this.revision = 0,
    this.drawerKind = PandoraChatDrawerKind.primary,
    this.intentRevision = 0,
  });

  final PandoraChatSurface surface;
  final PandoraChatSurface? pendingSurface;
  final double keyboardInset;
  final Size viewportSize;
  final double composerExtent;
  final int revision;
  final PandoraChatDrawerKind drawerKind;

  /// Advances for a new open/dismiss intent, not for layout or IME frames.
  final int intentRevision;

  bool get keyboardVisible => keyboardInset > 0;
  bool get transitioning => pendingSurface != null;
}

/// Serializes IME, modal picker, drawer and back intents for the retained shell.
///
/// Bind [attachView] from didChangeDependencies. The shell opens its Scaffold
/// drawer only after [value.surface] becomes [PandoraChatSurface.drawer], and
/// reports external drawer dismissal with [reportDrawer]. No timed guess about
/// keyboard animation may display a second foreground surface.
class PandoraChatPresentationController
    extends ValueNotifier<PandoraChatPresentationState>
    with WidgetsBindingObserver {
  PandoraChatPresentationController({required this.composerFocus})
      : super(const PandoraChatPresentationState()) {
    WidgetsBinding.instance.addObserver(this);
    composerFocus.addListener(_composerFocusChanged);
  }

  final FocusNode composerFocus;
  FlutterView? _view;
  FocusScopeNode? _drawerFocus;
  Completer<bool>? _transition;
  bool _disposed = false;

  /// The shell owns this scope's lifetime; only the one mounted modal drawer
  /// attaches it. Its search field can then own IME without reviving composer
  /// focus or confusing a late composer keyboard frame with drawer input.
  void attachDrawerFocus(FocusScopeNode focus) => _drawerFocus = focus;

  bool get drawerOwnsKeyboard =>
      value.surface == PandoraChatSurface.drawer &&
      (_drawerFocus?.hasFocus ?? false) &&
      !composerFocus.hasFocus;

  void _composerFocusChanged() {
    if (_disposed) return;
    // Focus precedes the platform's first IME metric and can also disappear
    // before its final metric. Notify every Back owner at both boundaries.
    _publish(surface: value.surface, pending: value.pendingSurface);
  }

  void attachView(FlutterView view) {
    _view = view;
    // Attachment can happen while an ancestor is building. Initial metrics do
    // not represent a presentation intent and must not notify that ancestor.
    final inset = view.viewInsets.bottom / view.devicePixelRatio;
    if (inset == value.keyboardInset) return;
    final previous = value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !identical(_view, view) || value != previous) return;
      reportKeyboardInset(inset);
    });
  }

  @override
  void didChangeMetrics() {
    final view = _view;
    if (view == null || _disposed) return;
    reportKeyboardInset(view.viewInsets.bottom / view.devicePixelRatio);
  }

  /// Also usable by tests that exercise intermediate IME animation frames.
  void reportKeyboardInset(double inset) {
    if (_disposed) return;
    final bounded = inset.isFinite && inset > 0 ? inset : 0.0;
    if (bounded == value.keyboardInset) return;
    final requiresClearViewport = value.surface == PandoraChatSurface.picker ||
        (value.surface == PandoraChatSurface.drawer && !drawerOwnsKeyboard);
    final target = value.pendingSurface ??
        (bounded > 0 && requiresClearViewport ? value.surface : null);
    final complete = bounded == 0 && target != null;
    if (bounded > 0 && target != null) {
      // IME metrics can arrive a frame after the open intent. Reconcile that
      // race by withholding the surface until the actual inset returns to zero.
      composerFocus.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
    }
    _publish(
      surface: complete
          ? target
          : (target != null ? PandoraChatSurface.none : value.surface),
      pending: complete ? null : target,
      keyboardInset: bounded,
    );
    if (complete) _completeTransition(true);
  }

  /// Actual LayoutBuilder constraints, never full screen size minus a second
  /// independently applied IME inset. Notification is deferred out of layout.
  void reportLayout({
    required Size viewportSize,
    required double composerExtent,
  }) {
    if (_disposed ||
        (viewportSize == value.viewportSize &&
            composerExtent == value.composerExtent)) {
      return;
    }
    final revision = value.revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || revision != value.revision) return;
      _publish(
        surface: value.surface,
        pending: value.pendingSurface,
        viewportSize: viewportSize,
        composerExtent: composerExtent,
      );
    });
  }

  Future<bool> showPicker() => _show(PandoraChatSurface.picker);

  /// Context routes wait for the composer's IME before opening, then may own
  /// their own text field and its keyboard (for example Rename conversation).
  Future<bool> showContext() =>
      _show(PandoraChatSurface.context, replaceCurrent: true);
  Future<bool> showDrawer({
    PandoraChatDrawerKind kind = PandoraChatDrawerKind.primary,
  }) =>
      _show(PandoraChatSurface.drawer, drawerKind: kind);

  Future<bool> _show(
    PandoraChatSurface target, {
    PandoraChatDrawerKind? drawerKind,
    bool replaceCurrent = false,
  }) {
    if (_disposed) return Future<bool>.value(false);
    final sameDrawer =
        target != PandoraChatSurface.drawer || drawerKind == value.drawerKind;
    if (!replaceCurrent &&
        value.surface == target &&
        value.pendingSurface == null &&
        sameDrawer) {
      return Future<bool>.value(true);
    }
    if (!replaceCurrent &&
        value.pendingSurface == target &&
        _transition != null &&
        sameDrawer) {
      return _transition!.future;
    }
    _completeTransition(false);
    final transition = Completer<bool>();
    _transition = transition;
    composerFocus.unfocus();
    // Focus may currently be in the picker rather than the composer.
    FocusManager.instance.primaryFocus?.unfocus();
    final view = _view;
    final currentInset = view == null
        ? value.keyboardInset
        : view.viewInsets.bottom / view.devicePixelRatio;
    if (currentInset > 0) {
      _publish(
        surface: PandoraChatSurface.none,
        pending: target,
        keyboardInset: currentInset,
        drawerKind: drawerKind,
        intentRevision: value.intentRevision + 1,
      );
    } else {
      _publish(
        surface: target,
        pending: null,
        keyboardInset: 0,
        drawerKind: drawerKind,
        intentRevision: value.intentRevision + 1,
      );
      _completeTransition(true);
    }
    return transition.future;
  }

  void closeSurface() {
    if (_disposed) return;
    _completeTransition(false);
    if (value.surface == PandoraChatSurface.none &&
        value.pendingSurface == null) {
      return;
    }
    _publish(
      surface: PandoraChatSurface.none,
      pending: null,
      intentRevision: value.intentRevision + 1,
    );
  }

  void reportDrawer(
    bool open, {
    PandoraChatDrawerKind? kind,
    int? expectedIntent,
  }) {
    if (_disposed) return;
    if (!open) {
      if (value.surface == PandoraChatSurface.drawer &&
          (kind == null || kind == value.drawerKind) &&
          (expectedIntent == null || expectedIntent == value.intentRevision)) {
        closeSurface();
      }
      return;
    }
    // External edge gestures must respect the same transition. The shell
    // disables unmanaged drawer dragging while the IME is visible.
    if (value.surface == PandoraChatSurface.none && !value.transitioning) {
      unawaited(showDrawer(kind: kind ?? PandoraChatDrawerKind.primary));
    }
  }

  /// Returns true if presentation consumed Back. It never cancels a generation.
  bool handleBack() {
    if (_disposed) return false;
    if (value.surface != PandoraChatSurface.none || value.transitioning) {
      closeSurface();
      return true;
    }
    if (value.keyboardVisible || composerFocus.hasFocus) {
      composerFocus.unfocus();
      return true;
    }
    return false;
  }

  void _publish({
    required PandoraChatSurface surface,
    required PandoraChatSurface? pending,
    double? keyboardInset,
    Size? viewportSize,
    double? composerExtent,
    PandoraChatDrawerKind? drawerKind,
    int? intentRevision,
  }) {
    value = PandoraChatPresentationState(
      surface: surface,
      pendingSurface: pending,
      keyboardInset: keyboardInset ?? value.keyboardInset,
      viewportSize: viewportSize ?? value.viewportSize,
      composerExtent: composerExtent ?? value.composerExtent,
      revision: value.revision + 1,
      drawerKind: drawerKind ?? value.drawerKind,
      intentRevision: intentRevision ?? value.intentRevision,
    );
  }

  void _completeTransition(bool accepted) {
    final transition = _transition;
    _transition = null;
    if (transition != null && !transition.isCompleted) {
      transition.complete(accepted);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    composerFocus.removeListener(_composerFocusChanged);
    WidgetsBinding.instance.removeObserver(this);
    _completeTransition(false);
    super.dispose();
  }
}
