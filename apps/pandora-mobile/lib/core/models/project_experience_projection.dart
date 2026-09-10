enum ProjectExperienceState {
  start,
  understand,
  build,
  live,
  focus,
  change,
  rebuild,
  review,
  publish,
  unknown,
}

ProjectExperienceState _projectExperienceStateFromWire(Object? value) {
  switch (value) {
    case 'START':
      return ProjectExperienceState.start;
    case 'UNDERSTAND':
      return ProjectExperienceState.understand;
    case 'BUILD':
      return ProjectExperienceState.build;
    case 'LIVE':
      return ProjectExperienceState.live;
    case 'FOCUS':
      return ProjectExperienceState.focus;
    case 'CHANGE':
      return ProjectExperienceState.change;
    case 'REBUILD':
      return ProjectExperienceState.rebuild;
    case 'REVIEW':
      return ProjectExperienceState.review;
    case 'PUBLISH':
      return ProjectExperienceState.publish;
    default:
      return ProjectExperienceState.unknown;
  }
}

class ProjectExperienceProjection {
  const ProjectExperienceProjection({
    required this.organizationId,
    required this.projectId,
    required this.state,
    required this.transitionSequence,
    required this.currentVersionId,
    required this.currentPreviewDeploymentId,
    required this.currentVerified,
    required this.candidateVersionId,
    required this.candidatePreviewDeploymentId,
    required this.candidateVerificationState,
    required this.productionVersionId,
    required this.productionDeploymentId,
    required this.activeBuildJobId,
    required this.buildPhase,
    required this.publicMessage,
    required this.needsYou,
    required this.retryAvailable,
    required this.canFocus,
    required this.canChange,
    required this.canUndo,
    required this.canPublish,
    required this.canRollback,
    required this.verificationSummary,
    required this.changeSummary,
    required this.safeFailureCode,
    required this.safeFailureMessage,
    required this.lastTransitionAt,
    required this.updatedAt,
  });

  factory ProjectExperienceProjection.fromJson(Map<String, Object?> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      throw FormatException('Missing or invalid $key.');
    }

    String? optionalString(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is String) {
        final text = value.trim();
        return text.isEmpty ? null : text;
      }
      throw FormatException('Invalid $key.');
    }

    bool requiredBool(String key) {
      final value = json[key];
      if (value is bool) return value;
      throw FormatException('Missing or invalid $key.');
    }

    int requiredInt(String key) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      throw FormatException('Missing or invalid $key.');
    }

    DateTime requiredDateTime(String key) {
      final value = requiredString(key);
      final parsed = DateTime.tryParse(value);
      if (parsed == null) throw FormatException('Invalid $key.');
      return parsed.toUtc();
    }

    Map<String, Object?> requiredJsonObject(String key) {
      final value = json[key];
      if (value is! Map) {
        throw FormatException('Missing or invalid $key.');
      }
      return Map<String, Object?>.unmodifiable(
        value.map((rawKey, rawValue) => MapEntry(rawKey.toString(), rawValue)),
      );
    }

    final state = _projectExperienceStateFromWire(json['experience_state']);
    final failClosed = state == ProjectExperienceState.unknown;

    return ProjectExperienceProjection(
      organizationId: requiredString('organization_id'),
      projectId: requiredString('project_id'),
      state: state,
      transitionSequence: requiredInt('transition_sequence'),
      currentVersionId: optionalString('current_version_id'),
      currentPreviewDeploymentId: optionalString(
        'current_preview_deployment_id',
      ),
      currentVerified: requiredBool('current_verified'),
      candidateVersionId: optionalString('candidate_version_id'),
      candidatePreviewDeploymentId: optionalString(
        'candidate_preview_deployment_id',
      ),
      candidateVerificationState: requiredString(
        'candidate_verification_state',
      ),
      productionVersionId: optionalString('production_version_id'),
      productionDeploymentId: optionalString('production_deployment_id'),
      activeBuildJobId: optionalString('active_build_job_id'),
      buildPhase: optionalString('build_phase'),
      publicMessage: requiredString('public_message'),
      needsYou: requiredBool('needs_you'),
      retryAvailable: requiredBool('retry_available'),
      canFocus: failClosed ? false : requiredBool('can_focus'),
      canChange: failClosed ? false : requiredBool('can_change'),
      canUndo: failClosed ? false : requiredBool('can_undo'),
      canPublish: failClosed ? false : requiredBool('can_publish'),
      canRollback: failClosed ? false : requiredBool('can_rollback'),
      verificationSummary: requiredJsonObject('verification_summary'),
      changeSummary: optionalString('change_summary'),
      safeFailureCode: optionalString('safe_failure_code'),
      safeFailureMessage: optionalString('safe_failure_message'),
      lastTransitionAt: requiredDateTime('last_transition_at'),
      updatedAt: requiredDateTime('updated_at'),
    );
  }

  final String organizationId;
  final String projectId;
  final ProjectExperienceState state;
  final int transitionSequence;
  final String? currentVersionId;
  final String? currentPreviewDeploymentId;
  final bool currentVerified;
  final String? candidateVersionId;
  final String? candidatePreviewDeploymentId;
  final String candidateVerificationState;
  final String? productionVersionId;
  final String? productionDeploymentId;
  final String? activeBuildJobId;
  final String? buildPhase;
  final String publicMessage;
  final bool needsYou;
  final bool retryAvailable;
  final bool canFocus;
  final bool canChange;
  final bool canUndo;
  final bool canPublish;
  final bool canRollback;
  final Map<String, Object?> verificationSummary;
  final String? changeSummary;
  final String? safeFailureCode;
  final String? safeFailureMessage;
  final DateTime lastTransitionAt;
  final DateTime updatedAt;

  bool get isLive =>
      state == ProjectExperienceState.live && productionVersionId != null;

  bool get isUpdating =>
      activeBuildJobId != null &&
      (state == ProjectExperienceState.live ||
          state == ProjectExperienceState.rebuild ||
          state == ProjectExperienceState.build);

  bool get hasSafeFailure =>
      safeFailureCode != null || safeFailureMessage != null;

  /// Simple Mode status only: Working | Ready | Live | Needs You | Problem.
  /// Theatre stage rails stay separate; blocked/failed never read as Building.
  String get statusLabel {
    if (needsYou) return 'Needs You';
    if (hasSafeFailure) return 'Problem';

    final phase = (buildPhase ?? '').trim().toLowerCase();
    if (phase.isNotEmpty) {
      if (phase == 'needs_you' || phase.contains('approval')) {
        return 'Needs You';
      }
      if (phase.contains('blocked') ||
          phase.contains('failed') ||
          phase.contains('error') ||
          phase.contains('problem') ||
          phase.contains('budget') ||
          phase.contains('trusted_primitive') ||
          phase.contains('pre_execution') ||
          phase.contains('preexecution')) {
        return 'Problem';
      }
      if (phase == 'preview_ready' || phase == 'updated_preview') {
        return 'Ready';
      }
      if (phase == 'live') {
        return isLive ? 'Live' : 'Ready';
      }
      // Active theatre phases (understanding/building/checking/publishing/…)
      // collapse to Working — never Preparing/Building/Checking badges.
      return 'Working';
    }

    switch (state) {
      case ProjectExperienceState.start:
      case ProjectExperienceState.understand:
      case ProjectExperienceState.focus:
      case ProjectExperienceState.change:
      case ProjectExperienceState.build:
      case ProjectExperienceState.rebuild:
      case ProjectExperienceState.publish:
      case ProjectExperienceState.unknown:
        return 'Working';
      case ProjectExperienceState.review:
        return 'Ready';
      case ProjectExperienceState.live:
        if (isUpdating) return 'Working';
        if (isLive) return 'Live';
        return currentVerified ? 'Ready' : 'Working';
    }
  }

  bool isNewerThan(ProjectExperienceProjection other) =>
      transitionSequence > other.transitionSequence ||
      (transitionSequence == other.transitionSequence &&
          updatedAt.isAfter(other.updatedAt));
}
