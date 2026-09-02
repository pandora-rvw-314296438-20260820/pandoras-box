import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/models/project_preview_identity.dart';

const _projectId = '11111111-1111-4111-8111-111111111111';
const _versionId = '22222222-2222-4222-8222-222222222222';
const _deploymentId = '33333333-3333-4333-8333-333333333333';
const _sourceSha =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _artifactDigest =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _sourceCommit = 'cccccccccccccccccccccccccccccccccccccccc';

Map<String, Object?> _file({
  String path = 'index.html',
  String deploymentId = _deploymentId,
  String? sourceCommitSha = _sourceCommit,
  String artifactDigest = _artifactDigest,
}) => <String, Object?>{
  'file': path,
  'previewProjectId': _projectId,
  'previewVersionId': _versionId,
  'previewDeploymentId': deploymentId,
  'sourceSha256': _sourceSha,
  if (sourceCommitSha != null) 'sourceCommitSha': sourceCommitSha,
  'artifactDigest': artifactDigest,
};

void main() {
  test(
    'hosted identity preserves exact version, deployment, source, and artifact',
    () {
      final identity = ProjectPreviewIdentity.fromExactPreviewFiles(
        <Map<String, Object?>>[_file(), _file(path: 'app.js')],
      );

      expect(identity.projectId, _projectId);
      expect(identity.versionId, _versionId);
      expect(identity.deploymentId, _deploymentId);
      expect(identity.sourceSha256, _sourceSha);
      expect(identity.sourceCommitSha, _sourceCommit);
      expect(identity.artifactDigest, _artifactDigest);
      expect(identity.isLocalArtifact, isFalse);
      expect(
        identity.matches(
          projectId: _projectId,
          versionId: _versionId,
          deploymentId: _deploymentId,
          sourceSha256: _sourceSha,
          artifactDigest: _artifactDigest,
        ),
        isTrue,
      );
    },
  );

  test('local artifact identity remains explicit and may omit source commit', () {
    final identity = ProjectPreviewIdentity.fromExactPreviewFiles(
      <Map<String, Object?>>[
        _file(
          deploymentId: ProjectPreviewIdentity.localArtifactDeploymentId,
          sourceCommitSha: null,
        ),
      ],
    );

    expect(identity.isLocalArtifact, isTrue);
    expect(identity.sourceCommitSha, isEmpty);
    expect(identity.toCreationParams()['localArtifact'], isTrue);
  });

  test('identity drift across files fails closed', () {
    expect(
      () => ProjectPreviewIdentity.fromExactPreviewFiles(<Map<String, Object?>>[
        _file(),
        _file(
          path: 'app.js',
          artifactDigest:
              'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
        ),
      ]),
      throwsFormatException,
    );
  });

  test('non-UUID hosted deployment identity is rejected', () {
    expect(
      () => ProjectPreviewIdentity.fromExactPreviewFiles(<Map<String, Object?>>[
        _file(deploymentId: 'stale-deployment'),
      ]),
      throwsFormatException,
    );
  });
}
