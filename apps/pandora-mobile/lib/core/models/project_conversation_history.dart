class ProjectConversationHistoryItem {
  const ProjectConversationHistoryItem({
    required this.id,
    required this.projectId,
    required this.organizationId,
    required this.kind,
    required this.occurredAt,
    required this.actorType,
    required this.title,
    required this.summary,
    required this.status,
    required this.sourceType,
    required this.sourceId,
    required this.sourceIntentId,
    required this.projectSpecId,
    required this.buildAuthorizationId,
    required this.buildJobId,
    required this.projectVersionId,
    required this.verificationRunId,
    required this.deploymentId,
    required this.expandable,
    required this.evidenceAvailable,
    required this.displayPayload,
  });

  factory ProjectConversationHistoryItem.fromJson(
    Map<String, Object?> json, {
    required String expectedProjectId,
    required String expectedOrganizationId,
  }) {
    String requiredText(String key) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      throw FormatException('Missing conversation $key.');
    }

    String? optionalText(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is String) {
        final text = value.trim();
        return text.isEmpty ? null : text;
      }
      throw FormatException('Invalid conversation $key.');
    }

    final projectId = requiredText('project_id');
    final organizationId = requiredText('organization_id');
    if (projectId.toLowerCase() != expectedProjectId.trim().toLowerCase() ||
        organizationId.toLowerCase() !=
            expectedOrganizationId.trim().toLowerCase()) {
      throw const FormatException('Conversation identity mismatch.');
    }

    final occurredAt = DateTime.tryParse(requiredText('occurred_at'));
    if (occurredAt == null) {
      throw const FormatException('Invalid conversation occurred_at.');
    }
    final rawPayload = json['display_payload'];
    if (rawPayload is! Map) {
      throw const FormatException('Invalid conversation display payload.');
    }

    return ProjectConversationHistoryItem(
      id: requiredText('conversation_item_id'),
      projectId: projectId,
      organizationId: organizationId,
      kind: requiredText('kind'),
      occurredAt: occurredAt.toUtc(),
      actorType: requiredText('actor_type'),
      title: requiredText('title'),
      summary: requiredText('summary'),
      status: optionalText('status'),
      sourceType: requiredText('source_type'),
      sourceId: requiredText('source_id'),
      sourceIntentId: optionalText('source_intent_id'),
      projectSpecId: optionalText('project_spec_id'),
      buildAuthorizationId: optionalText('build_authorization_id'),
      buildJobId: optionalText('build_job_id'),
      projectVersionId: optionalText('project_version_id'),
      verificationRunId: optionalText('verification_run_id'),
      deploymentId: optionalText('deployment_id'),
      expandable: json['expandable'] == true,
      evidenceAvailable: json['evidence_available'] == true,
      displayPayload: Map<String, Object?>.unmodifiable(
        rawPayload.map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      ),
    );
  }

  final String id;
  final String projectId;
  final String organizationId;
  final String kind;
  final DateTime occurredAt;
  final String actorType;
  final String title;
  final String summary;
  final String? status;
  final String sourceType;
  final String sourceId;
  final String? sourceIntentId;
  final String? projectSpecId;
  final String? buildAuthorizationId;
  final String? buildJobId;
  final String? projectVersionId;
  final String? verificationRunId;
  final String? deploymentId;
  final bool expandable;
  final bool evidenceAvailable;
  final Map<String, Object?> displayPayload;

  bool get isUserIntent =>
      kind == 'USER_INTENT' || kind == 'USER_CHANGE_INTENT';
  bool get isProposal => kind == 'PANDORA_PROPOSAL';
  bool get isBuild =>
      kind == 'BUILD_ADMITTED' ||
      kind == 'BUILD_ACTIVITY_SUMMARY' ||
      kind == 'REPAIR_SUMMARY';
  bool get isVerification => kind == 'VERIFICATION_RECEIPT';
  bool get isPreview => kind == 'PREVIEW_READY';
  bool get isPublish => kind == 'PUBLISH_RECEIPT';

  String? payloadText(String key) {
    final value = displayPayload[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  int? payloadInt(String key) {
    final value = displayPayload[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
