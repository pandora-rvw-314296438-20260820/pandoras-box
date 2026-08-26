import 'package:pandora_mobile/core/data/pandora_repository.dart';
import 'package:pandora_mobile/core/models/pandora_models.dart';
import 'package:pandora_mobile/core/network/pandora_api_error.dart';
import 'package:pandora_mobile/core/security/pandora_auth.dart';

/// Shared owner-API fakes for widget tests.
///
/// [FakeRepository.failing] flips every read to a provider failure so tests can
/// drive degraded and offline behaviour without touching the network.
class FakeAuth implements PandoraAuth {
  const FakeAuth();

  @override
  Stream<PandoraSession?> get changes => const Stream<PandoraSession?>.empty();

  @override
  PandoraSession? get currentSession => const PandoraSession(userId: 'fixture');

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

/// A minimal but complete project, so route tests can render project detail.
const fixtureProject = ProjectSummary(
  id: 'proj-fixture',
  name: 'Fixture project',
  purpose: 'Exercises owner surfaces in tests.',
  phase: 'Phase 1',
  status: 'active',
  progressVerified: false,
  freshness: FreshnessInfo(state: FreshnessState.notChecked),
  evidenceStages: <EvidenceStageStatus>[],
);

class FakeRepository implements PandoraRepository {
  bool failing = false;

  RepositorySnapshot<T> _snapshot<T>(T data) => RepositorySnapshot<T>(
        data: data,
        source: RepositorySource.network,
        fetchedAt: DateTime.utc(2026, 8, 14),
      );

  void _guard() {
    if (failing) {
      throw const PandoraRepositoryException(
        kind: PandoraApiErrorKind.unavailable,
        message: 'Owner API is unavailable.',
        code: 'provider_unavailable',
      );
    }
  }

  @override
  Future<RepositorySnapshot<HomeSummary>> home() async {
    _guard();
    return _snapshot(
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
  }

  @override
  Future<RepositorySnapshot<List<ProjectSummary>>> projects({
    bool allowCached = false,
  }) async {
    _guard();
    return _snapshot(const <ProjectSummary>[]);
  }

  @override
  Future<RepositorySnapshot<List<ApprovalSummary>>> approvals() async {
    _guard();
    return _snapshot(const <ApprovalSummary>[]);
  }

  @override
  Future<RepositorySnapshot<List<ActionDefinition>>> actions() async {
    _guard();
    return _snapshot(const <ActionDefinition>[]);
  }

  @override
  Future<RepositorySnapshot<List<AuditEvent>>> activity({
    bool allowCached = false,
  }) async {
    _guard();
    return _snapshot(const <AuditEvent>[]);
  }

  @override
  Future<RepositorySnapshot<List<ConnectionSummary>>> connections({
    bool allowCached = false,
  }) async {
    _guard();
    return _snapshot(const <ConnectionSummary>[]);
  }

  @override
  Future<RepositorySnapshot<ProjectDetail>> project(
    String id, {
    bool allowCached = false,
  }) async {
    _guard();
    return _snapshot(
      const ProjectDetail(
        summary: fixtureProject,
        phases: <ProjectPhase>[],
        tasks: <ProjectTask>[],
        evidence: <EvidenceItem>[],
      ),
    );
  }

  @override
  Future<RepositorySnapshot<SafetyOverview>> safety() async {
    _guard();
    return _snapshot(
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
  }

  @override
  Future<IntakeReceipt> ask({
    required String message,
    String? projectId,
    String? idempotencyKey,
  }) =>
      throw UnimplementedError();

  @override
  Future<ApprovalDecisionResult> decideApproval({
    required String approvalId,
    required ApprovalDecision decision,
    String reason = '',
  }) =>
      throw UnimplementedError();

  @override
  Future<IntakeReceipt> runAction({
    required String actionId,
    String? projectId,
    String? message,
    String? idempotencyKey,
  }) =>
      throw UnimplementedError();

  @override
  Future<IntakeReceipt> verifyExactSource({
    required String projectId,
    required String exactSha,
    required WorkerJobClass jobClass,
    int? maxRuntimeSeconds,
    String? idempotencyKey,
  }) =>
      throw UnimplementedError();

  @override
  Future<WorkerExecutionStatus> workerExecution({
    required String planId,
  }) async =>
      WorkerExecutionStatus(
        planId: planId,
        planStatus: 'completed',
        dispatchStatus: 'completed',
        lifecycleStage: 'final_proof_available',
        repository: 'pandora-rvw-314296438-20260820/pandoras-box',
        sourceSha: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        jobClass: 'node_regression',
        workerClaimObserved: true,
        workerLabel: 'Worker-01',
        workerIdentity: 'worker-01',
        providerResultObserved: true,
        finalProofAvailable: true,
        terminal: true,
      );

  @override
  void clearReadOnlyCache() {}

  @override
  void dispose() {}
}
