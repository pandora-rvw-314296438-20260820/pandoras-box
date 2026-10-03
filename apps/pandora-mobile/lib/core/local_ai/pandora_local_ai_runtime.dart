import 'dart:async';

import 'package:flutter/widgets.dart';

import 'pandora_local_ai.dart';

/// Owns the phone-local model lifetime for the whole Pandora application.
///
/// Screens may request warm/generation work, but navigation between screens
/// must not tear down a shared Qwen load. The runtime unloads only after the
/// application-wide idle window, explicit recovery/unload, or app background.
class PandoraLocalAiRuntime with WidgetsBindingObserver {
  PandoraLocalAiRuntime._();

  static final PandoraLocalAiRuntime instance = PandoraLocalAiRuntime._();

  static const Duration defaultIdleUnloadDelay = Duration(minutes: 2);

  Timer? _idleUnloadTimer;
  bool _started = false;
  bool _suspending = false;
  bool _foreground = true;
  int _residencyEpoch = 0;
  Future<bool>? _prewarming;
  Future<bool>? _warming;
  ({String key, String turnId, int epoch})? _conversation;

  int get residencyEpoch => _residencyEpoch;

  bool canContinueConversation(
          {required String conversationKey,
          required String previousTurnId,
          required bool loaded}) =>
      loaded &&
      _conversation?.key == conversationKey &&
      _conversation?.turnId == previousTurnId &&
      _conversation?.epoch == _residencyEpoch;

  void recordConversation(
      {required String conversationKey,
      required String completedTurnId,
      required int residencyEpoch}) {
    if (residencyEpoch != _residencyEpoch || !_foreground || _suspending) {
      return;
    }
    _conversation =
        (key: conversationKey, turnId: completedTurnId, epoch: residencyEpoch);
  }

  void invalidateConversation() => _conversation = null;

  /// One application-owned warm operation serves explicit and background callers.
  Future<bool> ensureWarm() {
    if (!_foreground || _suspending || !PandoraLocalAiPreference.cachedEnabled) {
      return Future<bool>.value(false);
    }
    final current = _warming;
    if (current != null) return current;
    final epoch = _residencyEpoch;
    late final Future<bool> work;
    work = () async {
      try {
        final warmed = await PandoraLocalAi.instance.warm();
        if (epoch != _residencyEpoch ||
            !_foreground ||
            !PandoraLocalAiPreference.cachedEnabled) {
          invalidateConversation();
          try {
            await PandoraLocalAi.instance.unload();
          } catch (_) {}
          return false;
        }
        return warmed;
      } catch (_) {
        return false;
      } finally {
        if (identical(_warming, work)) _warming = null;
      }
    }();
    _warming = work;
    return work;
  }

  /// Eligibility is re-read after the bounded idle delay; this never generates a
  /// synthetic prompt or resets a conversation, and never delays a cloud turn.
  Future<bool> prewarm(
      {required bool Function() stillEligible,
      Duration delay = const Duration(milliseconds: 800)}) {
    final current = _prewarming;
    if (current != null) return current;
    start();
    final epoch = _residencyEpoch;
    late final Future<bool> work;
    work = () async {
      try {
        await Future<void>.delayed(delay);
        bool eligible() =>
            _started &&
            _foreground &&
            !_suspending &&
            epoch == _residencyEpoch &&
            PandoraLocalAiPreference.cachedEnabled &&
            stillEligible();
        if (!eligible()) return false;
        final status = await PandoraLocalAi.instance.status();
        if (!eligible() || !status.supported || !status.configured) {
          return false;
        }
        final readiness = PandoraLocalAiRouter.decide(
          message: 'Prepare phone intelligence.',
          hasAttachment: false,
          hasProjectContext: false,
          hasSelectedCapability: false,
          hasCharacterContext: false,
          status: status,
        );
        if (!readiness.useLocal) return false;
        if (!status.loaded && !await ensureWarm()) return false;
        if (!eligible()) return false;
        keepResident();
        return true;
      } catch (_) {
        return false;
      } finally {
        if (identical(_prewarming, work)) _prewarming = null;
      }
    }();
    _prewarming = work;
    return work;
  }

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(PandoraLocalAiPreference.load());
  }

  void keepResident({Duration idleFor = defaultIdleUnloadDelay}) {
    if (!PandoraLocalAiPreference.cachedEnabled) {
      unawaited(unload());
      return;
    }
    start();
    _idleUnloadTimer?.cancel();
    _idleUnloadTimer = Timer(idleFor, () {
      unawaited(_idleUnload());
    });
  }

  void cancelIdleUnload() {
    _idleUnloadTimer?.cancel();
    _idleUnloadTimer = null;
  }

  Future<void> unload() async {
    _residencyEpoch += 1;
    invalidateConversation();
    cancelIdleUnload();
    try {
      await PandoraLocalAi.instance.cancel();
    } catch (_) {
      // Continue to unload; native cancellation is best-effort during recovery.
    }
    try {
      await PandoraLocalAi.instance.unload();
    } catch (_) {
      // Local cleanup must never break Pandora's cloud fallback path.
    }
  }

  Future<void> stop() async {
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      _started = false;
    }
    await _suspendAndUnload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _foreground = true;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      unawaited(_suspendAndUnload());
    }
  }

  Future<void> _idleUnload() async {
    _idleUnloadTimer = null;
    try {
      final status = await PandoraLocalAi.instance.status();
      if (!status.loaded) return;
      _residencyEpoch += 1;
      invalidateConversation();
      await PandoraLocalAi.instance.unload();
    } catch (_) {
      // Idle cleanup is intentionally silent.
    }
  }

  Future<void> _suspendAndUnload() async {
    if (_suspending) return;
    _suspending = true;
    _residencyEpoch += 1;
    invalidateConversation();
    cancelIdleUnload();
    try {
      try {
        await PandoraLocalAi.instance.cancel();
      } catch (_) {
        // Continue to unload; Android may already be suspending the process.
      }
      try {
        await PandoraLocalAi.instance.unload();
      } catch (_) {
        // Android may already be tearing down the process.
      }
    } finally {
      _suspending = false;
    }
  }
}
