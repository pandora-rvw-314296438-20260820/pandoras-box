import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/design/pandora_theme.dart';
import 'package:pandora_mobile/core/design/pandora_tokens.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/widgets/pandora_route_boundary.dart';
import 'package:pandora_mobile/features/settings/settings_screen.dart';
import 'package:pandora_mobile/features/simple/more_screen.dart';

import '../../helpers/fake_owner_api.dart';
import '../../helpers/test_app.dart';

void main() {
  for (final callerDark in [true, false]) {
    testWidgets(
        'More preserves the caller theme on pushed Settings: dark=$callerDark',
        (tester) async {
      await setTestSurface(tester, logicalSize: const Size(390, 844));
      final callerTheme =
          callerDark ? PandoraTheme.graphite : PandoraTheme.porcelain;
      await tester.pumpWidget(PandoraDependencies(
        auth: const FakeAuth(),
        repository: FakeRepository(),
        diagnostics: DiagnosticsStore(),
        child: testApp(
          themeMode: callerDark ? ThemeMode.light : ThemeMode.dark,
          child: Theme(
              data: callerTheme, child: const Scaffold(body: MoreScreen())),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      final settings = find.byType(SettingsScreen);
      expect(settings, findsOneWidget);
      final context = tester.element(settings);
      expect(Theme.of(context).brightness, callerTheme.brightness);
      final boundaryMaterial = find
          .descendant(
            of: find.descendant(
                of: settings, matching: find.byType(PandoraRouteBoundary)),
            matching: find.byType(Material),
          )
          .first;
      expect(tester.widget<Material>(boundaryMaterial).color,
          callerTheme.extension<PandoraPalette>()!.canvas);
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
      expect(find.byType(MoreScreen), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
