import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_chat_shell.dart';
import 'package:pandora_mobile/app/pandora_conversation_layer.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/local_ai/pandora_local_ai.dart';
import 'package:pandora_mobile/core/widgets/pandora_navigation.dart';
import 'package:pandora_mobile/features/operations/operations_room_screen.dart';
import 'package:pandora_mobile/features/simple/ask_pandora_screen.dart';
import 'package:pandora_mobile/features/simple/chat/pandora_chat_composer.dart';

import '../helpers/fake_chat_intelligence.dart';
import '../helpers/fake_owner_api.dart';
import '../helpers/test_app.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    Size size, {
    FakeRepository? repository,
    PandoraIntelligenceApi? intelligence,
  }) async {
    PandoraLocalAiPreference.setCachedForTesting(false);
    addTearDown(PandoraLocalAiPreference.resetForTesting);
    await setTestSurface(tester, logicalSize: size);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('pandora/local_ai'),
      (call) async => call.method == 'status'
          ? <String, Object?>{
              'supported': false,
              'configured': false,
              'loaded': false,
            }
          : null,
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('pandora/local_ai'),
        null,
      ),
    );
    await tester.pumpWidget(
      testApp(
        child: PandoraDependencies(
          auth: const FakeAuth(),
          repository: repository ?? FakeRepository(),
          intelligence: intelligence,
          diagnostics: DiagnosticsStore(),
          child: const PandoraChatShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    if (find.byType(AskPandoraScreen).evaluate().isEmpty) {
      if (size.width >= 900) {
        await tester.tap(find.widgetWithText(ListTile, 'Pandora').first);
      } else {
        await tester.tap(find.byTooltip('Open navigation'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('pandora-primary-navigation-drawer'),
            ),
            matching: find.widgetWithText(ListTile, 'Pandora'),
          ),
        );
      }
      await tester.pumpAndSettle();
    }
  }

  final menu = find.byTooltip('Open navigation');
  final primaryDrawer = find.byKey(
    const ValueKey<String>('pandora-primary-navigation-drawer'),
  );
  final recentDrawer = find.byKey(
    const ValueKey<String>('pandora-recent-chats-drawer'),
  );
  final recentChats = find.byKey(
    const ValueKey<String>('pandora-recent-chats'),
  );

  Future<Finder> drawerTile(WidgetTester tester, String title) async {
    final scrollable = find
        .descendant(
          of: primaryDrawer,
          matching: find.byType(Scrollable),
        )
        .first;
    final state = tester.state<ScrollableState>(scrollable);
    state.position.jumpTo(state.position.minScrollExtent);
    await tester.pump();
    final tile = find.descendant(
      of: primaryDrawer,
      matching: find.widgetWithText(ListTile, title),
    );
    if (tile.evaluate().isEmpty &&
        const {
          'Vision Intelligence',
          'Operations Room',
          'Capabilities & Providers',
          'Connections',
          'Platform',
          'Administration',
        }.contains(title)) {
      final advanced = find.byKey(
        const ValueKey<String>('pandora-advanced-navigation'),
      );
      await tester.ensureVisible(advanced);
      await tester.tap(find.descendant(
        of: advanced,
        matching: find.text('Advanced'),
      ));
      await tester.pumpAndSettle();
    }
    if (tile.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        tile,
        180,
        scrollable: scrollable,
      );
    }
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    expect(tile, findsOneWidget);
    return tile;
  }

  for (final width in <double>[360, 390, 600]) {
    testWidgets('phone $width uses full-width chat and one drawer',
        (tester) async {
      await mount(tester, Size(width, 800));
      expect(menu, findsOneWidget);
      expect(tester.getSize(find.byType(AskPandoraScreen)).width, width);
      expect(find.byType(NavigationRail), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey<String>('ask-pandora-objective')),
        'Keep this draft',
      );
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(primaryDrawer, findsOneWidget);
      expect(recentDrawer, findsNothing);
      expect(find.widgetWithText(ListTile, 'Capabilities & Providers'),
          findsNothing);
      for (final title in <String>[
        'Pandora',
        'Projects',
        'Needs You',
        'Activity',
        'Capabilities & Providers',
        'Saved evidence',
        'Verify & Safety',
        'Operations Room',
        'Settings & More',
      ]) {
        expect(await drawerTile(tester, title), findsOneWidget);
      }
      await tester.tap(await drawerTile(tester, 'Projects'));
      await tester.pumpAndSettle();
      expect(menu, findsOneWidget);
      expect(find.byTooltip('Create project'), findsOneWidget);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(await drawerTile(tester, 'Pandora'));
      await tester.pumpAndSettle();
      expect(find.text('Keep this draft'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(primaryDrawer, findsNothing);
      expect(recentDrawer, findsNothing);
      expect(find.text('Keep this draft'), findsOneWidget);
    });
  }

  testWidgets(
      'focused composer opens bounded drawer and reopening resets its scroll',
      (tester) async {
    await mount(tester, const Size(390, 844));
    addTearDown(tester.view.resetViewInsets);
    final objective =
        find.byKey(const ValueKey<String>('ask-pandora-objective'));
    await tester.enterText(objective, 'Keep the keyboard draft');
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(objective).focusNode!.hasFocus, isFalse);
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    final header =
        find.byKey(const ValueKey<String>('pandora-side-panel-top-overlay'));
    final viewport =
        find.byKey(const ValueKey<String>('pandora-side-panel-scroll'));
    expect(tester.getRect(viewport).top,
        greaterThanOrEqualTo(tester.getRect(header).bottom));
    final position = tester
        .state<ScrollableState>(find
            .descendant(of: viewport, matching: find.byType(Scrollable))
            .first)
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    final reopened = tester
        .state<ScrollableState>(find
            .descendant(of: viewport, matching: find.byType(Scrollable))
            .first)
        .position;
    expect(reopened.pixels, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Keep the keyboard draft'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet keeps the persistent sidebar without a drawer trigger',
      (tester) async {
    await mount(tester, const Size(1024, 800));
    expect(menu, findsNothing);
    expect(primaryDrawer, findsNothing);
    expect(find.widgetWithText(ListTile, 'Capabilities & Providers'),
        findsNothing);
    final advanced = find.byKey(
      const ValueKey<String>('pandora-advanced-navigation'),
    );
    await tester.ensureVisible(advanced);
    await tester.tap(find.descendant(
      of: advanced,
      matching: find.text('Advanced'),
    ));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Capabilities & Providers'),
        findsOneWidget);
    expect(tester.getSize(find.byType(AskPandoraScreen)).width, 759);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Operations Room opens the canonical team chat', (tester) async {
    await mount(tester, const Size(390, 800));
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(await drawerTile(tester, 'Operations Room'));
    await tester.pumpAndSettle();

    expect(find.byType(PandoraOperationsRoomScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('operations-room-chat')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('operations-room-composer')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('ask-pandora-composer')),
      findsOneWidget,
    );
    for (final role in <String>[
      'ATHENA',
      'APOLLO',
      'HERMES',
      'HEPHAESTUS',
      'THEMIS',
      'ARTEMIS',
    ]) {
      expect(find.text(role), findsWidgets);
    }
    expect(find.text('Execution'), findsOneWidget);
    expect(find.text('Council'), findsOneWidget);
    expect(find.text('Incident'), findsOneWidget);
    expect(menu, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Needs You and Settings & More expose exactly one navigation control',
      (tester) async {
    await mount(tester, const Size(390, 800));
    for (final title in <String>[
      'Needs You',
      'Settings & More',
      'Capabilities & Providers',
      'Activity',
      'Saved evidence',
      'Verify & Safety',
    ]) {
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(await drawerTile(tester, title));
      await tester.pumpAndSettle();
      expect(menu, findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$title layout');
    }
  });

  testWidgets('resizing across the sidebar breakpoint keeps the chat draft',
      (tester) async {
    await mount(tester, const Size(600, 800));
    await tester.enterText(
      find.byKey(const ValueKey<String>('ask-pandora-objective')),
      'Keep this while resizing',
    );
    tester.view.physicalSize = const Size(1024, 800);
    await tester.pumpAndSettle();
    expect(menu, findsNothing);
    expect(find.text('Keep this while resizing'), findsOneWidget);
    tester.view.physicalSize = const Size(600, 800);
    await tester.pumpAndSettle();
    expect(menu, findsOneWidget);
    expect(find.text('Keep this while resizing'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rotation preserves chat draft', (tester) async {
    await mount(tester, const Size(390, 844));
    final objective =
        find.byKey(const ValueKey<String>('ask-pandora-objective'));
    await tester.enterText(objective, 'Keep this through rotation');
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(find.text('Keep this through rotation'), findsOneWidget);
    expect(find.byType(AskPandoraScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.text('Keep this through rotation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back gives focused chat input priority over minimizing history',
      (tester) async {
    await mount(tester, const Size(390, 844));
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(await drawerTile(tester, 'Projects'));
    await tester.pumpAndSettle();
    final chat =
        tester.state<AskPandoraScreenState>(find.byType(AskPandoraScreen));
    chat.showHistory();
    await tester.pumpAndSettle();
    final objective =
        find.byKey(const ValueKey<String>('ask-pandora-objective'));
    await tester.enterText(objective, 'Keep this draft while going back');
    await tester.pump();
    // Focus precedes Android's first nonzero IME metric. One Back must still
    // affect only that input, even though both retained PopScopes observe it.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final history = find.byKey(
      const ValueKey<String>('pandora-active-chat-history-offstage'),
    );
    expect(tester.widget<Offstage>(history).offstage, isFalse);
    expect(tester.widget<TextField>(objective).focusNode!.hasFocus, isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.widget<Offstage>(history).offstage, isTrue);
    expect(tester.widget<TextField>(objective).controller!.text,
        'Keep this draft while going back');
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard inset keeps composer mounted', (tester) async {
    await mount(tester, const Size(390, 844));
    addTearDown(tester.view.resetViewInsets);
    final objective =
        find.byKey(const ValueKey<String>('ask-pandora-objective'));
    final plus = find.byKey(const ValueKey<String>('ask-pandora-plus'));
    final composer = find.byKey(const ValueKey<String>('ask-pandora-composer'));
    final composerDock =
        find.byKey(const ValueKey<String>('ask-pandora-composer-dock'));
    final voice = find.byKey(const ValueKey<String>('ask-pandora-voice'));
    final submit = find.byKey(const ValueKey<String>('ask-pandora-submit'));
    await tester.tap(objective);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    expect(objective, findsOneWidget);
    expect(plus, findsOneWidget);
    expect(composer, findsOneWidget);
    expect(composerDock, findsOneWidget);
    expect(voice, findsNothing);
    expect(submit, findsOneWidget);
    expect(
      find.descendant(
          of: submit, matching: find.byIcon(Icons.mic_none_rounded)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: composerDock, matching: find.byType(Divider)),
      findsNothing,
    );
    final composerRect = tester.getRect(composer);
    expect(composerRect.bottom, lessThanOrEqualTo(844 - 320));
    expect(tester.getRect(objective).bottom, lessThanOrEqualTo(844 - 320));
    final field = tester.widget<TextField>(objective);
    expect(field.minLines, 1);
    expect(field.maxLines, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'global composer floats above the safe area without a bottom slab',
    (tester) async {
      await setTestSurface(tester, logicalSize: const Size(390, 844));
      await tester.pumpWidget(
        testApp(
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              padding: EdgeInsets.only(bottom: 24),
              viewPadding: EdgeInsets.only(bottom: 24),
            ),
            child: PandoraDependencies(
              auth: const FakeAuth(),
              repository: FakeRepository(),
              diagnostics: DiagnosticsStore(),
              child: Material(
                color: const Color(0xFF07111B),
                child: PandoraConversationLayer(
                  businessWorkspace: const ColoredBox(
                    key: ValueKey<String>('business-clearance-fixture'),
                    color: Color(0xFF07111B),
                  ),
                  conversation: const AskPandoraScreen(shellOverlay: true),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final composerFinder =
          find.byKey(const ValueKey<String>('ask-pandora-composer'));
      final composer = tester.widget<Container>(composerFinder);
      final decoration = composer.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFF151515));
      expect(decoration.borderRadius, BorderRadius.circular(27));
      final rect = tester.getRect(composerFinder);
      expect(rect.left, closeTo(14, .1));
      expect(rect.right, closeTo(390 - 14, .1));
      expect(rect.height, closeTo(54, .1));
      final composerExtent = tester.getRect(find.byType(PandoraChatComposer));
      expect(composerExtent.bottom, closeTo(844 - 24, .1));
      expect(composerExtent.height,
          closeTo(PandoraChatComposer.minimumExtent, .1));
      expect(rect.bottom, lessThan(composerExtent.bottom));

      final clearance = tester.widget<Padding>(
        find.byKey(
          const ValueKey<String>('pandora-business-composer-clearance'),
        ),
      );
      final edgeInsets = clearance.padding as EdgeInsets;
      expect(
        edgeInsets.bottom,
        PandoraConversationLayer.compactComposerHeight + 24,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('recent chats opens only as the right-side drawer',
      (tester) async {
    await mount(tester, const Size(390, 800));
    expect(recentChats, findsOneWidget);
    expect(
      find.descendant(
        of: primaryDrawer,
        matching: find.text('Recent chats'),
      ),
      findsNothing,
    );

    for (var attempt = 0; attempt < 3; attempt++) {
      await tester.tap(recentChats);
      await tester.pumpAndSettle();
      expect(recentDrawer, findsOneWidget);
      expect(primaryDrawer, findsNothing);
      expect(
        find.byKey(const ValueKey<String>('pandora-recent-chats-panel')),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(recentDrawer, findsNothing);
      expect(tester.takeException(), isNull,
          reason: 'history attempt $attempt');
    }

    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(await drawerTile(tester, 'Projects'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Create project'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary and recent-chat drawers can never stack',
      (tester) async {
    await mount(tester, const Size(390, 800));
    final openRecentChats = tester.widget<IconButton>(recentChats).onPressed!;
    final menuButton = find.ancestor(
      of: menu,
      matching: find.byType(PandoraMenuButton),
    );
    expect(menuButton, findsOneWidget);
    final openPrimaryNavigation =
        tester.widget<PandoraMenuButton>(menuButton).onPressed;

    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(primaryDrawer, findsOneWidget);
    expect(recentDrawer, findsNothing);

    openRecentChats.call();
    await tester.pumpAndSettle();
    expect(primaryDrawer, findsNothing);
    expect(recentDrawer, findsOneWidget);

    openPrimaryNavigation();
    await tester.pumpAndSettle();
    expect(primaryDrawer, findsOneWidget);
    expect(recentDrawer, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty shell is logo-only and the resting composer is a floating pill',
    (tester) async {
      await mount(tester, const Size(390, 800));
      expect(
        find.byKey(const ValueKey<String>('pandora-logo-only-landing')),
        findsOneWidget,
      );
      expect(find.text('What can I help with?'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('ask-pandora-plus')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('ask-pandora-model-control')),
        findsOneWidget,
      );
      expect(find.textContaining('Model ·'), findsNothing);
      expect(find.textContaining('Reasoning ·'), findsNothing);

      final composer = tester.widget<Container>(
        find.byKey(const ValueKey<String>('ask-pandora-composer')),
      );
      final decoration = composer.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFF151515));
      expect(decoration.border, isNull);
      expect(decoration.borderRadius, BorderRadius.circular(27));
      final rect = tester.getRect(
        find.byKey(const ValueKey<String>('ask-pandora-composer')),
      );
      expect(rect.left, closeTo(14, .1));
      expect(rect.right, closeTo(390 - 14, .1));
      expect(rect.height, closeTo(54, .1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
      'attachment menu contains input actions without another navigation menu',
      (tester) async {
    await mount(tester, const Size(390, 800));
    await tester.tap(
      find.byKey(const ValueKey<String>('ask-pandora-objective')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('ask-pandora-plus')));
    await tester.pumpAndSettle();
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    expect(find.text('Settings & More'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat state survives keyboard changes and cross-page navigation',
      (tester) async {
    final intelligence = FakeChatIntelligence();
    await mount(
      tester,
      const Size(390, 800),
      intelligence: intelligence,
    );
    final conversationState = tester.state<AskPandoraScreenState>(
      find.byType(AskPandoraScreen),
    );

    final historyOffstage = find.byKey(
      const ValueKey<String>('pandora-active-chat-history-offstage'),
    );
    expect(tester.widget<Offstage>(historyOffstage).offstage, isFalse);
    expect(
      find.byKey(const ValueKey<String>('pandora-active-chat-minimize')),
      findsNothing,
    );

    await conversationState.submitExternalPrompt(
      'Start this conversation',
      requestFocus: false,
    );
    for (var i = 0;
        i < 40 && find.text('Conversation started.').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    expect(find.text('Start this conversation'), findsOneWidget);
    expect(intelligence.lastMessage, 'Start this conversation');
    expect(
        (intelligence.lastEnterpriseContext?['selectedObject']
            as Map?)?['coreMode'],
        'owner');

    addTearDown(tester.view.resetViewInsets);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(find.text('Start this conversation'), findsOneWidget);

    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(await drawerTile(tester, 'Projects'));
    await tester.pumpAndSettle();
    expect(tester.widget<Offstage>(historyOffstage).offstage, isTrue);
    expect(find.byTooltip('Create project'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('ask-pandora-composer')),
      findsOneWidget,
    );
    expect(
      identical(
        conversationState,
        tester.state<AskPandoraScreenState>(find.byType(AskPandoraScreen)),
      ),
      isTrue,
    );

    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(await drawerTile(tester, 'Pandora'));
    await tester.pumpAndSettle();
    expect(tester.widget<Offstage>(historyOffstage).offstage, isFalse);
    expect(find.text('Start this conversation'), findsOneWidget);
    expect(
      identical(
        conversationState,
        tester.state<AskPandoraScreenState>(find.byType(AskPandoraScreen)),
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
