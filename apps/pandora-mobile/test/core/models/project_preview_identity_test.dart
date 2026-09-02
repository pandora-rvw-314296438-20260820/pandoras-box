import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/models/project_preview_identity.dart';
import 'package:pandora_mobile/core/platform/pandora_preview_host.dart';
import 'package:flutter/material.dart';

Map<String, Object?> previewFile({
  required String projectId,
  required String versionId,
  required String artifactDigest,
  String? deploymentId,
  String? sourceSha256,
}) {
  return <String, Object?>{
    'file': 'index.html',
    'mimeType': 'text/html',
    'dataBase64': 'PGh0bWw+',
    'byteSize': 6,
    'sha256': artifactDigest,
    'artifactDigest': artifactDigest,
    'previewProjectId': projectId,
    'previewVersionId': versionId,
    if (deploymentId != null) 'previewDeploymentId': deploymentId,
    if (sourceSha256 != null) 'sourceSha256': sourceSha256,
  };
}

void main() {
  const projectId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const versionId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  const otherVersion = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  const digest =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  const source =
      'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';
  const deployment = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

  test('parses hosted identity with deployment and source digest', () {
    final identity = ProjectPreviewIdentity.fromExactPreviewFiles([
      previewFile(
        projectId: projectId,
        versionId: versionId,
        artifactDigest: digest,
        deploymentId: deployment,
        sourceSha256: source,
      ),
    ]);
    expect(identity.deploymentId, deployment);
    expect(identity.sourceSha256, source);
    expect(identity.isLocalArtifact, isFalse);
  });

  test('parses local-artifact when no deployment is present', () {
    final identity = ProjectPreviewIdentity.fromExactPreviewFiles([
      previewFile(
        projectId: projectId,
        versionId: versionId,
        artifactDigest: digest,
      ),
    ]);
    expect(
      identity.deploymentId,
      ProjectPreviewIdentity.localArtifactDeploymentId,
    );
    expect(identity.isLocalArtifact, isTrue);
  });

  test('rejects drifted file identity', () {
    expect(
      ProjectPreviewIdentity.tryParse([
        previewFile(
          projectId: projectId,
          versionId: versionId,
          artifactDigest: digest,
        ),
        previewFile(
          projectId: projectId,
          versionId: otherVersion,
          artifactDigest: digest,
        ),
      ]),
      isNull,
    );
  });

  testWidgets('host fails closed on version mismatch', (tester) async {
    const fallback = Text('fallback', key: Key('fallback'));
    await tester.pumpWidget(
      MaterialApp(
        home: PandoraPreviewHost(
          files: [
            previewFile(
              projectId: projectId,
              versionId: versionId,
              artifactDigest: digest,
            ),
          ],
          versionId: otherVersion,
          fallback: fallback,
        ),
      ),
    );
    expect(find.byKey(const Key('fallback')), findsOneWidget);
  });
}
