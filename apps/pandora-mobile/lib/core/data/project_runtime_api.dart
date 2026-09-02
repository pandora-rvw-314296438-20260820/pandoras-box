import 'dart:async';

import '../analytics/owner_analytics.dart';
import '../models/pandora_models.dart';
import '../models/project_journey_models.dart';
import '../network/idempotency_key.dart';
import '../network/pandora_api_client.dart';
import '../network/pandora_api_error.dart';

class ProjectRuntimeApi {
  ProjectRuntimeApi({
    required PandoraApiClient client,
    IdempotencyKeyFactory? idempotencyKeys,
  })  : _client = client,
        _keys = idempotencyKeys ?? IdempotencyKeyFactory();

  final PandoraApiClient _client;
  final IdempotencyKeyFactory _keys;

  Future<CustomerProject> createProject({
    required String name,
    required ProjectBuildKind buildKind,
    required String objective,
    String? idempotencyKey,
  }) async {
    final response = await _client.postJson(
      pathSegments: const ['projects'],
      operation: 'customerProject.create',
      routeTemplate: '/projects',
      idempotencyKey: idempotencyKey ?? _keys.create('customer-project-create'),
      body: <String, Object?>{
        'name': name.trim(),
        'buildKind': buildKind.wireValue,
        'objective': objective.trim(),
      },
    );
    final json = _map(response.data, 'create project');
    return CustomerProject.fromJson(json['project']);
  }

  Future<ProjectRuntimeSnapshot> runtime(String projectId) async {
    final response = await _client.getJson(
      pathSegments: <String>['projects', projectId, 'runtime'],
      operation: 'customerProject.runtime',
      routeTemplate: '/projects/:id/runtime',
    );
    return ProjectRuntimeSnapshot.fromJson(
      _map(response.data, 'project runtime'),
    );
  }

  Future<ProjectPreviewResult> createPreview({
    required String projectId,
    required String versionId,
    required String artifactDigest,
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? _keys.create('customer-project-preview');
    final response = await _client.postJson(
      pathSegments: <String>['projects', projectId, 'previews'],
      operation: 'customerProject.preview',
      routeTemplate: '/projects/:id/previews',
      idempotencyKey: key,
      body: <String, Object?>{
        'versionId': versionId.trim(),
        'artifactDigest': artifactDigest.trim().toLowerCase(),
        'idempotencyKey': key,
      },
    );
    return ProjectPreviewResult.fromJson(
      _map(response.data, 'project preview'),
    );
  }

  Future<ProjectRuntimeSnapshot> undo({
    required String projectId,
    required String versionId,
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? _keys.create('customer-project-undo');
    final response = await _client.postJson(
      pathSegments: <String>['projects', projectId, 'undo'],
      operation: 'customerProject.undo',
      routeTemplate: '/projects/:id/undo',
      idempotencyKey: key,
      body: <String, Object?>{
        'expectedVersionId': versionId.trim(),
        'idempotencyKey': key,
      },
    );
    return ProjectRuntimeSnapshot.fromJson(
      _map(response.data, 'project undo'),
    );
  }

  Future<void> rollback({
    required String projectId,
    required String targetVersionId,
    required String expectedProductionVersionId,
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? _keys.create('customer-project-rollback');
    await _client.postJson(
      pathSegments: <String>['projects', projectId, 'rollback'],
      operation: 'customerProject.rollback',
      routeTemplate: '/projects/:id/rollback',
      idempotencyKey: key,
      body: <String, Object?>{
        'targetVersionId': targetVersionId.trim(),
        'expectedProductionVersionId': expectedProductionVersionId.trim(),
        'idempotencyKey': key,
      },
    );
  }

  Future<ProjectPublishResult> publish({
    required String projectId,
    String? versionId,
    String? domain,
    String? idempotencyKey,
  }) async {
    final startedAt = DateTime.now().toUtc();
    unawaited(
      OwnerAnalytics.shared.capture(
        OwnerAnalyticsEvent.publishStarted,
        projectId: projectId,
        projectVersionId: versionId,
      ),
    );
    try {
      final current = await runtime(projectId);
      final expectedProductionVersionId = current.production?.versionId;
      final normalizedDomain = domain?.trim();
      final response = await _client.postJson(
        pathSegments: <String>['projects', projectId, 'publish'],
        operation: 'customerProject.publish',
        routeTemplate: '/projects/:id/publish',
        idempotencyKey:
            idempotencyKey ?? _keys.create('customer-project-publish'),
        body: <String, Object?>{
          if (versionId != null && versionId.trim().isNotEmpty)
            'versionId': versionId.trim(),
          'expectedProductionVersionId': expectedProductionVersionId,
          if (normalizedDomain != null && normalizedDomain.isNotEmpty)
            'domain': normalizedDomain,
        },
      );
      final result = ProjectPublishResult.fromJson(
        _map(response.data, 'project publish'),
      );
      unawaited(
        OwnerAnalytics.shared.capture(
          OwnerAnalyticsEvent.publishVerified,
          projectId: projectId,
          projectVersionId: versionId,
          status: 'verified',
          duration: DateTime.now().toUtc().difference(startedAt),
        ),
      );
      return result;
    } catch (_) {
      unawaited(
        OwnerAnalytics.shared.capture(
          OwnerAnalyticsEvent.publishFailed,
          projectId: projectId,
          projectVersionId: versionId,
          status: 'failed',
          duration: DateTime.now().toUtc().difference(startedAt),
        ),
      );
      unawaited(
        OwnerAnalytics.shared.capture(
          OwnerAnalyticsEvent.funnelDropOff,
          projectId: projectId,
          projectVersionId: versionId,
          resultClass: 'publish_failed',
          status: 'failed',
          duration: DateTime.now().toUtc().difference(startedAt),
        ),
      );
      rethrow;
    }
  }

  void beginAuthenticatedIdentityEpoch() =>
      _client.beginAuthenticatedIdentityEpoch();
  void close() => _client.close();

  JsonMap _map(Object? value, String operation) {
    if (value is Map) return asJsonMap(value);
    throw PandoraApiError(
      kind: PandoraApiErrorKind.contract,
      message: 'Pandora returned an unreadable $operation result.',
      code: 'PROJECT_RUNTIME_CONTRACT_INVALID',
    );
  }
}
