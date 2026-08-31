import '../models/project_experience_projection.dart';
import '../models/project_journey_models.dart';
import 'project_experience_api.dart';
import 'project_experience_projection_repository.dart';
import 'project_runtime_api.dart';

abstract interface class ProjectExperienceRepository {
  Future<ProjectExperienceProjection> loadExperience(String projectId);

  Stream<ProjectExperienceProjection> watchExperience(String projectId);

  Future<CustomerProject> createProject({
    required String name,
    required ProjectBuildKind buildKind,
    required String objective,
    String? idempotencyKey,
  });

  Future<String> submitIntent({
    required String projectId,
    required String intentText,
    String intentKind = 'build',
    String? idempotencyKey,
  });

  Future<String> submitChange({
    required String projectId,
    required String changeText,
    String? idempotencyKey,
  });

  Future<OwnerProjectUnderstanding> understanding({
    required String projectId,
    required String expectedSourceIntentId,
  });

  Future<void> requestBuild({
    required String projectId,
    required String idempotencyKey,
  });

  Future<List<Map<String, Object?>>> loadExactPreviewFiles({
    required String projectId,
    required String versionId,
  });

  Future<ProjectRuntimeSnapshot> runtime(String projectId);

  Future<ProjectPreviewResult> createPreview({
    required String projectId,
    required String versionId,
    required String artifactDigest,
    String? idempotencyKey,
  });

  Future<ProjectRuntimeSnapshot> undo({
    required String projectId,
    required String versionId,
    String? idempotencyKey,
  });

  Future<ProjectPublishResult> publish({
    required String projectId,
    String? versionId,
    String? domain,
    String? idempotencyKey,
  });

  Future<void> rollback({
    required String projectId,
    required String targetVersionId,
    required String expectedProductionVersionId,
    String? idempotencyKey,
  });

  void beginAuthenticatedIdentityEpoch();
}

class CompositeProjectExperienceRepository
    implements ProjectExperienceRepository {
  const CompositeProjectExperienceRepository({
    required ProjectExperienceProjectionRepository projection,
    required ProjectExperienceApi mutations,
    required ProjectRuntimeApi runtime,
  })  : _projection = projection,
        _mutations = mutations,
        _runtime = runtime;

  final ProjectExperienceProjectionRepository _projection;
  final ProjectExperienceApi _mutations;
  final ProjectRuntimeApi _runtime;

  @override
  Future<ProjectExperienceProjection> loadExperience(String projectId) =>
      _projection.load(projectId);

  @override
  Stream<ProjectExperienceProjection> watchExperience(String projectId) =>
      _projection.watch(projectId);

  @override
  Future<CustomerProject> createProject({
    required String name,
    required ProjectBuildKind buildKind,
    required String objective,
    String? idempotencyKey,
  }) =>
      _runtime.createProject(
        name: name,
        buildKind: buildKind,
        objective: objective,
        idempotencyKey: idempotencyKey,
      );

  @override
  Future<String> submitIntent({
    required String projectId,
    required String intentText,
    String intentKind = 'build',
    String? idempotencyKey,
  }) =>
      _mutations.submitIntent(
        projectId: projectId,
        intentText: intentText,
        intentKind: intentKind,
        idempotencyKey: idempotencyKey,
      );

  @override
  Future<String> submitChange({
    required String projectId,
    required String changeText,
    String? idempotencyKey,
  }) =>
      _mutations.submitIntent(
        projectId: projectId,
        intentText: changeText,
        intentKind: 'change',
        idempotencyKey: idempotencyKey,
      );

  @override
  Future<OwnerProjectUnderstanding> understanding({
    required String projectId,
    required String expectedSourceIntentId,
  }) =>
      _mutations.understanding(
        projectId: projectId,
        expectedSourceIntentId: expectedSourceIntentId,
      );

  @override
  Future<void> requestBuild({
    required String projectId,
    required String idempotencyKey,
  }) =>
      _mutations.requestBuild(
        projectId: projectId,
        idempotencyKey: idempotencyKey,
      );

  @override
  Future<List<Map<String, Object?>>> loadExactPreviewFiles({
    required String projectId,
    required String versionId,
  }) =>
      _mutations.loadExactPreviewFiles(
        projectId: projectId,
        versionId: versionId,
      );

  @override
  Future<ProjectRuntimeSnapshot> runtime(String projectId) =>
      _runtime.runtime(projectId);

  @override
  Future<ProjectPreviewResult> createPreview({
    required String projectId,
    required String versionId,
    required String artifactDigest,
    String? idempotencyKey,
  }) =>
      _runtime.createPreview(
        projectId: projectId,
        versionId: versionId,
        artifactDigest: artifactDigest,
        idempotencyKey: idempotencyKey,
      );

  @override
  Future<ProjectRuntimeSnapshot> undo({
    required String projectId,
    required String versionId,
    String? idempotencyKey,
  }) =>
      _runtime.undo(
        projectId: projectId,
        versionId: versionId,
        idempotencyKey: idempotencyKey,
      );

  @override
  Future<ProjectPublishResult> publish({
    required String projectId,
    String? versionId,
    String? domain,
    String? idempotencyKey,
  }) =>
      _runtime.publish(
        projectId: projectId,
        versionId: versionId,
        domain: domain,
        idempotencyKey: idempotencyKey,
      );

  @override
  Future<void> rollback({
    required String projectId,
    required String targetVersionId,
    required String expectedProductionVersionId,
    String? idempotencyKey,
  }) =>
      _runtime.rollback(
        projectId: projectId,
        targetVersionId: targetVersionId,
        expectedProductionVersionId: expectedProductionVersionId,
        idempotencyKey: idempotencyKey,
      );

  @override
  void beginAuthenticatedIdentityEpoch() {
    _mutations.beginAuthenticatedIdentityEpoch();
    _runtime.beginAuthenticatedIdentityEpoch();
  }
}
