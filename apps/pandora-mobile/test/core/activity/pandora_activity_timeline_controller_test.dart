import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/activity/pandora_activity_timeline_controller.dart';

Map<String, dynamic> rawEvent({
  required int sequence,
  String jobId = 'job-1',
  String state = 'acting',
  String? eventId,
}) {
  final at = DateTime.utc(2026, 9, 14, 9, 0, sequence).toIso8601String();
  final result = state == 'result';
  return <String, dynamic>{
    'projectionVersion': 1,
    'eventId': eventId ?? 'event-$sequence',
    'jobId': jobId,
    'sequence': sequence,
    'state': state,
    'message': result ? 'Verified result.' : 'Event $sequence',
    'occurredAt': at,
    'admittedAt': at,
    'domain': 'chat',
    'capability': 'universal_chat',
    'executionId': 'exec-$jobId',
    'source': <String, dynamic>{
      'sourceType': 'runtime',
      'sourceId': 'runtime-1',
      'sourceEventId': 'source-$jobId-$sequence',
      'observedAt': at,
    },
    'evidenceRefs': result
        ? <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'verification_receipt',
              'relation': 'verification',
              'ref': 'verify-$jobId-$sequence',
            },
          ]
        : <Map<String, dynamic>>[],
    'blocker': null,
    'outcome': result
        ? <String, dynamic>{
            'summary': 'Verified result.',
            'physicalDevice': false,
          }
        : null,
  };
}

Future<void> flushEvents() =>
    Future<void>.delayed(const Duration(milliseconds: 1));

void main() {
  test('merges replay/live duplicates and stops cleanly at Result', () async {
    final source = StreamController<Map<String, dynamic>>();
    final controller = PandoraActivityTimelineController();
    addTearDown(controller.dispose);
    addTearDown(source.close);

    await controller.bind(jobId: 'job-1', stream: source.stream);
    final first = rawEvent(sequence: 1, state: 'understanding');
    source.add(first);
    source.add(Map<String, dynamic>.from(first));
    await flushEvents();

    expect(controller.events, hasLength(1));
    expect(controller.hasError, isFalse);

    source.add(rawEvent(sequence: 2, state: 'result'));
    await flushEvents();

    expect(controller.events.map((event) => event.sequence), <int>[1, 2]);
    expect(controller.isTerminal, isTrue);
    expect(controller.hasError, isFalse);
  });

  test('fails closed on a sequence gap without exposing raw details', () async {
    final source = StreamController<Map<String, dynamic>>();
    final controller = PandoraActivityTimelineController();
    addTearDown(controller.dispose);
    addTearDown(source.close);

    await controller.bind(jobId: 'job-1', stream: source.stream);
    source.add(rawEvent(sequence: 1));
    source.add(rawEvent(sequence: 3));
    await flushEvents();

    expect(controller.events, hasLength(1));
    expect(controller.hasError, isTrue);
    expect(
      controller.publicError,
      'Pandora could not verify live Activity history.',
    );
  });

  test('rebind cancels the old stream and resets job state', () async {
    var firstCancelled = false;
    final first = StreamController<Map<String, dynamic>>(
      onCancel: () => firstCancelled = true,
    );
    final second = StreamController<Map<String, dynamic>>();
    final controller = PandoraActivityTimelineController();
    addTearDown(controller.dispose);
    addTearDown(first.close);
    addTearDown(second.close);

    await controller.bind(jobId: 'job-1', stream: first.stream);
    first.add(rawEvent(sequence: 1));
    await flushEvents();
    expect(controller.events, hasLength(1));

    await controller.bind(jobId: 'job-2', stream: second.stream);
    expect(firstCancelled, isTrue);
    expect(controller.jobId, 'job-2');
    expect(controller.events, isEmpty);

    first.add(rawEvent(sequence: 2));
    second.add(rawEvent(sequence: 1, jobId: 'job-2'));
    await flushEvents();

    expect(controller.events, hasLength(1));
    expect(controller.events.single.jobId, 'job-2');
    expect(controller.hasError, isFalse);
  });

  test('fails closed when a stream event changes job identity', () async {
    final source = StreamController<Map<String, dynamic>>();
    final controller = PandoraActivityTimelineController();
    addTearDown(controller.dispose);
    addTearDown(source.close);

    await controller.bind(jobId: 'job-1', stream: source.stream);
    source.add(rawEvent(sequence: 1, jobId: 'job-2'));
    await flushEvents();

    expect(controller.events, isEmpty);
    expect(controller.hasError, isTrue);
  });

  test('nonterminal stream completion fails closed', () async {
    final source = StreamController<Map<String, dynamic>>();
    final controller = PandoraActivityTimelineController();
    addTearDown(controller.dispose);

    await controller.bind(jobId: 'job-1', stream: source.stream);
    source.add(rawEvent(sequence: 1));
    await flushEvents();
    await source.close();
    await flushEvents();

    expect(controller.events, hasLength(1));
    expect(controller.hasError, isTrue);
  });

  test('clear cancels the current stream and drops prior activity', () async {
    var cancelled = false;
    final source = StreamController<Map<String, dynamic>>(
      onCancel: () => cancelled = true,
    );
    final controller = PandoraActivityTimelineController();
    addTearDown(controller.dispose);
    addTearDown(source.close);

    await controller.bind(jobId: 'job-1', stream: source.stream);
    source.add(rawEvent(sequence: 1));
    await flushEvents();

    await controller.clear();

    expect(cancelled, isTrue);
    expect(controller.jobId, isNull);
    expect(controller.events, isEmpty);
    expect(controller.hasError, isFalse);
  });

  test('dispose prevents rebinding and cancels the active source', () async {
    var cancelled = false;
    final source = StreamController<Map<String, dynamic>>(
      onCancel: () => cancelled = true,
    );
    final controller = PandoraActivityTimelineController();

    await controller.bind(jobId: 'job-1', stream: source.stream);
    controller.dispose();
    await flushEvents();

    expect(cancelled, isTrue);
    await expectLater(
      controller.bind(jobId: 'job-2', stream: const Stream.empty()),
      throwsA(isA<StateError>()),
    );
    await source.close();
  });
}
