import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/plp_enterprise_shell.dart';
import 'package:pandora_mobile/app/plp_navigation_drawer.dart';

void main() {
  Future<ScrollController> mountDrawer(WidgetTester tester, {double width = 390, double height = 844,
      double scale = 1, double keyboard = 0, ValueChanged<String>? onSelect}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: MediaQueryData(size: Size(width, height), textScaler: TextScaler.linear(scale), viewInsets: EdgeInsets.only(bottom: keyboard)),
      child: Scaffold(body: PlpNavigationDrawer(
        scrollController: scroll, selectedDestination: 'home', recentChats: const [],
        recentChatsLoading: false, recentChatsError: null, onRetryRecentChats: () {},
        onSelectDestination: onSelect ?? (_) {}, onSelectThread: (_) {}, onNewChat: () {},
      )),
    )));
    await tester.pumpAndSettle();
    return scroll;
  }

  testWidgets('PLP header and footer never overlap scrollable navigation', (tester) async {
    String? selected;
    final scroll = await mountDrawer(tester, onSelect: (value) => selected = value);
    final header = find.byKey(const ValueKey<String>('plp-drawer-header-overlay'));
    final viewport = find.byKey(const ValueKey<String>('plp-drawer-scroll'));
    final footer = find.byKey(const ValueKey<String>('plp-drawer-bottom-overlay'));
    expect(tester.getRect(viewport).top, greaterThanOrEqualTo(tester.getRect(header).bottom));
    expect(tester.getRect(viewport).bottom, lessThanOrEqualTo(tester.getRect(footer).top));
    final initialHeader = tester.getRect(header);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getRect(header), initialHeader);
    await tester.ensureVisible(find.byKey(const ValueKey<String>('plp-drawer-tax-compliance')));
    await tester.pumpAndSettle();
    final tax = find.byKey(const ValueKey<String>('plp-drawer-tax-compliance'));
    expect(tester.getRect(tax).top, greaterThanOrEqualTo(tester.getRect(header).bottom));
    await tester.tap(tax);
    expect(selected, 'tax-compliance');
    expect(tester.takeException(), isNull);
  });

  testWidgets('PLP search finds Tax and System destinations and can clear focus', (tester) async {
    String? selected;
    await mountDrawer(tester, onSelect: (value) => selected = value);
    final toggle = find.byKey(const ValueKey<String>('plp-drawer-search'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey<String>('plp-drawer-search-field'));
    await tester.enterText(field, 'tax');
    await tester.pumpAndSettle();
    final tax = find.byKey(const ValueKey<String>('plp-drawer-tax-compliance'));
    expect(tax, findsOneWidget);
    await tester.tap(tax);
    expect(selected, 'tax-compliance');
    await tester.enterText(field, 'local ai');
    await tester.pumpAndSettle();
    expect(find.text('Local AI'), findsOneWidget);
    final focus = tester.widget<TextField>(field).focusNode!;
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    expect(find.byKey(const ValueKey<String>('plp-drawer-home')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 640), const Size(844, 390)]) {
    testWidgets('PLP navigation stays scrollable with keyboard and large text at $size', (tester) async {
      await mountDrawer(tester, width: size.width, height: size.height, scale: 2, keyboard: 200);
      await tester.tap(find.byKey(const ValueKey<String>('plp-drawer-search')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey<String>('plp-drawer-search-field')), 'tax');
      await tester.pumpAndSettle();
      final tax = find.byKey(const ValueKey<String>('plp-drawer-tax-compliance'));
      await tester.ensureVisible(tax);
      await tester.pumpAndSettle();
      expect(tax, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

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
