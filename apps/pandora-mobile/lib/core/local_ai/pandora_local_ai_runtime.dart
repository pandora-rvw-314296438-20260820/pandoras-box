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

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void keepResident({Duration idleFor = defaultIdleUnloadDelay}) {
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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_suspendAndUnload());
    }
  }

  Future<void> _idleUnload() async {
    _idleUnloadTimer = null;
    try {
      final status = await PandoraLocalAi.instance.status();
      if (!status.loaded) return;
      await PandoraLocalAi.instance.unload();
    } catch (_) {
      // Idle cleanup is intentionally silent.
    }
  }

  Future<void> _suspendAndUnload() async {
    if (_suspending) return;
    _suspending = true;
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
