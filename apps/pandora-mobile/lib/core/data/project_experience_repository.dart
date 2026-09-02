import 'dart:async';

import '../analytics/owner_analytics.dart';
import '../models/project_experience_projection.dart';
import '../models/project_journey_models.dart';
import 'project_experience_api.dart';
import 'project_experience_projection_repository.dart';
import 'project_runtime_api.dart';

enum _OwnerFunnelDropOffReason {
  changeSubmitRejected('change_submit_rejected'),
  changeSubmitFailed('change_submit_failed'),
  buildRequestRejected('build_request_rejected'),
  buildRequestFailed('build_request_failed'),
  previewRequestRejected('preview_request_rejected'),
  previewRequestFailed('preview_request_failed');

  const _OwnerFunnelDropOffReason(this.wireName);
  final String wireName;
}

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

  Future<String> renameProject({
    required String projectId,
    required String name,
  });

  Future<ProjectBuildStart> requestBuild({
    required String projectId,
    required String idempotencyKey,
  });

  Future<String?> findBuildStreamId({
    required String projectId,
    required String buildJobId,
  });

  Stream<List<ProjectBuildStreamEvent>> watchBuildStream({
    required String projectId,
    required String streamId,
  });

  Stream<ProjectBuildStreamSnapshot> watchResilientBuildStream({
    required String projectId,
    required String streamId,
  });

  Future<List<Map<String, Object?>>> loadExactPreviewFiles({
    required String projectId,
    required String versionId,
  });

  Future<Map<String, Object?>?> loadLatestPublishReceipt({
    required String projectId,
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
  CompositeProjectExperienceRepository({
    required ProjectExperienceProjectionRepository projection,
    required ProjectExperienceApi mutations,
    required ProjectRuntimeApi runtime,
  })  : _projection = projection,
        _mutations = mutations,
        _runtime = runtime;

  final ProjectExperienceProjectionRepository _projection;
  final ProjectExperienceApi _mutations;
  final ProjectRuntimeApi _runtime;
  final Map<String, int> _successfulChangeSubmissions = <String, int>{};

  void _captureDropOff(
    String projectId,
    _OwnerFunnelDropOffReason reason,
  ) {
    unawaited(
      OwnerAnalytics.shared.capture(
        OwnerAnalyticsEvent.funnelDropOff,
        projectId: projectId,
        status: reason.wireName,
      ),
    );
  }

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
  }) async {
    try {
      final intentId = await _mutations.submitIntent(
        projectId: projectId,
        intentText: changeText,
        intentKind: 'change',
        idempotencyKey: idempotencyKey,
      );
      final submissionCount =
          (_successfulChangeSubmissions[projectId] ?? 0) + 1;
      _successfulChangeSubmissions[projectId] = submissionCount;
      if (submissionCount == 2) {
        unawaited(
          OwnerAnalytics.shared.capture(
            OwnerAnalyticsEvent.secondChange,
            projectId: projectId,
            count: submissionCount,
            status: 'submitted',
          ),
        );
      }
      return intentId;
    } on ProjectExperienceException {
      _captureDropOff(
        projectId,
        _OwnerFunnelDropOffReason.changeSubmitRejected,
      );
      rethrow;
    } catch (_) {
      _captureDropOff(
        projectId,
        _OwnerFunnelDropOffReason.changeSubmitFailed,
      );
      rethrow;
    }
  }

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
  Future<String> renameProject({
    required String projectId,
    required String name,
  }) =>
      _mutations.renameProject(projectId: projectId, name: name);

  @override
  Future<ProjectBuildStart> requestBuild({
    required String projectId,
    required String idempotencyKey,
  }) async {
    try {
      return await _mutations.requestBuild(
        projectId: projectId,
        idempotencyKey: idempotencyKey,
      );
    } on ProjectExperienceException {
      _captureDropOff(
        projectId,
        _OwnerFunnelDropOffReason.buildRequestRejected,
      );
      rethrow;
    } catch (_) {
      _captureDropOff(
        projectId,
        _OwnerFunnelDropOffReason.buildRequestFailed,
      );
      rethrow;
    }
  }

  @override
  Future<String?> findBuildStreamId({
    required String projectId,
    required String buildJobId,
  }) =>
      _mutations.findBuildStreamId(
        projectId: projectId,
        buildJobId: buildJobId,
      );

  @override
  Stream<List<ProjectBuildStreamEvent>> watchBuildStream({
    required String projectId,
    required String streamId,
  }) =>
      _mutations.watchBuildStream(projectId: projectId, streamId: streamId);

  @override
  Stream<ProjectBuildStreamSnapshot> watchResilientBuildStream({
    required String projectId,
    required String streamId,
  }) =>
      _mutations.watchResilientBuildStream(
        projectId: projectId,
        streamId: streamId,
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
  Future<Map<String, Object?>?> loadLatestPublishReceipt({
    required String projectId,
  }) =>
      _mutations.loadLatestPublishReceipt(projectId: projectId);

  @override
  Future<ProjectRuntimeSnapshot> runtime(String projectId) =>
      _runtime.runtime(projectId);

  @override
  Future<ProjectPreviewResult> createPreview({
    required String projectId,
    required String versionId,
    required String artifactDigest,
    String? idempotencyKey,
  }) async {
    try {
      return await _runtime.createPreview(
        projectId: projectId,
        versionId: versionId,
        artifactDigest: artifactDigest,
        idempotencyKey: idempotencyKey,
      );
    } on ProjectExperienceException {
      _captureDropOff(
        projectId,
        _OwnerFunnelDropOffReason.previewRequestRejected,
      );
      rethrow;
    } catch (_) {
      _captureDropOff(
        projectId,
        _OwnerFunnelDropOffReason.previewRequestFailed,
      );
      rethrow;
    }
  }

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
    _successfulChangeSubmissions.clear();
    _mutations.beginAuthenticatedIdentityEpoch();
    _runtime.beginAuthenticatedIdentityEpoch();
  }
}
