import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/simple/advanced_mode_screen.dart';
import 'package:pandora_mobile/features/simple/more_screen.dart';

void main() {
  testWidgets('More exposes a deliberate Advanced Mode entry', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: MoreScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Professional mode'), findsOneWidget);
    expect(find.text('Advanced Mode'), findsOneWidget);
    expect(
      find.textContaining('Code, changes, database, deployments'),
      findsOneWidget,
    );
  });

  testWidgets('Advanced Mode converges the nine technical surfaces', (
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
      'Settings',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    expect(
      find.textContaining(
        'same project, version, deployment, runtime, and evidence truth',
      ),
      findsOneWidget,
    );
  });
}
