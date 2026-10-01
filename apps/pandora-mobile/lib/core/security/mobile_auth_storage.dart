import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class PandoraSecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterPandoraSecureKeyValueStore implements PandoraSecureKeyValueStore {
  const FlutterPandoraSecureKeyValueStore();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'pandora_auth_v1',
      preferencesKeyPrefix: 'pandora_auth',
      resetOnError: true,
      migrateOnAlgorithmChange: true,
      migrateWithBackup: false,
    ),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class PandoraSecureAuthStorage extends LocalStorage {
  PandoraSecureAuthStorage(
    String supabaseUrl, {
    PandoraSecureKeyValueStore? secureStore,
  })  : _supabaseUrl = supabaseUrl,
        _sessionKey = PandoraMobileAuthStorage.secureSessionKey(supabaseUrl),
        _secureStore =
            secureStore ?? const FlutterPandoraSecureKeyValueStore();

  final String _supabaseUrl;
  final String _sessionKey;
  final PandoraSecureKeyValueStore _secureStore;

  @override
  Future<void> initialize() async {
    // Never migrate the legacy plaintext/shared-preferences token. Remove it.
    await PandoraMobileAuthStorage.clearLegacyPersistedSession(_supabaseUrl);
  }

  @override
  Future<bool> hasAccessToken() async {
    final persisted = await _secureStore.read(_sessionKey);
    return persisted != null && persisted.trim().isNotEmpty;
  }

  @override
  Future<String?> accessToken() => _secureStore.read(_sessionKey);

  @override
  Future<void> removePersistedSession() => _secureStore.delete(_sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) async {
    if (persistSessionString.trim().isEmpty) {
      await removePersistedSession();
      return;
    }
    await _secureStore.write(_sessionKey, persistSessionString);
  }
}

class PandoraMobileAuthStorage {
  const PandoraMobileAuthStorage._();

  static String _projectRef(String supabaseUrl) {
    final uri = Uri.tryParse(supabaseUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw StateError('Pandora Supabase URL must be an absolute HTTPS URL.');
    }

    final projectRef = uri.host.split('.').first.trim();
    if (projectRef.isEmpty) {
      throw StateError('Pandora Supabase project ref is missing.');
    }
    return projectRef;
  }

  static String legacySessionKey(String supabaseUrl) =>
      'sb-${_projectRef(supabaseUrl)}-auth-token';

  static String secureSessionKey(String supabaseUrl) =>
      'pandora-${_projectRef(supabaseUrl)}-auth-session-v1';

  static Future<void> clearLegacyPersistedSession(String supabaseUrl) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(legacySessionKey(supabaseUrl));
  }
}
