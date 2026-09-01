import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/models/project_candidate_safety.dart';
import 'package:pandora_mobile/core/models/project_experience_projection.dart';

Map<String, Object?> projectionJson({
  String? currentVersionId = 'current-v1',
  String? candidateVersionId = 'candidate-v2',
  String candidateVerificationState = 'checking',
  String? productionVersionId = 'production-v0',
  String? safeFailureMessage,
}) {
  return <String, Object?>{
    'organization_id': '11111111-1111-4111-8111-111111111111',
    'project_id': '22222222-2222-4222-8222-222222222222',
    'experience_state': 'REBUILD',
    'transition_sequence': 9,
    'current_version_id': currentVersionId,
    'current_preview_deployment_id': null,
    'current_verified': true,
    'candidate_version_id': candidateVersionId,
    'candidate_preview_deployment_id': null,
    'candidate_verification_state': candidateVerificationState,
    'production_version_id': productionVersionId,
    'production_deployment_id': null,
    'active_build_job_id': '33333333-3333-4333-8333-333333333333',
    'build_phase': 'checking',
    'public_message': 'Pandora is checking your update.',
    'needs_you': false,
    'retry_available': false,
    'can_focus': true,
    'can_change': false,
    'can_undo': false,
    'can_publish': false,
    'can_rollback': false,
    'verification_summary': <String, Object?>{},
    'change_summary': null,
    'safe_failure_code': safeFailureMessage == null ? null : 'CANDIDATE_FAILED',
    'safe_failure_message': safeFailureMessage,
    'last_transition_at': '2026-09-01T00:00:00Z',
    'updated_at': '2026-09-01T00:01:00Z',
  };
}

ProjectCandidateSafety safety({
  String? visibleCurrentVersionId = 'current-v1',
  String? currentVersionId = 'current-v1',
  String? candidateVersionId = 'candidate-v2',
  String candidateVerificationState = 'checking',
  String? productionVersionId = 'production-v0',
  String? safeFailureMessage,
}) {
  final projection = ProjectExperienceProjection.fromJson(
    projectionJson(
      currentVersionId: currentVersionId,
      candidateVersionId: candidateVersionId,
      candidateVerificationState: candidateVerificationState,
      productionVersionId: productionVersionId,
      safeFailureMessage: safeFailureMessage,
    ),
  );
  return ProjectCandidateSafety.fromProjection(
    projection,
    visibleCurrentVersionId: visibleCurrentVersionId,
  );
}

void main() {
  test('models visibleCurrent, candidate and production as separate roles', () {
    final state = safety();

    expect(state.roles.visibleCurrentVersionId, 'current-v1');
    expect(state.roles.candidateVersionId, 'candidate-v2');
    expect(state.roles.productionVersionId, 'production-v0');
    expect(state.roles.candidateIsVisible, isFalse);
    expect(state.roles.productionIsVisible, isFalse);
  });

  test('preserves current canvas while candidate is checking', () {
    final state = safety(candidateVerificationState: 'checking');

    expect(state.candidateVerified, isFalse);
    expect(state.versionToHydrate, isNull);
    expect(
      state.canCommitVisibleVersion(
        versionId: 'candidate-v2',
        exactPreviewReady: true,
      ),
      isFalse,
    );
    expect(state.roles.visibleCurrentVersionId, 'current-v1');
  });

  test('verified candidate swaps only after exact preview is ready', () {
    final state = safety(candidateVerificationState: 'passed');

    expect(state.versionToHydrate, 'candidate-v2');
    expect(
      state.canCommitVisibleVersion(
        versionId: 'candidate-v2',
        exactPreviewReady: false,
      ),
      isFalse,
    );
    expect(
      state.canCommitVisibleVersion(
        versionId: 'candidate-v2',
        exactPreviewReady: true,
      ),
      isTrue,
    );
  });

  test(
    'candidate failure cannot replace current and copy guarantees safety',
    () {
      final state = safety(
        candidateVerificationState: 'failed',
        safeFailureMessage: 'Pandora could not verify that change.',
      );

      expect(state.candidateFailed, isTrue);
      expect(state.versionToHydrate, isNull);
      expect(
        state.failureMessage(
          backendMessage: 'Pandora could not verify that change.',
        ),
        'Pandora could not verify that change. Your current version is unchanged.',
      );
      expect(state.roles.visibleCurrentVersionId, 'current-v1');
    },
  );

  test(
    'existing current can bootstrap while a newer candidate is checking',
    () {
      final state = safety(
        visibleCurrentVersionId: null,
        candidateVerificationState: 'checking',
      );

      expect(state.versionToHydrate, 'current-v1');
      expect(
        state.canCommitVisibleVersion(
          versionId: 'current-v1',
          exactPreviewReady: true,
        ),
        isTrue,
      );
    },
  );

  test('projection cannot force an unverified candidate into the canvas', () {
    final state = safety(
      currentVersionId: 'candidate-v2',
      candidateVerificationState: 'checking',
    );

    expect(state.versionToHydrate, isNull);
    expect(
      state.canCommitVisibleVersion(
        versionId: 'candidate-v2',
        exactPreviewReady: true,
      ),
      isFalse,
    );
  });
}
