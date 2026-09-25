import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/plp_enterprise_shell.dart';
import 'package:pandora_mobile/app/plp_navigation_drawer.dart';

void main() {
  testWidgets(
    'PLP drawer uses responsive premium navigation hierarchy',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String? selected;
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: PlpNavigationDrawer(
                selectedDestination: 'home',
                recentChats: const <PlpRecentChatItem>[
                  PlpRecentChatItem(
                    id: 'thread-1',
                    title: 'Connect to GitHub',
                  ),
                  PlpRecentChatItem(id: 'thread-2', title: 'Guest arrival briefing'),
                  PlpRecentChatItem(id: 'thread-3', title: 'Today occupancy'),
                  PlpRecentChatItem(id: 'thread-4', title: 'Restaurant operations'),
                  PlpRecentChatItem(id: 'thread-5', title: 'VIP guest requests'),
                  PlpRecentChatItem(id: 'thread-6', title: 'Revenue summary'),
                  PlpRecentChatItem(id: 'thread-7', title: 'Housekeeping priorities'),
                  PlpRecentChatItem(id: 'thread-8', title: 'Airport transfers'),
                  PlpRecentChatItem(id: 'thread-9', title: 'Tomorrow arrivals'),
                  PlpRecentChatItem(id: 'thread-10', title: 'Owner follow-ups'),
                ],
                recentChatsLoading: false,
                recentChatsError: null,
                onRetryRecentChats: () {},
                onSelectDestination: (value) => selected = value,
                onSelectThread: (_) {},
                onNewChat: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final drawer = find.byKey(
          const ValueKey<String>('plp-navigation-drawer'),
        );
        expect(drawer, findsOneWidget);
        expect(tester.getSize(drawer).width, closeTo(296.4, .6));
        expect(tester.getSize(drawer).height, closeTo(844, .6));
        final drawerWidget = tester.widget<Drawer>(drawer);
        expect(drawerWidget.backgroundColor, Colors.transparent);

        final scrollView = find.byKey(
          const ValueKey<String>('plp-drawer-scroll'),
        );
        final headerOverlay = find.byKey(
          const ValueKey<String>('plp-drawer-header-overlay'),
        );
        expect(scrollView, findsOneWidget);
        expect(headerOverlay, findsOneWidget);
        expect(find.byKey(const ValueKey<String>('plp-drawer-bottom-overlay')), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('plp-drawer-new-chat')), findsOneWidget);
        expect(
          tester.getTopLeft(scrollView).dy,
          closeTo(tester.getTopLeft(headerOverlay).dy, .5),
        );

        final underlayTarget = find.text('Guest Experience');
        final headerRect = tester.getRect(headerOverlay);
        final targetBefore = tester.getCenter(underlayTarget).dy;
        final desiredTargetY = headerRect.bottom - 18;
        await tester.drag(
          scrollView,
          Offset(0, -(targetBefore - desiredTargetY)),
        );
        await tester.pumpAndSettle();

        final targetAfter = tester.getRect(underlayTarget);
        expect(targetAfter.top, lessThan(headerRect.bottom));
        expect(targetAfter.bottom, greaterThan(headerRect.top));

        await tester.drag(scrollView, const Offset(0, 220));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(underlayTarget).top,
          greaterThan(headerRect.bottom),
        );

        expect(find.text('Pandora'), findsOneWidget);
        expect(find.text('PLP Boracay'), findsOneWidget);
        expect(find.text('Owner workspace'), findsOneWidget);
        expect(find.text('PLP Boracay owner workspace'), findsOneWidget);
        expect(find.text('BUSINESS'), findsNothing);
        expect(find.text('Recent chats'), findsOneWidget);
        expect(find.text('Connect to GitHub'), findsOneWidget);
        expect(find.bySemanticsLabel('Home, selected'), findsOneWidget);

        const ordered = <String>[
          'Home',
          'Overview',
          'Tax & Compliance',
          'Operations',
          'Vision',
          'Guest Experience',
          'Team & Access',
          'Revenue',
          'Needs You',
          'Activity',
          'Settings',
        ];
        var previous = -1.0;
        for (final label in ordered) {
          final finder = find.text(label);
          expect(finder, findsOneWidget);
          final center = tester.getCenter(finder);
          expect(center.dy, greaterThan(previous));
          previous = center.dy;
        }

        await tester.ensureVisible(find.text('Tax & Compliance'));
        await tester.tap(find.text('Tax & Compliance'));
        await tester.pump();
        expect(selected, 'tax-compliance');

        await tester.ensureVisible(find.text('Overview'));
        await tester.tap(find.text('Overview'));
        await tester.pump();
        expect(selected, 'overview');

        await tester.ensureVisible(find.text('System / Developer'));
        await tester.tap(find.text('System / Developer'));
        await tester.pumpAndSettle();
        expect(find.text('Privileged technical surfaces'), findsOneWidget);
        expect(find.text('Local AI'), findsOneWidget);
        expect(find.text('Developer diagnostics'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  );
  testWidgets('PLP command dock is the universal Pandora composer', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var submitted = false;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: PlpCommandDock(
            controller: controller,
            focusNode: focusNode,
            onSubmit: () async {
              submitted = true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('plp-persistent-command-bar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('plp-command-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('plp-command-submit')),
      findsOneWidget,
    );
    expect(find.text('Message Pandora'), findsOneWidget);
    expect(find.byIcon(Icons.view_in_ar_outlined), findsOneWidget);
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

    for (final legacyLabel in <String>[
      'Home',
      'Alfred',
      'Operations',
      'Vision',
      'Local AI',
      'Who needs attention?',
      'Show VIP guests',
      'Who arrives next?',
      'Who has access?',
      'Add team member',
      'Recent activity',
      'What needs attention?',
      'Show guest activity',
      'Show team updates',
    ]) {
      expect(find.text(legacyLabel), findsNothing);
    }

    await tester.enterText(
      find.byKey(const ValueKey<String>('plp-command-field')),
      'Check today arrivals',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('plp-command-submit')),
    );
    await tester.pump();

    expect(submitted, isTrue);
  });

}
