import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_chat_shell.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/data/pandora_repository.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/local_ai/pandora_local_ai.dart';
import 'package:pandora_mobile/core/models/pandora_models.dart';
import 'package:pandora_mobile/core/widgets/pandora_navigation.dart';
import 'package:pandora_mobile/features/simple/ask_pandora_screen.dart';
import 'package:pandora_mobile/features/simple/chat/pandora_chat_presentation_controller.dart';

import '../helpers/fake_chat_intelligence.dart';
import '../helpers/fake_owner_api.dart';
import '../helpers/test_app.dart';

class _CountingHistory extends FakeChatIntelligence {
  int reads = 0;
  List<PandoraIntelligenceThread> threads = const [];
  final List<String> renamed = [];

  @override
  Future<List<PandoraIntelligenceThread>> recentThreads(
      {int limit = 30}) async {
    reads += 1;
    return threads;
  }

  @override
  Future<void> renameThread(String threadId, String title) async {
    renamed.add('$threadId:$title');
  }
}

class _PendingProjects extends FakeRepository {
  Completer<RepositorySnapshot<List<ProjectSummary>>>? pending;

  @override
  Future<RepositorySnapshot<List<ProjectSummary>>> projects(
          {bool allowCached = false}) =>
      pending?.future ?? super.projects(allowCached: allowCached);
}

final _managedThread = PandoraIntelligenceThread(
  id: 'thread-fixture',
  title: 'Saved conversation',
  status: 'active',
  lastMessageAt: DateTime.utc(2026, 10, 3),
  createdAt: DateTime.utc(2026, 10, 3),
);

void main() {
  final primary =
      find.byKey(const ValueKey('pandora-primary-navigation-drawer'));
  final recent = find.byKey(const ValueKey('pandora-recent-chats-drawer'));
  final input = find.byKey(const ValueKey('ask-pandora-objective'));

  Future<_CountingHistory> mount(WidgetTester tester,
      {Size size = const Size(390, 844),
      _CountingHistory? intelligence,
      FakeRepository? repository}) async {
    PandoraLocalAiPreference.setCachedForTesting(false);
    addTearDown(PandoraLocalAiPreference.resetForTesting);
    await setTestSurface(tester, logicalSize: size);
    addTearDown(tester.view.resetViewInsets);
    final history = intelligence ?? _CountingHistory();
    await tester.pumpWidget(testApp(
      child: PandoraDependencies(
        auth: const FakeAuth(),
        repository: repository ?? FakeRepository(),
        intelligence: history,
        diagnostics: DiagnosticsStore(),
        child: const PandoraChatShell(),
      ),
    ));
    await tester.pumpAndSettle();
    return history;
  }

  AskPandoraScreenState chat(WidgetTester tester) =>
      tester.state<AskPandoraScreenState>(find.byType(AskPandoraScreen));

  VoidCallback navigation(WidgetTester tester) =>
      PandoraNavigationScope.maybeOf(
              tester.element(find.byType(AskPandoraScreen)))!
          .openDrawer!;

  void requestRecent(WidgetTester tester) => tester
      .widget<AskPandoraScreen>(find.byType(AskPandoraScreen))
      .onSearchChats!();

  Future<void> settleWithoutOverlap(WidgetTester tester) async {
    for (var i = 0; i < 45; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(primary.evaluate().length + recent.evaluate().length,
          lessThanOrEqualTo(1),
          reason: 'Departing and arriving drawer must not share a frame.');
    }
    await tester.pumpAndSettle();
  }

  testWidgets('late IME closes and then reopens the same intended drawer',
      (tester) async {
    await mount(tester);
    await tester.enterText(input, 'Keep this draft through navigation');
    navigation(tester)();
    await tester.pumpAndSettle();
    expect(primary, findsOneWidget);
    final presentation = chat(tester).presentationController;
    final intent = presentation.value.intentRevision;

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump(const Duration(milliseconds: 16));
    expect(primary.hitTestable(), findsNothing);
    await tester.pumpAndSettle();
    expect(primary, findsNothing);
    expect(recent, findsNothing);
    expect(presentation.value.surface, PandoraChatSurface.none);
    expect(presentation.value.pendingSurface, PandoraChatSurface.drawer);
    expect(presentation.value.intentRevision, intent);

    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    expect(primary, findsOneWidget);
    expect(recent, findsNothing);
    expect(presentation.value.surface, PandoraChatSurface.drawer);
    expect(presentation.value.drawerKind, PandoraChatDrawerKind.primary);
    expect(tester.widget<TextField>(input).focusNode!.hasFocus, isFalse);
    expect(tester.widget<TextField>(input).controller!.text,
        'Keep this draft through navigation');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'primary and recent switching waits for actual old drawer removal',
      (tester) async {
    final history = await mount(tester);
    final openNavigation = navigation(tester);
    openNavigation();
    await tester.pumpAndSettle();
    expect(primary, findsOneWidget);
    final reads = history.reads;
    requestRecent(tester);
    await settleWithoutOverlap(tester);
    expect(primary, findsNothing);
    expect(recent, findsOneWidget);
    expect(chat(tester).presentationController.value.drawerKind,
        PandoraChatDrawerKind.recent);
    expect(chat(tester).presentationController.value.surface,
        PandoraChatSurface.drawer);
    expect(history.reads, reads + 1);

    openNavigation();
    await settleWithoutOverlap(tester);
    expect(primary, findsOneWidget);
    expect(recent, findsNothing);
    expect(chat(tester).presentationController.value.drawerKind,
        PandoraChatDrawerKind.primary);
    expect(tester.takeException(), isNull);
  });

  testWidgets('latest requested drawer kind wins while IME closes',
      (tester) async {
    await mount(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    navigation(tester)();
    requestRecent(tester);
    await tester.pumpAndSettle();
    expect(primary, findsNothing);
    expect(recent, findsNothing);
    expect(chat(tester).presentationController.value.drawerKind,
        PandoraChatDrawerKind.recent);
    tester.view.viewInsets = const FakeViewPadding();
    await settleWithoutOverlap(tester);
    expect(primary, findsNothing);
    expect(recent, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back cancels an unpainted drawer without a later ghost opening',
      (tester) async {
    await mount(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    navigation(tester)();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    expect(primary, findsNothing);
    expect(recent, findsNothing);
    expect(chat(tester).presentationController.value.surface,
        PandoraChatSurface.none);
    expect(chat(tester).presentationController.value.pendingSurface, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop recent drawer reports Back and supports reopening',
      (tester) async {
    final history = await mount(tester, size: const Size(1024, 800));
    final initialReads = history.reads;
    for (var i = 0; i < 2; i++) {
      requestRecent(tester);
      await tester.pumpAndSettle();
      expect(recent, findsOneWidget);
      expect(primary, findsNothing);
      expect(chat(tester).presentationController.value.drawerKind,
          PandoraChatDrawerKind.recent);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(recent, findsNothing);
      expect(chat(tester).presentationController.value.surface,
          PandoraChatSurface.none);
    }
    expect(history.reads, initialReads + 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop breakpoint clears an invisible primary modal intent',
      (tester) async {
    await mount(tester);
    await tester.enterText(input, 'Keep this while resizing');
    navigation(tester)();
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1024, 800);
    await tester.pumpAndSettle();
    expect(primary, findsNothing);
    expect(chat(tester).presentationController.value.surface,
        PandoraChatSurface.none);
    expect(tester.widget<TextField>(input).controller!.text,
        'Keep this while resizing');
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    navigation(tester)();
    await tester.pumpAndSettle();
    expect(primary, findsOneWidget);
    expect(recent, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a new open while the same drawer is closing survives its removal',
      (tester) async {
    await mount(tester);
    final openNavigation = navigation(tester);
    openNavigation();
    await tester.pumpAndSettle();
    chat(tester).presentationController.closeSurface();
    await tester.pump(const Duration(milliseconds: 16));
    openNavigation();
    await tester.pumpAndSettle();
    expect(primary, findsOneWidget);
    expect(recent, findsNothing);
    expect(chat(tester).presentationController.value.surface,
        PandoraChatSurface.drawer);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(primary, findsNothing);
    expect(chat(tester).presentationController.value.surface,
        PandoraChatSurface.none);
    expect(tester.takeException(), isNull);
  });

  testWidgets('context owns the foreground while a departing drawer closes',
      (tester) async {
    await mount(tester);
    requestRecent(tester);
    await tester.pumpAndSettle();
    expect(recent, findsOneWidget);
    final presentation = chat(tester).presentationController;
    expect(await presentation.showContext(), isTrue);
    final contextIntent = presentation.value.intentRevision;
    await tester.pump(const Duration(milliseconds: 16));
    expect(recent.hitTestable(), findsNothing);
    await tester.pumpAndSettle();
    expect(recent, findsNothing);
    expect(primary, findsNothing);
    expect(presentation.value.surface, PandoraChatSurface.context);
    expect(presentation.value.intentRevision, contextIntent);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent search owns its IME without reopening the composer',
      (tester) async {
    await mount(tester);
    requestRecent(tester);
    await tester.pumpAndSettle();
    final search = find.widgetWithText(TextField, 'Search conversations');
    await tester.enterText(search, 'Keep this search');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final presentation = chat(tester).presentationController;
    expect(recent.hitTestable(), findsOneWidget);
    expect(primary, findsNothing);
    expect(presentation.value.surface, PandoraChatSurface.drawer);
    expect(presentation.value.pendingSurface, isNull);
    expect(presentation.drawerOwnsKeyboard, isTrue);
    expect(tester.getRect(recent).bottom, lessThanOrEqualTo(844 - 300));
    expect(tester.widget<TextField>(input).focusNode!.hasFocus, isFalse);
    expect(find.text('Keep this search'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(recent, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conversation management owns its route and Rename keyboard',
      (tester) async {
    final history = _CountingHistory()..threads = [_managedThread];
    await mount(tester, intelligence: history);
    requestRecent(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Conversation options'));
    await tester.pumpAndSettle();
    expect(recent, findsNothing);
    expect(chat(tester).presentationController.value.surface,
        PandoraChatSurface.context);
    await tester.tap(find.widgetWithText(ListTile, 'Rename'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Rename'), findsNothing);
    final name = find.widgetWithText(TextField, 'Conversation name');
    await tester.enterText(name, 'Renamed conversation');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(chat(tester).presentationController.value.surface,
        PandoraChatSurface.context);
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    expect(history.renamed, ['thread-fixture:Renamed conversation']);
    expect(find.byType(AlertDialog), findsNothing);
    expect(recent, findsNothing);
    expect(chat(tester).presentationController.value.surface,
        PandoraChatSurface.none);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late project list cannot cover a newer navigation intent',
      (tester) async {
    final repository = _PendingProjects();
    final history = _CountingHistory()..threads = [_managedThread];
    await mount(tester, intelligence: history, repository: repository);
    final openNavigation = navigation(tester);
    requestRecent(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Conversation options'));
    await tester.pumpAndSettle();
    repository.pending = Completer<RepositorySnapshot<List<ProjectSummary>>>();
    await tester.tap(find.widgetWithText(ListTile, 'Move to project'));
    await tester.pumpAndSettle();
    expect(chat(tester).presentationController.value.surface,
        PandoraChatSurface.context);
    openNavigation();
    await tester.pumpAndSettle();
    repository.pending!.complete(await FakeRepository().projects());
    await tester.pumpAndSettle();
    expect(find.text('Move conversation to project'), findsNothing);
    expect(primary, findsOneWidget);
    expect(recent, findsNothing);
    expect(chat(tester).presentationController.value.surface,
        PandoraChatSurface.drawer);
    expect(tester.takeException(), isNull);
  });
}
