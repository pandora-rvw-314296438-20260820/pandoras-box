import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/plp_connectivity_infrastructure_screen.dart';

void main() {
  testWidgets(
    'PLP connectivity surface defaults to truthful available states',
    (tester) async {
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

      expect(find.text('PLDT ENTERPRISE READY'), findsOneWidget);
      expect(find.text('The resort’s digital foundation.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('plp-connectivity-truth-contract')),
        findsOneWidget,
      );
      expect(find.text('AVAILABLE TO ACTIVATE'), findsNWidgets(8));
      expect(find.text('PROVIDER VERIFIED'), findsNothing);

      await tester.ensureVisible(
        find.byKey(const ValueKey('plp-connectivity-review-action')),
      );
      await tester.tap(
        find.byKey(const ValueKey('plp-connectivity-review-action')),
      );
      await tester.pump();

      expect(prompt, contains('Use only verified PLP data'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'PLP connectivity surface shows verified state only with evidence',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PlpConnectivityInfrastructureScreen(
            bootstrap: const <String, Object?>{
              'enterpriseConnectivity': <String, Object?>{
                'channelStatus': 'PLDT Enterprise provider link available',
                'verifiedAt': '2026-10-01T00:00:00+08:00',
                'services': <String, Object?>{
                  'dedicated-internet': <String, Object?>{
                    'state': 'healthy',
                    'providerVerified': true,
                    'evidenceRef': 'provider-readback:test',
                    'message': 'Primary connectivity provider readback is healthy.',
                  },
                },
              },
            },
            onAskPandora: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PROVIDER VERIFIED'), findsOneWidget);
      expect(find.text('AVAILABLE TO ACTIVATE'), findsNWidgets(7));
      expect(
        find.text('Primary connectivity provider readback is healthy.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
