import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/widgets/pandora_editorial_scope.dart';
import 'package:pandora_mobile/core/widgets/pandora_owner_theme.dart';
import 'package:pandora_mobile/features/simple/pandora_simple_ui.dart';
import 'package:pandora_mobile/features/simple/pandora_v2_ui.dart';

void main() {
  testWidgets('owner theme is the PLP canvas, not the dark console',
      (tester) async {
    late PandoraChromePalette palette;
    await tester.pumpWidget(
      MaterialApp(
        home: PandoraOwnerTheme(
          child: Builder(
            builder: (context) {
              palette = PandoraChrome.of(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    expect(palette.editorial, isTrue);
    expect(palette.canvas, const Color(0xFFFAF8F3));
    expect(palette.ink, const Color(0xFF171512));
    expect(palette.accent, const Color(0xFF70643F));
    final theme = Theme.of(tester.element(find.byType(SizedBox)));
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, const Color(0xFFFAF8F3));
    expect(theme.colorScheme.onSurface, const Color(0xFF171512));
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == const Color(0xFF000000),
      ),
      findsNothing,
    );
  });

  testWidgets('without the owner theme the dark console palette remains',
      (tester) async {
    late PandoraChromePalette palette;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            palette = PandoraChrome.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(palette.editorial, isFalse);
    expect(palette.canvas, const Color(0xFF090B0E));
    expect(
      pandoraOwnerColor(
        tester.element(find.byType(SizedBox)),
        PandoraV2Colors.canvas,
      ),
      PandoraV2Colors.canvas,
    );
  });

  testWidgets('simple owner pages inherit ivory instead of a black body',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PandoraOwnerTheme(
          child: PandoraSimplePage(
            header: SizedBox(key: Key('owner-header')),
            child: Text('Clients'),
          ),
        ),
      ),
    );
    final boxes = tester.widgetList<ColoredBox>(find.byType(ColoredBox));
    expect(boxes.map((box) => box.color), contains(const Color(0xFFFAF8F3)));
    expect(boxes.map((box) => box.color), isNot(contains(const Color(0xFF000000))));
    expect(find.text('Clients'), findsOneWidget);
  });
}
