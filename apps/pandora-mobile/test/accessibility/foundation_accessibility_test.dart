import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/foundation_catalog.dart';
import '../helpers/test_app.dart';

void main() {
  testWidgets('foundation remains accessible at 320px and 2x text', (
    tester,
  ) async {
    await setTestSurface(tester, logicalSize: const Size(320, 800));
    await tester.pumpWidget(
      testApp(
        child: const FoundationCatalog(),
        textScaler: TextScaler.linear(2),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel("Pandora's Box"), findsOneWidget);
    expect(find.bySemanticsLabel('Needs attention'), findsOneWidget);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });
}
