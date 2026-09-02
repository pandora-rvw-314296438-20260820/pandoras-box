class ProjectPreviewIdentity {
  const ProjectPreviewIdentity({
    required this.projectId,
    required this.versionId,
    required this.deploymentId,
    required this.sourceSha256,
    required this.artifactDigest,
    this.sourceCommitSha = '',
  });

  static const localArtifactDeploymentId = 'local-artifact';

  factory ProjectPreviewIdentity.fromExactPreviewFiles(
    List<Map<String, Object?>> files, {
    String? expectedProjectId,
    String? expectedVersionId,
  }) {
    final identity = tryParse(
      files,
      expectedProjectId: expectedProjectId,
      expectedVersionId: expectedVersionId,
    );
    if (identity == null) {
      throw const FormatException('Exact preview identity is invalid.');
    }
    return identity;
  }

  static ProjectPreviewIdentity? tryParse(
    List<Map<String, Object?>> files, {
    String? expectedProjectId,
    String? expectedVersionId,
  }) {
    if (files.isEmpty || files.length > 1000) return null;

    String? optionalText(Map<String, Object?> file, String key) {
      final value = file[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim().toLowerCase();
      }
      return null;
    }

    String? requiredText(Map<String, Object?> file, String key) {
      return optionalText(file, key);
    }

    final first = files.first;
    final projectId = requiredText(first, 'previewProjectId');
    final versionId = requiredText(first, 'previewVersionId');
    final artifactDigest = requiredText(first, 'artifactDigest');
    if (projectId == null || versionId == null || artifactDigest == null) {
      return null;
    }

    final rawDeployment = optionalText(first, 'previewDeploymentId') ??
        localArtifactDeploymentId;
    final sourceSha256 = optionalText(first, 'sourceSha256') ?? '';
    final sourceCommitSha = optionalText(first, 'sourceCommitSha') ?? '';

    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    final sha256 = RegExp(r'^[0-9a-f]{64}$');
    final commit = RegExp(r'^(?:[0-9a-f]{40}|[0-9a-f]{64})$');
    final deploymentOk = rawDeployment == localArtifactDeploymentId ||
        uuid.hasMatch(rawDeployment);
    if (!uuid.hasMatch(projectId) ||
        !uuid.hasMatch(versionId) ||
        !sha256.hasMatch(artifactDigest) ||
        !deploymentOk ||
        (sourceSha256.isNotEmpty && !sha256.hasMatch(sourceSha256)) ||
        (sourceCommitSha.isNotEmpty && !commit.hasMatch(sourceCommitSha))) {
      return null;
    }

    if (expectedProjectId != null &&
        expectedProjectId.trim().toLowerCase() != projectId) {
      return null;
    }
    if (expectedVersionId != null &&
        expectedVersionId.trim().toLowerCase() != versionId) {
      return null;
    }

    for (final file in files.skip(1)) {
      final fileSource = optionalText(file, 'sourceSha256') ?? '';
      final fileCommit = optionalText(file, 'sourceCommitSha') ?? '';
      final fileDeployment = optionalText(file, 'previewDeploymentId') ??
          localArtifactDeploymentId;
      if (requiredText(file, 'previewProjectId') != projectId ||
          requiredText(file, 'previewVersionId') != versionId ||
          requiredText(file, 'artifactDigest') != artifactDigest ||
          fileDeployment != rawDeployment ||
          fileSource != sourceSha256 ||
          fileCommit != sourceCommitSha) {
        return null;
      }
    }

    return ProjectPreviewIdentity(
      projectId: projectId,
      versionId: versionId,
      deploymentId: rawDeployment,
      sourceSha256: sourceSha256,
      sourceCommitSha: sourceCommitSha,
      artifactDigest: artifactDigest,
    );
  }

  final String projectId;
  final String versionId;
  final String deploymentId;
  final String sourceSha256;
  final String sourceCommitSha;
  final String artifactDigest;

  bool get isLocalArtifact => deploymentId == localArtifactDeploymentId;

  bool matchesHost({
    required String versionId,
    String? projectId,
  }) {
    if (this.versionId != versionId.trim().toLowerCase()) return false;
    if (projectId == null || projectId.trim().isEmpty) return true;
    return this.projectId == projectId.trim().toLowerCase();
  }
}
