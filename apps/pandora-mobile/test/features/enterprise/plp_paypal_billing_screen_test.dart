import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/plp_paypal_billing_screen.dart';

const _plans = [
  {'code': 'launch', 'currency': 'USD', 'monthly_fee_micros': 49000000},
  {'code': 'professional', 'currency': 'USD', 'monthly_fee_micros': 149000000},
];

final _year = DateTime.now().year;

Map<String, dynamic> _active({
  bool verified = true,
  Object? activity = const [],
}) =>
    {
      'subscription': {
        'plan_code': 'launch',
        'state': 'active',
        'currency': 'USD',
        'monthly_fee_micros': 49000000,
        'renews_on': '$_year-11-08',
        if (verified) 'source_kind': 'provider_verified',
        if (verified) 'verified_at': '$_year-10-08T03:00:00Z',
      },
      'plans': _plans,
      if (activity != null) 'activity': activity,
    };

class _Fake {
  _Fake(this.status);
  Map<String, dynamic> Function() status;
  final calls = <String>[];
  final opened = <Uri>[];
  final bodies = <String, Map<String, dynamic>>{};
  Object? failOn;
  Map<String, dynamic> cancelResult = const {};
  Completer<void>? gate;

  Future<Map<String, dynamic>> call(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    final code = body?['planCode'];
    calls.add('$method $path${code != null ? ' $code' : ''}');
    if (body != null) bodies[path] = body;
    if (gate != null) await gate!.future;
    if (failOn != null && path.endsWith(failOn.toString())) {
      throw Exception('PAYPAL_TIMEOUT');
    }
    if (path.endsWith('/checkout') || path.endsWith('/change-plan')) {
      return {'approvalUrl': 'https://www.paypal.com/approve'};
    }
    if (path.endsWith('/cancel')) return cancelResult;
    return status();
  }
}

Future<_Fake> _pump(WidgetTester tester, Map<String, dynamic> Function() s,
    {bool? isWeb, Uri? appBaseUri}) async {
  final fake = _Fake(s);
  await tester.pumpWidget(MaterialApp(
    home: PlpPaypalBillingScreen(
      organizationId: 'org-1',
      onOpenNavigation: () {},
      transport: fake.call,
      isWeb: isWeb,
      appBaseUri: appBaseUri,
      urlLauncher: (uri) async {
        fake.opened.add(uri);
        return true;
      },
    ),
  ));
  await tester.pumpAndSettle();
  return fake;
}

Future<void> _tap(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('plp-capability-$id')));
  await tester.pumpAndSettle();
}

void main() {
  test('monthly price reads micros with currency and interval', () {
    expect(plpBillingMonthlyPrice({'monthly_fee_micros': 49000000}),
        'USD 49 / month');
    expect(plpBillingMonthlyPrice({'monthly_fee_micros': '149000000'}),
        'USD 149 / month');
    expect(
      plpBillingMonthlyPrice(
          {'monthly_fee_micros': 149000000, 'discount_micros': 10500000}),
      'USD 138.50 / month',
    );
    expect(plpBillingMonthlyPrice({'monthly_fee': '49.00'}), 'USD 49 / month');
    expect(
      plpBillingMonthlyPrice(
          {'currency': 'PHP', 'monthly_fee_micros': 1250000000}),
      'PHP 1,250 / month',
    );
    expect(plpBillingMonthlyPrice({'monthly_fee': null}), 'Price unavailable');
    expect(
      plpBillingMonthlyPrice({
        'net_monthly_fee_micros': 99000000,
        'monthly_fee_micros': 149000000
      }),
      'USD 99 / month',
    );
    expect(
      plpBillingMonthlyPrice(
          {'monthly_fee_micros': 1000000, 'discount_micros': 2000000}),
      'Price unavailable',
    );
  });

  testWidgets(
      'setup shows both plans with currency and interval; select '
      'then pay', (tester) async {
    final fake =
        await _pump(tester, () => {'subscription': null, 'plans': _plans});
    expect(find.byKey(const ValueKey('plp-contextual-page-title')),
        findsOneWidget);
    expect(find.text('BILLING'), findsOneWidget);
    expect(find.text('USD 49 / month'), findsOneWidget);
    expect(find.text('USD 149 / month'), findsOneWidget);
    await _tap(tester, 'professional');
    expect(fake.calls.where((c) => c.startsWith('POST')), isEmpty);
    expect(find.text('Professional · USD 149 / month'), findsOneWidget);
    await _tap(tester, 'back');
    await _tap(tester, 'professional');
    await _tap(tester, 'pay-with-paypal');
    expect(fake.calls, contains('POST /billing/paypal/checkout professional'));
    expect(fake.opened.single.host, 'www.paypal.com');
  });

  test('PayPal returns web owners to the allowed site they started on', () {
    final omega = plpPaypalReturnUrls(
      isWeb: true,
      base: Uri.parse('https://enterprise-omega-five.vercel.app/#/enterprise'),
    );
    expect(omega.returnUrl,
        'https://enterprise-omega-five.vercel.app/#/enterprise/paypal-return');
    expect(omega.cancelUrl,
        'https://enterprise-omega-five.vercel.app/#/enterprise/paypal-cancel');
    expect(
      plpPaypalReturnUrls(
        isWeb: true,
        base: Uri.parse('https://pandoras-box-system.vercel.app/'),
      ).returnUrl,
      'https://pandoras-box-system.vercel.app/#/enterprise/paypal-return',
    );
    for (final base in [
      'https://evil.example.com/',
      'https://enterprise-omega-five.vercel.app.evil.com/',
      'http://enterprise-omega-five.vercel.app/',
      'http://localhost:8080/',
    ]) {
      expect(
        plpPaypalReturnUrls(isWeb: true, base: Uri.parse(base)).returnUrl,
        'https://mcpmaster.vercel.app/#/enterprise/paypal-return',
        reason: base,
      );
    }
    final android = plpPaypalReturnUrls(
      isWeb: false,
      base: Uri.parse('https://enterprise-omega-five.vercel.app/'),
    );
    expect(android.returnUrl,
        'https://mcpmaster.vercel.app/#/enterprise/paypal-return');
    expect(android.cancelUrl,
        'https://mcpmaster.vercel.app/#/enterprise/paypal-cancel');
  });

  testWidgets('web checkout sends return URLs for the current site',
      (tester) async {
    final fake = await _pump(
      tester,
      () => {'subscription': null, 'plans': _plans},
      isWeb: true,
      appBaseUri: Uri.parse('https://enterprise-omega-five.vercel.app/'),
    );
    await _tap(tester, 'launch');
    await _tap(tester, 'pay-with-paypal');
    final body = fake.bodies['/billing/paypal/checkout']!;
    expect(body['returnUrl'],
        'https://enterprise-omega-five.vercel.app/#/enterprise/paypal-return');
    expect(body['cancelUrl'],
        'https://enterprise-omega-five.vercel.app/#/enterprise/paypal-cancel');
  });

  testWidgets('rapid taps submit checkout once', (tester) async {
    final fake =
        await _pump(tester, () => {'subscription': null, 'plans': _plans});
    await _tap(tester, 'launch');
    fake.gate = Completer<void>();
    await tester
        .tap(find.byKey(const ValueKey('plp-capability-pay-with-paypal')));
    await tester.pump();
    await tester.tap(
        find.byKey(const ValueKey('plp-capability-pay-with-paypal')),
        warnIfMissed: false);
    await tester.pump();
    fake.gate!.complete();
    await tester.pumpAndSettle();
    expect(fake.calls.where((c) => c.contains('/checkout')).length, 1);
  });

  testWidgets('returning from PayPal without confirmation is not active',
      (tester) async {
    await _pump(
        tester,
        () => {
              'subscription': null,
              'plans': _plans,
              'checkout': {
                'plan_code': 'launch',
                'status': 'approval_pending',
                'approval_url': 'https://www.paypal.com/approve',
              },
            });
    expect(find.text('Finish in PayPal · not active yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-capability-open-paypal')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('plp-capability-change-plan')), findsNothing);
  });

  testWidgets('active shows micros price and truthful Verified',
      (tester) async {
    await _pump(tester, _active);
    expect(find.text('Launch · USD 49 / month · renews Nov 8'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
  });

  testWidgets('unverified subscription is Unconfirmed, never Verified',
      (tester) async {
    await _pump(tester, () => _active(verified: false));
    expect(find.text('Unconfirmed'), findsOneWidget);
    expect(find.text('Verified'), findsNothing);
  });

  testWidgets(
      'change plan confirm names the change; plan shown only from '
      'reconciled status', (tester) async {
    final fake = await _pump(tester, _active);
    await _tap(tester, 'change-plan');
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Launch to Professional · USD 149 / month from Nov 8'),
        findsOneWidget);
    await _tap(tester, 'switch-to-professional');
    expect(
        fake.calls, contains('POST /billing/paypal/change-plan professional'));
    expect(find.text('Launch · USD 49 / month · renews Nov 8'), findsOneWidget);
  });

  testWidgets('provider timeout on change keeps prior state with Retry',
      (tester) async {
    final fake = await _pump(tester, _active);
    fake.failOn = '/change-plan';
    await _tap(tester, 'change-plan');
    await _tap(tester, 'switch-to-professional');
    expect(find.text('PayPal didn’t respond.'), findsOneWidget);
    expect(find.textContaining('TIMEOUT'), findsNothing);
    await _tap(tester, 'back');
    expect(find.text('Launch · USD 49 / month · renews Nov 8'), findsOneWidget);
  });

  testWidgets('refresh failure keeps last confirmed state as Unconfirmed',
      (tester) async {
    final fake = await _pump(tester, _active);
    fake.failOn = '/reconcile';
    await _tap(tester, 'refresh');
    expect(find.text('PayPal didn’t respond.'), findsOneWidget);
    await _tap(tester, 'back');
    expect(find.text('Launch · USD 49 / month · renews Nov 8'), findsOneWidget);
    expect(find.text('Unconfirmed'), findsOneWidget);
    expect(find.text('Verified'), findsNothing);
    fake.failOn = null;
    await _tap(tester, 'refresh');
    expect(find.text('Verified'), findsOneWidget);
  });

  testWidgets('cancel confirms in page; accepted-not-reconciled is pending',
      (tester) async {
    final fake = await _pump(tester, _active);
    await _tap(tester, 'cancel');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Cancel Launch? No charge on Nov 8.'), findsOneWidget);
    expect(fake.calls, isNot(contains('POST /billing/paypal/cancel')));
    await _tap(tester, 'keep');
    expect(find.byKey(const ValueKey('plp-capability-change-plan')),
        findsOneWidget);
    fake.cancelResult = {
      'cancellation': {'cancelRequested': true, 'cancelled': false},
    };
    await _tap(tester, 'cancel');
    await _tap(tester, 'cancel');
    expect(fake.calls, contains('POST /billing/paypal/cancel'));
    expect(find.text('Cancellation pending'), findsOneWidget);
  });

  testWidgets('history distinguishes records, empty and unavailable',
      (tester) async {
    await _pump(
        tester,
        () => _active(activity: [
              {
                'occurred_at': '$_year-10-08T03:00:00Z',
                'amount_micros': 49000000,
                'currency': 'USD',
                'status': 'completed',
              },
              {'title': 'Not a payment'},
            ]));
    await _tap(tester, 'history');
    expect(find.text('USD 49'), findsOneWidget);
    expect(find.text('Oct 8 · Completed'), findsOneWidget);
    expect(find.text('Not a payment'), findsNothing);
  });

  testWidgets('history empty', (tester) async {
    await _pump(tester, () => _active(activity: const []));
    await _tap(tester, 'history');
    expect(find.text('No payments yet.'), findsOneWidget);
  });

  testWidgets('history unavailable', (tester) async {
    await _pump(tester, () => _active(activity: null));
    await _tap(tester, 'history');
    expect(find.text('History unavailable.'), findsOneWidget);
  });

  testWidgets('pull to refresh reconciles an active subscription',
      (tester) async {
    final fake = await _pump(tester, _active);
    await tester.fling(
      find.byKey(const ValueKey('plp-paypal-billing-list')),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();
    expect(fake.calls, contains('POST /billing/paypal/reconcile'));
  });

  testWidgets('cancelled shows end date and restart tiles', (tester) async {
    await _pump(
        tester,
        () => {
              'subscription': {
                'plan_code': 'launch',
                'state': 'cancelled',
                'ends_on': '$_year-11-08',
              },
              'plans': _plans,
            });
    expect(find.text('Cancelled · ends Nov 8'), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-capability-launch')), findsOneWidget);
  });

  testWidgets('existing PayPal approval is resumed, never a second checkout',
      (tester) async {
    final fake = await _pump(
        tester,
        () => {
              'subscription': null,
              'plans': _plans,
              'checkout': {
                'plan_code': 'professional',
                'status': 'approval_pending',
                'approval_url':
                    'https://www.paypal.com/approve?ba_token=EXISTING',
              },
            });
    await _tap(tester, 'open-paypal');
    expect(fake.opened.single.queryParameters['ba_token'], 'EXISTING');
    expect(fake.calls.where((c) => c.contains('/checkout')), isEmpty);
  });

  testWidgets('expired checkout returns to plans with its plan selected',
      (tester) async {
    await _pump(
        tester,
        () => {
              'subscription': null,
              'plans': _plans,
              'checkout': {
                'plan_code': 'professional',
                'status': 'expired',
                'approval_url': 'https://www.paypal.com/approve',
              },
            });
    expect(
        find.byKey(const ValueKey('plp-capability-open-paypal')), findsNothing);
    expect(
      tester.getSemantics(find.bySemanticsLabel(
          RegExp(r'^Professional, USD 149 / month, selected$'))),
      isNotNull,
    );
  });

  testWidgets('unknown renewal is never guessed', (tester) async {
    await _pump(tester, () {
      final status = _active();
      (status['subscription'] as Map).remove('renews_on');
      return status;
    });
    expect(find.text('Launch · USD 49 / month'), findsOneWidget);
    await _tap(tester, 'change-plan');
    expect(
        find.text('Launch to Professional · USD 149 / month'), findsOneWidget);
  });

  testWidgets('cancelled without an end date still says Cancelled',
      (tester) async {
    await _pump(
        tester,
        () => {
              'subscription': {'plan_code': 'launch', 'state': 'cancelled'},
              'plans': _plans,
              'provider': {'configured': false},
            });
    expect(find.text('Cancelled'), findsOneWidget);
  });

  testWidgets('load failure is one short line with Retry', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PlpPaypalBillingScreen(
        organizationId: 'org-1',
        onOpenNavigation: () {},
        transport: (path, {method = 'GET', body}) async =>
            throw Exception('BILLING_REQUEST_FAILED'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t load.'), findsOneWidget);
    expect(find.textContaining('BILLING_REQUEST_FAILED'), findsNothing);
    expect(find.byKey(const ValueKey('plp-capability-retry')), findsOneWidget);
  });
}
