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
  rollbackVerified('rollback_verified');

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
      if (duration != null) 'duration_ms': duration.inMilliseconds,
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
