import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_chat_shell.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/data/pandora_repository.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/models/pandora_models.dart';
import 'package:pandora_mobile/core/network/pandora_api_error.dart';
import 'package:pandora_mobile/features/simple/ask_pandora_screen.dart';

import '../helpers/fake_owner_api.dart';
import '../helpers/test_app.dart';

class _PendingChatRepository extends FakeRepository {
  final Completer<IntakeReceipt> pending = Completer<IntakeReceipt>();

  @override
  Future<IntakeReceipt> ask({
    required String message,
    String? projectId,
    String? idempotencyKey,
  }) =>
      pending.future;

  void complete() {
    if (pending.isCompleted) return;
    pending.complete(
      const IntakeReceipt(
        reply: 'Done.',
        needsApproval: false,
        actionId: 'lane-h-pending',
        status: IntakeStatus(
          whatChanged: 'Reply returned.',
          whereWeAre: 'Conversation',
          whatIsDone: 'Reply returned.',
          whatIsHappeningNow: 'Idle.',
          whatIWillDoNext: 'Wait.',
        ),
      ),
    );
  }
}

class _FailingChatRepository extends FakeRepository {
  @override
  Future<IntakeReceipt> ask({
    required String message,
    String? projectId,
    String? idempotencyKey,
  }) async {
    throw const PandoraRepositoryException(
      kind: PandoraApiErrorKind.unavailable,
      message: 'Please sign in again.',
      code: 'sign_in_required',
    );
  }
}

Future<void> _mount(
  WidgetTester tester, {
  FakeRepository? repository,
}) async {
  await setTestSurface(tester, logicalSize: const Size(390, 844));
  await tester.pumpWidget(
    testApp(
      themeMode: ThemeMode.dark,
      child: PandoraDependencies(
        auth: const FakeAuth(),
        repository: repository ?? FakeRepository(),
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
    final composer =
        find.byKey(const ValueKey<String>('ask-pandora-composer'));
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
    await _mount(tester, repository: _FailingChatRepository());
    addTearDown(tester.view.resetViewInsets);
    final objective =
        find.byKey(const ValueKey<String>('ask-pandora-objective'));
    await tester.tap(objective);
    await tester.enterText(objective, 'Hello');
    await tester.tap(
      find.byKey(const ValueKey<String>('ask-pandora-submit')),
    );
    for (var i = 0; i < 40 && find.text('Please sign in again.').evaluate().isEmpty; i++) {
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

  testWidgets('A4 send shows immediate thinking feedback', (tester) async {
    final repository = _PendingChatRepository();
    await _mount(tester, repository: repository);
    final objective =
        find.byKey(const ValueKey<String>('ask-pandora-objective'));
    await tester.tap(objective);
    await tester.enterText(objective, 'Hello');
    await tester.tap(
      find.byKey(const ValueKey<String>('ask-pandora-submit')),
    );
    await tester.pump();

    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Thinking through the request…'), findsOneWidget);

    repository.complete();
    for (var i = 0; i < 40 && find.text('Done.').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    expect(find.text('Done.'), findsOneWidget);
  });

  testWidgets('A5 landing sends no invalid enterprise page context banner',
      (tester) async {
    await _mount(tester);
    final screen = tester.widget<AskPandoraScreen>(
      find.byType(AskPandoraScreen),
    );
    expect(screen.enterpriseContext, isNull);
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
