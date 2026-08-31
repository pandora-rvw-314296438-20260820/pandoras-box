class ProjectFocusBounds {
  const ProjectFocusBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, Object?> toJson() => <String, Object?>{
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };

  String get compact =>
      'x=${x.toStringAsFixed(1)},y=${y.toStringAsFixed(1)},w=${width.toStringAsFixed(1)},h=${height.toStringAsFixed(1)}';
}

class ProjectFocusToken {
  const ProjectFocusToken._({
    required this.projectId,
    required this.versionId,
    required this.artifactDigest,
    required this.semanticId,
    required this.selector,
    required this.role,
    required this.accessibleName,
    required this.route,
    required this.sourceFile,
    required this.sourceLine,
    required this.bounds,
  });

  static const int schemaVersion = 1;

  factory ProjectFocusToken.create({
    required String projectId,
    required String versionId,
    required String artifactDigest,
    required String semanticId,
    required String selector,
    required String role,
    required String accessibleName,
    required String route,
    required String sourceFile,
    int? sourceLine,
    ProjectFocusBounds? bounds,
  }) {
    final normalizedProject = projectId.trim().toLowerCase();
    final normalizedVersion = versionId.trim().toLowerCase();
    final normalizedDigest = artifactDigest.trim().toLowerCase();
    final normalizedSemantic =
        semanticId.trim().isNotEmpty ? semanticId.trim() : selector.trim();
    final normalizedSource =
        sourceFile.trim().isEmpty ? 'index.html' : sourceFile.trim();
    if (normalizedProject.isEmpty ||
        normalizedVersion.isEmpty ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedDigest) ||
        normalizedSemantic.isEmpty ||
        normalizedSource.startsWith('/') ||
        normalizedSource.contains('..') ||
        normalizedSource.contains('\\')) {
      throw const FormatException('Invalid project focus token.');
    }
    return ProjectFocusToken._(
      projectId: normalizedProject,
      versionId: normalizedVersion,
      artifactDigest: normalizedDigest,
      semanticId: normalizedSemantic,
      selector: selector.trim(),
      role: role.trim(),
      accessibleName: accessibleName.trim(),
      route: route.trim().isEmpty ? '/' : route.trim(),
      sourceFile: normalizedSource,
      sourceLine: sourceLine != null && sourceLine > 0 ? sourceLine : null,
      bounds: bounds,
    );
  }

  final String projectId;
  final String versionId;
  final String artifactDigest;
  final String semanticId;
  final String selector;
  final String role;
  final String accessibleName;
  final String route;
  final String sourceFile;
  final int? sourceLine;
  final ProjectFocusBounds? bounds;

  bool matchesVisible({
    required String projectId,
    required String versionId,
    required String artifactDigest,
  }) =>
      this.projectId == projectId.trim().toLowerCase() &&
      this.versionId == versionId.trim().toLowerCase() &&
      this.artifactDigest == artifactDigest.trim().toLowerCase();

  String get intentContext {
    final parts = <String>[
      'FocusToken(v$schemaVersion)',
      'project=$projectId',
      'version=$versionId',
      'artifact_sha256=$artifactDigest',
      'semantic_id=$semanticId',
      'source=$sourceFile${sourceLine == null ? '' : ':$sourceLine'}',
      'route=$route',
      if (role.isNotEmpty) 'role=$role',
      if (accessibleName.isNotEmpty) 'name=$accessibleName',
      if (selector.isNotEmpty) 'selector=$selector',
      if (bounds != null) 'bounds=${bounds!.compact}',
    ];
    return '${parts.join(' ')}. Apply the owner change specifically to this exact selected object.';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'projectId': projectId,
        'versionId': versionId,
        'artifactDigest': artifactDigest,
        'semanticId': semanticId,
        'selector': selector,
        'role': role,
        'accessibleName': accessibleName,
        'route': route,
        'sourceFile': sourceFile,
        'sourceLine': sourceLine,
        'bounds': bounds?.toJson(),
      };
}
