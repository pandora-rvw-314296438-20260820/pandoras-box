
import 'package:supabase_flutter/supabase_flutter.dart';

import '../platform/pandora_native_io.dart';

class PandoraIntelligenceApi {
  PandoraIntelligenceApi({
    required SupabaseClient client,
    required String organizationId,
  })  : _client = client,
        _organizationId = organizationId;

  final SupabaseClient _client;
  final String _organizationId;

  static const functionName = 'pandora-intelligence-chat';

  Future<List<PandoraIntelligenceThread>> recentThreads({int limit = 30}) async {
    _requireSession();
    final safeLimit = limit.clamp(1, 100);
    try {
      final rows = await _client
          .from('pandora_intelligence_threads')
          .select('id,project_id,title,status,last_message_at,created_at,updated_at')
          .eq('organization_id', _organizationId)
          .eq('status', 'active')
          .order('last_message_at', ascending: false)
          .limit(safeLimit);
      return (rows as List<dynamic>)
          .map((row) => PandoraIntelligenceThread.fromJson(_map(row)))
          .toList(growable: false);
    } on PostgrestException {
      throw const PandoraIntelligenceException(
        'Pandora could not load conversation history.',
      );
    }
  }

  Future<List<PandoraIntelligenceMessage>> messages(
    String threadId, {
    int limit = 200,
  }) async {
    _requireSession();
    final safeLimit = limit.clamp(1, 500);
    try {
      final rows = await _client
          .from('pandora_intelligence_messages')
          .select('id,thread_id,author_role,content,attachment_manifest,created_at')
          .eq('organization_id', _organizationId)
          .eq('thread_id', threadId)
          .order('created_at')
          .limit(safeLimit);
      return (rows as List<dynamic>)
          .map((row) => PandoraIntelligenceMessage.fromJson(_map(row)))
          .toList(growable: false);
    } on PostgrestException {
      throw const PandoraIntelligenceException(
        'Pandora could not load that conversation.',
      );
    }
  }

  Future<PandoraIntelligenceTurn> chat({
    required String message,
    String? threadId,
    String? projectId,
    PandoraTextAttachment? textAttachment,
    PandoraImageAttachment? imageAttachment,
    PandoraIntelligenceMode mode = PandoraIntelligenceMode.auto,
  }) async {
    _requireSession();
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

  void _requireSession() {
    if (_client.auth.currentSession == null) {
      throw const PandoraIntelligenceException('Please sign in again.');
    }
  }
}

enum PandoraIntelligenceMode { auto, fast, deep }

class PandoraIntelligenceThread {
  const PandoraIntelligenceThread({
    required this.id,
    required this.title,
    required this.status,
    required this.lastMessageAt,
    required this.createdAt,
    this.projectId,
  });

  final String id;
  final String title;
  final String status;
  final DateTime lastMessageAt;
  final DateTime createdAt;
  final String? projectId;

  factory PandoraIntelligenceThread.fromJson(Map<String, dynamic> json) =>
      PandoraIntelligenceThread(
        id: _requiredText(json['id']),
        projectId: _optionalText(json['project_id']),
        title: _text(json['title'], fallback: 'New conversation'),
        status: _text(json['status'], fallback: 'active'),
        lastMessageAt: _date(json['last_message_at']),
        createdAt: _date(json['created_at']),
      );
}

class PandoraIntelligenceMessage {
  const PandoraIntelligenceMessage({
    required this.id,
    required this.threadId,
    required this.authorRole,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String threadId;
  final String authorRole;
  final String content;
  final DateTime createdAt;

  bool get isUser => authorRole == 'user';

  factory PandoraIntelligenceMessage.fromJson(Map<String, dynamic> json) =>
      PandoraIntelligenceMessage(
        id: _requiredText(json['id']),
        threadId: _requiredText(json['thread_id']),
        authorRole: _requiredText(json['author_role']),
        content: _requiredText(json['content']),
        createdAt: _date(json['created_at']),
      );
}

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

DateTime _date(Object? value) {
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw const PandoraIntelligenceException(
    'Pandora returned unreadable conversation history.',
  );
}
