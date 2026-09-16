import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/data/pandora_activity_stream_api.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/platform/pandora_native_io.dart';
import 'package:pandora_mobile/features/simple/ask_pandora_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fake_owner_api.dart';
import '../../helpers/test_app.dart';

class _FakeIntelligence extends PandoraIntelligenceApi {
  _FakeIntelligence()
      : super(
          client: SupabaseClient(
            'https://example.supabase.co',
            'fixture-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
          organizationId: 'org-fixture',
        );

  final StreamController<Map<String, dynamic>> events =
      StreamController<Map<String, dynamic>>();
  final Completer<PandoraIntelligenceTurn> turn =
      Completer<PandoraIntelligenceTurn>();
  PandoraActivityControlType? lastControlType;

  @override
  Future<PandoraIntelligenceExecution> startChatExecution({
    required String message,
    required String requestId,
    String? threadId,
    String? projectId,
    PandoraTextAttachment? textAttachment,
    PandoraImageAttachment? imageAttachment,
    PandoraIntelligenceMode mode = PandoraIntelligenceMode.auto,
  }) async =>
      PandoraIntelligenceExecution(
        jobId: 'job-1',
        events: events.stream,
        turn: turn.future,
      );

  @override
  Future<void> controlActivityJob({
    required String jobId,
    required String requestId,
    required PandoraActivityControlType type,
    String? instruction,
  }) async {
    lastControlType = type;
  }

  Future<void> close() async => events.close();
}

Map<String, dynamic> _activityEvent({
  required int sequence,
  required String state,
  required String message,
  List<Map<String, dynamic>> evidence = const <Map<String, dynamic>>[],
  Map<String, dynamic>? outcome,
}) {
  final second = sequence.toString().padLeft(2, '0');
  final timestamp = '2026-09-15T05:00:${second}Z';
  return <String, dynamic>{
    'projectionVersion': 1,
    'eventId': 'event-$sequence',
    'jobId': 'job-1',
    'sequence': sequence,
    'state': state,
    'message': message,
    'occurredAt': timestamp,
    'admittedAt': timestamp,
    'source': <String, dynamic>{
      'sourceType': 'runtime',
      'sourceId': 'runtime-1',
      'sourceEventId': 'source-$sequence',
      'observedAt': timestamp,
    },
    'evidenceRefs': evidence,
    if (outcome != null) 'outcome': outcome,
  };
}

void main() {
  testWidgets('Ask Pandora renders only canonical chronological Activity',
      (tester) async {
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    final intelligence = _FakeIntelligence();
    addTearDown(intelligence.close);

    await tester.pumpWidget(
      testApp(
        themeMode: ThemeMode.dark,
        child: PandoraDependencies(
          auth: const FakeAuth(),
          repository: FakeRepository(),
          intelligence: intelligence,
          diagnostics: DiagnosticsStore(),
          child: const AskPandoraScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('ask-pandora-objective')),
      'Check the current runtime',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('ask-pandora-submit')),
    );
    await tester.pump();
    expect(find.text('Waiting for verified activity…'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('ask-pandora-activity-theatre')),
      findsNothing,
    );

    intelligence.events.add(
      _activityEvent(
        sequence: 1,
        state: 'understanding',
        message: 'Understanding the runtime request.',
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('ask-pandora-activity-theatre')),
      findsOneWidget,
    );
    expect(find.text('Understanding'), findsWidgets);
    expect(find.text('Understanding the runtime request.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('ask-pandora-objective')),
      'Only use verified evidence',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('ask-pandora-submit')),
    );
    await tester.pump();
    expect(intelligence.lastControlType, PandoraActivityControlType.constraint);
    expect(find.text('Update sent to the active job.'), findsNothing);
    expect(find.text('Cancellation requested.'), findsNothing);
    expect(find.text('Understanding the runtime request.'), findsOneWidget);

    intelligence.events.add(
      _activityEvent(
        sequence: 2,
        state: 'verifying',
        message: 'Verifying runtime evidence.',
      ),
    );
    await tester.pump();
    expect(find.text('Understanding the runtime request.'), findsOneWidget);
    expect(find.text('Verifying runtime evidence.'), findsOneWidget);

    intelligence.events.add(
      _activityEvent(
        sequence: 3,
        state: 'result',
        message: 'Runtime evidence verified.',
        evidence: const <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'verification_receipt',
            'relation': 'verification',
            'ref': 'verification:runtime-1',
          },
        ],
        outcome: const <String, dynamic>{
          'summary': 'Runtime evidence verified.',
          'physicalDevice': false,
        },
      ),
    );
    intelligence.turn.complete(
      const PandoraIntelligenceTurn(
        threadId: 'thread-1',
        reply: 'The runtime check is complete.',
        intent: 'runtime_check',
        confidence: 1,
        needsClarification: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Activity · Done'), findsOneWidget);
    expect(find.text('The runtime check is complete.'), findsOneWidget);
    final activityY = tester
        .getTopLeft(
          find.byKey(const ValueKey<String>('ask-pandora-activity-theatre')),
        )
        .dy;
    final replyY = tester
        .getTopLeft(
          find.text('The runtime check is complete.'),
        )
        .dy;
    expect(activityY, lessThan(replyY));
    expect(tester.takeException(), isNull);
  });
}
