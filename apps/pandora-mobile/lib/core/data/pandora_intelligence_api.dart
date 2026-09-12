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

  Future<List<PandoraIntelligenceThread>> recentThreads({
    int limit = 30,
  }) async {
    _requireSession();
    final safeLimit = limit.clamp(1, 100).toInt();
    try {
      final rows = await _client
          .from('pandora_intelligence_threads')
          .select(
            'id,project_id,title,status,last_message_at,created_at,updated_at',
          )
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
    final safeLimit = limit.clamp(1, 500).toInt();
    try {
      final rows = await _client
          .from('pandora_intelligence_messages')
          .select(
            'id,thread_id,author_role,content,attachment_manifest,created_at',
          )
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

  Future<void> renameThread(String threadId, String title) async {
    final normalized = title.trim();
    if (normalized.isEmpty || normalized.length > 200) {
      throw const PandoraIntelligenceException(
        'Choose a conversation name between 1 and 200 characters.',
      );
    }
    await _manageThread(
      threadId: threadId,
      action: 'rename',
      title: normalized,
    );
  }

  Future<void> archiveThread(String threadId) =>
      _manageThread(threadId: threadId, action: 'archive');

  Future<void> restoreThread(String threadId) =>
      _manageThread(threadId: threadId, action: 'restore');

  Future<void> deleteThread(String threadId) =>
      _manageThread(threadId: threadId, action: 'delete');

  Future<void> associateThreadWithProject(String threadId, String? projectId) =>
      _manageThread(
        threadId: threadId,
        action: 'associate_project',
        projectId: projectId,
      );

  Future<void> _manageThread({
    required String threadId,
    required String action,
    String? title,
    String? projectId,
  }) async {
    _requireSession();
    try {
      final response = await _client.rpc(
        'pandora_intelligence_thread_manage_v1',
        params: <String, Object?>{
          'p_organization_id': _organizationId,
          'p_thread_id': threadId,
          'p_action': action,
          'p_title': title,
          'p_project_id': projectId,
        },
      );
      if (_map(response)['ok'] != true) {
        throw const PandoraIntelligenceException(
          'Pandora could not update that conversation.',
        );
      }
    } on PostgrestException {
      throw const PandoraIntelligenceException(
        'Pandora could not update that conversation.',
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
    if (textAttachment == null && imageAttachment == null) {
      final capabilityTurn = await _dispatchCapability(
        message: message,
        threadId: threadId,
        projectId: projectId,
      );
      if (capabilityTurn != null) return capabilityTurn;
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

  Future<PandoraCapabilityRegistry> capabilityRegistry() async {
    _requireSession();
    try {
      final response = await _client.rpc(
        'pandora_plugin_runtime_registry_v4',
        params: <String, Object?>{'p_organization_id': _organizationId},
      );
      return PandoraCapabilityRegistry.fromJson(_map(response));
    } on PostgrestException {
      throw const PandoraIntelligenceException(
        'Pandora could not verify plugin runtime state right now.',
      );
    }
  }

  Future<List<PandoraProjectContext>> projectContexts({int limit = 60}) async {
    _requireSession();
    final safeLimit = limit.clamp(1, 100).toInt();
    try {
      final rows = await _client
          .from('projectos_projects')
          .select('id,project_key,name,repository,status,updated_at')
          .eq('organization_id', _organizationId)
          .neq('status', 'archived')
          .neq('project_key', 'projectos-inbox')
          .order('updated_at', ascending: false)
          .limit(safeLimit);
      return (rows as List<dynamic>)
          .map((row) => PandoraProjectContext.fromJson(_map(row)))
          .toList(growable: false);
    } on PostgrestException {
      throw const PandoraIntelligenceException(
        'Pandora could not verify project context right now.',
      );
    }
  }

  Future<PandoraIntelligenceTurn?> _dispatchCapability({
    required String message,
    String? threadId,
    String? projectId,
  }) async {
    if (message.trim().isEmpty) return null;
    try {
      final response = await _client.rpc(
        'pandora_chat_universal_dispatch_v7',
        params: <String, Object?>{
          'p_organization_id': _organizationId,
          'p_message': message.trim(),
          if (threadId != null) 'p_thread_id': threadId,
          if (projectId != null) 'p_project_id': projectId,
        },
      );
      final payload = _map(response);
      if (payload['handled'] != true) return null;
      return PandoraIntelligenceTurn.fromJson(payload);
    } on PostgrestException {
      throw const PandoraIntelligenceException(
        'Pandora could not verify that capability right now.',
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

class PandoraCapabilityRegistry {
  const PandoraCapabilityRegistry({
    required this.contractVersion,
    required this.observedAt,
    required this.projectRequired,
    required this.providers,
  });

  final String contractVersion;
  final DateTime observedAt;
  final bool projectRequired;
  final List<PandoraCapabilityProvider> providers;

  factory PandoraCapabilityRegistry.fromJson(Map<String, dynamic> json) {
    final rawProviders = json['providers'];
    return PandoraCapabilityRegistry(
      contractVersion: _text(json['contractVersion'], fallback: 'unknown'),
      observedAt: _date(json['observedAt']),
      projectRequired: json['projectRequired'] == true,
      providers: rawProviders is List
          ? rawProviders
              .map((value) => PandoraCapabilityProvider.fromJson(_map(value)))
              .toList(growable: false)
          : const <PandoraCapabilityProvider>[],
    );
  }
}

class PandoraCapabilityProvider {
  const PandoraCapabilityProvider({
    required this.provider,
    required this.label,
    required this.state,
    required this.rawStatus,
    required this.canUseNow,
    required this.readAvailable,
    required this.writeAvailable,
    required this.authorization,
    required this.accountVerified,
    required this.scopesVerified,
    required this.actions,
    this.accountLabel,
    this.lastVerifiedAt,
    this.failureCode,
    this.failureMessage,
  });

  final String provider;
  final String label;
  final String state;
  final String rawStatus;
  final bool canUseNow;
  final bool readAvailable;
  final bool writeAvailable;
  final String authorization;
  final bool accountVerified;
  final bool scopesVerified;
  final List<PandoraCapabilityAction> actions;
  final String? accountLabel;
  final DateTime? lastVerifiedAt;
  final String? failureCode;
  final String? failureMessage;

  bool get installed => state == 'Connected' && canUseNow;

  factory PandoraCapabilityProvider.fromJson(Map<String, dynamic> json) {
    final account = _map(json['account']);
    final health = _map(json['health']);
    final failure = _map(json['failure']);
    final rawActions = json['actions'];
    return PandoraCapabilityProvider(
      provider: _text(json['provider'], fallback: 'unknown'),
      label: _text(json['label'], fallback: 'Plugin'),
      state: _text(json['state'], fallback: 'Unavailable'),
      rawStatus: _text(
        health['rawStatus'],
        fallback: _text(json['status'], fallback: 'unknown'),
      ),
      canUseNow: health['canUseNow'] == true || json['canUseNow'] == true,
      readAvailable: json['readAvailable'] == true,
      writeAvailable: json['writeAvailable'] == true,
      authorization: _text(
        json['authorization'],
        fallback: 'Authorization state is not available.',
      ),
      accountVerified: account['verified'] == true,
      accountLabel: _optionalText(account['label']),
      scopesVerified: json['scopesVerified'] == true,
      lastVerifiedAt: _optionalDate(json['lastVerifiedAt']) ??
          _optionalDate(health['lastVerifiedAt']),
      failureCode: _optionalText(failure['code']),
      failureMessage: _optionalText(failure['message']),
      actions: rawActions is List
          ? rawActions
              .map((value) => PandoraCapabilityAction.fromJson(_map(value)))
              .toList(growable: false)
          : const <PandoraCapabilityAction>[],
    );
  }
}

class PandoraCapabilityAction {
  const PandoraCapabilityAction({
    required this.name,
    required this.mode,
    required this.available,
    this.approval,
  });

  final String name;
  final String mode;
  final bool available;
  final String? approval;

  factory PandoraCapabilityAction.fromJson(Map<String, dynamic> json) =>
      PandoraCapabilityAction(
        name: _text(json['name'], fallback: 'unknown.action'),
        mode: _text(json['mode'], fallback: 'read'),
        available: json['available'] == true,
        approval: _optionalText(json['approval']),
      );
}

class PandoraProjectContext {
  const PandoraProjectContext({
    required this.id,
    required this.projectKey,
    required this.name,
    required this.status,
    this.repository,
  });

  final String id;
  final String projectKey;
  final String name;
  final String status;
  final String? repository;

  factory PandoraProjectContext.fromJson(Map<String, dynamic> json) =>
      PandoraProjectContext(
        id: _requiredText(json['id']),
        projectKey: _requiredText(json['project_key']),
        name: _requiredText(json['name']),
        status: _text(json['status'], fallback: 'active'),
        repository: _optionalText(json['repository']),
      );
}

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

DateTime? _optionalDate(Object? value) {
  if (value is String) return DateTime.tryParse(value);
  return null;
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
