
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/provider_ecosystem_screen.dart';

void main() {
  testWidgets('shows Pandora universal capability vocabulary', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProviderEcosystemScreen(onOpenConnections: () {}),
      ),
    );

    expect(find.text('Capabilities & Providers'), findsOneWidget);
    expect(find.textContaining('15 capability families'), findsOneWidget);

    final search =
        find.byKey(const ValueKey<String>('provider-ecosystem-search'));
    for (final capability in <String>[
      'Compute',
      'Data',
      'Telecom',
      'Communications',
      'Marketing',
      'Commerce',
      'Money',
      'Logistics',
      'Identity',
      'Government',
      'Location',
      'Documents',
      'Security',
      'Devices',
      'Intelligence',
    ]) {
      await tester.enterText(search, capability);
      await tester.pump();
      expect(find.text(capability), findsWidgets);
    }
  });

  testWidgets('searches provider catalog without claiming connectivity',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProviderEcosystemScreen(onOpenConnections: () {}),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('provider-ecosystem-search')),
      'Ubivelox',
    );
    await tester.pump();

    expect(find.text('Identity'), findsOneWidget);
    expect(find.text('Compute'), findsNothing);
    expect(
      find.textContaining('Catalog presence never means connected'),
      findsOneWidget,
    );
  });
}
