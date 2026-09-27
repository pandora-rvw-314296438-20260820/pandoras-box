import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../pandora_config.dart';

/// Only Supabase Auth's public settings can make the client login visible.
/// A network error, malformed response, or missing key fails closed.
Future<bool> readFacebookProviderEnabled({
  required http.Client client,
  required Uri supabaseUrl,
  required String publishableKey,
}) async {
  if (supabaseUrl.scheme != 'https' || publishableKey.isEmpty) return false;
  try {
    final response = await client.get(
      supabaseUrl.resolve('/auth/v1/settings'),
      headers: <String, String>{'apikey': publishableKey},
    ).timeout(const Duration(seconds: 4));
    if (response.statusCode != 200 || response.bodyBytes.length > 8192) {
      return false;
    }
    final settings = jsonDecode(response.body);
    return settings is Map &&
        settings['external'] is Map &&
        (settings['external'] as Map)['facebook'] == true;
  } catch (_) {
    return false;
  }
}

Future<bool> pandoraFacebookProviderEnabled() async {
  final client = http.Client();
  try {
    return await readFacebookProviderEnabled(
      client: client,
      supabaseUrl: Uri.parse(PandoraConfig.supabaseUrl),
      publishableKey: PandoraConfig.supabasePublishableKey,
    );
  } finally {
    client.close();
  }
}
