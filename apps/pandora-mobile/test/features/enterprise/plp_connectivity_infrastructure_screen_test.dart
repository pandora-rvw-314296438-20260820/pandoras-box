import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/plp_connectivity_infrastructure_screen.dart';

void main() {
  testWidgets(
    'PLP infrastructure is outcome-first instead of a provider catalogue',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String? prompt;
      await tester.pumpWidget(
        MaterialApp(
          home: PlpConnectivityInfrastructureScreen(
            bootstrap: const <String, Object?>{},
            onAskPandora: (value) => prompt = value,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('RESORT RESILIENCE'), findsOneWidget);
      expect(find.text('Set the resort’s baseline.'), findsOneWidget);
      expect(find.text('NOT VERIFIED'), findsNWidgets(4));

      for (final key in <String>['internet', 'resilience', 'team', 'property']) {
        expect(
          find.byKey(ValueKey<String>('plp-infra-signal-$key')),
          findsOneWidget,
        );
      }

      for (final oldCopy in <String>[
        'PLDT ENTERPRISE READY',
        'Commercial integration not connected',
        'ENTERPRISE CAPABILITIES',
        'AVAILABLE TO ACTIVATE',
        'WHEN PANDORA FINDS AN OPPORTUNITY',
      ]) {
        expect(find.text(oldCopy), findsNothing);
      }

      final baseline =
          find.byKey(const ValueKey('plp-infrastructure-baseline-action'));
      await tester.scrollUntilVisible(
        baseline,
        280,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(baseline);
      await tester.pump();

      expect(prompt, contains('verified infrastructure baseline'));
      expect(prompt, contains('Do not turn this into a service catalogue'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'PLP infrastructure promotes only provider-backed evidence',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: PlpConnectivityInfrastructureScreen(
            bootstrap: const <String, Object?>{
              'enterpriseConnectivity': <String, Object?>{
                'services': <String, Object?>{
                  'dedicated-internet': <String, Object?>{
                    'state': 'healthy',
                    'providerVerified': true,
                    'evidenceRef': 'provider-readback:test',
                  },
                  'fiveg-backup': <String, Object?>{
                    'state': 'pending_verification',
                    'providerVerified': false,
                  },
                },
              },
            },
            onAskPandora: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('2 of 4 areas have provider evidence.'),
        findsOneWidget,
      );

      final internet =
          find.byKey(const ValueKey('plp-infra-signal-internet'));
      expect(
        find.descendant(of: internet, matching: find.text('VERIFIED')),
        findsOneWidget,
      );

      final resilience =
          find.byKey(const ValueKey('plp-infra-signal-resilience'));
      expect(
        find.descendant(of: resilience, matching: find.text('CHECKING')),
        findsOneWidget,
      );

      expect(find.text('AVAILABLE TO ACTIVATE'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
