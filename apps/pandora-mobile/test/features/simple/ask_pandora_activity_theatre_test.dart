import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/chat/pandora_chat_state.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/local_ai/pandora_local_ai.dart';
import 'package:pandora_mobile/features/simple/ask_pandora_screen.dart';

import '../../helpers/fake_chat_intelligence.dart';
import '../../helpers/fake_owner_api.dart';
import '../../helpers/test_app.dart';

void main() {
  setUp(() => PandoraLocalAiPreference.setCachedForTesting(false));
  tearDown(PandoraLocalAiPreference.resetForTesting);

  testWidgets(
      'Activity metadata cannot become transcript content or a second generation owner',
      (tester) async {
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    final events = StreamController<Map<String, dynamic>>.broadcast();
    final reply = Completer<PandoraIntelligenceTurn>();
    final intelligence = FakeChatIntelligence(
        events: events.stream, onReply: (_) => reply.future);
    final key = GlobalKey<AskPandoraScreenState>();
    await tester.pumpWidget(testApp(
        child: PandoraDependencies(
            auth: const FakeAuth(),
            repository: FakeRepository(),
            intelligence: intelligence,
            diagnostics: DiagnosticsStore(),
            child: AskPandoraScreen(key: key))));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey<String>('ask-pandora-objective')),
        'Check the current runtime');
    await tester.tap(find.byKey(const ValueKey<String>('ask-pandora-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(intelligence.dispatches.length, 1);
    final turnId = key.currentState!.debugChatState.turns.single.id;
    events.add({
      'projectionVersion': 1,
      'eventId': 'event-1',
      'jobId': 'fixture-chat-execution',
      'sequence': 1,
      'state': 'understanding',
      'message': 'Internal registry stage fixture',
      'occurredAt': '2026-10-03T01:00:00Z',
      'admittedAt': '2026-10-03T01:00:00Z',
      'source': {
        'sourceType': 'runtime',
        'sourceId': 'fixture',
        'sourceEventId': 'fixture-1',
        'observedAt': '2026-10-03T01:00:00Z'
      },
      'evidenceRefs': <Object?>[],
    });
    await tester.pump();
    expect(find.text('Internal registry stage fixture'), findsNothing);
    expect(find.text('Pandora is working…'), findsOneWidget);
    expect(key.currentState!.debugChatState.turns.single.id, turnId);
    expect(key.currentState!.debugChatState.turns.single.phase,
        PandoraChatPhase.accepted);
    reply.complete(const PandoraIntelligenceTurn(
        threadId: 'fixture-chat-thread',
        reply: 'Everything needed for this request is available.',
        intent: 'conversation',
        confidence: 1,
        needsClarification: false));
    await tester.pumpAndSettle();
    expect(find.text('Pandora is working…'), findsNothing);
    expect(key.currentState!.debugChatState.turns.single.phase,
        PandoraChatPhase.completed);
    expect(find.text('Everything needed for this request is available.'),
        findsOneWidget);
    expect(key.currentState!.debugChatState.turns.single.id, turnId);
    await tester.pumpWidget(const SizedBox());
    await events.close();
  });

  testWidgets(
      'completed turns each get one fresh request identity in the retained thread',
      (tester) async {
    final intelligence = FakeChatIntelligence();
    final key = GlobalKey<AskPandoraScreenState>();
    await tester.pumpWidget(testApp(
        child: PandoraDependencies(
            auth: const FakeAuth(),
            repository: FakeRepository(),
            intelligence: intelligence,
            diagnostics: DiagnosticsStore(),
            child: AskPandoraScreen(key: key))));
    await tester.pumpAndSettle();
    for (final prompt in ['Hi', 'Hello']) {
      await tester.enterText(
          find.byKey(const ValueKey<String>('ask-pandora-objective')), prompt);
      await tester
          .tap(find.byKey(const ValueKey<String>('ask-pandora-submit')));
      await tester.pumpAndSettle();
    }
    expect(intelligence.dispatches.length, 2);
    expect(intelligence.dispatches.first.token.turnId,
        isNot(intelligence.dispatches.last.token.turnId));
    expect(intelligence.dispatches.first.token.attemptId,
        isNot(intelligence.dispatches.last.token.attemptId));
    expect(intelligence.dispatches.last.threadId, 'fixture-chat-thread');
    expect(key.currentState!.debugChatState.turns.map((t) => t.phase),
        everyElement(PandoraChatPhase.completed));
  });
}
