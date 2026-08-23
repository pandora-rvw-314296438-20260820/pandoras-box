import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/models/pandora_models.dart';
import 'package:pandora_mobile/core/widgets/content_state.dart';
import 'package:pandora_mobile/core/widgets/freshness_label.dart';
import 'package:pandora_mobile/core/widgets/proof_ladder.dart';
import 'package:pandora_mobile/core/widgets/status_badge.dart';

import '../../helpers/foundation_catalog.dart';
import '../../helpers/test_app.dart';

void main() {
  testWidgets('status uses icon, text, and a semantic label', (tester) async {
    await tester.pumpWidget(
      testApp(
        child: const Scaffold(
          body: Center(
            child: StatusBadge(
              label: 'Needs attention',
              tone: PandoraStatusTone.attention,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.byIcon(Icons.priority_high_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('Needs attention'), findsOneWidget);
  });

  testWidgets('proof ladder announces independent stage states', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        child: const Scaffold(
          body: ProofLadder(stages: FoundationCatalog.stages),
        ),
      ),
    );

    expect(
      find.bySemanticsLabel(RegExp(r'Tested: Failed\. Deployed: Not checked')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });

  testWidgets('freshness has relative display and exact semantic time', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        child: Scaffold(
          body: FreshnessLabel(
            freshness: FreshnessInfo(
              state: FreshnessState.fresh,
              lastVerifiedAt: DateTime.utc(2026, 8, 14),
            ),
            now: DateTime.utc(2026, 8, 14, 1),
          ),
        ),
      ),
    );

    expect(find.text('Verified 1h ago'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('2026-08-14T00:00:00.000Z')),
      findsOneWidget,
    );
  });

  testWidgets('error state retries only after an explicit tap', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      testApp(
        child: Scaffold(
          body: ErrorContent(
            title: 'Could not refresh',
            message: 'Keep the prior snapshot.',
            onRetry: () => retries += 1,
          ),
        ),
      ),
    );

    expect(retries, 0);
    expect(find.bySemanticsLabel('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retries, 1);
  });

  test('negated truth labels never receive verified tone', () {
    for (final status in [
      'Not verified',
      'Unhealthy',
      'Unprotected',
      'Inactive',
    ]) {
      expect(statusToneFor(status), isNot(PandoraStatusTone.verified));
    }
  });

  test('risk and health language maps to truthful severity tones', () {
    expect(statusToneFor('High risk'), PandoraStatusTone.critical);
    expect(statusToneFor('Problem'), PandoraStatusTone.critical);
    expect(statusToneFor('Medium risk'), PandoraStatusTone.attention);
    expect(statusToneFor('Degraded'), PandoraStatusTone.attention);
    expect(statusToneFor('Not blocked'), PandoraStatusTone.neutral);
  });
}
