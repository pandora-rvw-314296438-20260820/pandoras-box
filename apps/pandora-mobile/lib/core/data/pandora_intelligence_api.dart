import 'package:supabase_flutter/supabase_flutter.dart';

import '../platform/pandora_native_io.dart';

class PandoraIntelligenceApi {
  PandoraIntelligenceApi({
    required SupabaseClient client,
    required String organizationId,
  }) : _client = client,
       _organizationId = organizationId;

  final SupabaseClient _client;
  final String _organizationId;

  static const functionName = 'pandora-intelligence-chat';

  Future<PandoraIntelligenceTurn> chat({
    required String message,
    String? threadId,
    String? projectId,
    PandoraTextAttachment? textAttachment,
    PandoraImageAttachment? imageAttachment,
    PandoraIntelligenceMode mode = PandoraIntelligenceMode.auto,
  }) async {
    if (_client.auth.currentSession == null) {
      throw const PandoraIntelligenceException('Please sign in again.');
    }
    final attachments = <Map<String, Object?>>[
      if (textAttachment != null)
        <String, Object?>{
          'kind': 'text',
          'name': textAttachment.name,
          'mimeType': textAttachment.mimeType,
          'text': textAttachment.text,
        },
      if (imageAttachment != null)
        <String, Object?>{
          'kind': 'image',
          'name': imageAttachment.name,
          'mimeType': imageAttachment.mimeType,
          'dataBase64': imageAttachment.dataBase64,
        },
    ];

    try {
      final response = await _client.functions.invoke(
        functionName,
        method: HttpMethod.post,
        headers: <String, String>{'x-organization-id': _organizationId},
        body: <String, Object?>{
          'message': message.trim(),
          if (threadId != null) 'threadId': threadId,
          if (projectId != null) 'projectId': projectId,
          'mode': mode.name,
          if (attachments.isNotEmpty) 'attachments': attachments,
        },
      );
      final payload = _map(response.data);
      if (response.status < 200 ||
          response.status >= 300 ||
          payload['ok'] != true) {
        throw PandoraIntelligenceException(
          _text(
            payload['plainMessage'],
            fallback: 'Pandora intelligence is temporarily unavailable.',
          ),
        );
      }
      return PandoraIntelligenceTurn.fromJson(payload);
    } on FunctionException catch (error) {
      throw PandoraIntelligenceException(
        _text(
          _map(error.details)['plainMessage'],
          fallback: 'Pandora intelligence is temporarily unavailable.',
        ),
      );
    }
  }
}

enum PandoraIntelligenceMode { auto, fast, deep }

class PandoraIntelligenceTurn {
  const PandoraIntelligenceTurn({
    required this.threadId,
    required this.reply,
    required this.intent,
    required this.confidence,
    required this.needsClarification,
    this.clarifyingQuestion,
    this.handoff,
  });

  final String threadId;
  final String reply;
  final String intent;
  final double confidence;
  final bool needsClarification;
  final String? clarifyingQuestion;
  final PandoraIntelligenceHandoff? handoff;

  factory PandoraIntelligenceTurn.fromJson(Map<String, dynamic> json) {
    final handoffJson = _map(json['handoff']);
    return PandoraIntelligenceTurn(
      threadId: _requiredText(json['threadId']),
      reply: _requiredText(json['reply']),
      intent: _text(json['intent'], fallback: 'chat'),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      needsClarification: json['needsClarification'] == true,
      clarifyingQuestion: _optionalText(json['clarifyingQuestion']),
      handoff: handoffJson['required'] == true
          ? PandoraIntelligenceHandoff(
              request: _requiredText(handoffJson['request']),
              projectId: _optionalText(handoffJson['projectId']),
            )
          : null,
    );
  }
}

class PandoraIntelligenceHandoff {
  const PandoraIntelligenceHandoff({required this.request, this.projectId});

  final String request;
  final String? projectId;
}

class PandoraIntelligenceException implements Exception {
  const PandoraIntelligenceException(this.message);
  final String message;

  @override
  String toString() => message;
}

Map<String, dynamic> _map(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : <String, dynamic>{};

String _text(Object? value, {String fallback = ''}) =>
    value is String && value.trim().isNotEmpty ? value.trim() : fallback;

String? _optionalText(Object? value) {
  final result = _text(value);
  return result.isEmpty ? null : result;
}

String _requiredText(Object? value) {
  final result = _text(value);
  if (result.isEmpty) {
    throw const PandoraIntelligenceException(
      'Pandora returned an unreadable intelligence result.',
    );
  }
  return result;
}
