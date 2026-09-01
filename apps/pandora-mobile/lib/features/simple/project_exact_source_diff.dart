import 'dart:convert';

enum ProjectExactSourceDiffStatus { added, modified, removed }

class ProjectExactSourceDiffFile {
  const ProjectExactSourceDiffFile({
    required this.path,
    required this.status,
    required this.currentByteCount,
    required this.candidateByteCount,
    required this.currentLineCount,
    required this.candidateLineCount,
  });

  final String path;
  final ProjectExactSourceDiffStatus status;
  final int? currentByteCount;
  final int? candidateByteCount;
  final int? currentLineCount;
  final int? candidateLineCount;

  int? get textLineDelta {
    final before = currentLineCount;
    final after = candidateLineCount;
    if (before == null || after == null) return null;
    return after - before;
  }

  String get statusLabel => switch (status) {
        ProjectExactSourceDiffStatus.added => 'Added',
        ProjectExactSourceDiffStatus.modified => 'Modified',
        ProjectExactSourceDiffStatus.removed => 'Removed',
      };

  String get detailLabel {
    final delta = textLineDelta;
    if (delta == null) return statusLabel;
    if (delta == 0) return '$statusLabel · no net line change';
    return '$statusLabel · ${_signed(delta)} ${delta.abs() == 1 ? 'line' : 'lines'} net';
  }
}

class ProjectExactSourceDiff {
  const ProjectExactSourceDiff({
    required this.projectId,
    required this.baselineVersionId,
    required this.candidateVersionId,
    required this.baselineArtifactDigest,
    required this.candidateArtifactDigest,
    required this.files,
  });

  final String projectId;
  final String baselineVersionId;
  final String candidateVersionId;
  final String baselineArtifactDigest;
  final String candidateArtifactDigest;
  final List<ProjectExactSourceDiffFile> files;

  int get changedFileCount => files.length;
  int get addedFileCount => files
      .where((file) => file.status == ProjectExactSourceDiffStatus.added)
      .length;
  int get modifiedFileCount => files
      .where((file) => file.status == ProjectExactSourceDiffStatus.modified)
      .length;
  int get removedFileCount => files
      .where((file) => file.status == ProjectExactSourceDiffStatus.removed)
      .length;

  int? get netTextLineDelta {
    final deltas = files.map((file) => file.textLineDelta).whereType<int>();
    if (deltas.isEmpty) return null;
    return deltas.fold<int>(0, (total, value) => total + value);
  }

  String get compactSummary {
    final filesLabel =
        '$changedFileCount ${changedFileCount == 1 ? 'file' : 'files'} changed';
    final delta = netTextLineDelta;
    if (delta == null) return filesLabel;
    if (delta == 0) return '$filesLabel · no net text-line change';
    return '$filesLabel · ${_signed(delta)} text ${delta.abs() == 1 ? 'line' : 'lines'} net';
  }

  factory ProjectExactSourceDiff.fromExactPreviewBundles({
    required String projectId,
    required String baselineVersionId,
    required List<Map<String, Object?>> baselineFiles,
    required String candidateVersionId,
    required List<Map<String, Object?>> candidateFiles,
  }) {
    final normalizedProjectId = _requiredIdentity(projectId, 'project');
    final normalizedBaselineVersion =
        _requiredIdentity(baselineVersionId, 'baseline version');
    final normalizedCandidateVersion =
        _requiredIdentity(candidateVersionId, 'candidate version');
    if (normalizedBaselineVersion == normalizedCandidateVersion) {
      throw const FormatException(
        'Baseline and candidate versions must be different.',
      );
    }

    final baseline = _ExactBundle.parse(
      projectId: normalizedProjectId,
      versionId: normalizedBaselineVersion,
      files: baselineFiles,
      label: 'baseline',
    );
    final candidate = _ExactBundle.parse(
      projectId: normalizedProjectId,
      versionId: normalizedCandidateVersion,
      files: candidateFiles,
      label: 'candidate',
    );

    final paths = <String>{
      ...baseline.byPath.keys,
      ...candidate.byPath.keys,
    }.toList()
      ..sort();

    final changes = <ProjectExactSourceDiffFile>[];
    for (final path in paths) {
      final before = baseline.byPath[path];
      final after = candidate.byPath[path];
      if (before != null && after != null && before.sha256 == after.sha256) {
        if (before.byteCount != after.byteCount) {
          throw const FormatException(
            'Exact preview file metadata changed without digest change.',
          );
        }
        continue;
      }

      final status = before == null
          ? ProjectExactSourceDiffStatus.added
          : after == null
              ? ProjectExactSourceDiffStatus.removed
              : ProjectExactSourceDiffStatus.modified;
      final currentLineCount = before == null
          ? (after?.lineCount == null ? null : 0)
          : before.lineCount;
      final candidateLineCount = after == null
          ? (before?.lineCount == null ? null : 0)
          : after.lineCount;

      changes.add(
        ProjectExactSourceDiffFile(
          path: path,
          status: status,
          currentByteCount: before?.byteCount,
          candidateByteCount: after?.byteCount,
          currentLineCount: currentLineCount,
          candidateLineCount: candidateLineCount,
        ),
      );
    }

    return ProjectExactSourceDiff(
      projectId: normalizedProjectId,
      baselineVersionId: normalizedBaselineVersion,
      candidateVersionId: normalizedCandidateVersion,
      baselineArtifactDigest: baseline.artifactDigest,
      candidateArtifactDigest: candidate.artifactDigest,
      files: List<ProjectExactSourceDiffFile>.unmodifiable(changes),
    );
  }
}

class _ExactBundle {
  const _ExactBundle({
    required this.artifactDigest,
    required this.byPath,
  });

  final String artifactDigest;
  final Map<String, _ExactBundleFile> byPath;

  factory _ExactBundle.parse({
    required String projectId,
    required String versionId,
    required List<Map<String, Object?>> files,
    required String label,
  }) {
    if (files.isEmpty || files.length > 1000) {
      throw FormatException('$label exact preview file count is invalid.');
    }

    String? artifactDigest;
    final byPath = <String, _ExactBundleFile>{};
    for (final raw in files) {
      final path = _safePath(raw['file'], '$label file');
      if (byPath.containsKey(path)) {
        throw FormatException('Duplicate $label exact preview file path.');
      }
      final previewProjectId =
          _requiredIdentity(raw['previewProjectId'], '$label project');
      final previewVersionId =
          _requiredIdentity(raw['previewVersionId'], '$label version');
      if (previewProjectId != projectId || previewVersionId != versionId) {
        throw FormatException('$label exact preview identity mismatch.');
      }

      final digest = _exactDigest(raw['artifactDigest'], '$label artifact');
      artifactDigest ??= digest;
      if (artifactDigest != digest) {
        throw FormatException('$label artifact digest is inconsistent.');
      }

      final sha256 = _exactDigest(raw['sha256'], '$label file');
      final mimeType = _requiredText(raw['mimeType'], '$label mime type');
      final encoded = _requiredText(raw['dataBase64'], '$label file bytes');
      final byteCount = raw['byteSize'];
      if (byteCount is! int || byteCount < 1) {
        throw FormatException('$label file byte size is invalid.');
      }

      late final List<int> bytes;
      try {
        bytes = base64.decode(encoded);
      } on FormatException {
        throw FormatException('$label file bytes are invalid.');
      }
      if (bytes.length != byteCount) {
        throw FormatException('$label file byte size does not match bytes.');
      }

      byPath[path] = _ExactBundleFile(
        sha256: sha256,
        byteCount: byteCount,
        lineCount: _textLineCount(path, mimeType, bytes),
      );
    }

    return _ExactBundle(
      artifactDigest: artifactDigest!,
      byPath: Map<String, _ExactBundleFile>.unmodifiable(byPath),
    );
  }
}

class _ExactBundleFile {
  const _ExactBundleFile({
    required this.sha256,
    required this.byteCount,
    required this.lineCount,
  });

  final String sha256;
  final int byteCount;
  final int? lineCount;
}

String _requiredText(Object? value, String label) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$label is required.');
  }
  return value.trim();
}

String _requiredIdentity(Object? value, String label) =>
    _requiredText(value, label).toLowerCase();

String _exactDigest(Object? value, String label) {
  final digest = _requiredIdentity(value, '$label digest');
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
    throw FormatException('$label digest is invalid.');
  }
  return digest;
}

String _safePath(Object? value, String label) {
  final path = _requiredText(value, '$label path');
  final segments = path.split('/');
  if (path.length > 512 ||
      path.startsWith('/') ||
      path.endsWith('/') ||
      path.contains(r'\') ||
      path.contains('\u0000') ||
      path.contains('?') ||
      path.contains('#') ||
      segments.any((part) =>
          part.isEmpty || part == '.' || part == '..' || part.length > 255)) {
    throw FormatException('$label path is invalid.');
  }
  return path;
}

int? _textLineCount(String path, String mimeType, List<int> bytes) {
  if (!_isTextLike(path, mimeType)) return null;
  try {
    final text = utf8.decode(bytes, allowMalformed: false);
    if (text.isEmpty) return 0;
    return '\n'.allMatches(text).length + 1;
  } on FormatException {
    return null;
  }
}

bool _isTextLike(String path, String mimeType) {
  final mime = mimeType.toLowerCase();
  if (mime.startsWith('text/')) return true;
  if (const <String>{
    'application/json',
    'application/javascript',
    'application/typescript',
    'application/xml',
    'application/yaml',
    'application/x-yaml',
  }.contains(mime)) {
    return true;
  }

  final lower = path.toLowerCase();
  const extensions = <String>[
    '.css',
    '.csv',
    '.dart',
    '.go',
    '.html',
    '.java',
    '.js',
    '.json',
    '.jsx',
    '.kt',
    '.less',
    '.md',
    '.mjs',
    '.py',
    '.rs',
    '.sass',
    '.scss',
    '.sql',
    '.swift',
    '.toml',
    '.ts',
    '.tsx',
    '.txt',
    '.xml',
    '.yaml',
    '.yml',
  ];
  return extensions.any(lower.endsWith);
}

String _signed(int value) => value > 0 ? '+$value' : '$value';
