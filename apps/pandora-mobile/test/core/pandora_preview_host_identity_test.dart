import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/platform/pandora_preview_host.dart';

const _projectId = '11111111-1111-4111-8111-111111111111';
const _versionId = '22222222-2222-4222-8222-222222222222';
const _deploymentId = '33333333-3333-4333-8333-333333333333';
const _sourceSha =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _artifactDigest =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _sourceCommit = 'cccccccccccccccccccccccccccccccccccccccc';

List<Map<String, Object?>> _files() => <Map<String, Object?>>[
      <String, Object?>{
        'file': 'index.html',
        'mimeType': 'text/html',
        'dataBase64': 'PGh0bWw+PC9odG1sPg==',
        'byteSize': 13,
        'sha256':
            'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
        'previewProjectId': _projectId,
        'previewVersionId': _versionId,
        'previewDeploymentId': _deploymentId,
        'sourceSha256': _sourceSha,
        'sourceCommitSha': _sourceCommit,
        'artifactDigest': _artifactDigest,
      },
    ];

void main() {
  testWidgets('host refuses files bound to a different requested version', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PandoraPreviewHost(
          files: _files(),
          versionId: '44444444-4444-4444-8444-444444444444',
          fallback: const Text('fallback'),
        ),
      ),
    );

    expect(find.text('fallback'), findsOneWidget);
  });

  testWidgets('host refuses identity drift inside the exact file bundle', (
    tester,
  ) async {
    final files = _files();
    files.add(<String, Object?>{
      ...files.first,
      'file': 'app.js',
      'artifactDigest':
          'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PandoraPreviewHost(
          files: files,
          versionId: _versionId,
          fallback: const Text('fallback'),
        ),
      ),
    );

    expect(find.text('fallback'), findsOneWidget);
  });
}
