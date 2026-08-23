import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_app.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/app/pandora_shell.dart';
import 'package:pandora_mobile/core/data/pandora_repository.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/models/pandora_models.dart';
import 'package:pandora_mobile/core/network/pandora_api_error.dart';
import 'package:pandora_mobile/core/security/pandora_auth.dart';
import 'package:pandora_mobile/features/approvals/approvals_screen.dart';
import 'package:pandora_mobile/features/command/command_screen.dart';
import 'package:pandora_mobile/features/diagnostics/developer_diagnostics_screen.dart';
import 'package:pandora_mobile/features/home/home_screen.dart';

import '../helpers/test_app.dart';

class _Auth implements PandoraAuth {
  const _Auth({this.session = const PandoraSession(userId: 'fixture')});

  final PandoraSession? session;

  @override
  Stream<PandoraSession?> get changes => const Stream<PandoraSession?>.empty();

  @override
  PandoraSession? get currentSession => session;

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}

class _Repository implements PandoraRepository {
  int homeCalls = 0;
  int projectCalls = 0;
  int approvalCalls = 0;
  int actionCalls = 0;
  int activityCalls = 0;

  RepositorySnapshot<T> _snapshot<T>(T data) => RepositorySnapshot<T>(
    data: data,
    source: RepositorySource.network,
    fetchedAt: DateTime.utc(2026, 8, 14),
  );

  RepositorySnapshot<HomeSummary> _homeSnapshot() => _snapshot(
    const HomeSummary(
      healthState: 'protected',
      healthLabel: 'Protected',
      freshness: FreshnessInfo(state: FreshnessState.notChecked),
      approvalCount: 0,
      activeProjectCount: 0,
      needsAttentionCount: 0,
      topProjects: <ProjectSummary>[],
      recentActivity: <AuditEvent>[],
    ),
  );

  @override
  Future<RepositorySnapshot<HomeSummary>> home() async {
    homeCalls += 1;
    return _homeSnapshot();
  }

  @override
  Future<RepositorySnapshot<List<ProjectSummary>>> projects({
    bool allowCached = false,
  }) async {
    projectCalls += 1;
    return _snapshot(const <ProjectSummary>[]);
  }

  @override
  Future<RepositorySnapshot<List<ApprovalSummary>>> approvals() async {
    approvalCalls += 1;
    return _snapshot(const <ApprovalSummary>[]);
  }

  @override
  Future<RepositorySnapshot<List<ActionDefinition>>> actions() async {
    actionCalls += 1;
    return _snapshot(const <ActionDefinition>[]);
  }

  @override
  Future<RepositorySnapshot<List<AuditEvent>>> activity({
    bool allowCached = false,
  }) async {
    activityCalls += 1;
    return _snapshot(const <AuditEvent>[]);
  }

  @override
  Future<RepositorySnapshot<List<ConnectionSummary>>> connections({
    bool allowCached = false,
  }) async => _snapshot(const <ConnectionSummary>[]);

  @override
  Future<RepositorySnapshot<ProjectDetail>> project(
    String id, {
    bool allowCached = false,
  }) => throw UnimplementedError();

  @override
  Future<RepositorySnapshot<SafetyOverview>> safety() async => _snapshot(
    const SafetyOverview(
      state: 'not_checked',
      status: 'Not checked',
      auditChain: AuditChainStatus(
        valid: false,
        label: 'Audit chain needs attention',
      ),
      sections: <SafetySection>[],
      extraIdentityCheckAdvertised: false,
    ),
  );

  @override
  Future<IntakeReceipt> ask({
    required String message,
    String? projectId,
    String? idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<ApprovalDecisionResult> decideApproval({
    required String approvalId,
    required ApprovalDecision decision,
    String reason = '',
  }) => throw UnimplementedError();

  @override
  Future<IntakeReceipt> runAction({
    required String actionId,
    String? projectId,
    String? message,
    String? idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<IntakeReceipt> verifyExactSource({
    required String projectId,
    required String exactSha,
    required WorkerJobClass jobClass,
    int? maxRuntimeSeconds,
    String? idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<WorkerExecutionStatus> workerExecution({required String planId}) =>
      throw UnimplementedError();

  @override
  void clearReadOnlyCache() {}

  @override
  void dispose() {}
}

class _MutableAuth implements PandoraAuth {
  _MutableAuth(PandoraSession? session) : _session = session;

  final StreamController<PandoraSession?> _changes =
      StreamController<PandoraSession?>.broadcast(sync: true);
  PandoraSession? _session;

  void setSession(PandoraSession? session) {
    _session = session;
    _changes.add(session);
  }

  @override
  Stream<PandoraSession?> get changes => _changes.stream;

  @override
  PandoraSession? get currentSession => _session;

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async => setSession(null);

  Future<void> close() => _changes.close();
}

class _AuthorizationRepository extends _Repository
    implements AuthorizationInvalidationSource {
  final StreamController<AuthorizationInvalidation> _invalidations =
      StreamController<AuthorizationInvalidation>.broadcast(sync: true);

  @override
  Stream<AuthorizationInvalidation> get authorizationInvalidations =>
      _invalidations.stream;
  Completer<RepositorySnapshot<HomeSummary>>? delayedHome;

  @override
  Future<RepositorySnapshot<HomeSummary>> home() {
    final delayed = delayedHome;
    delayedHome = null;
    return delayed?.future ?? super.home();
  }

  void invalidate(int generation) => _invalidations.add(
    AuthorizationInvalidation(
      generation: generation,
      kind: PandoraApiErrorKind.forbidden,
      message: 'Owner access changed.',
    ),
  );

  Future<void> close() => _invalidations.close();
}

class _ThrowingSignOutAuth extends _MutableAuth {
  _ThrowingSignOutAuth(super.session);

  @override
  Future<void> signOut() async {
    throw const PandoraAuthFailure('Fixture sign-out failure.');
  }
}

class _CommandRepository extends _Repository {
  final List<String?> idempotencyKeys = <String?>[];

  @override
  Future<IntakeReceipt> ask({
    required String message,
    String? projectId,
    String? idempotencyKey,
  }) async {
    idempotencyKeys.add(idempotencyKey);
    if (idempotencyKeys.length == 1) {
      throw const PandoraApiError(
        kind: PandoraApiErrorKind.ambiguousMutation,
        message: 'Pandora could not confirm the outcome.',
        code: 'AMBIGUOUS_FIXTURE',
      );
    }
    return const IntakeReceipt(
      reply: 'The request is recorded.',
      needsApproval: false,
      actionId: 'action-fixture-1',
      status: IntakeStatus(
        whatChanged: 'Request recorded.',
        whereWeAre: 'Planning',
        whatIsDone: 'Intake complete.',
        whatIsHappeningNow: 'Checking preconditions.',
        whatIWillDoNext: 'Show the plan.',
      ),
    );
  }
}

class _ApprovalRepository extends _Repository {
  @override
  Future<RepositorySnapshot<List<ApprovalSummary>>> approvals() async =>
      _snapshot(<ApprovalSummary>[
        const ApprovalSummary(
          id: 'approval-fixture-1',
          action: 'Publish a candidate',
          reason: 'Owner decision required.',
          change: 'A release alias would move.',
          risk: ActionRisk.high,
          reversible: false,
          decision: 'Pending',
          state: ApprovalState.pending,
        ),
      ]);
}

class _ConflictApprovalRepository extends _Repository {
  _ConflictApprovalRepository({
    required this.refreshFails,
    this.decisionErrorCode = 'APPROVAL_CONFLICT',
  });

  final bool refreshFails;
  final String decisionErrorCode;
  var approvalLoads = 0;

  ApprovalSummary get _pending => ApprovalSummary(
    id: 'approval-conflict-fixture',
    action: 'Publish a candidate',
    reason: 'Owner decision required.',
    change: 'A release alias would move.',
    risk: ActionRisk.high,
    reversible: false,
    decision: 'Pending',
    state: ApprovalState.pending,
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  );

  @override
  Future<RepositorySnapshot<List<ApprovalSummary>>> approvals() async {
    approvalLoads += 1;
    if (approvalLoads == 1) return _snapshot(<ApprovalSummary>[_pending]);
    if (refreshFails) {
      throw const PandoraApiError(
        kind: PandoraApiErrorKind.unavailable,
        message: 'Queue refresh failed.',
        code: 'REFRESH_FAILED',
      );
    }
    if (decisionErrorCode == 'APPROVAL_FORBIDDEN') {
      return _snapshot(<ApprovalSummary>[_pending]);
    }
    return _snapshot(const <ApprovalSummary>[]);
  }

  @override
  Future<ApprovalDecisionResult> decideApproval({
    required String approvalId,
    required ApprovalDecision decision,
    String reason = '',
  }) async {
    throw PandoraApiError(
      kind: decisionErrorCode == 'APPROVAL_FORBIDDEN'
          ? PandoraApiErrorKind.forbidden
          : PandoraApiErrorKind.conflict,
      message: 'That approval is no longer available.',
      code: decisionErrorCode,
    );
  }
}

class _UnverifiedHomeRepository extends _Repository {
  @override
  Future<RepositorySnapshot<HomeSummary>> home() async =>
      _snapshot(HomeSummary.fromJson(<String, Object?>{}));
}

void main() {
  testWidgets('PandoraApp follows system brightness', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      PandoraApp(
        auth: const _Auth(session: null),
        repository: _Repository(),
        diagnostics: DiagnosticsStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('tabs load lazily and preserve their first mounted state', (
    tester,
  ) async {
    await setTestSurface(tester, logicalSize: const Size(400, 800));
    final repository = _Repository();
    await tester.pumpWidget(
      testApp(
        child: PandoraDependencies(
          auth: _Auth(),
          repository: repository,
          diagnostics: DiagnosticsStore(),
          child: const PandoraShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.homeCalls, 1);
    expect(repository.projectCalls, 0);
    expect(repository.approvalCalls, 0);
    expect(repository.actionCalls, 0);
    expect(repository.activityCalls, 0);

    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    expect(repository.projectCalls, 1);

    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    expect(repository.projectCalls, 1);
  });

  testWidgets('sign-out removes every pushed authenticated route', (
    tester,
  ) async {
    await setTestSurface(tester, logicalSize: const Size(400, 800));
    final auth = _MutableAuth(const PandoraSession(userId: 'fixture'));
    addTearDown(auth.close);
    await tester.pumpWidget(
      PandoraApp(
        auth: auth,
        repository: _Repository(),
        diagnostics: DiagnosticsStore(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);

    auth.setSession(null);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsNothing);
    expect(find.text('Sign in securely'), findsOneWidget);
  });

  testWidgets('switching users destroys the prior user route tree', (
    tester,
  ) async {
    await setTestSurface(tester, logicalSize: const Size(400, 800));
    final auth = _MutableAuth(const PandoraSession(userId: 'owner-a'));
    addTearDown(auth.close);
    await tester.pumpWidget(
      PandoraApp(
        auth: auth,
        repository: _Repository(),
        diagnostics: DiagnosticsStore(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);

    auth.setSession(const PandoraSession(userId: 'owner-b'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsNothing);
    expect(find.text('Home'), findsWidgets);
  });

  testWidgets('Android back pops the authenticated inner route first', (
    tester,
  ) async {
    await setTestSurface(tester, logicalSize: const Size(400, 800));
    await tester.pumpWidget(
      PandoraApp(
        auth: const _Auth(),
        repository: _Repository(),
        diagnostics: DiagnosticsStore(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsNothing);
    expect(find.text('Home'), findsWidgets);
  });

  testWidgets('authorization invalidation discards every protected route', (
    tester,
  ) async {
    await setTestSurface(tester, logicalSize: const Size(400, 800));
    final auth = _MutableAuth(const PandoraSession(userId: 'fixture'));
    final repository = _AuthorizationRepository();
    addTearDown(auth.close);
    addTearDown(repository.close);
    await tester.pumpWidget(
      PandoraApp(
        auth: auth,
        repository: repository,
        diagnostics: DiagnosticsStore(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);

    repository.invalidate(1);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsNothing);
    expect(find.text('Home'), findsNothing);
    expect(find.text('Owner access needs rechecking'), findsWidgets);
    expect(find.text('Sign out'), findsOneWidget);

    await tester.tap(find.text('Recheck owner access'));
    await tester.pumpAndSettle();
    expect(find.text('Owner access needs rechecking'), findsNothing);
    expect(find.text('Home'), findsWidgets);
  });

  for (final failOldRecheck in <bool>[false, true]) {
    testWidgets(
      'old owner ${failOldRecheck ? 'failed' : 'successful'} recheck cannot affect a new owner',
      (tester) async {
        await setTestSurface(tester, logicalSize: const Size(400, 800));
        final auth = _MutableAuth(const PandoraSession(userId: 'owner-a'));
        final repository = _AuthorizationRepository();
        addTearDown(auth.close);
        addTearDown(repository.close);
        await tester.pumpWidget(
          PandoraApp(
            auth: auth,
            repository: repository,
            diagnostics: DiagnosticsStore(),
          ),
        );
        await tester.pumpAndSettle();

        repository.invalidate(1);
        await tester.pumpAndSettle();
        final oldRecheck = Completer<RepositorySnapshot<HomeSummary>>();
        repository.delayedHome = oldRecheck;
        await tester.tap(find.text('Recheck owner access'));
        await tester.pump();

        auth.setSession(const PandoraSession(userId: 'owner-b'));
        await tester.pump();
        if (failOldRecheck) {
          oldRecheck.completeError(
            const PandoraApiError(
              kind: PandoraApiErrorKind.forbidden,
              message: 'Old owner forbidden.',
              code: 'OLD_OWNER_FORBIDDEN',
            ),
          );
        } else {
          oldRecheck.complete(repository._homeSnapshot());
        }
        await tester.pumpAndSettle();

        expect(find.text('Owner access needs rechecking'), findsNothing);
        expect(find.text('Home'), findsWidgets);
      },
    );
  }

  testWidgets('access-paused sign-out failure remains recoverable', (
    tester,
  ) async {
    await setTestSurface(tester, logicalSize: const Size(400, 800));
    final auth = _ThrowingSignOutAuth(const PandoraSession(userId: 'fixture'));
    final repository = _AuthorizationRepository();
    addTearDown(auth.close);
    addTearDown(repository.close);
    await tester.pumpWidget(
      PandoraApp(
        auth: auth,
        repository: repository,
        diagnostics: DiagnosticsStore(),
      ),
    );
    await tester.pumpAndSettle();
    repository.invalidate(1);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Fixture sign-out failure.'), findsOneWidget);
    final signOut = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Sign out'),
    );
    expect(signOut.onPressed, isNotNull);
  });

  testWidgets('ambiguous command locks without a retry control', (
    tester,
  ) async {
    await setTestSurface(tester, logicalSize: const Size(400, 800));
    final repository = _CommandRepository();
    await tester.pumpWidget(
      testApp(
        child: PandoraDependencies(
          auth: const _Auth(),
          repository: repository,
          diagnostics: DiagnosticsStore(),
          child: const CommandScreen(),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('command-objective')),
      'Prepare a safe plan',
    );
    // Objective starters now sit above the submit control, which puts it below
    // the fold on a 800pt-tall surface.
    await tester.ensureVisible(find.text('Submit to Pandora'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit to Pandora'));
    await tester.pumpAndSettle();
    expect(find.textContaining('will not retry'), findsOneWidget);
    expect(find.textContaining('Retry'), findsNothing);
    expect(repository.idempotencyKeys, hasLength(1));
    expect(repository.idempotencyKeys.first, isNotNull);
    final submit = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('command-submit')),
    );
    expect(submit.onPressed, isNull);
  });

  testWidgets('approval controls fail closed when expiry is not verified', (
    tester,
  ) async {
    await setTestSurface(tester, logicalSize: const Size(400, 800));
    await tester.pumpWidget(
      testApp(
        child: PandoraDependencies(
          auth: const _Auth(),
          repository: _ApprovalRepository(),
          diagnostics: DiagnosticsStore(),
          child: const Scaffold(body: ApprovalsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final approve = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Approve'),
    );
    final reject = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Reject'),
    );
    expect(approve.onPressed, isNull);
    expect(reject.onPressed, isNull);
    expect(
      find.text('Decision disabled — expiry not verified'),
      findsOneWidget,
    );
  });

  for (final refreshFails in <bool>[false, true]) {
    testWidgets(
      'approval conflict reconciles and ${refreshFails ? 'disables stale controls' : 'removes stale state'}',
      (tester) async {
        await setTestSurface(tester, logicalSize: const Size(400, 800));
        final repository = _ConflictApprovalRepository(
          refreshFails: refreshFails,
        );
        await tester.pumpWidget(
          testApp(
            child: PandoraDependencies(
              auth: const _Auth(),
              repository: repository,
              diagnostics: DiagnosticsStore(),
              child: const Scaffold(body: ApprovalsScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The approval card now carries target, consequence, risk, expiry and
        // rollback above the controls, so the decision sits below the fold.
        await tester.ensureVisible(find.text('Approve'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Approve'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Approve this plan'));
        await tester.pumpAndSettle();

        expect(repository.approvalLoads, 2);
        expect(
          find.textContaining('Pandora tried to refresh the queue'),
          findsOneWidget,
        );
        if (refreshFails) {
          final approve = tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Approve'),
          );
          final reject = tester.widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Reject'),
          );
          expect(approve.onPressed, isNull);
          expect(reject.onPressed, isNull);
          expect(find.text('Queue refresh failed.'), findsOneWidget);
        } else {
          expect(find.text('Nothing needs your decision'), findsOneWidget);
        }
      },
    );
  }

  testWidgets(
    'operation-local approval denial reconciles and disables stale controls',
    (tester) async {
      await setTestSurface(tester, logicalSize: const Size(400, 800));
      final repository = _ConflictApprovalRepository(
        refreshFails: false,
        decisionErrorCode: 'APPROVAL_FORBIDDEN',
      );
      await tester.pumpWidget(
        testApp(
          child: PandoraDependencies(
            auth: const _Auth(),
            repository: repository,
            diagnostics: DiagnosticsStore(),
            child: const Scaffold(body: ApprovalsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The approval card now carries target, consequence, risk, expiry and
      // rollback above the controls, so the decision sits below the fold.
      await tester.ensureVisible(find.text('Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve this plan'));
      await tester.pumpAndSettle();

      expect(repository.approvalLoads, 2);
      expect(
        find.textContaining('Pandora tried to refresh the queue'),
        findsOneWidget,
      );
      final approve = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Approve'),
      );
      final reject = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Reject'),
      );
      expect(approve.onPressed, isNull);
      expect(reject.onPressed, isNull);
      expect(
        find.text(
          'Decision disabled — this owner cannot decide this approval.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('home presents missing counters as unverified, not zero', (
    tester,
  ) async {
    await setTestSurface(tester, logicalSize: const Size(400, 800));
    await tester.pumpWidget(
      testApp(
        child: PandoraDependencies(
          auth: const _Auth(),
          repository: _UnverifiedHomeRepository(),
          diagnostics: DiagnosticsStore(),
          child: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The briefing hero states this as a heading, so it carries no full stop.
    // The paired negative below must track the current verified-state heading,
    // otherwise it would pass against copy the screen can no longer render.
    expect(find.text('Owner decision state is not verified'), findsOneWidget);
    expect(find.text('Nothing requires your decision'), findsNothing);
    // Every unverified counter reads as an em dash rather than a number, and
    // never as zero.
    expect(find.text('—'), findsNWidgets(3));
    expect(find.text('0'), findsNothing);
    // The dash alone means nothing to a screen reader. The counter cells
    // announce as one merged node, so assert that node names every counter as
    // not verified rather than letting a dash stand in for a value.
    expect(
      find.bySemanticsLabel(
        RegExp(
          r'Approvals: not verified\s+'
          r'Active projects: not verified\s+'
          r'Needs attention: not verified',
        ),
      ),
      findsAtLeastNWidgets(1),
      reason: 'Every unverified counter must announce its unverified state.',
    );
  });

  testWidgets('diagnostics owner authorization expires and rechecks', (
    tester,
  ) async {
    await setTestSurface(tester, logicalSize: const Size(400, 800));
    final repository = _Repository();
    await tester.pumpWidget(
      testApp(
        child: PandoraDependencies(
          auth: const _Auth(),
          repository: repository,
          diagnostics: DiagnosticsStore(),
          child: const DeveloperDiagnosticsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.homeCalls, 1);

    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(repository.homeCalls, 2);
  });
}
