import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'restartable_broadcast_stream.dart';

class PandoraActivityStreamException implements Exception {
  const PandoraActivityStreamException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PandoraActivityReplayPage {
  const PandoraActivityReplayPage({
    required this.jobId,
    required this.afterSequence,
    required this.watermarkSequence,
    required this.events,
    required this.hasMore,
    required this.historyGap,
  });

  final String jobId;
  final int afterSequence;
  final int watermarkSequence;
  final List<Map<String, Object?>> events;
  final bool hasMore;
  final bool historyGap;
}
abstract interface class PandoraActivityStreamRepository {
  Future<PandoraActivityReplayPage> replay(
    String jobId, {
    int afterSequence = 0,
  });

  Stream<PandoraActivityReplayPage> watch(
    String jobId, {
    int afterSequence = 0,
  });
}

class SupabasePandoraActivityStreamRepository
    implements PandoraActivityStreamRepository {
  SupabasePandoraActivityStreamRepository({required SupabaseClient client})
      : _client = client;

  static const _eventTable = 'pandora_activity_events';
  static const _replayRpc = 'pandora_activity_replay_v1';

  final SupabaseClient _client;

  @override
  Future<PandoraActivityReplayPage> replay(
    String jobId, {
    int afterSequence = 0,
  }) async {
    final id = _requiredUuid(jobId);
    _validateCursor(afterSequence);
    _requireSession();
    try {
      final raw = await _client.rpc(
        _replayRpc,
        params: <String, Object?>{
          'p_job_id': id,
          'p_after_sequence': afterSequence,
          'p_limit': 250,
        },
      );
      return _decodeReplay(id, _map(raw));
    } on PostgrestException {
      throw const PandoraActivityStreamException(
        'Pandora could not replay this activity stream.',
      );
    }
  }

  @override
  Stream<PandoraActivityReplayPage> watch(
    String jobId, {
    int afterSequence = 0,
  }) {
    final id = _requiredUuid(jobId);
    _validateCursor(afterSequence);
    return restartableBroadcastStream(
      () => _watchOnce(id, afterSequence),
    );
  }

  Stream<PandoraActivityReplayPage> _watchOnce(
    String jobId,
    int afterSequence,
  ) async* {
    _requireSession();
    var cursor = afterSequence;
    while (true) {
      final page = await replay(jobId, afterSequence: cursor);
      if (page.historyGap) {
        throw const PandoraActivityStreamException(
          'Pandora detected an activity history gap and will not invent missing events.',
        );
      }
      if (page.events.isNotEmpty) {
        yield page;
        cursor = _lastSequence(page.events);
      }
      if (!page.hasMore) break;
    }

    await for (final rows in _client
        .from(_eventTable)
        .stream(primaryKey: const <String>['id'])
        .eq('job_id', jobId)) {
      final pending = rows
          .map((row) => _map(row['projection']))
          .where((event) => _sequence(event) > cursor)
          .toList(growable: false)
        ..sort((a, b) => _sequence(a).compareTo(_sequence(b)));
      if (pending.isEmpty) continue;

      if (_sequence(pending.first) != cursor + 1) {
        final recovered = await replay(jobId, afterSequence: cursor);
        if (recovered.historyGap) {
          throw const PandoraActivityStreamException(
            'Pandora detected an activity history gap and will not invent missing events.',
          );
        }
        if (recovered.events.isNotEmpty) {
          yield recovered;
          cursor = _lastSequence(recovered.events);
        }
        continue;
      }
      final page = PandoraActivityReplayPage(
        jobId: jobId,
        afterSequence: cursor,
        watermarkSequence: _sequence(pending.last),
        events: pending,
        hasMore: false,
        historyGap: false,
      );
      yield page;
      cursor = _lastSequence(pending);
    }
  }

  void _requireSession() {
    if (_client.auth.currentSession == null) {
      throw const PandoraActivityStreamException('Please sign in again.');
    }
  }

  static PandoraActivityReplayPage _decodeReplay(
    String expectedJobId,
    Map<String, dynamic> json,
  ) {
    if (_text(json['contractVersion']) != 'pandora-activity-replay-v1') {
      throw const PandoraActivityStreamException(
        'Pandora returned an unsupported activity replay contract.',
      );
    }
    final job = _map(json['job']);
    final jobId = _text(job['jobId']);
    if (jobId != expectedJobId) {
      throw const PandoraActivityStreamException(
        'Pandora returned activity for a different job.',
      );
    }
    final rawEvents = json['events'];
    final events = rawEvents is List
        ? rawEvents
            .map((value) => Map<String, Object?>.from(_map(value)))
            .toList(growable: false)
        : const <Map<String, Object?>>[];
    events.sort((a, b) => _sequence(a).compareTo(_sequence(b)));

    final after = _int(json['afterSequence']);
    final watermark = _int(json['watermarkSequence']);
    if (after < 0 || watermark < 0 || watermark < after) {
      throw const PandoraActivityStreamException(
        'Pandora returned invalid activity replay metadata.',
      );
    }
    var expected = after + 1;
    for (final event in events) {
      if (_text(event['jobId']) != expectedJobId || _sequence(event) != expected) {
        throw const PandoraActivityStreamException(
          'Pandora returned a non-contiguous activity replay.',
        );
      }
      expected += 1;
    }

    return PandoraActivityReplayPage(
      jobId: expectedJobId,
      afterSequence: after,
      watermarkSequence: watermark,
      events: events,
      hasMore: json['hasMore'] == true,
      historyGap: json['historyGapDueToRetention'] == true,
    );
  }
  static int _lastSequence(List<Map<String, Object?>> events) {
    if (events.isEmpty) return 0;
    return _sequence(events.last);
  }

  static int _sequence(Map<String, Object?> event) {
    final value = event['sequence'];
    final sequence = value is int ? value : int.tryParse(value?.toString() ?? '');
    if (sequence == null || sequence < 1) {
      throw const PandoraActivityStreamException(
        'Pandora returned an invalid activity sequence.',
      );
    }
    return sequence;
  }

  static int _int(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? -1;
  }

  static String _text(Object? value) =>
      value is String ? value.trim() : '';

  static Map<String, dynamic> _map(Object? value) => value is Map
      ? value.map((key, value) => MapEntry(key.toString(), value))
      : <String, dynamic>{};
  static String _requiredUuid(String value) {
    final text = value.trim().toLowerCase();
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(text)) {
      throw ArgumentError.value(value, 'jobId', 'Must be a UUID.');
    }
    return text;
  }

  static void _validateCursor(int value) {
    if (value < 0) {
      throw ArgumentError.value(
        value,
        'afterSequence',
        'Must be non-negative.',
      );
    }
  }
}
