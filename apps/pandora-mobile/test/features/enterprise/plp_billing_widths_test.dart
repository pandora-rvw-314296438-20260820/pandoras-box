import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/plp_editorial_surfaces.dart';

void main() {
  testWidgets('revenue billing editorial layout holds at required widths', (tester) async {
    const widths = <double>[320, 360, 390, 600, 768, 1280];
    for (final width in widths) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(
        MaterialApp(
          home: PlpEditorialPage(
            pageKey: ValueKey('billing-width-$width'),
            eyebrow: 'Revenue',
            title: 'Professional',
            intro: 'Subscription truth for this PLP Enterprise account.',
            onOpenNavigation: () {},
            children: const [
              PlpSectionTitle('Current subscription'),
              PlpEditorialRow(
                title: 'Professional',
                detail: 'active · Verified',
                value: 'PHP 149.00',
              ),
              PlpEditorialRow(
                title: 'Professional → Enterprise',
                detail: 'Approval required · approval_pending',
                value: '+PHP 100.00',
              ),
              PlpEditorialRow(
                title: 'Reconcile with PayPal',
                detail: 'Re-read provider state.',
              ),
              PlpEditorialRow(
                title: 'Cancel subscription',
                detail: 'Destructive and subordinate.',
                tone: plpWarn,
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'overflow at $width');
      expect(find.text('Revenue'), findsNothing);
      expect(find.text('REVENUE'), findsOneWidget);
      expect(find.text('Professional → Enterprise'), findsOneWidget);
    }
    await tester.binding.setSurfaceSize(null);
  });
}
