import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/simple/project_exact_source_diff.dart';

const _project = '00000000-0000-4000-8000-000000000001';
const _baseline = '00000000-0000-4000-8000-000000000002';
const _candidate = '00000000-0000-4000-8000-000000000003';
const _baselineArtifact =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _candidateArtifact =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Map<String, Object?> exactFile({
  required String versionId,
  required String artifactDigest,
  required String path,
  required String content,
  required String sha,
  String mimeType = 'text/plain',
}) {
  final bytes = utf8.encode(content);
  return <String, Object?>{
    'file': path,
    'mimeType': mimeType,
    'dataBase64': base64.encode(bytes),
    'byteSize': bytes.length,
    'sha256': sha * 64,
    'artifactDigest': artifactDigest,
    'previewProjectId': _project,
    'previewVersionId': versionId,
  };
}

Map<String, Object?> binaryFile({
  required String versionId,
  required String artifactDigest,
  required String path,
  required List<int> bytes,
  required String sha,
}) =>
    <String, Object?>{
      'file': path,
      'mimeType': 'image/png',
      'dataBase64': base64.encode(bytes),
      'byteSize': bytes.length,
      'sha256': sha * 64,
      'artifactDigest': artifactDigest,
      'previewProjectId': _project,
      'previewVersionId': versionId,
    };

void main() {
  test('computes exact add modify remove and net text-line delta', () {
    final diff = ProjectExactSourceDiff.fromExactPreviewBundles(
      projectId: _project,
      baselineVersionId: _baseline,
      baselineFiles: <Map<String, Object?>>[
        exactFile(
          versionId: _baseline,
          artifactDigest: _baselineArtifact,
          path: 'index.html',
          content: 'one\ntwo',
          sha: '1',
        ),
        exactFile(
          versionId: _baseline,
          artifactDigest: _baselineArtifact,
          path: 'old.js',
          content: 'a\nb\nc',
          sha: '2',
        ),
        binaryFile(
          versionId: _baseline,
          artifactDigest: _baselineArtifact,
          path: 'logo.png',
          bytes: const <int>[0, 159, 1, 2],
          sha: '3',
        ),
      ],
      candidateVersionId: _candidate,
      candidateFiles: <Map<String, Object?>>[
        exactFile(
          versionId: _candidate,
          artifactDigest: _candidateArtifact,
          path: 'index.html',
          content: 'one\ntwo\nthree\nfour',
          sha: '4',
        ),
        exactFile(
          versionId: _candidate,
          artifactDigest: _candidateArtifact,
          path: 'new.js',
          content: 'x\ny',
          sha: '5',
        ),
        binaryFile(
          versionId: _candidate,
          artifactDigest: _candidateArtifact,
          path: 'logo.png',
          bytes: const <int>[0, 159, 1, 2],
          sha: '3',
        ),
      ],
    );

    expect(diff.changedFileCount, 3);
    expect(diff.addedFileCount, 1);
    expect(diff.modifiedFileCount, 1);
    expect(diff.removedFileCount, 1);
    expect(diff.netTextLineDelta, 1);
    expect(diff.compactSummary, '3 files changed · +1 text line net');
    expect(
      diff.files.map((file) => '${file.statusLabel}:${file.path}').toList(),
      const <String>[
        'Modified:index.html',
        'Added:new.js',
        'Removed:old.js',
      ],
    );
    expect(
      diff.files.firstWhere((file) => file.path == 'index.html').textLineDelta,
      2,
    );
    expect(
      diff.files.firstWhere((file) => file.path == 'new.js').textLineDelta,
      2,
    );
    expect(
      diff.files.firstWhere((file) => file.path == 'old.js').textLineDelta,
      -3,
    );
  });

  test('does not invent line counts for binary changes', () {
    final diff = ProjectExactSourceDiff.fromExactPreviewBundles(
      projectId: _project,
      baselineVersionId: _baseline,
      baselineFiles: <Map<String, Object?>>[
        binaryFile(
          versionId: _baseline,
          artifactDigest: _baselineArtifact,
          path: 'logo.png',
          bytes: const <int>[0, 159, 1, 2],
          sha: '1',
        ),
      ],
      candidateVersionId: _candidate,
      candidateFiles: <Map<String, Object?>>[
        binaryFile(
          versionId: _candidate,
          artifactDigest: _candidateArtifact,
          path: 'logo.png',
          bytes: const <int>[0, 159, 1, 3],
          sha: '2',
        ),
      ],
    );

    expect(diff.changedFileCount, 1);
    expect(diff.netTextLineDelta, isNull);
    expect(diff.files.single.textLineDelta, isNull);
    expect(diff.files.single.detailLabel, 'Modified');
  });

  test('same exact file digest produces no material change', () {
    final baselineFile = exactFile(
      versionId: _baseline,
      artifactDigest: _baselineArtifact,
      path: 'index.html',
      content: 'same',
      sha: '1',
    );
    final candidateFile = <String, Object?>{
      ...baselineFile,
      'previewVersionId': _candidate,
      'artifactDigest': _candidateArtifact,
    };

    final diff = ProjectExactSourceDiff.fromExactPreviewBundles(
      projectId: _project,
      baselineVersionId: _baseline,
      baselineFiles: <Map<String, Object?>>[baselineFile],
      candidateVersionId: _candidate,
      candidateFiles: <Map<String, Object?>>[candidateFile],
    );

    expect(diff.files, isEmpty);
    expect(diff.compactSummary, '0 files changed');
  });

  test('fails closed on candidate version substitution', () {
    final wrong = exactFile(
      versionId: _baseline,
      artifactDigest: _candidateArtifact,
      path: 'index.html',
      content: 'candidate',
      sha: '2',
    );

    expect(
      () => ProjectExactSourceDiff.fromExactPreviewBundles(
        projectId: _project,
        baselineVersionId: _baseline,
        baselineFiles: <Map<String, Object?>>[
          exactFile(
            versionId: _baseline,
            artifactDigest: _baselineArtifact,
            path: 'index.html',
            content: 'baseline',
            sha: '1',
          ),
        ],
        candidateVersionId: _candidate,
        candidateFiles: <Map<String, Object?>>[wrong],
      ),
      throwsFormatException,
    );
  });

  test('fails closed on duplicate path and byte-length drift', () {
    final duplicate = exactFile(
      versionId: _baseline,
      artifactDigest: _baselineArtifact,
      path: 'index.html',
      content: 'baseline',
      sha: '1',
    );
    expect(
      () => ProjectExactSourceDiff.fromExactPreviewBundles(
        projectId: _project,
        baselineVersionId: _baseline,
        baselineFiles: <Map<String, Object?>>[duplicate, duplicate],
        candidateVersionId: _candidate,
        candidateFiles: <Map<String, Object?>>[
          exactFile(
            versionId: _candidate,
            artifactDigest: _candidateArtifact,
            path: 'index.html',
            content: 'candidate',
            sha: '2',
          ),
        ],
      ),
      throwsFormatException,
    );

    final badLength = <String, Object?>{
      ...exactFile(
        versionId: _candidate,
        artifactDigest: _candidateArtifact,
        path: 'index.html',
        content: 'candidate',
        sha: '2',
      ),
      'byteSize': 999,
    };
    expect(
      () => ProjectExactSourceDiff.fromExactPreviewBundles(
        projectId: _project,
        baselineVersionId: _baseline,
        baselineFiles: <Map<String, Object?>>[duplicate],
        candidateVersionId: _candidate,
        candidateFiles: <Map<String, Object?>>[badLength],
      ),
      throwsFormatException,
    );
  });
}
