import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_chat_shell.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/features/simple/ask_pandora_screen.dart';

import '../helpers/fake_owner_api.dart';
import '../helpers/test_app.dart';

void main() {
  Future<void> mount(WidgetTester tester, Size size) async {
    await setTestSurface(tester, logicalSize: size);
    await tester.pumpWidget(
      testApp(
        child: PandoraDependencies(
          auth: const FakeAuth(),
          repository: FakeRepository(),
          diagnostics: DiagnosticsStore(),
          child: const PandoraChatShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final menu = find.byTooltip('Open navigation');

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
      final drawer = find.byType(Drawer);
      for (final title in <String>[
        'Pandora',
        'Projects',
        'Needs You',
        'Activity',
        'Connections',
        'Saved evidence',
        'Verify & Safety',
        'Settings & More',
      ]) {
        expect(
          find.descendant(
            of: drawer,
            matching: find.widgetWithText(ListTile, title),
          ),
          findsOneWidget,
        );
      }
      await tester.tap(
        find.descendant(
          of: drawer,
          matching: find.widgetWithText(ListTile, 'Projects'),
        ),
      );
      await tester.pumpAndSettle();
      expect(menu, findsOneWidget);
      expect(find.byTooltip('Create project'), findsOneWidget);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: drawer,
          matching: find.widgetWithText(ListTile, 'Pandora'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Keep this draft'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsNothing);
      expect(find.text('Keep this draft'), findsOneWidget);
    });
  }

  testWidgets('tablet keeps the persistent sidebar without a drawer trigger',
      (tester) async {
    await mount(tester, const Size(1024, 800));
    expect(menu, findsNothing);
    expect(find.byType(Drawer), findsNothing);
    expect(find.widgetWithText(ListTile, 'Connections'), findsOneWidget);
    expect(tester.getSize(find.byType(AskPandoraScreen)).width, 759);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Needs You and Settings & More expose exactly one navigation control',
      (tester) async {
    await mount(tester, const Size(390, 800));
    for (final title in <String>[
      'Needs You',
      'Settings & More',
      'Connections',
      'Activity',
      'Saved evidence',
      'Verify & Safety',
    ]) {
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.widgetWithText(ListTile, title),
        ),
      );
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

  testWidgets(
      'attachment menu contains input actions without another navigation menu',
      (tester) async {
    await mount(tester, const Size(390, 800));
    await tester.tap(find.byKey(const ValueKey<String>('ask-pandora-plus')));
    await tester.pumpAndSettle();
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    expect(find.text('Settings & More'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
