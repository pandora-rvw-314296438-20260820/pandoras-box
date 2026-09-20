import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pandora_local_ai.dart';

/// Starts after the first frame. Grants stay in memory; native storage contains
/// only immutable model bytes and unsigned, non-secret integrity metadata.
class PandoraModelLifecycle with WidgetsBindingObserver {
  PandoraModelLifecycle._(this._client);
  final SupabaseClient _client;
  static PandoraModelLifecycle? _instance;
  Timer? _timer;
  Timer? _backgroundUnload;
  StreamSubscription<AuthState>? _auth;
  bool _busy = false;
  bool _visible = true;
  DateTime? _lastManifest;

  static void start(SupabaseClient client) {
    if (_instance != null) return;
    final value = PandoraModelLifecycle._(client);
    _instance = value;
    WidgetsBinding.instance.addObserver(value);
    value._auth = client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedOut) {
        unawaited(PandoraLocalAi.instance.cancel());
      }
      value._lastManifest = null;
      unawaited(value._recover());
    });
    value._timer = Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(value._recover());
    });
    unawaited(value._recover());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    if (_visible) {
      _backgroundUnload?.cancel();
      unawaited(_recover());
    } else if (state == AppLifecycleState.paused) {
      _backgroundUnload?.cancel();
      _backgroundUnload = Timer(const Duration(minutes: 2), () {
        unawaited(PandoraLocalAi.instance.unload());
      });
    }
  }

  Future<void> _recover() async {
    if (_busy || !_visible) return;
    _busy = true;
    try {
      await PandoraLocalAi.instance.prepare();
      // A cached model is prepared without any network or authentication call.
      if (_client.auth.currentSession == null) return;
      final status = await PandoraLocalAi.instance.status();
      final now = DateTime.now().toUtc();
      if (status.localReady && _lastManifest != null &&
          now.difference(_lastManifest!) < const Duration(hours: 1)) return;
      final response = await _client.functions.invoke('pandora-model-manifest')
          .timeout(const Duration(seconds: 10));
      if (response.status != 200 || response.data is! Map) return;
      final data = response.data as Map;
      final manifest = data['model'];
      if (manifest is! Map) return;
      await PandoraLocalAi.instance.configure(
        Map<String, Object?>.from(manifest),
      );
      _lastManifest = now;
    } catch (_) {
      // Cloud remains available. Retain partial bytes and retry with a fresh grant.
    } finally { _busy = false; }
  }
}
