import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/data/pandora_repository.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/models/pandora_models.dart';
import 'package:pandora_mobile/features/connections/connections_screen.dart';

import '../../helpers/fake_owner_api.dart';
import '../../helpers/test_app.dart';

void main() {
  testWidgets('Connections renders Partial without raw account identifiers',
      (tester) async {
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    await tester.pumpWidget(
      testApp(
        child: PandoraDependencies(
          auth: const FakeAuth(),
          repository: _ConnectionsRepository(),
          diagnostics: DiagnosticsStore(),
          child: const ConnectionsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Partial'), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('Pandora GitHub account'), findsOneWidget);
    expect(find.textContaining('pandora-rvw-314296438-20260820'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('connections-verify-all')),
      findsOneWidget,
    );
    expect(find.text('Verify all (2)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _ConnectionsRepository extends FakeRepository {
  @override
  Future<RepositorySnapshot<List<ConnectionSummary>>> connections({
    bool allowCached = false,
  }) async =>
      RepositorySnapshot<List<ConnectionSummary>>(
        data: <ConnectionSummary>[
          ConnectionSummary(
            id: 'github-fixture',
            name: 'GitHub Account — pandora-rvw-314296438-20260820',
            purpose: 'Code, issues, and proposed changes',
            state: 'not_checked',
            status: 'Not checked yet',
            canRead: false,
            canChange: false,
            freshness: const FreshnessInfo(
              state: FreshnessState.notChecked,
            ),
          ),
          ConnectionSummary(
            id: 'vercel-fixture',
            name: 'Vercel',
            purpose: 'Live web versions and service health',
            state: 'Connected',
            status: 'Authorized',
            canRead: false,
            canChange: false,
            freshness: FreshnessInfo(
              state: FreshnessState.fresh,
              lastVerifiedAt: DateTime.utc(2026, 10, 2, 0),
            ),
          ),
        ],
        source: RepositorySource.network,
        fetchedAt: DateTime.utc(2026, 10, 2, 1),
      );
}
