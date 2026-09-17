import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/activity/pandora_activity_projection.dart';
import 'package:pandora_mobile/core/activity/pandora_activity_timeline_view.dart';

PandoraActivityProjection event({
  required int sequence,
  required PandoraActivityState state,
  String? message,
  PandoraActivityBlocker? blocker,
}) {
  final at = DateTime.utc(2026, 9, 14, 9, 0, sequence);
  return PandoraActivityProjection(
    eventId: 'event-$sequence',
    jobId: 'job-1',
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
    evidenceRefs: const [],
    blocker: blocker,
    outcome: state == PandoraActivityState.result
        ? const PandoraActivityOutcome(
            summary: 'Verified result.',
            physicalDevice: false,
          )
        : null,
  );
}

Widget harness(List<PandoraActivityProjection> events) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PandoraActivityTimelineView(events: events),
        ),
      ),
    );

void main() {
  testWidgets('renders only the latest live Activity stage', (tester) async {
    await tester.pumpWidget(
      harness([
        event(
          sequence: 1,
          state: PandoraActivityState.understanding,
          message: 'Understanding request.',
        ),
        event(
          sequence: 2,
          state: PandoraActivityState.acting,
          message: 'Calling the selected capability.',
        ),
      ]),
    );

    expect(find.text('Understanding request.'), findsNothing);
    expect(find.text('Calling the selected capability.'), findsOneWidget);
  });

  testWidgets('keeps Needs You required action visible', (tester) async {
    await tester.pumpWidget(
      harness([
        event(
          sequence: 1,
          state: PandoraActivityState.needsYou,
          message: 'Protected app requires your presence.',
          blocker: const PandoraActivityBlocker(
            reasonCode: 'protected_app_user_presence_required',
            reason: 'Biometric confirmation is required.',
            requiredAction: 'Confirm on the phone.',
            approvalRequired: false,
          ),
        ),
      ]),
    );

    expect(find.text('Protected app requires your presence.'), findsOneWidget);
    expect(find.text('Required action: Confirm on the phone.'), findsOneWidget);
  });

  testWidgets('shows the latest verified Result inline', (tester) async {
    await tester.pumpWidget(
      harness([
        event(
          sequence: 1,
          state: PandoraActivityState.verifying,
          message: 'Verifying the result.',
        ),
        event(
          sequence: 2,
          state: PandoraActivityState.result,
          message: 'Done.',
        ),
      ]),
    );

    expect(find.text('Activity · Done'), findsNothing);
    expect(find.text('Verifying the result.'), findsNothing);
    expect(find.text('Done.'), findsOneWidget);
  });

  test('maps every canonical state to the frozen owner-facing label', () {
    expect(
      activityStateLabel(PandoraActivityState.understanding),
      'Understanding',
    );
    expect(activityStateLabel(PandoraActivityState.planning), 'Planning');
    expect(activityStateLabel(PandoraActivityState.acting), 'Working');
    expect(activityStateLabel(PandoraActivityState.checking), 'Checking');
    expect(activityStateLabel(PandoraActivityState.needsYou), 'Needs You');
    expect(activityStateLabel(PandoraActivityState.retrying), 'Retrying');
    expect(
      activityStateLabel(PandoraActivityState.fallback),
      'Switching approach',
    );
    expect(activityStateLabel(PandoraActivityState.verifying), 'Verifying');
    expect(activityStateLabel(PandoraActivityState.paused), 'Paused');
    expect(activityStateLabel(PandoraActivityState.resuming), 'Resuming');
    expect(activityStateLabel(PandoraActivityState.result), 'Done');
    expect(activityStateLabel(PandoraActivityState.failed), 'Problem');
    expect(activityStateLabel(PandoraActivityState.cancelled), 'Cancelled');
  });

  testWidgets(
    'does not expose provenance or evidence refs in the visible timeline',
    (tester) async {
      final at = DateTime.utc(2026, 9, 14, 9);
      await tester.pumpWidget(
        harness([
          PandoraActivityProjection(
            eventId: 'event-private-1',
            jobId: 'job-1',
            sequence: 1,
            state: PandoraActivityState.acting,
            message: 'Calling the selected capability.',
            occurredAt: at,
            admittedAt: at,
            domain: 'chat',
            capability: 'universal_chat',
            executionId: 'exec-internal-1',
            source: PandoraActivitySource(
              sourceType: 'tool',
              sourceId: 'private-tool-id',
              sourceEventId: 'private-source-event',
              observedAt: at,
            ),
            evidenceRefs: const [
              PandoraActivityEvidenceRef(
                type: 'tool_receipt',
                relation: 'source',
                ref: 'internal-receipt-ref',
              ),
            ],
          ),
        ]),
      );

      expect(find.text('Calling the selected capability.'), findsOneWidget);
      expect(find.textContaining('private-tool-id'), findsNothing);
      expect(find.textContaining('private-source-event'), findsNothing);
      expect(find.textContaining('internal-receipt-ref'), findsNothing);
      expect(find.textContaining('exec-internal-1'), findsNothing);
    },
  );

  testWidgets('remains usable at narrow phone width with 200 percent text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: harness([
          event(
            sequence: 1,
            state: PandoraActivityState.needsYou,
            message:
                'Pandora needs a real user action before it can continue safely.',
            blocker: const PandoraActivityBlocker(
              reasonCode: 'protected_app_user_presence_required',
              reason: 'User presence is required.',
              requiredAction: 'Confirm the protected action on the phone.',
              approvalRequired: false,
            ),
          ),
        ]),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.text('Required action: Confirm the protected action on the phone.'),
      findsOneWidget,
    );
  });
}
