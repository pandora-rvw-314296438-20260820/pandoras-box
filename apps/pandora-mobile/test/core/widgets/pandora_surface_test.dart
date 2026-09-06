import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/widgets/pandora_surface.dart';

void main() {
  testWidgets(
    'compact surface keeps long connection title readable beside status',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const badgeKey = ValueKey<String>('connection-status');
      const title = 'GitHub Account — banataosystems';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(8),
              child: PandoraSurface(
                title: title,
                subtitle: 'Code, issues, and proposed changes',
                leading: const Icon(Icons.code),
                trailing: Container(
                  key: badgeKey,
                  width: 190,
                  padding: const EdgeInsets.all(8),
                  child: const Text('Legacy connection · no longer used'),
                ),
                child: const SizedBox(height: 40),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final titleRect = tester.getRect(find.text(title));
      final badgeRect = tester.getRect(find.byKey(badgeKey));
      expect(titleRect.width, greaterThan(120));
      expect(badgeRect.top, greaterThan(titleRect.bottom));
      expect(tester.takeException(), isNull);
    },
  );
}
