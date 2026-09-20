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
                ],
                recentChatsLoading: false,
                recentChatsError: null,
                onRetryRecentChats: () {},
                onSelectDestination: (value) => selected = value,
                onSelectThread: (_) {},
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
  testWidgets('PLP command dock exposes destination button semantics', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: PlpCommandDock(
            selectedIndex: 0,
            controller: controller,
            focusNode: focusNode,
            showPersistentComposer: false,
            onSubmit: () async {},
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final entry in <(String, bool)>[
      ('Home', true),
      ('Alfred', false),
      ('Operations', false),
      ('Vision', false),
      ('Local AI', false),
    ]) {
      final finder = find.bySemanticsLabel(entry.$1);
      expect(finder, findsOneWidget);
      expect(
        tester.getSemantics(finder),
        matchesSemantics(
          label: entry.$1,
          isButton: true,
          isSelected: entry.$2,
        ),
      );
    }
;
  });

}
