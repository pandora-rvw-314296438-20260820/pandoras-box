import 'package:flutter/material.dart';

class PandoraSimpleMarkdown extends StatelessWidget {
  const PandoraSimpleMarkdown(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    return SelectableText.rich(
      _parseBlock(text, baseStyle),
    );
  }

  TextSpan _parseBlock(String text, TextStyle baseStyle) {
    final lines = text.split('\n');
    final children = <TextSpan>[];

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      TextStyle lineStyle = baseStyle;
      String prefix = '';

      if (line.startsWith('# ')) {
        lineStyle = baseStyle.copyWith(
          fontSize: (baseStyle.fontSize ?? 14) * 1.4,
          fontWeight: FontWeight.w700,
        );
        line = line.substring(2);
      } else if (line.startsWith('## ')) {
        lineStyle = baseStyle.copyWith(
          fontSize: (baseStyle.fontSize ?? 14) * 1.2,
          fontWeight: FontWeight.w700,
        );
        line = line.substring(3);
      } else if (line.startsWith('### ')) {
        lineStyle = baseStyle.copyWith(
          fontSize: (baseStyle.fontSize ?? 14) * 1.1,
          fontWeight: FontWeight.w700,
        );
        line = line.substring(4);
      } else if (line.trimLeft().startsWith('- ')) {
        final indent = line.substring(0, line.indexOf('- '));
        prefix = '$indent• ';
        line = line.trimLeft().substring(2);
      } else if (line.trimLeft().startsWith('* ')) {
        final indent = line.substring(0, line.indexOf('* '));
        prefix = '$indent• ';
        line = line.trimLeft().substring(2);
      } else {
        // Check for numbered lists
        final match = RegExp(r'^(\s*)(\d+\.)\s(.*)').firstMatch(line);
        if (match != null) {
          final indent = match.group(1)!;
          final number = match.group(2)!;
          prefix = '$indent$number ';
          line = match.group(3)!;
        }
      }

      if (prefix.isNotEmpty) {
        children.add(TextSpan(text: prefix, style: lineStyle));
      }

      children.addAll(_parseInline(line, lineStyle));

      if (i < lines.length - 1) {
        children.add(const TextSpan(text: '\n'));
      }
    }

    return TextSpan(children: children);
  }

  List<TextSpan> _parseInline(String text, TextStyle style) {
    final spans = <TextSpan>[];
    // Regex for bold (**text**) and italic (*text* or _text_)
    // Avoid matching if there are spaces around the asterisks
    final pattern = RegExp(r'(\*\*(.*?)\*\*|\b_(.*?)_\b|\*(.*?)\*)');
    int lastMatchEnd = 0;

    for (final match in pattern.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: style,
        ));
      }
      if (match.group(2) != null) {
        // Bold (**...**)
        spans.add(TextSpan(
          text: match.group(2),
          style: style.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (match.group(3) != null) {
        // Italic (_..._)
        spans.add(TextSpan(
          text: match.group(3),
          style: style.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (match.group(4) != null) {
        // Italic (*...*)
        spans.add(TextSpan(
          text: match.group(4),
          style: style.copyWith(fontStyle: FontStyle.italic),
        ));
      }
      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastMatchEnd), style: style));
    }

    return spans;
  }
}
