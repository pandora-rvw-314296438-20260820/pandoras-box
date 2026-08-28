import '../models/project_journey_models.dart';
import '../models/pandora_models.dart';
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
    String? idempotencyKey,
  }) async {
    final response = await _client.postJson(
      pathSegments: <String>['projects', projectId, 'previews'],
      operation: 'customerProject.preview',
      routeTemplate: '/projects/:id/previews',
      idempotencyKey:
          idempotencyKey ?? _keys.create('customer-project-preview'),
      body: const <String, Object?>{},
    );
    return ProjectPreviewResult.fromJson(
      _map(response.data, 'project preview'),
    );
  }

  Future<ProjectPublishResult> publish({
    required String projectId,
    String? versionId,
    String? domain,
    String? idempotencyKey,
  }) async {
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
        if (normalizedDomain != null && normalizedDomain.isNotEmpty)
          'domain': normalizedDomain,
      },
    );
    return ProjectPublishResult.fromJson(
      _map(response.data, 'project publish'),
    );
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
