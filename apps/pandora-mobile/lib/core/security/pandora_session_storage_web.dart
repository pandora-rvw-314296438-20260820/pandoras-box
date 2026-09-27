import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

import '../../pandora_config.dart';

final _tabStorage = web.window.sessionStorage;
final _sessionKey =
    'pandora-client-sb-${Uri.parse(PandoraConfig.supabaseUrl).host.split('.').first}-auth-token';

LocalStorage pandoraSessionStorage() => const _PandoraTabSessionStorage();
GotrueAsyncStorage pandoraPkceStorage() => const _PandoraTabPkceStorage();

class _PandoraTabSessionStorage extends LocalStorage {
  const _PandoraTabSessionStorage();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async =>
      _tabStorage.getItem(_sessionKey) != null;

  @override
  Future<String?> accessToken() async => _tabStorage.getItem(_sessionKey);

  @override
  Future<void> removePersistedSession() async =>
      _tabStorage.removeItem(_sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) async =>
      _tabStorage.setItem(_sessionKey, persistSessionString);
}

class _PandoraTabPkceStorage extends GotrueAsyncStorage {
  const _PandoraTabPkceStorage();

  String _key(String key) => 'pandora-client-pkce-$key';

  @override
  Future<String?> getItem({required String key}) async =>
      _tabStorage.getItem(_key(key));

  @override
  Future<void> removeItem({required String key}) async =>
      _tabStorage.removeItem(_key(key));

  @override
  Future<void> setItem({required String key, required String value}) async =>
      _tabStorage.setItem(_key(key), value);
}
