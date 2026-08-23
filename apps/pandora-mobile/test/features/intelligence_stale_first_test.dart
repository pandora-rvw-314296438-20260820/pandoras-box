import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/features/intelligence/owner_intelligence_screen.dart';

import '../helpers/fake_owner_api.dart';
import '../helpers/test_app.dart';

/// Regression net for P0.4.
///
/// A refresh must never replace verified owner content with a skeleton, and
/// retained content must always be labelled rather than silently presented as
/// live truth.
void main() {
  testWidgets('a failed refresh keeps labelled verified content', (
    tester,
  ) async {
    final repository = FakeRepository();

    await tester.pumpWidget(
      testApp(
        child: PandoraDependencies(
          auth: const FakeAuth(),
          repository: repository,
          diagnostics: DiagnosticsStore(),
          child: const OwnerIntelligenceScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The first load succeeded, so verified content is on screen.
    expect(find.text('Showing saved information'), findsNothing);
    expect(tester.takeException(), isNull);

    // The provider now fails. Refreshing must not blank the screen.
    repository.failing = true;
    await tester.tap(find.byTooltip('Refresh verified owner data'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.text('Showing saved information'),
      findsOneWidget,
      reason: 'Retained content must be labelled, never silently stale.',
    );
    expect(
      find.textContaining('could not be refreshed'),
      findsOneWidget,
      reason: 'The owner must be told the refresh failed.',
    );
    expect(
      find.textContaining('Verified'),
      findsWidgets,
      reason: 'Retained content must carry its verification age.',
    );
    expect(
      find.byType(LinearProgressIndicator),
      findsNothing,
      reason: 'A failed refresh must not fall back to a loading skeleton.',
    );
    expect(tester.takeException(), isNull);
  });
}
