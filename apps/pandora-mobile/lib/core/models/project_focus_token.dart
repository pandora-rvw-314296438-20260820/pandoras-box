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
    required this.componentId,
    required this.semanticId,
    required this.selector,
    required this.role,
    required this.accessibleName,
    required this.route,
    required this.sourceFile,
    required this.sourceLine,
    required this.bounds,
    required this.issuedAt,
    required this.expiresAt,
  });

  static const int schemaVersion = 2;
  static const Duration defaultTtl = Duration(minutes: 15);

  factory ProjectFocusToken.create({
    required String projectId,
    required String versionId,
    required String artifactDigest,
    String componentId = '',
    required String semanticId,
    required String selector,
    required String role,
    required String accessibleName,
    required String route,
    required String sourceFile,
    int? sourceLine,
    ProjectFocusBounds? bounds,
    DateTime? issuedAt,
    DateTime? expiresAt,
  }) {
    final normalizedProject = projectId.trim().toLowerCase();
    final normalizedVersion = versionId.trim().toLowerCase();
    final normalizedDigest = artifactDigest.trim().toLowerCase();
    final normalizedSemantic =
        semanticId.trim().isNotEmpty ? semanticId.trim() : selector.trim();
    final normalizedComponent =
        componentId.trim().isNotEmpty ? componentId.trim() : normalizedSemantic;
    final normalizedSource =
        sourceFile.trim().isEmpty ? 'index.html' : sourceFile.trim();
    final issued = (issuedAt ?? DateTime.now()).toUtc();
    final expires = (expiresAt ?? issued.add(defaultTtl)).toUtc();
    final ttl = expires.difference(issued);
    if (normalizedProject.isEmpty ||
        normalizedVersion.isEmpty ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedDigest) ||
        normalizedComponent.isEmpty ||
        normalizedComponent.length > 200 ||
        normalizedComponent.contains(RegExp(r'[\r\n\u0000]')) ||
        normalizedSemantic.isEmpty ||
        normalizedSource.startsWith('/') ||
        normalizedSource.contains('..') ||
        normalizedSource.contains('\\') ||
        !expires.isAfter(issued) ||
        ttl > defaultTtl) {
      throw const FormatException('Invalid project focus token.');
    }
    return ProjectFocusToken._(
      projectId: normalizedProject,
      versionId: normalizedVersion,
      artifactDigest: normalizedDigest,
      componentId: normalizedComponent,
      semanticId: normalizedSemantic,
      selector: selector.trim(),
      role: role.trim(),
      accessibleName: accessibleName.trim(),
      route: route.trim().isEmpty ? '/' : route.trim(),
      sourceFile: normalizedSource,
      sourceLine: sourceLine != null && sourceLine > 0 ? sourceLine : null,
      bounds: bounds,
      issuedAt: issued,
      expiresAt: expires,
    );
  }

  final String projectId;
  final String versionId;
  final String artifactDigest;
  final String componentId;
  final String semanticId;
  final String selector;
  final String role;
  final String accessibleName;
  final String route;
  final String sourceFile;
  final int? sourceLine;
  final ProjectFocusBounds? bounds;
  final DateTime issuedAt;
  final DateTime expiresAt;

  bool isExpired({DateTime? at}) {
    final moment = (at ?? DateTime.now()).toUtc();
    return !moment.isBefore(expiresAt);
  }

  bool matchesVisible({
    required String projectId,
    required String versionId,
    required String artifactDigest,
    DateTime? at,
  }) =>
      !isExpired(at: at) &&
      this.projectId == projectId.trim().toLowerCase() &&
      this.versionId == versionId.trim().toLowerCase() &&
      this.artifactDigest == artifactDigest.trim().toLowerCase();

  String get intentContext {
    final parts = <String>[
      'FocusToken(v$schemaVersion)',
      'project=$projectId',
      'version=$versionId',
      'artifact_sha256=$artifactDigest',
      'component_id=$componentId',
      'semantic_id=$semanticId',
      'source=$sourceFile${sourceLine == null ? '' : ':$sourceLine'}',
      'route=$route',
      'issued_at=${issuedAt.toIso8601String()}',
      'expires_at=${expiresAt.toIso8601String()}',
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
        'componentId': componentId,
        'semanticId': semanticId,
        'selector': selector,
        'role': role,
        'accessibleName': accessibleName,
        'route': route,
        'sourceFile': sourceFile,
        'sourceLine': sourceLine,
        'bounds': bounds?.toJson(),
        'issuedAt': issuedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
      };
}
