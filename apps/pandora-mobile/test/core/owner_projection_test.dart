import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/owner_projection.dart';
import 'package:pandora_mobile/core/models/pandora_models.dart';

void main() {
  group('owner project truth resolver', () {
    test(
      'uses owner action > blocked > executing > monitoring > idle > archived',
      () {
        final blockedProject = _project(
          status: 'active',
          blocker: 'Waiting for API',
        );
        final workingTask = _task(ProjectTaskState.inProgress);
        final approvalTask = _task(ProjectTaskState.waitingApproval);

        expect(
          resolveOwnerProjectState(
            blockedProject,
            tasks: [workingTask, approvalTask],
          ),
          OwnerProjectState.ownerActionRequired,
        );
        expect(
          resolveOwnerProjectState(blockedProject, tasks: [workingTask]),
          OwnerProjectState.blocked,
        );
        expect(
          resolveOwnerProjectState(
            _project(status: 'active'),
            tasks: [workingTask],
          ),
          OwnerProjectState.executing,
        );
        expect(
          resolveOwnerProjectState(_project(status: 'active')),
          OwnerProjectState.monitoring,
        );
        expect(
          resolveOwnerProjectState(
            _project(status: 'active', freshness: FreshnessState.stale),
          ),
          OwnerProjectState.idle,
        );
        expect(
          resolveOwnerProjectState(_project(status: 'archived')),
          OwnerProjectState.archived,
        );
      },
    );

    test('phase not verified never becomes the primary owner state', () {
      final project = _project(status: 'active', phase: 'Phase not verified');
      expect(resolveOwnerProjectState(project), OwnerProjectState.monitoring);
    });
  });

  group('provider health truth resolver', () {
    test('expired failure is stale, not down', () {
      final connection = _connection(
        state: 'down',
        status: 'Down',
        freshness: FreshnessState.stale,
      );
      expect(providerTruthState(connection), ProviderTruthState.stale);
    });

    test('missing freshness is unknown, not down', () {
      final connection = _connection(
        state: 'down',
        status: 'Down',
        freshness: FreshnessState.notChecked,
      );
      expect(providerTruthState(connection), ProviderTruthState.unknown);
    });

    test('fresh evidence distinguishes down, degraded and healthy', () {
      expect(
        providerTruthState(_connection(state: 'down', status: 'Down')),
        ProviderTruthState.down,
      );
      expect(
        providerTruthState(_connection(state: 'degraded', status: 'Degraded')),
        ProviderTruthState.degraded,
      );
      expect(
        providerTruthState(_connection(state: 'healthy', status: 'Healthy')),
        ProviderTruthState.healthy,
      );
    });

    test('intentional absence remains not configured', () {
      expect(
        providerTruthState(
          _connection(state: 'not_configured', status: 'Not configured'),
        ),
        ProviderTruthState.notConfigured,
      );
    });
  });

  group('owner-facing truth dimensions', () {
    test(
      'online health does not hide blocked work or missing production proof',
      () {
        final project = _project(status: 'active', blocker: 'Waiting for API');
        expect(ownerSystemHealthLabel(project), 'Online');
        expect(ownerWorkStatusLabel(project), 'Blocked');
        expect(ownerProductionStatusLabel(project), 'Production not verified');
      },
    );

    test('generic active is not enough to call a provider healthy', () {
      final connection = _connection(state: 'active', status: 'Active');
      expect(providerTruthState(connection), ProviderTruthState.unknown);
      expect(
        resolveOwnerConnectionState(connection),
        OwnerConnectionState.capabilityUnverified,
      );
    });

    test(
      'legacy GitHub account is quarantined from current connection truth',
      () {
        final connection = _connection(
          state: 'connected',
          status: 'Connected',
          name: 'GitHub Account — banataosystems',
          purpose: 'Legacy GitHub account',
        );
        expect(
          resolveOwnerConnectionState(connection),
          OwnerConnectionState.legacy,
        );
      },
    );
  });

  test('proof summary is compact and names the first missing stage', () {
    final project = _project(
      evidence: const [
        EvidenceStageStatus(
          stage: EvidenceStage.documented,
          state: EvidenceClaimState.verified,
          rawStage: 'documented',
          rawState: 'verified',
        ),
        EvidenceStageStatus(
          stage: EvidenceStage.implemented,
          state: EvidenceClaimState.verified,
          rawStage: 'implemented',
          rawState: 'verified',
        ),
      ],
    );
    expect(compactProofSummary(project), '2 of 5 verified · Tested missing');
  });

  test(
    'internal recovery and ingestion records are hidden only from owner view',
    () {
      expect(
        isOwnerVisibleProject(_project(name: 'Pandora recovery workboard')),
        isFalse,
      );
      expect(isOwnerVisibleProject(_project(name: "Pandora's Box")), isTrue);
    },
  );
}

ProjectSummary _project({
  String name = "Pandora's Box",
  String status = 'idle',
  String phase = 'Technical alpha',
  String? blocker,
  FreshnessState freshness = FreshnessState.fresh,
  List<EvidenceStageStatus> evidence = const [],
}) => ProjectSummary(
  id: 'pandoras-box',
  name: name,
  purpose: 'Turn intent into a trusted working result.',
  phase: phase,
  status: status,
  progressVerified: false,
  freshness: FreshnessInfo(state: freshness),
  evidenceStages: evidence,
  blocker: blocker,
);

ProjectTask _task(ProjectTaskState state) => ProjectTask(
  id: 'task',
  title: 'Task',
  status: state.name,
  state: state,
  risk: ActionRisk.low,
);

ConnectionSummary _connection({
  required String state,
  required String status,
  FreshnessState freshness = FreshnessState.fresh,
  String name = 'Provider',
  String purpose = 'Provider health',
  bool canRead = true,
  bool canChange = false,
}) => ConnectionSummary(
  id: 'provider',
  name: name,
  purpose: purpose,
  state: state,
  status: status,
  canRead: canRead,
  canChange: canChange,
  freshness: FreshnessInfo(state: freshness),
);
