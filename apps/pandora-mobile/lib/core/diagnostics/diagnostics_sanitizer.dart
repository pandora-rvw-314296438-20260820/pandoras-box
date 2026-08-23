class DiagnosticsSanitizer {
  const DiagnosticsSanitizer({
    int maxDepth = 5,
    int maxMapEntries = 50,
    int maxListItems = 20,
    int maxStringLength = 512,
  })  : maxDepth = maxDepth < 1 ? 1 : (maxDepth > 10 ? 10 : maxDepth),
        maxMapEntries =
            maxMapEntries < 1 ? 1 : (maxMapEntries > 100 ? 100 : maxMapEntries),
        maxListItems =
            maxListItems < 1 ? 1 : (maxListItems > 100 ? 100 : maxListItems),
        maxStringLength = maxStringLength < 32
            ? 32
            : (maxStringLength > 4096 ? 4096 : maxStringLength);

  static const redacted = '[REDACTED]';
  static const truncated = '[TRUNCATED]';

  final int maxDepth;
  final int maxMapEntries;
  final int maxListItems;
  final int maxStringLength;

  static final RegExp _sensitiveKey = RegExp(
    r'(authorization|password|passwd|secret|token|cookie|api[_-]?key|'
    r'private[_-]?key|service[_-]?role|client[_-]?secret|credential)',
    caseSensitive: false,
  );
  static final RegExp _bearer = RegExp(
    r'\bBearer\s+[A-Za-z0-9._~+/=-]+',
    caseSensitive: false,
  );
  static final RegExp _jwt = RegExp(
    r'\b[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\b',
  );
  static final RegExp _knownSecretPrefix = RegExp(
    r'\b(?:sb_secret_|service_role_|github_pat_|gh[pousr]_|sk_live_)'
    r'[A-Za-z0-9_-]+\b',
    caseSensitive: false,
  );
  static final RegExp _email = RegExp(
    r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
    caseSensitive: false,
  );
  static final RegExp _embeddedUrl = RegExp(
    r'''https?://[^\s<>"']+''',
    caseSensitive: false,
  );

  Object? sanitize(Object? value) => _sanitize(value, 0);

  String sanitizeText(String value) => _sanitizeString(value);

  Object? _sanitize(Object? value, int depth) {
    if (value == null || value is num || value is bool) return value;
    if (depth >= maxDepth) return truncated;
    if (value is String) return _sanitizeString(value);
    if (value is Uri) return _sanitizeUri(value);
    if (value is Map) {
      final result = <String, Object?>{};
      var count = 0;
      for (final entry in value.entries) {
        if (count >= maxMapEntries) {
          result[truncated] = '${value.length - count} more entries';
          break;
        }
        final key = entry.key.toString();
        result[key] = _sensitiveKey.hasMatch(key)
            ? redacted
            : _sanitize(entry.value, depth + 1);
        count += 1;
      }
      return result;
    }
    if (value is Iterable) {
      final result = <Object?>[];
      var count = 0;
      for (final item in value) {
        if (count >= maxListItems) {
          result.add(truncated);
          break;
        }
        result.add(_sanitize(item, depth + 1));
        count += 1;
      }
      return result;
    }
    return _sanitizeString(value.toString());
  }

  String _sanitizeString(String value) {
    var sanitized = value
        .replaceAll(_bearer, redacted)
        .replaceAll(_jwt, redacted)
        .replaceAll(_knownSecretPrefix, redacted)
        .replaceAll(_email, redacted);
    sanitized = sanitized.replaceAllMapped(_embeddedUrl, (match) {
      final uri = Uri.tryParse(match.group(0)!);
      return uri == null ? redacted : _sanitizeUri(uri);
    });
    final uri = Uri.tryParse(sanitized);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      sanitized = _sanitizeUri(uri);
    }
    if (sanitized.length <= maxStringLength) return sanitized;
    return '${sanitized.substring(0, maxStringLength)}$truncated';
  }

  String _sanitizeUri(Uri uri) {
    final safe = uri.replace(
      userInfo: '',
      query: uri.hasQuery ? 'redacted' : null,
      fragment: '',
    );
    return safe.toString();
  }
}
