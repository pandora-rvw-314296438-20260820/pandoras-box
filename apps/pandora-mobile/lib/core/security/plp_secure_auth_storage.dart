import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlpSecureAuthStorage extends LocalStorage {
  PlpSecureAuthStorage({
    required String supabaseUrl,
    FlutterSecureStorage? storage,
  })  : _persistSessionKey = _sessionKey(supabaseUrl),
        _storage = storage ??
            FlutterSecureStorage(
              aOptions: const AndroidOptions(
                storageNamespace: 'pandora_plp_auth_v1',
              ),
            );

  final String _persistSessionKey;
  final FlutterSecureStorage _storage;

  static String _sessionKey(String supabaseUrl) {
    final uri = Uri.tryParse(supabaseUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw StateError('Pandora Supabase URL must be an absolute HTTPS URL.');
    }
    final projectRef = uri.host.split('.').first.trim();
    if (projectRef.isEmpty) {
      throw StateError('Pandora Supabase project ref is missing.');
    }
    return 'pandora-plp-$projectRef-auth-session-v1';
  }

  @override
  Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
  }

  @override
  Future<bool> hasAccessToken() =>
      _storage.containsKey(key: _persistSessionKey);

  @override
  Future<String?> accessToken() =>
      _storage.read(key: _persistSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(
        key: _persistSessionKey,
        value: persistSessionString,
      );

  @override
  Future<void> removePersistedSession() =>
      _storage.delete(key: _persistSessionKey);
}
