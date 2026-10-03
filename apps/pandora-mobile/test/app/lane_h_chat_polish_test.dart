import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_chat_shell.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/local_ai/pandora_local_ai.dart';
import 'package:pandora_mobile/features/simple/ask_pandora_screen.dart';

import '../helpers/fake_chat_intelligence.dart';
import '../helpers/fake_owner_api.dart';
import '../helpers/test_app.dart';

Future<void> _mount(
  WidgetTester tester, {
  PandoraIntelligenceApi? intelligence,
}) async {
  PandoraLocalAiPreference.setCachedForTesting(false);
  addTearDown(PandoraLocalAiPreference.resetForTesting);
  await setTestSurface(tester, logicalSize: const Size(390, 844));
  await tester.pumpWidget(
    testApp(
      themeMode: ThemeMode.dark,
      child: PandoraDependencies(
        auth: const FakeAuth(),
        repository: FakeRepository(),
        intelligence: intelligence ?? FakeChatIntelligence(),
        diagnostics: DiagnosticsStore(),
        child: const PandoraChatShell(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('A2 keyboard raises the entire composer as one unit',
      (tester) async {
    await _mount(tester);
    addTearDown(tester.view.resetViewInsets);
    final objective =
        find.byKey(const ValueKey<String>('ask-pandora-objective'));
    final composer = find.byKey(const ValueKey<String>('ask-pandora-composer'));
    await tester.tap(objective);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();

    final rect = tester.getRect(composer);
    expect(rect.left, closeTo(14, .1));
    expect(rect.right, closeTo(376, .1));
    expect(rect.height, closeTo(54, .1));
    expect(rect.bottom, lessThanOrEqualTo(844 - 320));
    for (final key in <String>[
      'ask-pandora-plus',
      'ask-pandora-model-control',
      'ask-pandora-submit',
    ]) {
      final item = find.byKey(ValueKey<String>(key));
      expect(item, findsOneWidget);
      expect(tester.getRect(item).bottom, lessThanOrEqualTo(rect.bottom));
    }
    expect(find.textContaining('Model ·'), findsNothing);
    expect(find.textContaining('Reasoning ·'), findsNothing);
  });

  testWidgets('A3 failed send survives keyboard dismissal with Retry',
      (tester) async {
    await _mount(tester,
        intelligence: FakeChatIntelligence(
          startFailure:
              const PandoraIntelligenceException('Please sign in again.'),
        ));
    addTearDown(tester.view.resetViewInsets);
    final objective =
        find.byKey(const ValueKey<String>('ask-pandora-objective'));
    await tester.tap(objective);
    await tester.enterText(objective, 'Hello');
    await tester.tap(
      find.byKey(const ValueKey<String>('ask-pandora-submit')),
    );
    for (var i = 0;
        i < 40 && find.text('Please sign in again.').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }

    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Please sign in again.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('pandora-chat-retry')),
      findsOneWidget,
    );

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();

    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Please sign in again.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('pandora-chat-retry')),
      findsOneWidget,
    );
  });

  testWidgets('A4 operational send shows immediate thinking feedback',
      (tester) async {
    final pending = Completer<PandoraIntelligenceTurn>();
    final activity = StreamController<Map<String, dynamic>>();
    final intelligence = FakeChatIntelligence(
        onReply: (_) => pending.future, events: activity.stream);
    await _mount(tester, intelligence: intelligence);
    final objective =
        find.byKey(const ValueKey<String>('ask-pandora-objective'));
    await tester.tap(objective);
    await tester.enterText(objective, 'Inspect current customer connections');
    await tester.tap(
      find.byKey(const ValueKey<String>('ask-pandora-submit')),
    );
    await tester.pump();

    expect(find.text('Inspect current customer connections'), findsOneWidget);
    expect(find.text('Thinking through the request…'), findsOneWidget);

    expect(
        (intelligence.lastEnterpriseContext?['selectedObject']
            as Map?)?['coreMode'],
        'owner');
    pending.complete(const PandoraIntelligenceTurn(
      threadId: 'fixture-pending-thread',
      reply: 'Done.',
      intent: 'conversation',
      confidence: 1,
      needsClarification: false,
    ));
    for (var i = 0; i < 40 && find.text('Done.').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    expect(find.text('Done.'), findsOneWidget);
    await activity.close();
  });

  testWidgets('A5 owner landing carries explicit Core context', (tester) async {
    await _mount(tester);
    final screen = tester.widget<AskPandoraScreen>(
      find.byType(AskPandoraScreen),
    );
    expect(screen.enterpriseContext?['route'], '/enterprise/core/home');
    expect(screen.enterpriseContext?['identityScope'], 'pandora_organization');
    expect((screen.enterpriseContext?['selectedObject'] as Map?)?['coreMode'],
        'owner');
    final state = tester.state<AskPandoraScreenState>(
      find.byType(AskPandoraScreen),
    );
    state.showExternalFailureMessage(
      'Pandora could not validate this Enterprise page context.',
    );
    await tester.pump();

    expect(
      find.text('Pandora could not validate this Enterprise page context.'),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('pandora-chat-message-error')),
      findsNothing,
    );
    expect(
      tester
          .widget<Offstage>(
            find.byKey(
              const ValueKey<String>(
                'pandora-active-chat-history-offstage',
              ),
            ),
          )
          .offstage,
      isFalse,
    );
    expect(
      find.byKey(const ValueKey<String>('pandora-active-chat-minimize')),
      findsNothing,
    );
  });
}
