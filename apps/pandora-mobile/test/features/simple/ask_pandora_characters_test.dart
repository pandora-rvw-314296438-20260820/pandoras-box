import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/features/simple/ask_pandora_screen.dart';

import '../../helpers/fake_owner_api.dart';
import '../../helpers/test_app.dart';

void main() {
  testWidgets('Characters is not exposed in the composer menu', (tester) async {
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

    await tester.tap(
      find.byKey(const ValueKey<String>('ask-pandora-objective')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('ask-pandora-plus')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('ask-pandora-plus')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('ask-pandora-menu-characters')),
      findsNothing,
    );
    expect(find.text('Characters'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
