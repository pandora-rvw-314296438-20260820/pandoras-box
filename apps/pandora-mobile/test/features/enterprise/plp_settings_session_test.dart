import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/plp_editorial_surfaces.dart';

void main() {
  testWidgets('PLP settings confirms sign out before ending the session',
      (tester) async {
    var signOuts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PlpSettingsScreen(
          bootstrap: const <String, Object?>{
            'teamAccess': <String, Object?>{'members': <Object?>[]},
            'sourceHealth': <String, Object?>{
              'state': 'healthy',
              'message': 'Live provider',
            },
          },
          onOpenNavigation: () {},
          onOpenFullSettings: () {},
          onOpenLocalAi: () {},
          onOpenDeveloper: () {},
          onSignOut: () async {
            signOuts += 1;
          },
        ),
      ),
    );

    final signOut = find.byKey(const ValueKey('plp-settings-sign-out'));
    await tester.ensureVisible(signOut);
    await tester.tap(signOut);
    await tester.pumpAndSettle();

    expect(find.text('Sign out of this device?'), findsOneWidget);
    expect(signOuts, 0);

    await tester.tap(find.byKey(const ValueKey('plp-sign-out-cancel')));
    await tester.pumpAndSettle();
    expect(signOuts, 0);

    await tester.tap(signOut);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plp-sign-out-confirm')));
    await tester.pumpAndSettle();

    expect(signOuts, 1);
    expect(tester.takeException(), isNull);
  });
}
