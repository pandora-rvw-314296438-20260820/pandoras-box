import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/data/pandora_repository.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/models/pandora_models.dart';
import 'package:pandora_mobile/core/network/pandora_api_error.dart';
import 'package:pandora_mobile/features/simple/pandora_simple_ui.dart';
import 'package:pandora_mobile/features/simple/simple_safety_screen.dart';

import '../../helpers/fake_owner_api.dart';
import '../../helpers/test_app.dart';

SafetyOverview _safety({String status = 'Verified', bool complete = true}) =>
    SafetyOverview(
      state: 'verified',
      status: 'Verified',
      auditChain:
          const AuditChainStatus(valid: true, label: 'Audit chain verified'),
      sections: [
        SafetySection(
          id: 'claims',
          title: 'Claims',
          items: [
            SafetyItem(
                id: 'identity',
                title: 'Identity access',
                status: status,
                explanation: 'Observed access state.'),
            if (complete) ...[
              const SafetyItem(
                  id: 'approval',
                  title: 'Approval execution',
                  status: 'Verified',
                  explanation: 'Observed execution state.'),
              const SafetyItem(
                  id: 'source',
                  title: 'Source authority',
                  status: 'Verified',
                  explanation: 'Observed source state.'),
              const SafetyItem(
                  id: 'runtime',
                  title: 'Credential protection',
                  status: 'Verified',
                  explanation: 'Observed runtime state.'),
            ],
          ],
        ),
      ],
      extraIdentityCheckAdvertised: false,
    );

class _SafetyRepository extends FakeRepository {
  _SafetyRepository(this.read);
  Future<RepositorySnapshot<SafetyOverview>> Function() read;
  @override
  Future<RepositorySnapshot<SafetyOverview>> safety() => read();
}

RepositorySnapshot<SafetyOverview> _snapshot(SafetyOverview safety,
        {bool cached = false}) =>
    RepositorySnapshot(
        data: safety,
        source:
            cached ? RepositorySource.memoryCache : RepositorySource.network,
        fetchedAt: DateTime.utc(2026, 10, 3));

Widget _app(PandoraRepository repository) => testApp(
      themeMode: ThemeMode.dark,
      child: PandoraDependencies(
        auth: const FakeAuth(),
        repository: repository,
        diagnostics: DiagnosticsStore(),
        child: const Scaffold(body: SimpleSafetyScreen()),
      ),
    );

void main() {
  for (final entry in <String, String>{
    'Not verified': 'Not checked',
    'Unverified': 'Not checked',
    'Not connected': 'Blocked',
    'Inactive': 'Blocked',
  }.entries) {
    testWidgets('${entry.key} never becomes healthy by substring',
        (tester) async {
      await setTestSurface(tester, logicalSize: const Size(390, 844));
      final repository =
          _SafetyRepository(() async => _snapshot(_safety(status: entry.key)));
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();
      expect(find.text('Your protection is healthy'), findsNothing);
      final pills =
          tester.widgetList<PandoraStatusPill>(find.byType(PandoraStatusPill));
      expect(pills.any((pill) => pill.label == entry.value), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'verified audit cannot hide missing protection layers and badges stay graphite',
      (tester) async {
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    await tester.pumpWidget(_app(
        _SafetyRepository(() async => _snapshot(_safety(complete: false)))));
    await tester.pumpAndSettle();
    expect(find.text('Protection is not verified'), findsOneWidget);
    expect(find.text('3 not verified'), findsOneWidget);
    final badges =
        tester.widgetList<PandoraIconBadge>(find.byType(PandoraIconBadge));
    final pills =
        tester.widgetList<PandoraStatusPill>(find.byType(PandoraStatusPill));
    expect(badges.every((badge) => badge.background != Colors.white), isTrue);
    expect(pills.every((pill) => pill.background != Colors.white), isTrue);
    expect(
        pills
            .where((pill) => pill.label == 'Not checked')
            .every((pill) => pill.background == PandoraSimpleColors.surface),
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'healthy claims require current observations and failed refresh removes healthy aggregate',
      (tester) async {
    final repository = _SafetyRepository(() async => _snapshot(_safety()));
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    expect(find.text('Your protection is healthy'), findsOneWidget);
    repository.read = () async => throw const PandoraApiError(
        kind: PandoraApiErrorKind.unavailable,
        message: 'Unavailable',
        code: 'TEST_UNAVAILABLE');
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(find.text('Your protection is healthy'), findsNothing);
    expect(find.text('Protection is not verified'), findsOneWidget);
    expect(
        find.text(
            'Refresh failed. Earlier observations below may be out of date.'),
        findsOneWidget);
    repository.read = () async => _snapshot(_safety(), cached: true);
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(find.text('Your protection is healthy'), findsNothing);
  });

  testWidgets(
      'repository change cannot reuse or complete an old safety controller',
      (tester) async {
    final oldRead = Completer<RepositorySnapshot<SafetyOverview>>();
    await tester.pumpWidget(_app(_SafetyRepository(() => oldRead.future)));
    await tester.pump();
    await tester.pumpWidget(_app(_SafetyRepository(
        () async => _snapshot(_safety(status: 'Not verified')))));
    await tester.pumpAndSettle();
    oldRead.complete(_snapshot(_safety()));
    await tester.pumpAndSettle();
    expect(find.text('Protection is not verified'), findsOneWidget);
    expect(find.text('Your protection is healthy'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
