import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/simple/advanced_mode_screen.dart';
import 'package:pandora_mobile/features/simple/more_screen.dart';

void main() {
  testWidgets('More keeps professional tools available without visual clutter', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: MoreScreen()));
    await tester.pumpAndSettle();

    expect(find.text('When you need more'), findsOneWidget);
    expect(find.text('Professional tools'), findsOneWidget);
    expect(
      find.textContaining('Code, versions, runtime, evidence'),
      findsOneWidget,
    );
    expect(find.text('Advanced requests'), findsNothing);
    expect(find.text('Developer details'), findsNothing);
  });

  testWidgets('Advanced Mode exposes technical surfaces without duplicate settings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: AdvancedModeScreen()));
    await tester.pumpAndSettle();

    for (final label in <String>[
      'Code',
      'Changes',
      'Database',
      'Deployments',
      'Jobs & Logs',
      'Versions',
      'Evidence',
      'Runtime',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    expect(find.text('Settings'), findsNothing);
    expect(
      find.textContaining(
        'same project, version, deployment, runtime, and evidence truth',
      ),
      findsOneWidget,
    );
  });
}
