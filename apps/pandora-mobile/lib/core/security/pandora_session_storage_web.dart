import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

// Accessing sessionStorage can throw when the browser blocks storage.
// Probe lazily so email sign-in and app startup still work in that browser.
web.Storage? _safeTabStorage() {
  try {
    final storage = web.window.sessionStorage;
    const probeKey = 'pandora-client-pkce-storage-probe';
    storage.setItem(probeKey, '1');
    final available = storage.getItem(probeKey) == '1';
    storage.removeItem(probeKey);
    return available ? storage : null;
  } catch (_) {
    return null;
  }
}

bool pandoraCanCompleteFacebookRedirect() => _safeTabStorage() != null;

GotrueAsyncStorage pandoraPkceStorage() => const _PandoraTabPkceStorage();

class _PandoraTabPkceStorage extends GotrueAsyncStorage {
  const _PandoraTabPkceStorage();

  String _key(String key) => 'pandora-client-pkce-$key';

  @override
  Future<String?> getItem({required String key}) async =>
      _safeTabStorage()?.getItem(_key(key));

  @override
  Future<void> removeItem({required String key}) async {
    _safeTabStorage()?.removeItem(_key(key));
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    final storage = _safeTabStorage();
    if (storage == null) {
      throw StateError('Browser tab storage is unavailable');
    }
    storage.setItem(_key(key), value);
  }
}
