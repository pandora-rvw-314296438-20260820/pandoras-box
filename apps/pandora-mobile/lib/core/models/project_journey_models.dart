import 'pandora_models.dart';

enum ProjectBuildKind {
  website(
    'website',
    'Website',
    'Marketing site, bookings, ecommerce or customer pages',
  ),
  webApp('web_app', 'Web app', 'Interactive product, portal or dashboard'),
  mobileApp(
    'mobile_app',
    'Mobile app',
    'Mobile-first product for Android or iOS',
  ),
  internalTool(
    'internal_tool',
    'Internal business tool',
    'Operations, staff workflows or dashboards',
  ),
  automation(
    'automation',
    'Automation',
    'Automate repetitive work and handoffs',
  ),
  apiBackend('api_backend', 'API / backend', 'Data, APIs and backend services'),
  fullSystem(
    'full_system',
    'Full system',
    'Frontend, backend, data and integrations',
  ),
  helpMeDecide(
    'help_me_decide',
    'Help me decide',
    'Describe the result and Pandora will choose the right shape',
  );

  const ProjectBuildKind(this.wireValue, this.label, this.description);
  final String wireValue;
  final String label;
  final String description;

  static ProjectBuildKind parse(Object? value) {
    final wire = jsonText(value).toLowerCase();
    for (final kind in values) {
      if (kind.wireValue == wire) return kind;
    }
    return helpMeDecide;
  }
}

class CustomerProject {
  const CustomerProject({
    required this.id,
    required this.projectKey,
    required this.name,
    required this.objective,
    required this.buildKind,
    required this.stage,
    required this.runtimeStatus,
    this.vercelProjectId,
    this.vercelProjectName,
    this.previewUrl,
    this.liveUrl,
    this.requestedDomain,
    this.domainStatus,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String projectKey;
  final String name;
  final String objective;
  final ProjectBuildKind buildKind;
  final String stage;
  final String runtimeStatus;
  final String? vercelProjectId;
  final String? vercelProjectName;
  final String? previewUrl;
  final String? liveUrl;
  final String? requestedDomain;
  final String? domainStatus;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isLive => stage == 'live' && liveUrl != null;
  bool get hasPreview => previewUrl != null;

  CustomerProject copyWith({String? name}) => CustomerProject(
        id: id,
        projectKey: projectKey,
        name: name ?? this.name,
        objective: objective,
        buildKind: buildKind,
        stage: stage,
        runtimeStatus: runtimeStatus,
        vercelProjectId: vercelProjectId,
        vercelProjectName: vercelProjectName,
        previewUrl: previewUrl,
        liveUrl: liveUrl,
        requestedDomain: requestedDomain,
        domainStatus: domainStatus,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  factory CustomerProject.fromJson(Object? value) {
    final json = asJsonMap(value);
    return CustomerProject(
      id: requiredJsonText(json, const ['id'], field: 'customerProject.id'),
      projectKey: requiredJsonText(
          json,
          const [
            'projectKey',
            'project_key',
          ],
          field: 'customerProject.projectKey'),
      name: requiredJsonText(
          json,
          const [
            'name',
          ],
          field: 'customerProject.name'),
      objective: jsonText(json['objective']),
      buildKind: ProjectBuildKind.parse(json['buildKind']),
      stage: jsonText(json['stage'], fallback: 'idea'),
      runtimeStatus: jsonText(
        json['runtimeStatus'],
        fallback: 'not_configured',
      ),
      vercelProjectId: _optionalText(json['vercelProjectId']),
      vercelProjectName: _optionalText(json['vercelProjectName']),
      previewUrl: _optionalText(json['previewUrl']),
      liveUrl: _optionalText(json['liveUrl']),
      requestedDomain: _optionalText(json['requestedDomain']),
      domainStatus: _optionalText(json['domainStatus']),
      createdAt: jsonDateTime(json['createdAt']),
      updatedAt: jsonDateTime(json['updatedAt']),
    );
  }
}

class ProjectRuntimeDeployment {
  const ProjectRuntimeDeployment({
    required this.id,
    required this.versionId,
    required this.environment,
    required this.status,
    required this.sourceSha256,
    this.providerDeploymentId,
    this.url,
    this.createdAt,
  });
  final String id;
  final String versionId;
  final String environment;
  final String status;
  final String sourceSha256;
  final String? providerDeploymentId;
  final String? url;
  final DateTime? createdAt;

  factory ProjectRuntimeDeployment.fromJson(Object? value) {
    final json = asJsonMap(value);
    return ProjectRuntimeDeployment(
      id: requiredJsonText(json, const ['id'], field: 'projectDeployment.id'),
      versionId: jsonText(json['version_id']),
      environment: jsonText(json['environment'], fallback: 'preview'),
      status: jsonText(json['status'], fallback: 'pending'),
      sourceSha256: jsonText(json['source_sha256']),
      providerDeploymentId: _optionalText(json['provider_deployment_id']),
      url: _optionalText(json['url']),
      createdAt: jsonDateTime(json['created_at']),
    );
  }
}

class ProjectRuntimeDomain {
  const ProjectRuntimeDomain({
    required this.id,
    required this.domain,
    required this.status,
    required this.verified,
    required this.primary,
    required this.verification,
    this.updatedAt,
  });
  final String id;
  final String domain;
  final String status;
  final bool verified;
  final bool primary;
  final List<Object?> verification;
  final DateTime? updatedAt;

  factory ProjectRuntimeDomain.fromJson(Object? value) {
    final json = asJsonMap(value);
    return ProjectRuntimeDomain(
      id: requiredJsonText(json, const ['id'], field: 'projectDomain.id'),
      domain: requiredJsonText(
          json,
          const [
            'domain',
          ],
          field: 'projectDomain.domain'),
      status: jsonText(json['status'], fallback: 'pending'),
      verified: jsonBool(json['verified']),
      primary: jsonBool(json['primary_domain']),
      verification: asJsonList(json['verification']),
      updatedAt: jsonDateTime(json['updated_at']),
    );
  }
}

class ProjectRuntimeCandidate {
  const ProjectRuntimeCandidate({
    required this.versionId,
    required this.artifactDigest,
    required this.status,
    this.parentVersionId,
  });

  final String versionId;
  final String artifactDigest;
  final String status;
  final String? parentVersionId;

  static final RegExp _artifactDigestPattern = RegExp(r'^[0-9a-f]{64}$');
  static const Set<String> _previewEligibleStatuses = <String>{
    'built',
    'verification_pending',
    'verified',
    'preview_ready',
  };

  bool get canUndo => parentVersionId != null && parentVersionId!.isNotEmpty;

  bool get isPreviewEligible {
    final normalizedStatus = status.trim().toLowerCase();
    final normalizedDigest = artifactDigest.trim().toLowerCase();
    return _previewEligibleStatuses.contains(normalizedStatus) &&
        _artifactDigestPattern.hasMatch(normalizedDigest);
  }

  factory ProjectRuntimeCandidate.fromJson(Object? value) {
    final json = asJsonMap(value);
    return ProjectRuntimeCandidate(
      versionId: requiredJsonText(
          json,
          const [
            'versionId',
          ],
          field: 'projectCandidate.versionId'),
      artifactDigest: requiredJsonText(
          json,
          const [
            'artifactDigest',
          ],
          field: 'projectCandidate.artifactDigest'),
      status: jsonText(json['status'], fallback: 'built'),
      parentVersionId: _optionalText(json['parentVersionId']),
    );
  }
}

class ProjectRuntimeVerification {
  const ProjectRuntimeVerification({
    required this.state,
    required this.publishEligible,
    this.versionId,
    this.checkedAt,
  });

  final String state;
  final bool publishEligible;
  final String? versionId;
  final DateTime? checkedAt;

  bool isPublishReadyFor(ProjectRuntimeCandidate candidate) =>
      publishEligible && versionId == candidate.versionId;

  factory ProjectRuntimeVerification.fromJson(Object? value) {
    final json = asJsonMap(value);
    return ProjectRuntimeVerification(
      state: jsonText(json['state'], fallback: 'not_checked_yet'),
      publishEligible: jsonBool(json['publishEligible']),
      versionId: _optionalText(json['versionId']),
      checkedAt: jsonDateTime(json['checkedAt']),
    );
  }
}

class ProjectRuntimeSnapshot {
  const ProjectRuntimeSnapshot({
    required this.project,
    this.preview,
    this.production,
    this.domain,
    this.candidate,
    this.verification,
  });
  final CustomerProject project;
  final ProjectRuntimeDeployment? preview;
  final ProjectRuntimeDeployment? production;
  final ProjectRuntimeDomain? domain;
  final ProjectRuntimeCandidate? candidate;
  final ProjectRuntimeVerification? verification;

  factory ProjectRuntimeSnapshot.fromJson(Object? value) {
    final json = asJsonMap(value);
    final preview = json['preview'];
    final production = json['production'];
    final domain = json['domain'];
    final candidate = json['candidate'];
    final verification = json['verification'];
    return ProjectRuntimeSnapshot(
      project: CustomerProject.fromJson(json['project']),
      preview:
          preview == null ? null : ProjectRuntimeDeployment.fromJson(preview),
      production: production == null
          ? null
          : ProjectRuntimeDeployment.fromJson(production),
      domain: domain == null ? null : ProjectRuntimeDomain.fromJson(domain),
      candidate: candidate == null
          ? null
          : ProjectRuntimeCandidate.fromJson(candidate),
      verification: verification == null
          ? null
          : ProjectRuntimeVerification.fromJson(verification),
    );
  }
}

class ProjectPreviewResult {
  const ProjectPreviewResult({
    required this.project,
    required this.deployment,
    this.previewUrl,
    this.versionId,
  });
  final CustomerProject project;
  final ProjectRuntimeDeployment? deployment;
  final String? previewUrl;
  final String? versionId;

  factory ProjectPreviewResult.fromJson(Object? value) {
    final json = asJsonMap(value);
    final version = asJsonMap(json['version']);
    final deployment = json['deployment'];
    return ProjectPreviewResult(
      project: CustomerProject.fromJson(json['project']),
      deployment: deployment is Map && deployment['id'] != null
          ? ProjectRuntimeDeployment.fromJson(deployment)
          : null,
      previewUrl: _optionalText(json['previewUrl']),
      versionId: _optionalText(version['id']),
    );
  }
}

class ProjectPublishResult {
  const ProjectPublishResult({
    required this.project,
    required this.production,
    required this.domainVerified,
    this.domain,
    this.liveUrl,
  });
  final CustomerProject project;
  final ProjectRuntimeDeployment production;
  final ProjectRuntimeDomain? domain;
  final String? liveUrl;
  final bool domainVerified;

  factory ProjectPublishResult.fromJson(Object? value) {
    final json = asJsonMap(value);
    final domain = json['domain'];
    return ProjectPublishResult(
      project: CustomerProject.fromJson(json['project']),
      production: ProjectRuntimeDeployment.fromJson(json['production']),
      domain: domain == null ? null : ProjectRuntimeDomain.fromJson(domain),
      liveUrl: _optionalText(json['liveUrl']),
      domainVerified: jsonBool(json['domainVerified']),
    );
  }
}

String? _optionalText(Object? value) {
  final text = jsonText(value);
  return text.isEmpty ? null : text;
}
