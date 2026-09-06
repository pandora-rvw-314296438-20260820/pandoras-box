String _collapseWhitespace(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();

String _decodeBasicHtmlEntities(String value) => value
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&nbsp;', ' ');

bool looksLikeProjectSource(String value) {
  final text = value.trimLeft();
  if (text.isEmpty) return false;
  return RegExp(
    r'<!doctype\s+html|<html\b|<head\b|<body\b|<script\b|<style\b',
    caseSensitive: false,
  ).hasMatch(text);
}

String deriveProjectDisplayName(String value) {
  final text = value.trim();
  if (looksLikeProjectSource(text)) {
    final title = RegExp(
      r'<title[^>]*>([\s\S]*?)</title>',
      caseSensitive: false,
    ).firstMatch(text)?.group(1);
    if (title != null) {
      final clean = _collapseWhitespace(
        _decodeBasicHtmlEntities(title.replaceAll(RegExp(r'<[^>]+>'), ' ')),
      );
      if (clean.isNotEmpty) {
        return clean.length <= 80 ? clean : clean.substring(0, 80).trim();
      }
    }
    return 'New web project';
  }

  final plain = _collapseWhitespace(text);
  final forIndex = plain.toLowerCase().lastIndexOf(' for ');
  if (forIndex >= 0) {
    var candidate = plain.substring(forIndex + 5);
    candidate = candidate
        .split(
          RegExp(r'[,.;]|\bwhere\b|\bthat\b|\bwith\b', caseSensitive: false),
        )
        .first
        .trim();
    final words =
        candidate.split(' ').where((word) => word.isNotEmpty).take(5).toList();
    if (words.isNotEmpty) return words.join(' ');
  }
  var candidate = plain.replaceFirst(
    RegExp(
      r'^(please\s+)?(build|create|make|design|develop)\s+(me\s+)?',
      caseSensitive: false,
    ),
    '',
  );
  candidate = candidate.split(RegExp(r'[,.;]')).first.trim();
  final words =
      candidate.split(' ').where((word) => word.isNotEmpty).take(5).toList();
  return words.isEmpty ? 'New project' : words.join(' ');
}

String deriveProjectStoredObjective(String value) {
  final text = value.trim();
  if (!looksLikeProjectSource(text)) return text;
  final name = deriveProjectDisplayName(text);
  return name == 'New web project'
      ? 'Build and refine the supplied web project.'
      : 'Build and refine $name.';
}

String projectPurposeForDisplay(String value) {
  final text = _collapseWhitespace(value);
  if (text.isEmpty) return '';
  if (looksLikeProjectSource(value)) return deriveProjectStoredObjective(value);
  if (text.length <= 180) return text;
  return '${text.substring(0, 177).trimRight()}…';
}
