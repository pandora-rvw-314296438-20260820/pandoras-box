import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../network/idempotency_key.dart';

class ProjectExperienceApi {
  ProjectExperienceApi({
    required SupabaseClient client,
    required String organizationId,
    IdempotencyKeyFactory? idempotencyKeys,
  })  : _client = client,
        _organizationId = organizationId,
        _keys = idempotencyKeys ?? IdempotencyKeyFactory();

  final SupabaseClient _client;
  final String _organizationId;
  final IdempotencyKeyFactory _keys;
  final Map<String, DateTime> _lastCompilationRequest = <String, DateTime>{};

  Future<String> submitIntent({
    required String projectId,
    required String intentText,
    String intentKind = 'build',
    String? idempotencyKey,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const ProjectExperienceException(
        'Please sign in again before changing this project.',
      );
    }
    final text = intentText.trim();
    if (text.isEmpty) {
      throw const ProjectExperienceException(
        'Tell Pandora what you want to build.',
      );
    }
    final key = idempotencyKey ?? _keys.create('project-intent');
    try {
      final result = await _client
          .from('pandora_project_intents')
          .insert(<String, Object?>{
            'organization_id': _organizationId,
            'project_id': projectId,
            'requester_id': userId,
            'intent_kind': intentKind,
            'intent_text': text,
            'source': 'customer',
            'idempotency_key': key,
            'provenance': const <String, Object?>{
              'surface': 'pandora_mobile_simple_mode',
            },
          })
          .select('id')
          .single();
      return _requiredText(result['id']);
    } on PostgrestException catch (error) {
      if (error.code != '23505') {
        throw const ProjectExperienceException(
          'Pandora could not save that request right now.',
        );
      }
      final existing = await _client
          .from('pandora_project_intents')
          .select('id')
          .eq('organization_id', _organizationId)
          .eq('project_id', projectId)
          .eq('idempotency_key', key)
          .maybeSingle();
      if (existing == null) {
        throw const ProjectExperienceException(
          'Pandora could not confirm that request yet.',
        );
      }
      return _requiredText(existing['id']);
    }
  }

  Future<OwnerProjectUnderstanding> understanding({
    required String projectId,
    required String expectedSourceIntentId,
  }) async {
    try {
      final spec = await _client
          .from('pandora_project_specs')
          .select(
            'id,version,status,source_intent_id,project_type,'
            'target_user_summary,business_summary,created_at',
          )
          .eq('organization_id', _organizationId)
          .eq('project_id', projectId)
          .order('version', ascending: false)
          .limit(1)
          .maybeSingle();

      if (spec == null ||
          _text(spec['source_intent_id']) != expectedSourceIntentId) {
        unawaited(_ensureCompilation(expectedSourceIntentId));
        return const OwnerProjectUnderstanding.waiting();
      }

      final status = _text(spec['status']);
      if (status == 'rejected') {
        return const OwnerProjectUnderstanding.rejected();
      }
      if (status != 'active') {
        unawaited(_ensureCompilation(expectedSourceIntentId));
        return const OwnerProjectUnderstanding.waiting();
      }

      final specId = _requiredText(spec['id']);
      final objectives = await _client
          .from('pandora_project_business_objectives')
          .select('objective,desired_outcome')
          .eq('organization_id', _organizationId)
          .eq('project_id', projectId)
          .eq('project_spec_id', specId)
          .order('ordinal')
          .limit(3);
      final requirements = await _client
          .from('pandora_project_requirements')
          .select('statement,category,priority')
          .eq('organization_id', _organizationId)
          .eq('project_id', projectId)
          .eq('project_spec_id', specId)
          .order('category')
          .limit(8);

      return OwnerProjectUnderstanding.ready(
        specId: specId,
        version: _int(spec['version']),
        projectType: _text(spec['project_type'], fallback: 'Project'),
        targetUsers: _optionalText(spec['target_user_summary']),
        businessSummary: _optionalText(spec['business_summary']),
        objectives: <String>[
          for (final row in objectives)
            if (_text(row['desired_outcome']).isNotEmpty)
              _text(row['desired_outcome'])
            else if (_text(row['objective']).isNotEmpty)
              _text(row['objective']),
        ],
        requirements: <String>[
          for (final row in requirements)
            if (_text(row['statement']).isNotEmpty) _text(row['statement']),
        ],
        compiledAt: DateTime.tryParse(_text(spec['created_at'])),
      );
    } on ProjectExperienceException {
      rethrow;
    } on PostgrestException {
      throw const ProjectExperienceException(
        'Pandora could not refresh its understanding right now.',
      );
    }
  }

  Future<List<OwnerProjectConversationTurn>> conversationHistory({
    required String projectId,
  }) async {
    try {
      final intents = await _client
          .from('pandora_project_intents')
          .select('id,intent_text,intent_kind,created_at')
          .eq('organization_id', _organizationId)
          .eq('project_id', projectId)
          .order('created_at');

      final specs = await _client
          .from('pandora_project_specs')
          .select(
            'source_intent_id,status,version,project_type,'
            'target_user_summary,business_summary,created_at',
          )
          .eq('organization_id', _organizationId)
          .eq('project_id', projectId)
          .order('version');

      final latestSpecByIntent = <String, Map<String, dynamic>>{};
      for (final raw in specs) {
        final spec = Map<String, dynamic>.from(raw);
        final sourceIntentId = _text(spec['source_intent_id']);
        if (sourceIntentId.isNotEmpty) {
          latestSpecByIntent[sourceIntentId] = spec;
        }
      }

      return <OwnerProjectConversationTurn>[
        for (final raw in intents)
          _conversationTurnFromRows(
            Map<String, dynamic>.from(raw),
            latestSpecByIntent[_text(raw['id'])],
          ),
      ];
    } on PostgrestException {
      throw const ProjectExperienceException(
        'Pandora could not refresh this conversation right now.',
      );
    }
  }

  Future<void> requestBuild({
    required String projectId,
    required String idempotencyKey,
  }) async {
    if (_client.auth.currentUser == null) {
      throw const ProjectExperienceException(
        'Please sign in again before building this project.',
      );
    }
    try {
      final result = await _client.functions.invoke(
        'pandora-project-source-generator',
        body: <String, Object?>{
          'projectId': projectId,
          'idempotencyKey': idempotencyKey,
        },
      );
      final data = result.data;
      if (data is Map && data['ok'] == false && data['state'] == 'blocked') {
        throw const ProjectExperienceException(
          'Pandora found something to resolve before this build can start.',
        );
      }
    } on FunctionException {
      throw const ProjectExperienceException(
        'Pandora could not start this build right now.',
      );
    }
  }

  Future<void> _ensureCompilation(String sourceIntentId) async {
    final now = DateTime.now();
    final last = _lastCompilationRequest[sourceIntentId];
    if (last != null && now.difference(last) < const Duration(seconds: 20)) {
      return;
    }
    _lastCompilationRequest[sourceIntentId] = now;
    try {
      await _client.functions.invoke(
        'pandora-project-spec-compiler',
        body: <String, Object?>{'intentId': sourceIntentId},
      );
    } catch (_) {
      // Compilation is authoritative server work. A transient trigger failure
      // leaves the durable intent intact and the UI truthfully waiting.
    }
  }

  void beginAuthenticatedIdentityEpoch() {
    _lastCompilationRequest.clear();
  }
}

OwnerProjectConversationTurn _conversationTurnFromRows(
  Map<String, dynamic> intent,
  Map<String, dynamic>? spec,
) {
  final status = _text(spec?['status']);
  final assistantState = switch (status) {
    'active' => OwnerProjectUnderstandingState.ready,
    'rejected' => OwnerProjectUnderstandingState.rejected,
    _ => null,
  };
  return OwnerProjectConversationTurn(
    intentId: _requiredText(intent['id']),
    intentText: _text(intent['intent_text']),
    intentKind: _text(intent['intent_kind'], fallback: 'change'),
    createdAt: DateTime.tryParse(_text(intent['created_at'])),
    assistantState: assistantState,
    assistantSummary: assistantState == OwnerProjectUnderstandingState.ready
        ? _optionalText(spec?['business_summary'])
        : assistantState == OwnerProjectUnderstandingState.rejected
            ? 'I need a little more direction before I can turn that into a reliable build plan.'
            : null,
    projectType: _optionalText(spec?['project_type']),
    targetUsers: _optionalText(spec?['target_user_summary']),
    specVersion: spec == null ? null : _int(spec['version']),
    compiledAt:
        spec == null ? null : DateTime.tryParse(_text(spec['created_at'])),
  );
}

class OwnerProjectConversationTurn {
  const OwnerProjectConversationTurn({
    required this.intentId,
    required this.intentText,
    required this.intentKind,
    required this.createdAt,
    required this.assistantState,
    required this.assistantSummary,
    required this.projectType,
    required this.targetUsers,
    required this.specVersion,
    required this.compiledAt,
  });

  final String intentId;
  final String intentText;
  final String intentKind;
  final DateTime? createdAt;
  final OwnerProjectUnderstandingState? assistantState;
  final String? assistantSummary;
  final String? projectType;
  final String? targetUsers;
  final int? specVersion;
  final DateTime? compiledAt;
}

class ProjectExperienceException implements Exception {
  const ProjectExperienceException(this.message);
  final String message;

  @override
  String toString() => message;
}

enum OwnerProjectUnderstandingState { waiting, ready, rejected }

class OwnerProjectUnderstanding {
  const OwnerProjectUnderstanding._({
    required this.state,
    this.specId,
    this.version,
    this.projectType,
    this.targetUsers,
    this.businessSummary,
    this.objectives = const <String>[],
    this.requirements = const <String>[],
    this.compiledAt,
  });

  const OwnerProjectUnderstanding.waiting()
      : this._(state: OwnerProjectUnderstandingState.waiting);

  const OwnerProjectUnderstanding.rejected()
      : this._(state: OwnerProjectUnderstandingState.rejected);

  factory OwnerProjectUnderstanding.ready({
    required String specId,
    required int version,
    required String projectType,
    required String? targetUsers,
    required String? businessSummary,
    required List<String> objectives,
    required List<String> requirements,
    required DateTime? compiledAt,
  }) =>
      OwnerProjectUnderstanding._(
        state: OwnerProjectUnderstandingState.ready,
        specId: specId,
        version: version,
        projectType: projectType,
        targetUsers: targetUsers,
        businessSummary: businessSummary,
        objectives: List<String>.unmodifiable(objectives),
        requirements: List<String>.unmodifiable(requirements),
        compiledAt: compiledAt,
      );

  final OwnerProjectUnderstandingState state;
  final String? specId;
  final int? version;
  final String? projectType;
  final String? targetUsers;
  final String? businessSummary;
  final List<String> objectives;
  final List<String> requirements;
  final DateTime? compiledAt;

  bool get isReady => state == OwnerProjectUnderstandingState.ready;
}

String _text(Object? value, {String fallback = ''}) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return fallback;
}

String? _optionalText(Object? value) {
  final valueText = _text(value);
  return valueText.isEmpty ? null : valueText;
}

String _requiredText(Object? value) {
  final valueText = _text(value);
  if (valueText.isEmpty) {
    throw const ProjectExperienceException(
      'Pandora returned an unreadable project result.',
    );
  }
  return valueText;
}

int _int(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
