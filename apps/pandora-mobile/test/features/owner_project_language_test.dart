import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/models/project_journey_models.dart';
import 'package:pandora_mobile/features/simple/owner_project_language.dart';

CustomerProject _project({
  String stage = 'understanding',
  String runtimeStatus = 'ready',
  String? previewUrl,
  String? liveUrl,
}) {
  return CustomerProject(
    id: 'project-1',
    projectKey: 'project-1',
    name: 'Resort booking',
    objective: 'Increase direct bookings.',
    buildKind: ProjectBuildKind.website,
    stage: stage,
    runtimeStatus: runtimeStatus,
    previewUrl: previewUrl,
    liveUrl: liveUrl,
  );
}

ProjectRuntimeDeployment _preview({
  String status = 'ready',
  String? url = 'https://preview.example.com',
}) {
  return ProjectRuntimeDeployment(
    id: 'deployment-1',
    versionId: 'version-1',
    environment: 'preview',
    status: status,
    sourceSha256: 'abc123',
    url: url,
  );
}

void main() {
  test('owner build stage begins from durable understanding state', () {
    final snapshot = ProjectRuntimeSnapshot(project: _project());
    expect(
      pandoraOwnerBuildStage(snapshot),
      PandoraOwnerBuildStage.understanding,
    );
  });

  test('ready deployment maps to preview ready without provider language', () {
    final snapshot = ProjectRuntimeSnapshot(
      project: _project(previewUrl: 'https://preview.example.com'),
      preview: _preview(),
    );
    expect(
      pandoraOwnerBuildStage(snapshot),
      PandoraOwnerBuildStage.previewReady,
    );
    expect(pandoraHasLivePreview(snapshot), isTrue);
    expect(pandoraOwnerProjectState(snapshot.project), 'Preview ready');
  });

  test('failed durable state maps to fixing and owner-safe failure copy', () {
    final snapshot = ProjectRuntimeSnapshot(
      project: _project(runtimeStatus: 'deployment_failed'),
      preview: _preview(status: 'failed', url: null),
    );
    expect(pandoraOwnerBuildStage(snapshot), PandoraOwnerBuildStage.fixing);
    expect(
      pandoraOwnerFailureMessage('deployment_failed'),
      'Pandora couldn’t make this version live yet.',
    );
  });

  test('verification and approval states use owner language', () {
    expect(
      pandoraOwnerFailureMessage('verification_required'),
      'Pandora is still checking this version.',
    );
    expect(
      pandoraOwnerFailureMessage('policy_approval_required'),
      'Pandora needs your approval.',
    );
    expect(
      pandoraOwnerFailureMessage('migration_blocked'),
      'Pandora found a data change that needs review.',
    );
  });

  test('live URL wins over lower-level runtime state', () {
    final project = _project(
      stage: 'live',
      runtimeStatus: 'ready',
      liveUrl: 'https://www.example.com',
    );
    expect(pandoraOwnerProjectState(project), 'Live');
  });
}
