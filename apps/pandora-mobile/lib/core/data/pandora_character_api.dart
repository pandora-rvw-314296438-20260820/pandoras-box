import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

class PandoraCharacterApi {
  PandoraCharacterApi({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String baseUrl = String.fromEnvironment(
    'PANDORA_CHARACTER_BASE_URL',
  );

  static const availableCharacters = <PandoraCharacterProfile>[
    PandoraCharacterProfile(
      id: 'melodee',
      name: 'Melodee',
      description: 'Private local character - memory + canon + roleplay modes',
    ),
  ];
  Future<PandoraCharacterTurn> chat({
    required String characterId,
    required String message,
    String? sessionId,
    String mode = 'auto',
    String responseLength = 'auto',
  }) async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw const PandoraCharacterException('Sign in to use Characters.');
    }
    final payload = await _post(
      '/v1/characters/$characterId/chat',
      token: session.accessToken,
      body: <String, Object?>{
        'message': message.trim(),
        if (sessionId != null) 'session_id': sessionId,
        'mode': mode,
        'response_length': responseLength,
      },
    );
    if (payload['ok'] != true) {
      throw PandoraCharacterException(
        _text(payload['error'], fallback: 'Character generation failed.'),
      );
    }
    return PandoraCharacterTurn.fromJson(payload);
  }

  Future<void> reset({
    required String characterId,
    required String sessionId,
  }) async {
    final session = _client.auth.currentSession;
    if (session == null) return;
    await _post(
      '/v1/characters/$characterId/reset',
      token: session.accessToken,
      body: <String, Object?>{'session_id': sessionId},
    );
  }

  Future<Map<String, Object?>> _post(
    String path, {
    required String token,
    required Map<String, Object?> body,
  }) async {
    if (baseUrl.trim().isEmpty) {
      throw const PandoraCharacterException(
        'Characters are not configured on this build yet.',
      );
    }
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('$baseUrl$path'));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.write(jsonEncode(body));
      final response = await request.close().timeout(
            const Duration(minutes: 6),
          );
      final raw = await utf8.decoder.bind(response).join();
      final decoded =
          raw.trim().isEmpty ? <String, Object?>{} : jsonDecode(raw);
      final payload = decoded is Map
          ? decoded.map((key, value) => MapEntry(key.toString(), value))
          : <String, Object?>{};
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw PandoraCharacterException(
          _text(payload['error'], fallback: 'Character service unavailable.'),
        );
      }
      return payload;
    } on TimeoutException {
      throw const PandoraCharacterException(
        'Character generation is taking too long on the current local machine.',
      );
    } on SocketException {
      throw const PandoraCharacterException(
        'Character service is offline or unreachable.',
      );
    } finally {
      client.close(force: true);
    }
  }

  static String _text(Object? value, {required String fallback}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}

class PandoraCharacterProfile {
  const PandoraCharacterProfile({
    required this.id,
    required this.name,
    required this.description,
  });

  final String id;
  final String name;
  final String description;
}

class PandoraCharacterTurn {
  const PandoraCharacterTurn({
    required this.sessionId,
    required this.reply,
    required this.mode,
    required this.modeSource,
    required this.generationSeconds,
  });

  final String sessionId;
  final String reply;
  final String mode;
  final String modeSource;
  final double generationSeconds;

  factory PandoraCharacterTurn.fromJson(Map<String, Object?> json) =>
      PandoraCharacterTurn(
        sessionId: json['session_id']?.toString() ?? '',
        reply: json['reply']?.toString() ?? '',
        mode: json['mode']?.toString() ?? 'baseline',
        modeSource: json['mode_source']?.toString() ?? 'explicit',
        generationSeconds:
            (json['generation_seconds'] as num?)?.toDouble() ?? 0,
      );
}

class PandoraCharacterException implements Exception {
  const PandoraCharacterException(this.message);

  final String message;

  @override
  String toString() => message;
}
