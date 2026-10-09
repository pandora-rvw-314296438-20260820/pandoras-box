import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/app/plp_enterprise_shell.dart';
import 'package:pandora_mobile/core/data/plp_paypal_billing_api.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';

import '../helpers/fake_owner_api.dart';
import '../helpers/test_app.dart';

Map<String, Object?> _bootstrap(String organizationId, {String role = 'owner'}) =>
    <String, Object?>{
      'generatedAt': '2026-10-09T00:00:00Z',
      'organization': <String, Object?>{
        'id': organizationId,
        'propertyName': 'Pueblo La Perla',
        'propertySlug': 'plp-boracay',
      },
      'user': <String, Object?>{'displayName': 'QA', 'role': role},
      'sourceHealth': <String, Object?>{'state': 'healthy'},
    };

const _plans = [
  {'code': 'launch', 'name': 'Launch', 'currency': 'USD', 'monthly_fee_micros': 49000000},
  {'code': 'professional', 'name': 'Professional', 'currency': 'USD', 'monthly_fee_micros': 149000000},
];

Map<String, dynamic> _subscription({bool verified = true}) => {
      'plan_code': 'launch',
      'state': 'active',
      'currency': 'USD',
      'monthly_fee_micros': 49000000,
      if (verified) 'source_kind': 'provider_verified',
      if (verified) 'verified_at': '2026-10-08T03:00:00Z',
    };

final _unpaid = <String, dynamic>{
  'subscription': null,
  'plans': _plans,
  'checkout': null,
  'provider': {'configured': true},
};
final _verified = <String, dynamic>{'subscription': _subscription(), 'plans': _plans};
final _unconfirmed = <String, dynamic>{
  'subscription': _subscription(verified: false),
  'plans': _plans,
};
final _pending = <String, dynamic>{
  'subscription': null,
  'plans': _plans,
  'checkout': {
    'plan_code': 'launch',
    'status': 'approval_pending',
    'approval_url': 'https://www.paypal.com/webapps/billing/subscriptions?ba_token=X',
  },
};

PlpBillingTransport _transport(
  Map<String, dynamic> Function() status, {
  List<String>? calls,
}) =>
    (path, {method = 'GET', body}) async {
      calls?.add('$method $path');
      return status();
    };

Future<void> _mount(
  WidgetTester tester, {
  required Map<String, Object?> bootstrap,
  required PlpBillingTransport transport,
}) async {
  await setTestSurface(tester, logicalSize: const Size(390, 844));
  await tester.pumpWidget(
    PandoraDependencies(
      auth: const FakeAuth(),
      repository: FakeRepository(),
      diagnostics: DiagnosticsStore(),
      child: testApp(
        child: PlpEnterpriseShell(
          bootstrapOverride: bootstrap,
          billingTransport: transport,
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('plp-floating-navigation')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byKey(const ValueKey('plp-navigation-drawer')), findsOneWidget);
}

Finder _gate() => find.byKey(const ValueKey('plp-subscription-gate'));
Finder _home() => find.byKey(const ValueKey('plp-enterprise-home'));
Finder _plansHome() => find.byKey(const ValueKey('plp-subscription-plans'));

void main() {
  test('only an active, PayPal-verified subscription unlocks', () {
    expect(plpBillingStatusUnlocked(_verified), isTrue);
    expect(plpBillingStatusUnlocked(_unpaid), isFalse);
    expect(plpBillingStatusUnlocked(_pending), isFalse);
    expect(plpBillingStatusUnlocked(_unconfirmed), isFalse);
    expect(
      plpBillingStatusUnlocked({
        'subscription': {..._subscription(), 'state': 'cancelled'},
      }),
      isFalse,
    );
    expect(
      plpBillingStatusUnlocked({
        'subscription': {..._subscription(), 'verified_at': null},
      }),
      isFalse,
    );
  });

  testWidgets('unpaid owner lands on the plans as home', (tester) async {
    final calls = <String>[];
    await _mount(
      tester,
      bootstrap: _bootstrap('org-unpaid'),
      transport: _transport(() => _unpaid, calls: calls),
    );

    expect(_gate(), findsOneWidget);
    expect(_plansHome(), findsOneWidget);
    expect(find.text('Pay monthly with PayPal.'), findsOneWidget);
    expect(find.text('Launch'), findsOneWidget);
    expect(find.text('Professional'), findsOneWidget);
    expect(find.text('USD 49 / month'), findsOneWidget);
    expect(find.text('USD 149 / month'), findsOneWidget);
    expect(_home(), findsNothing);
    // Alfred is a paid feature: no assistant launcher while locked.
    expect(find.byKey(const ValueKey('plp-ai-launcher')), findsNothing);
    // Status reads only; the gate never starts a checkout by itself.
    expect(calls.every((call) => call == 'GET /billing/paypal/status'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('verified active subscription opens the normal home',
      (tester) async {
    await _mount(
      tester,
      bootstrap: _bootstrap('org-verified'),
      transport: _transport(() => _verified),
    );

    expect(_gate(), findsNothing);
    expect(_home(), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-ai-launcher')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending checkout stays locked on Finish in PayPal',
      (tester) async {
    await _mount(
      tester,
      bootstrap: _bootstrap('org-pending'),
      transport: _transport(() => _pending),
    );

    expect(_plansHome(), findsOneWidget);
    expect(find.text('Finish in PayPal · not active yet'), findsOneWidget);
    expect(find.text('Open PayPal'), findsOneWidget);
    expect(_home(), findsNothing);
  });

  testWidgets('active but unconfirmed by PayPal stays locked', (tester) async {
    await _mount(
      tester,
      bootstrap: _bootstrap('org-unconfirmed'),
      transport: _transport(() => _unconfirmed),
    );

    expect(_plansHome(), findsOneWidget);
    expect(_home(), findsNothing);
  });

  testWidgets('staff of an unpaid org see only the waiting notice',
      (tester) async {
    await _mount(
      tester,
      bootstrap: _bootstrap('org-staff', role: 'operator'),
      transport: _transport(() => _unpaid),
    );

    expect(find.text('Waiting for the owner to subscribe.'), findsOneWidget);
    expect(_plansHome(), findsNothing);
    expect(find.text('Launch'), findsNothing);
    expect(_home(), findsNothing);
  });

  testWidgets('staff denied billing access stay on the waiting notice',
      (tester) async {
    await _mount(
      tester,
      bootstrap: _bootstrap('org-staff-denied', role: 'member'),
      transport: (path, {method = 'GET', body}) async =>
          throw const PlpBillingRequestException(
            statusCode: 403,
            code: 'OWNER_ROLE_REQUIRED',
            message: 'You do not have permission for this yet.',
          ),
    );

    expect(find.text('Waiting for the owner to subscribe.'), findsOneWidget);
    expect(_home(), findsNothing);
  });

  testWidgets('status error shows Couldn’t load and Retry recovers',
      (tester) async {
    var fail = true;
    await _mount(
      tester,
      bootstrap: _bootstrap('org-error'),
      transport: (path, {method = 'GET', body}) async {
        if (fail) throw Exception('BILLING_REQUEST_FAILED');
        return _verified;
      },
    );

    expect(find.text('Couldn’t load.'), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-capability-retry')), findsOneWidget);
    expect(_home(), findsNothing);

    fail = false;
    await tester.tap(find.byKey(const ValueKey('plp-capability-retry')));
    await _settle(tester);
    expect(_home(), findsOneWidget);
  });

  testWidgets('a verified org stays open when a later status read fails',
      (tester) async {
    await _mount(
      tester,
      bootstrap: _bootstrap('org-cached'),
      transport: _transport(() => _verified),
    );
    expect(_home(), findsOneWidget);

    // A fresh shell in the same app session, provider now unreachable.
    await tester.pumpWidget(const SizedBox.shrink());
    await _mount(
      tester,
      bootstrap: _bootstrap('org-cached'),
      transport: (path, {method = 'GET', body}) async =>
          throw Exception('network down'),
    );
    expect(_home(), findsOneWidget);
    expect(find.text('Couldn’t load.'), findsNothing);
  });

  testWidgets('locked menu: Billing open, every feature locked back to plans',
      (tester) async {
    await _mount(
      tester,
      bootstrap: _bootstrap('org-menu-locked'),
      transport: _transport(() => _unpaid),
    );
    await _openDrawer(tester);

    final billing = find.byKey(const ValueKey('plp-drawer-billing'));
    expect(billing, findsOneWidget);
    expect(find.descendant(of: billing, matching: find.byIcon(Icons.lock_outline_rounded)),
        findsNothing);
    final rooms = find.byKey(const ValueKey('plp-drawer-rooms'));
    expect(find.descendant(of: rooms, matching: find.byIcon(Icons.lock_outline_rounded)),
        findsOneWidget);
    expect(find.byKey(const ValueKey('plp-drawer-lock')), findsWidgets);

    await tester.tap(rooms);
    await _settle(tester);
    expect(_plansHome(), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-resort-rooms')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paid menu keeps Billing and opens the billing page',
      (tester) async {
    await _mount(
      tester,
      bootstrap: _bootstrap('org-menu-paid'),
      transport: _transport(() => _verified),
    );
    await _openDrawer(tester);

    final billing = find.byKey(const ValueKey('plp-drawer-billing'));
    expect(billing, findsOneWidget);
    expect(find.byKey(const ValueKey('plp-drawer-lock')), findsNothing);

    await tester.tap(billing);
    await _settle(tester);
    expect(find.byKey(const ValueKey('plp-paypal-billing')), findsOneWidget);
    expect(find.text('Change plan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner confirming payment in Billing unlocks the workspace',
      (tester) async {
    var status = _unpaid;
    await _mount(
      tester,
      bootstrap: _bootstrap('org-unlock'),
      transport: (path, {method = 'GET', body}) async => status,
    );
    expect(_plansHome(), findsOneWidget);

    // PayPal confirmed server-side; the owner pulls to refresh billing.
    status = _verified;
    await tester.fling(
      find.byKey(const ValueKey('plp-paypal-billing-list')),
      const Offset(0, 400),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    expect(_home(), findsOneWidget);
  });
}
