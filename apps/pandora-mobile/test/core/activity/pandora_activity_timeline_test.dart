import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/activity/pandora_activity_projection.dart';
import 'package:pandora_mobile/core/activity/pandora_activity_timeline.dart';

PandoraActivityProjection event({
  required int sequence,
  PandoraActivityState state = PandoraActivityState.acting,
  String jobId = 'job-1',
  String? eventId,
  String? message,
  List<PandoraActivityEvidenceRef> evidence = const [],
}) {
  final at = DateTime.utc(2026, 9, 14, 9, 0, sequence);
  return PandoraActivityProjection(
    eventId: eventId ?? 'event-$sequence',
    jobId: jobId,
    sequence: sequence,
    state: state,
    message: message ?? 'Event $sequence',
    occurredAt: at,
    admittedAt: at,
    domain: 'chat',
    capability: 'universal_chat',
    executionId: 'exec-1',
    source: PandoraActivitySource(
      sourceType: 'runtime',
      sourceId: 'runtime-1',
      sourceEventId: 'source-$sequence',
      observedAt: at,
    ),
    evidenceRefs: evidence,
    blocker: null,
    outcome: state == PandoraActivityState.result
        ? const PandoraActivityOutcome(
            summary: 'Verified result.',
            physicalDevice: false,
          )
        : null,
  );
}

void main() {
  group('PandoraActivityTimelineReducer', () {
    test('merges canonical events oldest to newest', () {
      final reducer = PandoraActivityTimelineReducer();

      final merged = reducer.merge([
        event(sequence: 1, state: PandoraActivityState.understanding),
        event(sequence: 2, state: PandoraActivityState.acting),
      ]);

      expect(merged.map((item) => item.sequence), [1, 2]);
      expect(reducer.jobId, 'job-1');
    });

    test('collapses exact duplicate delivery', () {
      final reducer = PandoraActivityTimelineReducer();
      final first = event(sequence: 1);

      reducer.merge([first, first]);

      expect(reducer.events, hasLength(1));
    });

    test('rejects reused event identity with changed evidence', () {
      final reducer = PandoraActivityTimelineReducer();
      final first = event(sequence: 1, eventId: 'same-event');
      final changed = event(
        sequence: 1,
        eventId: 'same-event',
        evidence: const [
          PandoraActivityEvidenceRef(
            type: 'runtime_event',
            relation: 'source',
            ref: 'runtime:changed',
          ),
        ],
      );

      reducer.merge([first]);

      expect(
        () => reducer.merge([changed]),
        throwsA(isA<PandoraActivityTimelineException>()),
      );
    });

    test('rejects sequence gaps', () {
      final reducer = PandoraActivityTimelineReducer();
      reducer.merge([event(sequence: 1)]);

      expect(
        () => reducer.merge([event(sequence: 3)]),
        throwsA(isA<PandoraActivityTimelineException>()),
      );
    });

    test('rejects job identity changes', () {
      final reducer = PandoraActivityTimelineReducer();
      reducer.merge([event(sequence: 1)]);

      expect(
        () => reducer.merge([event(sequence: 2, jobId: 'job-2')]),
        throwsA(isA<PandoraActivityTimelineException>()),
      );
    });

    test('allows Resuming after an admitted Paused state', () {
      final reducer = PandoraActivityTimelineReducer();

      reducer.merge([
        event(sequence: 1, state: PandoraActivityState.paused),
        event(sequence: 2, state: PandoraActivityState.checking),
        event(sequence: 3, state: PandoraActivityState.resuming),
      ]);

      expect(reducer.events.last.state, PandoraActivityState.resuming);
    });

    test('rejects Resuming without prior Paused state', () {
      final reducer = PandoraActivityTimelineReducer();
      reducer.merge([event(sequence: 1)]);

      expect(
        () => reducer.merge([
          event(sequence: 2, state: PandoraActivityState.resuming),
        ]),
        throwsA(isA<PandoraActivityTimelineException>()),
      );
    });

    test('freezes timeline after a terminal event', () {
      final reducer = PandoraActivityTimelineReducer();
      reducer.merge([
        event(sequence: 1),
        event(sequence: 2, state: PandoraActivityState.result),
      ]);

      expect(reducer.isTerminal, isTrue);
      expect(
        () => reducer.merge([event(sequence: 3)]),
        throwsA(isA<PandoraActivityTimelineException>()),
      );
    });

    test('requires initial replay to start at sequence one', () {
      final reducer = PandoraActivityTimelineReducer();

      expect(
        () => reducer.merge([event(sequence: 4)]),
        throwsA(isA<PandoraActivityTimelineException>()),
      );
    });
  });
}
