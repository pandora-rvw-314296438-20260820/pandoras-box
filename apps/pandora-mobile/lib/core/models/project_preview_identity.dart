class ProjectPreviewIdentity {
  const ProjectPreviewIdentity({
    required this.projectId,
    required this.versionId,
    required this.deploymentId,
    required this.sourceSha256,
    required this.sourceCommitSha,
    required this.artifactDigest,
  });

  factory ProjectPreviewIdentity.fromExactPreviewFiles(
    List<Map<String, Object?>> files,
  ) {
    if (files.isEmpty || files.length > 1000) {
      throw const FormatException('Exact preview identity requires files.');
    }

    String requiredText(Map<String, Object?> file, String key) {
      final value = file[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim().toLowerCase();
      }
      throw FormatException('Exact preview $key is missing.');
    }

    final first = files.first;
    final projectId = requiredText(first, 'previewProjectId');
    final versionId = requiredText(first, 'previewVersionId');
    final deploymentId = requiredText(first, 'previewDeploymentId');
    final sourceSha256 = requiredText(first, 'sourceSha256');
    final sourceCommitSha = requiredText(first, 'sourceCommitSha');
    final artifactDigest = requiredText(first, 'artifactDigest');

    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    final sha256 = RegExp(r'^[0-9a-f]{64}$');
    final commit = RegExp(r'^(?:[0-9a-f]{40}|[0-9a-f]{64})$');
    if (!uuid.hasMatch(projectId) ||
        !uuid.hasMatch(versionId) ||
        !uuid.hasMatch(deploymentId) ||
        !sha256.hasMatch(sourceSha256) ||
        !commit.hasMatch(sourceCommitSha) ||
        !sha256.hasMatch(artifactDigest)) {
      throw const FormatException('Exact preview identity is invalid.');
    }

    for (final file in files.skip(1)) {
      if (requiredText(file, 'previewProjectId') != projectId ||
          requiredText(file, 'previewVersionId') != versionId ||
          requiredText(file, 'previewDeploymentId') != deploymentId ||
          requiredText(file, 'sourceSha256') != sourceSha256 ||
          requiredText(file, 'sourceCommitSha') != sourceCommitSha ||
          requiredText(file, 'artifactDigest') != artifactDigest) {
        throw const FormatException(
          'Exact preview identity drifted across files.',
        );
      }
    }

    return ProjectPreviewIdentity(
      projectId: projectId,
      versionId: versionId,
      deploymentId: deploymentId,
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

  bool matches({
    required String projectId,
    required String versionId,
    required String deploymentId,
  }) =>
      this.projectId == projectId.trim().toLowerCase() &&
      this.versionId == versionId.trim().toLowerCase() &&
      this.deploymentId == deploymentId.trim().toLowerCase();
}
