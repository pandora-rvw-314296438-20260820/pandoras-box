import '../models/pandora_models.dart';

enum OwnerProjectState {
  ownerActionRequired,
  blocked,
  executing,
  monitoring,
  idle,
  archived,
}

extension OwnerProjectStateLabel on OwnerProjectState {
  String get label => switch (this) {
        OwnerProjectState.ownerActionRequired => 'Owner action required',
        OwnerProjectState.blocked => 'Blocked',
        OwnerProjectState.executing => 'Working now',
        OwnerProjectState.monitoring => 'Monitoring',
        OwnerProjectState.idle => 'Idle',
        OwnerProjectState.archived => 'Archived',
      };
}

enum ProviderTruthState {
  healthy,
  degraded,
  down,
  stale,
  unknown,
  notConfigured,
}

extension ProviderTruthStateLabel on ProviderTruthState {
  String get label => switch (this) {
        ProviderTruthState.healthy => 'Healthy',
        ProviderTruthState.degraded => 'Degraded',
        ProviderTruthState.down => 'Down',
        ProviderTruthState.stale => 'Stale',
        ProviderTruthState.unknown => 'Unknown',
        ProviderTruthState.notConfigured => 'Not configured',
      };
}

enum OwnerConnectionState {
  verified,
  needsAttention,
  stale,
  capabilityUnverified,
  disconnected,
  legacy,
}

extension OwnerConnectionStateLabel on OwnerConnectionState {
  String get label => switch (this) {
        OwnerConnectionState.verified => 'Connected and verified now',
        OwnerConnectionState.needsAttention => 'Connected · needs attention',
        OwnerConnectionState.stale => 'Connected but stale',
        OwnerConnectionState.capabilityUnverified => 'Access not verified',
        OwnerConnectionState.disconnected => 'Disconnected',
        OwnerConnectionState.legacy => 'Legacy connection · no longer used',
      };
}

List<ConnectionSummary> deduplicateConnections(
  Iterable<ConnectionSummary> connections,
) {
  final unique = <String, ConnectionSummary>{};
  for (final connection in connections) {
    final key = normalizeProviderKey(connection.name);
    final existing = unique[key];
    if (existing == null ||
        connectionAttentionRank(connection) >
            connectionAttentionRank(existing)) {
      unique[key] = connection;
    }
  }
  final result = unique.values.toList(growable: true)
    ..sort(
      (left, right) => connectionAttentionRank(right)
          .compareTo(connectionAttentionRank(left)),
    );
  return List<ConnectionSummary>.unmodifiable(result);
}

String normalizeProviderKey(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

ProviderTruthState providerTruthState(ConnectionSummary connection) {
  final words = '${connection.state} ${connection.status}'.toLowerCase();
  if (words.contains('not configured') ||
      words.contains('not_configured') ||
      words.contains('disabled by configuration')) {
    return ProviderTruthState.notConfigured;
  }
  if (connection.freshness.state == FreshnessState.stale) {
    return ProviderTruthState.stale;
  }
  if (connection.freshness.state == FreshnessState.notChecked) {
    return ProviderTruthState.unknown;
  }
  if (words.contains('down') ||
      words.contains('failed') ||
      words.contains('critical') ||
      words.contains('unhealthy') ||
      words.contains('unreachable')) {
    return ProviderTruthState.down;
  }
  if (words.contains('degraded') ||
      words.contains('warning') ||
      words.contains('partial') ||
      words.contains('impaired')) {
    return ProviderTruthState.degraded;
  }
  if (words.contains('healthy') ||
      words.contains('connected') ||
      words.contains('ready')) {
    return ProviderTruthState.healthy;
  }
  return ProviderTruthState.unknown;
}

int connectionAttentionRank(ConnectionSummary connection) =>
    switch (providerTruthState(connection)) {
      ProviderTruthState.down => 5,
      ProviderTruthState.degraded => 4,
      ProviderTruthState.stale => 3,
      ProviderTruthState.unknown => 2,
      ProviderTruthState.notConfigured => 1,
      ProviderTruthState.healthy => 0,
    };

bool isLegacyConnection(ConnectionSummary connection) {
  final words = '${connection.name} ${connection.purpose}'.toLowerCase();
  final github = words.contains('github');
  return github &&
      (words.contains('banataosystems') || words.contains('mbanatao'));
}

OwnerConnectionState resolveOwnerConnectionState(ConnectionSummary connection) {
  if (isLegacyConnection(connection)) return OwnerConnectionState.legacy;
  if (connection.freshness.state == FreshnessState.stale) {
    return OwnerConnectionState.stale;
  }
  if (connection.freshness.state == FreshnessState.notChecked) {
    return OwnerConnectionState.capabilityUnverified;
  }
  final truth = providerTruthState(connection);
  if (connection.canRead || connection.canChange) {
    if (truth == ProviderTruthState.down ||
        truth == ProviderTruthState.degraded) {
      return OwnerConnectionState.needsAttention;
    }
    if (truth == ProviderTruthState.healthy) {
      return OwnerConnectionState.verified;
    }
    return OwnerConnectionState.capabilityUnverified;
  }
  if (truth == ProviderTruthState.notConfigured) {
    return OwnerConnectionState.disconnected;
  }
  return OwnerConnectionState.capabilityUnverified;
}

String ownerConnectionCapabilityLabel(ConnectionSummary connection) {
  if (connection.canChange) return 'Read + approved changes';
  if (connection.canRead) return 'Read access';
  return 'No verified capability';
}

OwnerProjectState resolveOwnerProjectState(
  ProjectSummary project, {
  Iterable<ProjectTask> tasks = const <ProjectTask>[],
  bool hasOwnerApproval = false,
}) {
  final status = project.status.toLowerCase();
  final taskList = tasks.toList(growable: false);
  if (hasOwnerApproval ||
      taskList.any((task) => task.state == ProjectTaskState.waitingApproval)) {
    return OwnerProjectState.ownerActionRequired;
  }
  if (project.blocker?.trim().isNotEmpty == true ||
      taskList.any((task) => task.state == ProjectTaskState.blocked) ||
      status.contains('blocked')) {
    return OwnerProjectState.blocked;
  }
  if (taskList.any(
        (task) =>
            task.state == ProjectTaskState.inProgress ||
            task.state == ProjectTaskState.ready ||
            task.state == ProjectTaskState.waitingReview,
      ) ||
      status.contains('executing') ||
      status.contains('running') ||
      status.contains('in progress') ||
      status.contains('working')) {
    return OwnerProjectState.executing;
  }
  if (status.contains('archived') ||
      status.contains('cancelled') ||
      status.contains('retired')) {
    return OwnerProjectState.archived;
  }
  if (status.contains('monitoring') ||
      (project.freshness.isFresh &&
          (status.contains('active') || status.contains('healthy')))) {
    return OwnerProjectState.monitoring;
  }
  return OwnerProjectState.idle;
}

String ownerSystemHealthLabel(ProjectSummary project) {
  if (project.freshness.state == FreshnessState.stale) {
    return 'Health check stale';
  }
  if (project.freshness.state == FreshnessState.notChecked) {
    return 'Health not verified';
  }
  final words = project.status.toLowerCase();
  if (words.contains('down') ||
      words.contains('unhealthy') ||
      words.contains('failed') ||
      words.contains('unreachable')) {
    return 'Needs attention';
  }
  if (words.contains('active') ||
      words.contains('healthy') ||
      words.contains('live') ||
      words.contains('running')) {
    return 'Online';
  }
  return 'State verified';
}

String ownerWorkStatusLabel(ProjectSummary project) =>
    resolveOwnerProjectState(project).label;

String ownerProductionStatusLabel(ProjectSummary project) =>
    switch (project.evidenceState(EvidenceStage.productionVerified)) {
      EvidenceClaimState.verified => 'Production verified',
      EvidenceClaimState.failed => 'Production blocked',
      EvidenceClaimState.notChecked => 'Production not verified',
    };

String compactProofSummary(ProjectSummary project) {
  const ordered = <EvidenceStage>[
    EvidenceStage.documented,
    EvidenceStage.implemented,
    EvidenceStage.tested,
    EvidenceStage.deployed,
    EvidenceStage.productionVerified,
  ];
  final verified = ordered
      .where(
        (stage) => project.evidenceState(stage) == EvidenceClaimState.verified,
      )
      .length;
  EvidenceStage? firstMissing;
  for (final stage in ordered) {
    if (project.evidenceState(stage) != EvidenceClaimState.verified) {
      firstMissing = stage;
      break;
    }
  }
  if (firstMissing == null) {
    return '5 of 5 verified · Production verified';
  }
  return '$verified of 5 verified · ${firstMissing.label} missing';
}

bool isOwnerVisibleProject(ProjectSummary project) {
  final words = '${project.name} ${project.purpose} ${project.repository ?? ''}'
      .toLowerCase();
  const internalMarkers = <String>[
    'recovery',
    'workboard',
    'worker ',
    'worker-',
    'ingestion',
    'source parity',
    'provider retry',
    'alpha workboard',
  ];
  return !internalMarkers.any(words.contains);
}

String canonicalOwnerProjectLabel(ProjectSummary project) {
  final words = '${project.name} ${project.repository ?? ''}'
      .toLowerCase()
      .replaceAll('_', '-');
  if (words.contains('pandoras-box') ||
      words.contains("pandora's box") ||
      words.contains('mcpmaster-pandoras-box')) {
    return "Pandora's Box";
  }
  return project.name;
}

bool isMeaningfulOwnerPriority(ApprovalSummary? priority) {
  if (priority == null || priority.state != ApprovalState.pending) return false;
  final action = priority.action.toLowerCase();
  return !action.contains('nothing needs you') &&
      !action.contains('nothing requires') &&
      !action.contains('no action required');
}
