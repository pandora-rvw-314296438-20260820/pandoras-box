import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/features/simple/ask_pandora_screen.dart';

import '../../helpers/fake_owner_api.dart';
import '../../helpers/test_app.dart';

void main() {
  testWidgets('Characters appears in composer and selects Melodee',
      (tester) async {
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    await tester.pumpWidget(
      testApp(
        themeMode: ThemeMode.dark,
        child: PandoraDependencies(
          auth: const FakeAuth(),
          repository: FakeRepository(),
          diagnostics: DiagnosticsStore(),
          child: const AskPandoraScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('ask-pandora-plus')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('ask-pandora-menu-characters')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('ask-pandora-menu-characters')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Characters'), findsWidgets);
    expect(find.text('Melodee'), findsOneWidget);

    await tester.tap(find.text('Melodee'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('ask-pandora-character-context')),
      findsOneWidget,
    );
    expect(find.text('Character · Melodee'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
