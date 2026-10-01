import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      'pandora-${_projectRef(supabaseUrl)}-secure-auth-session-v1';

  static Future<void> clearLegacyPersistedSession(String supabaseUrl) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(legacySessionKey(supabaseUrl));
  }
}

/// Supabase session persistence backed by flutter_secure_storage.
///
/// Android uses Keystore-backed encryption and iOS uses Keychain storage.
/// No access or refresh token is written to SharedPreferences.
class PandoraSecureSupabaseSessionStorage extends LocalStorage {
  PandoraSecureSupabaseSessionStorage({
    required this.persistSessionKey,
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  final String persistSessionKey;
  final FlutterSecureStorage _storage;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() =>
      _storage.containsKey(key: persistSessionKey);

  @override
  Future<String?> accessToken() =>
      _storage.read(key: persistSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(
        key: persistSessionKey,
        value: persistSessionString,
      );

  @override
  Future<void> removePersistedSession() =>
      _storage.delete(key: persistSessionKey);
}
