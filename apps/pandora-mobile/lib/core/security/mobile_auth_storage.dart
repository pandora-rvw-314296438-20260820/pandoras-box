import 'package:shared_preferences/shared_preferences.dart';

class PandoraMobileAuthStorage {
  const PandoraMobileAuthStorage._();

  static String legacySessionKey(String supabaseUrl) {
    final uri = Uri.tryParse(supabaseUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw StateError('Pandora Supabase URL must be an absolute HTTPS URL.');
    }

    final projectRef = uri.host.split('.').first.trim();
    if (projectRef.isEmpty) {
      throw StateError('Pandora Supabase project ref is missing.');
    }

    return 'sb-$projectRef-auth-token';
  }

  static Future<void> clearLegacyPersistedSession(String supabaseUrl) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(legacySessionKey(supabaseUrl));
  }
}
