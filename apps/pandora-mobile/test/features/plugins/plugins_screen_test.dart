import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/data/pandora_repository.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/models/pandora_models.dart';
import 'package:pandora_mobile/core/network/pandora_api_error.dart';
import 'package:pandora_mobile/features/plugins/plugins_screen.dart';

import '../../helpers/fake_owner_api.dart';
import '../../helpers/test_app.dart';

class _Connections extends FakeRepository {
  final result = Completer<RepositorySnapshot<List<ConnectionSummary>>>();
  Future<RepositorySnapshot<List<ConnectionSummary>>>? retryResult;
  int reads = 0;

  @override
  Future<RepositorySnapshot<List<ConnectionSummary>>> connections({
    bool allowCached = false,
  }) {
    reads++;
    return retryResult ?? result.future;
  }

  void complete([List<ConnectionSummary> rows = const []]) {
    result.complete(RepositorySnapshot(
      data: rows,
      source: RepositorySource.network,
      fetchedAt: DateTime.utc(2026, 10, 3),
    ));
  }
}

class _Registry implements PandoraIntelligenceApi {
  final result = Completer<PandoraCapabilityRegistry>();
  Future<PandoraCapabilityRegistry>? retryResult;
  int reads = 0;

  @override
  Future<PandoraCapabilityRegistry> capabilityRegistry() {
    reads++;
    return retryResult ?? result.future;
  }

  void complete() => result.complete(PandoraCapabilityRegistry(
        contractVersion: 'test',
        observedAt: DateTime.utc(2026, 10, 3),
        projectRequired: true,
        providers: const [],
      ));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mount(WidgetTester tester, _Connections repository,
    {_Registry? registry}) async {
  await setTestSurface(tester, logicalSize: const Size(390, 1000));
  await tester.pumpWidget(testApp(
      child: PandoraDependencies(
    auth: const FakeAuth(),
    repository: repository,
    diagnostics: DiagnosticsStore(),
    intelligence: registry,
    child: const PluginsScreen(),
  )));
  await tester.pump();
}

void main() {
  for (final registryFinishesFirst in [true, false]) {
    testWidgets(
        'pending reads do not become empty when registry finishes first=$registryFinishesFirst',
        (tester) async {
      final connections = _Connections();
      final registry = _Registry();
      await _mount(tester, connections, registry: registry);
      expect(find.text('Loading connection records'), findsOneWidget);
      expect(find.text('No connection records available'), findsNothing);
      expect(find.text('No matching connections'), findsNothing);
      if (registryFinishesFirst) {
        registry.complete();
      } else {
        connections.complete();
      }
      await tester.pump();
      expect(find.text('Loading connection records'), findsOneWidget);
      expect(find.text('No connection records available'), findsNothing);
      expect(
          find.text('No verified connections in these records.'), findsNothing);
      if (registryFinishesFirst) {
        connections.complete();
      } else {
        registry.complete();
      }
      await tester.pumpAndSettle();
      expect(find.text('No connection records available'), findsOneWidget);
      expect(find.text('Try a different search term.'), findsNothing);
      expect(find.text('Loading connection records'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'an actual query miss is distinct from zero records and clears back to the list',
      (tester) async {
    final connections = _Connections();
    connections.complete(const [
      ConnectionSummary(
        id: 'github-test',
        name: 'GitHub',
        purpose: 'Source changes',
        state: 'not_checked',
        status: 'Not checked yet',
        canRead: false,
        canChange: false,
        freshness: FreshnessInfo(state: FreshnessState.notChecked),
      )
    ]);
    await _mount(tester, connections);
    await tester.pumpAndSettle();
    expect(find.text('GitHub'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'missing-provider');
    await tester.pumpAndSettle();
    expect(find.text('No matching connections'), findsOneWidget);
    expect(find.text('No connection records available'), findsNothing);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('No matching connections'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final registryFails in [true, false]) {
    testWidgets(
        'failed ${registryFails ? 'registry' : 'connection'} read is not an empty success',
        (tester) async {
      final connections = _Connections();
      final registry = _Registry();
      await _mount(tester, connections, registry: registry);
      if (registryFails) {
        connections.complete();
        registry.result
            .completeError(const PandoraIntelligenceException('read failed'));
      } else {
        registry.complete();
        connections.result.completeError(const PandoraRepositoryException(
          kind: PandoraApiErrorKind.unavailable,
          code: 'READ_UNAVAILABLE',
          message: 'Private provider detail must not render',
        ));
      }
      await tester.pumpAndSettle();
      expect(find.text('Connection records could not load'), findsOneWidget);
      expect(find.text('No connection records available'), findsNothing);
      expect(find.text('No matching connections'), findsNothing);
      expect(
          find.text('Private provider detail must not render'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      connections.retryResult = Future.value(RepositorySnapshot(
        data: const <ConnectionSummary>[],
        source: RepositorySource.network,
        fetchedAt: DateTime.utc(2026, 10, 3),
      ));
      registry.retryResult = Future.value(PandoraCapabilityRegistry(
        contractVersion: 'test',
        observedAt: DateTime.utc(2026, 10, 3),
        projectRequired: true,
        providers: const [],
      ));
      await tester.ensureVisible(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('No connection records available'), findsOneWidget);
      expect(find.text('Connection records could not load'), findsNothing);
      expect(connections.reads, 2);
      expect(registry.reads, 2);
      expect(tester.takeException(), isNull);
    });
  }
}
