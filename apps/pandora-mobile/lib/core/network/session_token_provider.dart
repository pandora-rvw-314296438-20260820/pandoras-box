import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class SessionTokenProvider {
  Future<String?> accessToken();
}

class SupabaseSessionTokenProvider implements SessionTokenProvider {
  const SupabaseSessionTokenProvider(this.client);

  final SupabaseClient client;

  @override
  Future<String?> accessToken() async {
    final token = client.auth.currentSession?.accessToken.trim();
    return token == null || token.isEmpty ? null : token;
  }
}
