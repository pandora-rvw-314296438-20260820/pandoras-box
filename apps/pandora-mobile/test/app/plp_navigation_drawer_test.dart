import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/plp_enterprise_shell.dart';
import 'package:pandora_mobile/app/plp_navigation_drawer.dart';

void main() {
  Future<ScrollController> mountDrawer(
    WidgetTester tester, {
    double width = 390,
    double height = 844,
    double scale = 1,
    double keyboard = 0,
    ValueChanged<String>? onSelect,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final scroll = ScrollController();
    addTearDown(scroll.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, height),
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: Scaffold(
            body: PlpNavigationDrawer(
              scrollController: scroll,
              selectedDestination: 'home',
              recentChats: const [],
              recentChatsLoading: false,
              recentChatsError: null,
              onRetryRecentChats: () {},
              onSelectDestination: onSelect ?? (_) {},
              onSelectThread: (_) {},
              onNewChat: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return scroll;
  }

  testWidgets('PLP navigation leads with resort work, not system pages', (tester) async {
    String? selected;
    await mountDrawer(tester, onSelect: (value) => selected = value);

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Stays'), findsOneWidget);
    expect(find.text('Rooms'), findsOneWidget);
    expect(find.text('Guests'), findsOneWidget);
    expect(find.text('Experiences'), findsOneWidget);
    expect(find.text('Overview'), findsNothing);
    expect(find.text('Needs You'), findsNothing);

    final rooms = find.byKey(const ValueKey<String>('plp-drawer-rooms'));
    await tester.ensureVisible(rooms);
    await tester.tap(rooms);
    expect(selected, 'rooms');
    expect(tester.takeException(), isNull);
  });

  testWidgets('PLP search still reaches technical System destinations', (tester) async {
    String? selected;
    await mountDrawer(tester, onSelect: (value) => selected = value);

    await tester.tap(find.byKey(const ValueKey<String>('plp-drawer-search')));
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey<String>('plp-drawer-search-field'));
    await tester.enterText(field, 'tax');
    await tester.pumpAndSettle();

    final tax = find.byKey(
      const ValueKey<String>('plp-drawer-tax-compliance'),
    );
    expect(tax, findsOneWidget);
    await tester.tap(tax);
    expect(selected, 'tax-compliance');
    expect(tester.takeException(), isNull);
  });

  testWidgets('PLP full-width mobile drawer remains scrollable with keyboard', (tester) async {
    await mountDrawer(
      tester,
      width: 320,
      height: 640,
      scale: 1.6,
      keyboard: 200,
    );

    final drawer = find.byKey(
      const ValueKey<String>('plp-navigation-drawer'),
    );
    expect(drawer, findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('plp-drawer-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('plp-drawer-search-field')),
      'rooms',
    );
    await tester.pumpAndSettle();

    final rooms = find.byKey(const ValueKey<String>('plp-drawer-rooms'));
    await tester.ensureVisible(rooms);
    expect(rooms, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PLP command dock remains the universal Pandora composer', (tester) async {
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
    expect(find.text('Message Pandora'), findsOneWidget);

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
