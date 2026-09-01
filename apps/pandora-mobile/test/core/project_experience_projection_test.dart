import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/models/project_experience_projection.dart';

Map<String, Object?> projectionJson({
  String state = 'LIVE',
  int transitionSequence = 7,
  String? activeBuildJobId,
  bool canFocus = true,
  bool canChange = true,
  bool canUndo = true,
  bool canPublish = true,
  bool canRollback = true,
  String updatedAt = '2026-08-31T07:00:00Z',
}) =>
    <String, Object?>{
      'organization_id': '11111111-1111-4111-8111-111111111111',
      'project_id': '22222222-2222-4222-8222-222222222222',
      'experience_state': state,
      'transition_sequence': transitionSequence,
      'current_version_id': '33333333-3333-4333-8333-333333333333',
      'current_preview_deployment_id': null,
      'current_verified': true,
      'candidate_version_id': '44444444-4444-4444-8444-444444444444',
      'candidate_preview_deployment_id': null,
      'candidate_verification_state': 'not_started',
      'production_version_id': '33333333-3333-4333-8333-333333333333',
      'production_deployment_id': '55555555-5555-4555-8555-555555555555',
      'active_build_job_id': activeBuildJobId,
      'build_phase': activeBuildJobId == null ? null : 'building',
      'public_message': 'Your project is live.',
      'needs_you': false,
      'retry_available': false,
      'can_focus': canFocus,
      'can_change': canChange,
      'can_undo': canUndo,
      'can_publish': canPublish,
      'can_rollback': canRollback,
      'verification_summary': <String, Object?>{'state': 'PASS'},
      'change_summary': null,
      'safe_failure_code': null,
      'safe_failure_message': null,
      'last_transition_at': '2026-08-31T06:59:00Z',
      'updated_at': updatedAt,
    };

void main() {
  test('LIVE remains primary while a background build is active', () {
    final projection = ProjectExperienceProjection.fromJson(
      projectionJson(
        activeBuildJobId: '66666666-6666-4666-8666-666666666666',
      ),
    );

    expect(projection.state, ProjectExperienceState.live);
    expect(projection.isLive, isTrue);
    expect(projection.isUpdating, isTrue);
    expect(projection.statusLabel, 'Live · updating');
  });

  test('unknown future lifecycle state fails owner actions closed', () {
    final projection = ProjectExperienceProjection.fromJson(
      projectionJson(state: 'FUTURE_STATE'),
    );

    expect(projection.state, ProjectExperienceState.unknown);
    expect(projection.canFocus, isFalse);
    expect(projection.canChange, isFalse);
    expect(projection.canUndo, isFalse);
    expect(projection.canPublish, isFalse);
    expect(projection.canRollback, isFalse);
    expect(projection.statusLabel, 'Working');
  });

  test('transition sequence and timestamp define monotonic freshness', () {
    final current = ProjectExperienceProjection.fromJson(
      projectionJson(transitionSequence: 7),
    );
    final laterSequence = ProjectExperienceProjection.fromJson(
      projectionJson(
        transitionSequence: 8,
        updatedAt: '2026-08-31T06:00:00Z',
      ),
    );
    final sameSequenceNewerUpdate = ProjectExperienceProjection.fromJson(
      projectionJson(
        transitionSequence: 7,
        updatedAt: '2026-08-31T08:00:00Z',
      ),
    );

    expect(laterSequence.isNewerThan(current), isTrue);
    expect(sameSequenceNewerUpdate.isNewerThan(current), isTrue);
    expect(current.isNewerThan(laterSequence), isFalse);
  });
}
