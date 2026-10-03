import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/data/pandora_repository.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/models/pandora_models.dart';
import 'package:pandora_mobile/core/network/pandora_api_error.dart';
import 'package:pandora_mobile/core/security/pandora_auth.dart';
import 'package:pandora_mobile/features/simple/offline_evidence_screen.dart';

import '../../helpers/fake_owner_api.dart';
import '../../helpers/test_app.dart';

RepositorySnapshot<T> _snapshot<T>(T data,
        {int day = 3, bool cached = false}) =>
    RepositorySnapshot(
        data: data,
        source:
            cached ? RepositorySource.memoryCache : RepositorySource.network,
        fetchedAt: DateTime.utc(2026, 10, day, 8, 30));

class _Batch {
  final projects = Completer<RepositorySnapshot<List<ProjectSummary>>>();
  final connections = Completer<RepositorySnapshot<List<ConnectionSummary>>>();
  final activity = Completer<RepositorySnapshot<List<AuditEvent>>>();

  void complete(int systems, {bool cached = false}) {
    projects.complete(_snapshot(List.filled(systems, fixtureProject), day: 3));
    connections
        .complete(_snapshot(<ConnectionSummary>[], day: 1, cached: cached));
    activity.complete(_snapshot(<AuditEvent>[], day: 2));
  }

  void fail(Object error) {
    projects.completeError(error);
    connections.complete(_snapshot(<ConnectionSummary>[]));
    activity.complete(_snapshot(<AuditEvent>[]));
  }
}

class _Repository extends FakeRepository {
  _Repository(this.batches);
  final List<_Batch> batches;
  int projectReads = 0, connectionReads = 0, activityReads = 0;
  @override
  Future<RepositorySnapshot<List<ProjectSummary>>> projects(
      {bool allowCached = false}) {
    expect(allowCached, isTrue);
    return batches[projectReads++].projects.future;
  }

  @override
  Future<RepositorySnapshot<List<ConnectionSummary>>> connections(
      {bool allowCached = false}) {
    expect(allowCached, isTrue);
    return batches[connectionReads++].connections.future;
  }

  @override
  Future<RepositorySnapshot<List<AuditEvent>>> activity(
      {bool allowCached = false}) {
    expect(allowCached, isTrue);
    return batches[activityReads++].activity.future;
  }
}

class _Auth extends FakeAuth {
  final controller = StreamController<PandoraSession?>.broadcast(sync: true);
  PandoraSession? session = const PandoraSession(userId: 'first-user');
  @override
  Stream<PandoraSession?> get changes => controller.stream;
  @override
  PandoraSession? get currentSession => session;
  void change(PandoraSession? next) {
    session = next;
    controller.add(next);
  }
}

Widget _app(PandoraRepository repository,
        {PandoraAuth auth = const FakeAuth()}) =>
    testApp(
      themeMode: ThemeMode.dark,
      child: PandoraDependencies(
        auth: auth,
        repository: repository,
        diagnostics: DiagnosticsStore(),
        child: const Scaffold(body: OfflineEvidenceScreen()),
      ),
    );

Future<void> _refresh(WidgetTester tester) =>
    tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();

void _expectSystems(int count) {
  final row =
      find.ancestor(of: find.text('Systems'), matching: find.byType(Row));
  expect(
      find.descendant(of: row, matching: find.text('$count')), findsOneWidget);
}

void main() {
  testWidgets(
      'all independent reads begin together and show actual oldest observation',
      (tester) async {
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    final batch = _Batch();
    final repository = _Repository([batch]);
    await tester.pumpWidget(_app(repository));
    expect([
      repository.projectReads,
      repository.connectionReads,
      repository.activityReads
    ], [
      1,
      1,
      1
    ]);
    expect(find.text('Loading evidence…'), findsOneWidget);
    batch.complete(2, cached: true);
    await tester.pumpAndSettle();
    _expectSystems(2);
    expect(
        find.text('Oldest observation: 2026-10-01 08:30 UTC'), findsOneWidget);
    expect(
        find.text(
            'Showing earlier observations held in this session. They may be out of date.'),
        findsOneWidget);
    expect(find.textContaining('verified'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('latest refresh wins when an older request later fails',
      (tester) async {
    final first = _Batch(), second = _Batch();
    await tester.pumpWidget(_app(_Repository([first, second])));
    final refresh = _refresh(tester);
    second.complete(4);
    await refresh;
    await tester.pumpAndSettle();
    _expectSystems(4);
    first.fail(const PandoraApiError(
        kind: PandoraApiErrorKind.forbidden,
        message: 'RAW_PRIVATE_ERROR',
        code: 'FORBIDDEN'));
    await tester.pumpAndSettle();
    _expectSystems(4);
    expect(find.text('Evidence unavailable'), findsNothing);
    expect(find.textContaining('RAW_PRIVATE_ERROR'), findsNothing);
  });

  testWidgets(
      'scope replacement clears previous packet and fences a late old success',
      (tester) async {
    final initial = _Batch(), oldRefresh = _Batch(), nextScope = _Batch();
    final repository = _Repository([initial, oldRefresh]);
    await tester.pumpWidget(_app(repository));
    initial.complete(2);
    await tester.pumpAndSettle();
    _expectSystems(2);
    final refresh = _refresh(tester);
    await tester.pump();
    expect(find.text('Refreshing evidence…'), findsOneWidget);
    await tester.pumpWidget(_app(_Repository([nextScope])));
    expect(find.text('Systems'), findsNothing);
    expect(find.text('Loading evidence…'), findsOneWidget);
    nextScope.complete(5);
    await tester.pumpAndSettle();
    oldRefresh.complete(9);
    await refresh;
    await tester.pumpAndSettle();
    _expectSystems(5);
    expect(tester.takeException(), isNull);
  });

  for (final kind in [
    PandoraApiErrorKind.forbidden,
    PandoraApiErrorKind.sessionExpired
  ]) {
    testWidgets(
        '$kind clears previously visible packet and exposes a safe failure',
        (tester) async {
      final initial = _Batch(), denied = _Batch();
      await tester.pumpWidget(_app(_Repository([initial, denied])));
      initial.complete(3);
      await tester.pumpAndSettle();
      _expectSystems(3);
      final refresh = _refresh(tester);
      denied.fail(PandoraApiError(
          kind: kind, message: 'RAW_PRIVATE_ERROR', code: 'AUTH_FAILURE'));
      await refresh;
      await tester.pumpAndSettle();
      expect(find.text('Systems'), findsNothing);
      expect(
          find.text('Oldest observation: 2026-10-01 08:30 UTC'), findsNothing);
      expect(find.text('Evidence unavailable'), findsOneWidget);
      expect(
          find.text(kind == PandoraApiErrorKind.forbidden
              ? 'Access to this evidence is no longer available.'
              : 'Sign in again to view evidence.'),
          findsOneWidget);
      expect(find.textContaining('RAW_PRIVATE_ERROR'), findsNothing);
    });
  }

  testWidgets('unknown failures clear stale claims and Check again recovers',
      (tester) async {
    final failed = _Batch(), recovered = _Batch();
    await tester.pumpWidget(_app(_Repository([failed, recovered])));
    failed.fail(StateError('RAW_PRIVATE_ERROR'));
    await tester.pumpAndSettle();
    expect(find.text('Evidence unavailable'), findsOneWidget);
    expect(find.textContaining('RAW_PRIVATE_ERROR'), findsNothing);
    await tester.tap(find.text('Check again'));
    await tester.pump();
    recovered.complete(1);
    await tester.pumpAndSettle();
    _expectSystems(1);
    expect(find.text('Evidence unavailable'), findsNothing);
  });

  testWidgets(
      'account change clears packet and rejects late results without reusing the old repository',
      (tester) async {
    final initial = _Batch(), pending = _Batch();
    final auth = _Auth();
    addTearDown(auth.controller.close);
    final repository = _Repository([initial, pending]);
    await tester.pumpWidget(_app(repository, auth: auth));
    initial.complete(3);
    await tester.pumpAndSettle();
    final refresh = _refresh(tester);
    auth.change(null);
    await tester.pump();
    expect(find.text('Systems'), findsNothing);
    expect(find.text('Your account changed. Reopen Saved evidence.'),
        findsOneWidget);
    pending.complete(7);
    await refresh;
    await tester.pumpAndSettle();
    expect(find.text('Systems'), findsNothing);
    await tester.tap(find.text('Check again'));
    await tester.pump();
    expect(repository.projectReads, 2);
    expect(tester.takeException(), isNull);
  });
}
