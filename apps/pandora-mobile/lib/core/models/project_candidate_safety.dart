import 'project_experience_projection.dart';

/// Derived display identities for Project Experience.
///
/// These roles do not replace the canonical projection. `visibleCurrentVersionId`
/// is the version currently committed to the local product canvas; candidate and
/// production identities always come from the authoritative projection.
class ProjectVersionRoles {
  const ProjectVersionRoles({
    required this.visibleCurrentVersionId,
    required this.candidateVersionId,
    required this.productionVersionId,
  });

  final String? visibleCurrentVersionId;
  final String? candidateVersionId;
  final String? productionVersionId;

  factory ProjectVersionRoles.fromProjection(
    ProjectExperienceProjection projection, {
    required String? visibleCurrentVersionId,
  }) {
    return ProjectVersionRoles(
      visibleCurrentVersionId: visibleCurrentVersionId,
      candidateVersionId: projection.candidateVersionId,
      productionVersionId: projection.productionVersionId,
    );
  }

  bool get candidateIsVisible =>
      candidateVersionId != null &&
      candidateVersionId == visibleCurrentVersionId;

  bool get productionIsVisible =>
      productionVersionId != null &&
      productionVersionId == visibleCurrentVersionId;
}

/// Fail-closed candidate/display policy derived from Project Experience.
///
/// The caller may prepare an exact candidate preview only after verification has
/// passed. The visible canvas is committed only after exact preview files are
/// ready, so a failed or incomplete candidate can never replace the current
/// working result.
class ProjectCandidateSafety {
  const ProjectCandidateSafety._({
    required this.roles,
    required this.projectedCurrentVersionId,
    required this.candidateVerificationState,
  });

  factory ProjectCandidateSafety.fromProjection(
    ProjectExperienceProjection projection, {
    required String? visibleCurrentVersionId,
  }) {
    return ProjectCandidateSafety._(
      roles: ProjectVersionRoles.fromProjection(
        projection,
        visibleCurrentVersionId: visibleCurrentVersionId,
      ),
      projectedCurrentVersionId: projection.currentVersionId,
      candidateVerificationState:
          projection.candidateVerificationState.trim().toLowerCase(),
    );
  }

  final ProjectVersionRoles roles;
  final String? projectedCurrentVersionId;
  final String candidateVerificationState;

  bool get candidateVerified => candidateVerificationState == 'passed';

  bool get candidateFailed =>
      candidateVerificationState == 'failed' ||
      candidateVerificationState == 'blocked';

  /// The only version the canvas may attempt to hydrate next.
  ///
  /// An existing visible version is preserved while a candidate is building,
  /// checking, failed, or blocked. A verified candidate may be prepared, but is
  /// not committed until [canCommitVisibleVersion] also sees exact preview
  /// readiness.
  String? get versionToHydrate {
    final visible = roles.visibleCurrentVersionId;
    final candidate = roles.candidateVersionId;

    if (candidate != null) {
      if (candidateVerified && candidate != visible) return candidate;

      if (visible == null &&
          projectedCurrentVersionId != null &&
          projectedCurrentVersionId != candidate) {
        return projectedCurrentVersionId;
      }
      return null;
    }

    if (projectedCurrentVersionId != null &&
        projectedCurrentVersionId != visible) {
      return projectedCurrentVersionId;
    }
    return null;
  }

  bool canCommitVisibleVersion({
    required String versionId,
    required bool exactPreviewReady,
  }) {
    if (!exactPreviewReady) return false;

    final candidate = roles.candidateVersionId;
    if (candidate != null && versionId == candidate) {
      return candidateVerified;
    }

    return versionId == projectedCurrentVersionId && versionId != candidate;
  }

  String failureMessage({String? backendMessage}) {
    final message = backendMessage?.trim() ?? '';
    const assurance = 'Your current version is unchanged.';
    if (message.isEmpty) {
      return 'Pandora could not complete that candidate. $assurance';
    }
    final normalized = message.toLowerCase();
    if (normalized.contains('current version is unchanged') ||
        normalized.contains('current project remains') ||
        normalized.contains('current project is unchanged')) {
      return message;
    }
    return '$message $assurance';
  }
}
