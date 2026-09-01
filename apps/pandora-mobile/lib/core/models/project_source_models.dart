
class ProjectSourceEntry {
  const ProjectSourceEntry({
    required this.path,
    required this.byteSize,
    required this.sha256,
    required this.isText,
  });

  factory ProjectSourceEntry.fromJson(Map<String, Object?> json) =>
      ProjectSourceEntry(
        path: _requiredText(json['path'], 'source path'),
        byteSize: _requiredInt(json['byteSize'], 'source byteSize'),
        sha256: _requiredText(json['sha256'], 'source sha256'),
        isText: json['text'] == true,
      );

  final String path;
  final int byteSize;
  final String sha256;
  final bool isText;
}

class ProjectSourceTree {
  const ProjectSourceTree({
    required this.projectId,
    required this.versionId,
    required this.artifactDigest,
    required this.files,
  });

  factory ProjectSourceTree.fromJson(Map<String, Object?> json) {
    final rawFiles = json['files'];
    if (rawFiles is! List) throw const FormatException('Invalid source tree.');
    return ProjectSourceTree(
      projectId: _requiredText(json['projectId'], 'source projectId'),
      versionId: _requiredText(json['versionId'], 'source versionId'),
      artifactDigest: _requiredText(
        json['artifactDigest'],
        'source artifactDigest',
      ),
      files: List<ProjectSourceEntry>.unmodifiable(
        rawFiles.map((raw) {
          if (raw is! Map) throw const FormatException('Invalid source entry.');
          return ProjectSourceEntry.fromJson(
            Map<String, Object?>.from(
              raw.map((key, value) => MapEntry(key.toString(), value)),
            ),
          );
        }),
      ),
    );
  }

  final String projectId;
  final String versionId;
  final String artifactDigest;
  final List<ProjectSourceEntry> files;
}

class ProjectSourceFile {
  const ProjectSourceFile({
    required this.projectId,
    required this.versionId,
    required this.path,
    required this.sha256,
    required this.byteSize,
    required this.encoding,
    required this.content,
    required this.redacted,
  });

  factory ProjectSourceFile.fromJson(Map<String, Object?> json) =>
      ProjectSourceFile(
        projectId: _requiredText(json['projectId'], 'source projectId'),
        versionId: _requiredText(json['versionId'], 'source versionId'),
        path: _requiredText(json['path'], 'source path'),
        sha256: _requiredText(json['sha256'], 'source sha256'),
        byteSize: _requiredInt(json['byteSize'], 'source byteSize'),
        encoding: _requiredText(json['encoding'], 'source encoding'),
        content: _requiredText(json['content'], 'source content'),
        redacted: json['redacted'] == true,
      );

  final String projectId;
  final String versionId;
  final String path;
  final String sha256;
  final int byteSize;
  final String encoding;
  final String content;
  final bool redacted;
}

class ProjectSourceSearchMatch {
  const ProjectSourceSearchMatch({
    required this.path,
    required this.line,
    required this.snippet,
  });

  factory ProjectSourceSearchMatch.fromJson(Map<String, Object?> json) =>
      ProjectSourceSearchMatch(
        path: _requiredText(json['path'], 'search path'),
        line: _requiredInt(json['line'], 'search line'),
        snippet: _requiredText(json['snippet'], 'search snippet'),
      );

  final String path;
  final int line;
  final String snippet;
}

class ProjectSourceSearchResult {
  const ProjectSourceSearchResult({
    required this.projectId,
    required this.versionId,
    required this.query,
    required this.truncated,
    required this.matches,
  });

  factory ProjectSourceSearchResult.fromJson(Map<String, Object?> json) {
    final rawMatches = json['matches'];
    if (rawMatches is! List) {
      throw const FormatException('Invalid source search results.');
    }
    return ProjectSourceSearchResult(
      projectId: _requiredText(json['projectId'], 'search projectId'),
      versionId: _requiredText(json['versionId'], 'search versionId'),
      query: _requiredText(json['query'], 'search query'),
      truncated: json['truncated'] == true,
      matches: List<ProjectSourceSearchMatch>.unmodifiable(
        rawMatches.map((raw) {
          if (raw is! Map) {
            throw const FormatException('Invalid source search match.');
          }
          return ProjectSourceSearchMatch.fromJson(
            Map<String, Object?>.from(
              raw.map((key, value) => MapEntry(key.toString(), value)),
            ),
          );
        }),
      ),
    );
  }

  final String projectId;
  final String versionId;
  final String query;
  final bool truncated;
  final List<ProjectSourceSearchMatch> matches;
}

String _requiredText(Object? value, String field) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  throw FormatException('Missing $field.');
}

int _requiredInt(Object? value, String field) {
  if (value is int && value >= 0) return value;
  if (value is num && value >= 0) return value.toInt();
  throw FormatException('Invalid $field.');
}
