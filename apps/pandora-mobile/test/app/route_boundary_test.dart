import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/widgets/pandora_page.dart';

import '../helpers/test_app.dart';

/// Regression net for P0.1.
///
/// `PandoraPage` used to provide only a `SafeArea` and a `CustomScrollView`, so
/// a page pushed as its own route — every Settings destination, including
/// Portfolio Intelligence — had no `Material` ancestor. Material-dependent
/// controls then threw `No Material widget found` on a physical device.
///
/// Owner navigation must raise zero framework exceptions.
void main() {
  Future<void> pushPage(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      testApp(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PandoraPage(title: 'Route', child: child),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a pushed page resolves Material ancestry', (tester) async {
    await pushPage(
      tester,
      DropdownButtonFormField<int>(
        initialValue: 1,
        items: const [
          DropdownMenuItem(value: 1, child: Text('One')),
          DropdownMenuItem(value: 2, child: Text('Two')),
        ],
        onChanged: (_) {},
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
  });

  testWidgets('the dropdown opens without a framework error', (tester) async {
    await pushPage(
      tester,
      DropdownButtonFormField<int>(
        initialValue: 1,
        items: const [
          DropdownMenuItem(value: 1, child: Text('One')),
          DropdownMenuItem(value: 2, child: Text('Two')),
        ],
        onChanged: (_) {},
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('other Material-dependent controls resolve', (tester) async {
    await pushPage(
      tester,
      const Column(
        children: [
          TextField(decoration: InputDecoration(labelText: 'Field')),
          ListTile(title: Text('Tile')),
          Chip(label: Text('Chip')),
          Switch.adaptive(value: true, onChanged: null),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
