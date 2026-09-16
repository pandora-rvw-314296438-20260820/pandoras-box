import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/simple/pandora_simple_markdown.dart';

void main() {
  group('PandoraSimpleMarkdown', () {
    testWidgets('renders plain text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PandoraSimpleMarkdown('Hello world'),
          ),
        ),
      );

      final selectable =
          tester.widget<SelectableText>(find.byType(SelectableText));
      final textSpan = selectable.textSpan as TextSpan;
      expect(textSpan.toPlainText(), 'Hello world');
    });

    testWidgets('renders headings correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PandoraSimpleMarkdown('# Headline finding:'),
          ),
        ),
      );

      final selectable =
          tester.widget<SelectableText>(find.byType(SelectableText));
      final textSpan = selectable.textSpan as TextSpan;
      // Should strip '# '
      expect(textSpan.toPlainText(), 'Headline finding:');

      // Should be bold and larger
      final childSpan = textSpan.children!.first as TextSpan;
      expect(childSpan.style!.fontWeight, FontWeight.w700);
    });

    testWidgets('renders emphasis correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PandoraSimpleMarkdown('Some **bold** and *italic* text.'),
          ),
        ),
      );

      final selectable =
          tester.widget<SelectableText>(find.byType(SelectableText));
      final textSpan = selectable.textSpan as TextSpan;

      // Should not contain asterisks
      expect(textSpan.toPlainText(), 'Some bold and italic text.');
    });

    testWidgets('renders lists cleanly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PandoraSimpleMarkdown('- Item 1\n* Item 2\n1. Item 3'),
          ),
        ),
      );

      final selectable =
          tester.widget<SelectableText>(find.byType(SelectableText));
      final textSpan = selectable.textSpan as TextSpan;

      // Should format with bullets or numbers properly, without raw markdown markers for unorderded lists
      expect(textSpan.toPlainText(), '• Item 1\n• Item 2\n1. Item 3');
    });
  });
}
