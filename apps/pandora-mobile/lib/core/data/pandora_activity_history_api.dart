import 'package:supabase_flutter/supabase_flutter.dart';

import '../activity/pandora_activity_projection.dart';
import 'pandora_activity_stream_api.dart';

class PandoraActivityHistoryException implements Exception {
  const PandoraActivityHistoryException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PandoraActivityHistoryCursor {
  const PandoraActivityHistoryCursor({
    required this.admittedAt,
    required this.jobId,
    required this.sequence,
  });
  final DateTime admittedAt;
  final String jobId;
  final int sequence;
}

class PandoraActivityHistoryRecord {
  const PandoraActivityHistoryRecord({
    required this.organizationId,
    required this.organizationName,
    required this.requestedBy,
    required this.activity,
    this.requestedByName,
    this.threadId,
    this.projectId,
  });
  final String organizationId;
  final String organizationName;
  final String requestedBy;
  final String? requestedByName;
  final String? threadId;
  final String? projectId;
  final PandoraActivityProjection activity;
  String get personLabel => requestedByName ?? requestedBy;
}

class PandoraActivityHistoryPage {
  const PandoraActivityHistoryPage({
    required this.items,
    required this.hasMore,
    required this.retentionBoundary,
    this.nextCursor,
  });
  final List<PandoraActivityHistoryRecord> items;
  final bool hasMore;
  final PandoraActivityHistoryCursor? nextCursor;
  final String retentionBoundary;
}

class PandoraActivityHistoryQuery {
  const PandoraActivityHistoryQuery({
    this.text,
    this.states = const <String>[],
    this.domains = const <String>[],
    this.sourceTypes = const <String>[],
    this.requestedBy,
    this.jobId,
    this.from,
    this.to,
    this.cursor,
    this.limit = 100,
  });
  final String? text;
  final List<String> states;
  final List<String> domains;
  final List<String> sourceTypes;
  final String? requestedBy;
  final String? jobId;
  final DateTime? from;
  final DateTime? to;
  final PandoraActivityHistoryCursor? cursor;
  final int limit;
}

abstract interface class PandoraActivityHistorySource {
  Future<PandoraActivityHistoryPage> search(PandoraActivityHistoryQuery query);
}

class SupabasePandoraActivityHistorySource
    implements PandoraActivityHistorySource {
  SupabasePandoraActivityHistorySource({
    required SupabaseClient client,
    required String organizationId,
  })  : _client = client,
        _organizationId = organizationId;

  final SupabaseClient _client;
  final String _organizationId;

  @override
  Future<PandoraActivityHistoryPage> search(
    PandoraActivityHistoryQuery query,
  ) async {
    if (_client.auth.currentSession == null) {
      throw const PandoraActivityHistoryException('Please sign in again.');
    }
    if (query.limit < 1 || query.limit > 200) {
      throw const PandoraActivityHistoryException(
        'Pandora rejected an invalid Activity History request.',
      );
    }
    try {
      final cursor = query.cursor;
      final response = await _client.rpc(
        'pandora_activity_history_search_v1',
        params: <String, Object?>{
          'p_organization_id': _organizationId,
          'p_query': _optional(query.text),
          'p_states': query.states.isEmpty ? null : query.states,
          'p_domains': query.domains.isEmpty ? null : query.domains,
          'p_source_types':
              query.sourceTypes.isEmpty ? null : query.sourceTypes,
          'p_requested_by': _optional(query.requestedBy),
          'p_job_id': _optional(query.jobId),
          'p_from': query.from?.toUtc().toIso8601String(),
          'p_to': query.to?.toUtc().toIso8601String(),
          'p_before_admitted_at': cursor?.admittedAt.toUtc().toIso8601String(),
          'p_before_job_id': cursor?.jobId,
          'p_before_sequence': cursor?.sequence,
          'p_limit': query.limit,
        },
      );
      return parsePandoraActivityHistoryPage(response);
    } on PostgrestException {
      throw const PandoraActivityHistoryException(
        'Pandora could not read Activity History right now.',
      );
    } on FormatException {
      throw const PandoraActivityHistoryException(
        'Pandora rejected unreadable Activity History.',
      );
    }
  }
}

PandoraActivityHistoryPage parsePandoraActivityHistoryPage(Object? value) {
  final json = _map(value);
  if (_int(json['projectionVersion']) != 1) {
    throw const FormatException('Unsupported Activity History projection.');
  }
  final rawItems = json['items'];
  if (rawItems is! List) {
    throw const FormatException('Activity History items are invalid.');
  }
  final items = rawItems.map((raw) {
    final item = _map(raw);
    final canonical = _map(item['event']);
    if (canonical.isEmpty) {
      throw const FormatException('Activity History event is missing.');
    }
    final activity = PandoraActivityProjection.fromJson(
      pandoraActivityPublicProjection(canonical),
    );
    return PandoraActivityHistoryRecord(
      organizationId: _required(item, 'organizationId'),
      organizationName: _required(item, 'organizationName'),
      requestedBy: _required(item, 'requestedBy'),
      requestedByName: _optional(item['requestedByName']),
      threadId: _optional(item['threadId']),
      projectId: _optional(item['projectId']),
      activity: activity,
    );
  }).toList(growable: false);

  final rawCursor = json['nextCursor'];
  PandoraActivityHistoryCursor? cursor;
  if (rawCursor != null) {
    final cursorJson = _map(rawCursor);
    final admittedAt = DateTime.tryParse(_required(cursorJson, 'admittedAt'));
    final sequence = _int(cursorJson['sequence']);
    if (admittedAt == null || sequence < 1) {
      throw const FormatException('Activity History cursor is invalid.');
    }
    cursor = PandoraActivityHistoryCursor(
      admittedAt: admittedAt.toUtc(),
      jobId: _required(cursorJson, 'jobId'),
      sequence: sequence,
    );
  }

  final hasMore = json['hasMore'] == true;
  if (hasMore != (cursor != null)) {
    throw const FormatException('Activity History pagination is inconsistent.');
  }
  return PandoraActivityHistoryPage(
    items: List<PandoraActivityHistoryRecord>.unmodifiable(items),
    hasMore: hasMore,
    nextCursor: cursor,
    retentionBoundary: _required(json, 'retentionBoundary'),
  );
}

Map<String, dynamic> _map(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : <String, dynamic>{};

String _required(Map<String, dynamic> json, String key) {
  final value = _optional(json[key]);
  if (value == null) {
    throw FormatException('Activity History $key is invalid.');
  }
  return value;
}

String? _optional(Object? value) {
  if (value is! String) return null;
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
