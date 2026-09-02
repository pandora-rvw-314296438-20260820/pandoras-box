import 'dart:convert';

import 'package:http/http.dart' as http;

enum OwnerAnalyticsEvent {
  appOpened('app_opened'),
  screenViewed('screen_viewed'),
  commandSubmitted('command_submitted'),
  commandSucceeded('command_succeeded'),
  commandFailed('command_failed'),
  projectOpened('project_opened'),
  nextActionPrepared('next_action_prepared'),
  nextActionStarted('next_action_started'),
  nextActionCompleted('next_action_completed'),
  approvalRequested('approval_requested'),
  approvalResolved('approval_resolved'),
  artifactOpened('artifact_opened'),
  releaseOpened('release_opened'),
  rollbackStarted('rollback_started'),
  rollbackVerified('rollback_verified'),
  intentSent('intent_sent'),
  proposalShown('proposal_shown'),
  buildClicked('build_clicked'),
  buildAdmitted('build_admitted'),
  firstStreamEvent('first_stream_event'),
  firstCode('first_code'),
  fileComplete('file_complete'),
  sourceComplete('source_complete'),
  previewReady('preview_ready'),
  secondChange('second_change'),
  funnelDropOff('funnel_dropoff'),
  repairStarted('repair_started'),
  repairCompleted('repair_completed'),
  streamReconnected('stream_reconnected'),
  historyGap('history_gap'),
  publishStarted('publish_started'),
  publishVerified('publish_verified'),
  publishFailed('publish_failed'),
  sourcePaywallViewed('source_paywall_viewed'),
  sourceAccessGranted('source_access_granted'),
  sourceExported('source_exported');

  const OwnerAnalyticsEvent(this.wireName);
  final String wireName;
}

class OwnerAnalytics {
  OwnerAnalytics({http.Client? client, DateTime Function()? clock})
      : _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now,
        _sessionId = 'pm-${(clock ?? DateTime.now)().microsecondsSinceEpoch}';

  static final OwnerAnalytics shared = OwnerAnalytics();

  static const _host = String.fromEnvironment('PANDORA_POSTHOG_HOST');
  static const _projectKey = String.fromEnvironment(
    'PANDORA_POSTHOG_PROJECT_KEY',
  );
  static const _releaseSha = String.fromEnvironment(
    'PANDORA_RELEASE_SHA',
    defaultValue: 'unverified',
  );
  static const _appVersion = String.fromEnvironment(
    'PANDORA_APP_VERSION',
    defaultValue: 'unverified',
  );

  final http.Client _client;
  final DateTime Function() _clock;
  final String _sessionId;

  bool get enabled => _host.trim().isNotEmpty && _projectKey.trim().isNotEmpty;

  Future<void> capture(
    OwnerAnalyticsEvent event, {
    String? projectKey,
    String? resultClass,
    String? errorCode,
    String? proofStage,
    String? buildKey,
    String? versionKey,
    String? statusClass,
    String? capability,
    int? sequence,
    int? itemCount,
    int? attempt,
    bool? historyGap,
    String? projectId,
    String? buildJobId,
    String? streamId,
    String? projectVersionId,
    int? count,
    String? status,
    Duration? duration,
  }) async {
    if (!enabled) return;
    final properties = <String, Object?>{
      'distinct_id': _sessionId,
      'app': 'pandora-mobile',
      'release_sha': _bounded(_releaseSha, 80),
      'app_version': _bounded(_appVersion, 40),
      'recorded_at': _clock().toUtc().toIso8601String(),
      if (projectKey != null && projectKey.trim().isNotEmpty)
        'project_key': _bounded(projectKey, 160),
      if (resultClass != null && resultClass.trim().isNotEmpty)
        'result_class': _bounded(resultClass, 80),
      if (errorCode != null && errorCode.trim().isNotEmpty)
        'error_code': _bounded(errorCode, 80),
      if (proofStage != null && proofStage.trim().isNotEmpty)
        'proof_stage': _bounded(proofStage, 80),
      if (buildKey != null && buildKey.trim().isNotEmpty)
        'build_key': _bounded(buildKey, 160),
      if (versionKey != null && versionKey.trim().isNotEmpty)
        'version_key': _bounded(versionKey, 160),
      if (statusClass != null && statusClass.trim().isNotEmpty)
        'status_class': _bounded(statusClass, 80),
      if (capability != null && capability.trim().isNotEmpty)
        'capability': _bounded(capability, 40),
      if (sequence != null && sequence >= 0) 'sequence': sequence,
      if (itemCount != null && itemCount >= 0) 'item_count': itemCount,
      if (attempt != null && attempt >= 0) 'attempt': attempt,
      if (historyGap != null) 'history_gap': historyGap,
      if (projectId != null && projectId.trim().isNotEmpty)
        'project_id': _bounded(projectId, 80),
      if (buildJobId != null && buildJobId.trim().isNotEmpty)
        'build_job_id': _bounded(buildJobId, 80),
      if (streamId != null && streamId.trim().isNotEmpty)
        'stream_id': _bounded(streamId, 80),
      if (projectVersionId != null && projectVersionId.trim().isNotEmpty)
        'project_version_id': _bounded(projectVersionId, 80),
      if (count != null && count >= 0) 'count': count,
      if (status != null && status.trim().isNotEmpty)
        'status': _bounded(status, 80),
      if (duration != null && duration.inMilliseconds >= 0)
        'duration_ms': duration.inMilliseconds,
    };

    try {
      final base = Uri.parse(_host);
      final uri = base.replace(
        path: '${base.path.replaceFirst(RegExp(r'/$'), '')}/i/v0/e/',
      );
      await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(<String, Object?>{
              'api_key': _projectKey,
              'event': event.wireName,
              'properties': properties,
            }),
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Analytics is non-authoritative and must never block the owner journey.
    }
  }

  String _bounded(String value, int maximum) {
    final text = value.trim();
    return text.length <= maximum ? text : text.substring(0, maximum);
  }

  void close() => _client.close();
}
