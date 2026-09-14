import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class PandoraActivityStreamException implements Exception {
  const PandoraActivityStreamException(this.message);
  final String message;

  @override
  String toString() => message;
}

enum PandoraActivityControlType { cancel, redirect, constraint }\n\nclass PandoraActivityReplayPage {
  const PandoraActivityReplayPage({
    required this.events,
    required this.watermarkSequence,
    required this.historyGapDueToRetention,
    required this.hasMore,
    required this.terminalState,
  });

  final List<Map<String, dynamic>> events;
  final int watermarkSequence;
  final bool historyGapDueToRetention;
  final bool hasMore;
  final String? terminalState;
}

class PandoraActivityStreamApi {
  PandoraActivityStreamApi({
    required SupabaseClient client,
    required String organizationId,
  })  : _client = client,
        _organizationId = organizationId;
  final SupabaseClient _client;
  final String _organizationId;
  Future<String> beginJob({
    required String requestId,
    String? threadId,
    String? projectId,
  }) async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw const PandoraActivityStreamException('Please sign in again.');
    }
    final normalizedRequestId = requestId.trim();
    if (normalizedRequestId.length < 8 || normalizedRequestId.length > 200) {
      throw const PandoraActivityStreamException(
        'Pandora could not create an activity stream.',
      );
    }
    try {
      final response = await _client.rpc(
        'pandora_activity_job_begin_v1',
        params: <String, Object?>{
          'p_organization_id': _organizationId,
          'p_request_id': normalizedRequestId,
          'p_thread_id': threadId,
          'p_project_id': projectId,
        },
      );
      final json = _map(response);
      final jobId = _text(json['jobId']);
      if (jobId.isEmpty) {
        throw const PandoraActivityStreamException(
          'Pandora could not create an activity stream.',
        );
      }
      return jobId;
    } on PostgrestException {
      throw const PandoraActivityStreamException(
        'Pandora could not create an activity stream.',
      );
    }
  }

  Future<void> requestControl({
    required String jobId,
    required String requestId,
    required PandoraActivityControlType type,
    String? instruction,
  }) async {
    if (_client.auth.currentSession == null) {
      throw const PandoraActivityStreamException('Please sign in again.');
    }
    final normalizedJobId = jobId.trim();
    final normalizedRequestId = requestId.trim();
    final normalizedInstruction = instruction?.trim();
    if (normalizedJobId.isEmpty ||
        normalizedRequestId.length < 8 ||
        normalizedRequestId.length > 200 ||
        ((type == PandoraActivityControlType.redirect ||
                type == PandoraActivityControlType.constraint) &&
            (normalizedInstruction == null ||
                normalizedInstruction.isEmpty ||
                normalizedInstruction.length > 2000)) ||
        (type == PandoraActivityControlType.cancel &&
            normalizedInstruction != null &&
            normalizedInstruction.isNotEmpty)) {
      throw const PandoraActivityStreamException(
        'Pandora could not submit that live update.',
      );
    }
    try {
      final response = await _client.rpc(
        'pandora_activity_control_request_v1',
        params: <String, Object?>{
          'p_organization_id': _organizationId,
          'p_job_id': normalizedJobId,
          'p_request_id': normalizedRequestId,
          'p_control_type': type.name,
          'p_instruction': type == PandoraActivityControlType.cancel
              ? null
              : normalizedInstruction,
        },
      );
      if (_text(_map(response)['controlId']).isEmpty) {
        throw const PandoraActivityStreamException(
          'Pandora could not submit that live update.',
        );
      }
    } on PostgrestException {
      throw const PandoraActivityStreamException(
        'Pandora could not submit that live update.',
      );
    }
  }

  Future<PandoraActivityReplayPage> replay({
    required String jobId,
    int afterSequence = 0,
    int limit = 250,
  }) async {
    try {
      final response = await _client.rpc(
        'pandora_activity_replay_v1',
        params: <String, Object?>{
          'p_organization_id': _organizationId,
          'p_job_id': jobId,
          'p_after_sequence': afterSequence,
          'p_limit': limit,
        },
      );
      final json = _map(response);
      final rawEvents = json['events'];
      final events = rawEvents is List
          ? rawEvents
              .map((value) => _map(value))
              .where((value) => value.isNotEmpty)
              .toList(growable: false)
          : const <Map<String, dynamic>>[];
      return PandoraActivityReplayPage(
        events: events,
        watermarkSequence: _int(json['watermarkSequence']),
        historyGapDueToRetention: json['historyGapDueToRetention'] == true,
        hasMore: json['hasMore'] == true,
        terminalState: _optionalText(json['terminalState']),
      );
    } on PostgrestException {
      throw const PandoraActivityStreamException(
        'Pandora could not replay activity right now.',
      );
    }
  }

  Stream<Map<String, dynamic>> watchJob(String jobId) async* {
    var cursor = 0;
    int? writerEpoch;
    String? writerId;
    String? terminalState;
    const terminalStates = <String>{'result', 'failed', 'cancelled'};

    Map<String, dynamic> validateEvent(Map<String, dynamic> event) {
      final sequence = _int(event['sequence']);
      final epoch = _int(event['writerEpoch']);
      final admittedBy = _text(event['admittedBy']);
      final eventJobId = _text(event['jobId']);
      final state = _text(event['state']);
      if (_int(event['schemaVersion']) != 1 ||
          eventJobId != jobId ||
          sequence != cursor + 1 ||
          epoch < 1 ||
          admittedBy.isEmpty ||
          !const <String>{'online', 'offline'}
              .contains(_text(event['admissionMode'])) ||
          state.isEmpty ||
          _text(event['message']).isEmpty) {
        throw const PandoraActivityStreamException(
          'Pandora received an invalid activity event.',
        );
      }
      if (writerEpoch != null && epoch < writerEpoch!) {
        throw const PandoraActivityStreamException(
          'Pandora detected an activity writer rollback.',
        );
      }
      if (writerEpoch == epoch && writerId != null && writerId != admittedBy) {
        throw const PandoraActivityStreamException(
          'Pandora detected two writers in one activity epoch.',
        );
      }
      if (writerEpoch == null || epoch > writerEpoch!) {
        writerEpoch = epoch;
        writerId = admittedBy;
      }
      cursor = sequence;
      if (terminalStates.contains(state)) terminalState = state;
      return event;
    }

    Future<List<Map<String, dynamic>>> catchUp() async {
      final collected = <Map<String, dynamic>>[];
      var pages = 0;
      while (true) {
        pages += 1;
        if (pages > 20) {
          throw const PandoraActivityStreamException(
            'Pandora stopped an unbounded activity replay.',
          );
        }
        final page = await replay(
          jobId: jobId,
          afterSequence: cursor,
          limit: 500,
        );
        if (page.historyGapDueToRetention) {
          throw const PandoraActivityStreamException(
            'Activity history is incomplete and requires authoritative recovery.',
          );
        }
        for (final event in page.events) {
          collected.add(pandoraActivityPublicProjection(validateEvent(event)));
        }
        terminalState = page.terminalState ?? terminalState;
        if (!page.hasMore) return collected;
      }
    }

    for (final event in await catchUp()) {
      yield event;
    }
    if (terminalState != null) return;

    final live = _client
        .from('pandora_activity_events')
        .stream(primaryKey: const <String>['job_id', 'sequence'])
        .eq('job_id', jobId)
        .order('sequence');

    await for (final rows in live) {
      final pending = rows
          .map((row) => _map(row))
          .where((row) => _int(row['sequence']) > cursor)
          .toList(growable: false)
        ..sort(
          (a, b) => _int(a['sequence']).compareTo(_int(b['sequence'])),
        );

      if (pending.isNotEmpty && _int(pending.first['sequence']) != cursor + 1) {
        for (final event in await catchUp()) {
          yield event;
        }
        if (terminalState != null) return;
        continue;
      }

      for (final row in pending) {
        final sequence = _int(row['sequence']);
        if (sequence != cursor + 1) {
          for (final event in await catchUp()) {
            yield event;
          }
          if (terminalState != null) return;
          break;
        }
        final event = _map(row['event']);
        if (event.isEmpty || _int(event['sequence']) != sequence) {
          throw const PandoraActivityStreamException(
            'Pandora received an unreadable activity event.',
          );
        }
        yield pandoraActivityPublicProjection(validateEvent(event));
        if (terminalState != null) return;
      }
    }
  }
}

Map<String, dynamic> pandoraActivityPublicProjection(
  Map<String, dynamic> event,
) {
  final provenance = _map(event['provenance']);
  final rawEvidence = event['evidence'];
  final evidenceRefs = rawEvidence is List
      ? rawEvidence.map((value) => _map(value)).toList(growable: false)
      : const <Map<String, dynamic>>[];
  return <String, dynamic>{
    'projectionVersion': 1,
    'eventId': event['eventId'],
    'jobId': event['jobId'],
    'sequence': event['sequence'],
    'state': event['state'],
    'message': event['message'],
    'occurredAt': event['occurredAt'],
    'admittedAt': event['admittedAt'],
    'domain': event['domain'],
    'capability': event['capability'],
    'executionId': event['executionId'],
    'source': provenance,
    'evidenceRefs': evidenceRefs,
    'blocker': event['blocker'],
    'outcome': event['outcome'],
  };
}

Map<String, dynamic> _map(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : <String, dynamic>{};

String _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : '';

String? _optionalText(Object? value) {
  final result = _text(value);
  return result.isEmpty ? null : result;
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
