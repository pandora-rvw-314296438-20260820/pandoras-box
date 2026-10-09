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
  PlpBillingTransport? transport,
  PlpEntitlementReader? entitlement,
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
          billingTransport: transport ??
              (path, {method = 'GET', body}) async =>
                  throw StateError('staff must not read billing'),
          entitlementReader: entitlement ??
              (_) async => throw StateError('entitlement unavailable'),
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

Future<void> _tapDrawer(WidgetTester tester, String id) async {
  final item = find.byKey(ValueKey<String>('plp-drawer-$id'));
  await tester.ensureVisible(item);
  await tester.tap(item);
  await _settle(tester);
}

Finder _home() => find.byKey(const ValueKey('plp-enterprise-home'));
Finder _billing() => find.byKey(const ValueKey('plp-paypal-billing'));
Finder _notice() => find.byKey(const ValueKey('plp-unlock-notice'));
Finder _chat() => find.byKey(const ValueKey('plp-ai-launcher'));
Finder _lockedChat() => find.byKey(const ValueKey('plp-ai-launcher-locked'));
Finder _lockIn(String id) => find.descendant(
      of: find.byKey(ValueKey<String>('plp-drawer-$id')),
      matching: find.byIcon(Icons.lock_outline_rounded),
    );

const _freeMenu = ['home', 'rooms', 'activity', 'billing'];
const _lockedMenu = [
  'stays',
  'guests',
  'operations',
  'revenue',
  'experiences',
  'team',
];

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

  testWidgets('unpaid owner lands on Today with one unlock line',
      (tester) async {
    final calls = <String>[];
    await _mount(
      tester,
      bootstrap: _bootstrap('org-unpaid'),
      transport: _transport(() => _unpaid, calls: calls),
    );

    expect(_home(), findsOneWidget);
    expect(_billing(), findsNothing);
    expect(_notice(), findsOneWidget);
    expect(find.text('Unlock everything · from USD 49 / month'), findsOneWidget);
    // The assistant is locked: no live launcher, a locked one instead.
    expect(_chat(), findsNothing);
    expect(_lockedChat(), findsOneWidget);
    // Locked workspace tiles on Today keep a small lock.
    expect(find.byKey(const ValueKey('plp-section-lock')), findsWidgets);
    expect(calls.every((call) => call == 'GET /billing/paypal/status'), isTrue);

    await tester.tap(_notice());
    await _settle(tester);
    expect(_billing(), findsOneWidget);
    expect(find.text('Grow\nwhat’s next.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('plp-billing-choose-plan')));
     await _settle(tester);
     await tester.tap(find.byKey(const ValueKey('plp-billing-choose-plan')));
    await _settle(tester);
    expect(find.text('Choose your plan.'), findsOneWidget);
    expect(find.text('Launch'), findsWidgets);
    expect(find.text('Professional'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unpaid menu: free items open, locked items keep a lock',
      (tester) async {
    await _mount(
      tester,
      bootstrap: _bootstrap('org-menu'),
      transport: _transport(() => _unpaid),
    );
    await _openDrawer(tester);
    for (final id in _freeMenu) {
      expect(find.byKey(ValueKey<String>('plp-drawer-$id')), findsOneWidget,
          reason: id);
      expect(_lockIn(id), findsNothing, reason: id);
    }
    for (final id in _lockedMenu) {
      expect(_lockIn(id), findsOneWidget, reason: id);
    }

    await _tapDrawer(tester, 'rooms');
    expect(find.byKey(const ValueKey('plp-resort-rooms')), findsOneWidget);
    expect(_billing(), findsNothing);

    await _openDrawer(tester);
    await _tapDrawer(tester, 'activity');
    expect(find.byKey(const ValueKey('plp-resort-activity')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('locked menu item and locked tile open Billing plans',
      (tester) async {
    await _mount(
      tester,
      bootstrap: _bootstrap('org-locked-tap'),
      transport: _transport(() => _unpaid),
    );
    await _openDrawer(tester);
    await _tapDrawer(tester, 'stays');
    expect(find.byKey(const ValueKey('plp-resort-stays')), findsNothing);
    expect(_billing(), findsOneWidget);
    expect(find.text('Grow\nwhat’s next.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('plp-billing-choose-plan')));
     await _settle(tester);
     await tester.tap(find.byKey(const ValueKey('plp-billing-choose-plan')));
    await _settle(tester);
    expect(find.text('Choose your plan.'), findsOneWidget);
    expect(find.text('Launch'), findsWidgets);
    expect(find.text('Professional'), findsOneWidget);

    await _openDrawer(tester);
    await _tapDrawer(tester, 'home');
    expect(_home(), findsOneWidget);
    final guests = find.byKey(const ValueKey('plp-section-tile-guests'));
    await tester.ensureVisible(guests);
    await tester.tap(guests);
    await _settle(tester);
    expect(find.byKey(const ValueKey('plp-resort-guests')), findsNothing);
    expect(_billing(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('assistant, Recent chats and New chat are locked while unpaid',
      (tester) async {
    await _mount(
      tester,
      bootstrap: _bootstrap('org-chat'),
      transport: _transport(() => _unpaid),
    );
    await tester.tap(_lockedChat());
    await _settle(tester);
    expect(_billing(), findsOneWidget);

    await _openDrawer(tester);
    final newChat = find.byKey(const ValueKey('plp-drawer-new-chat'));
    expect(
      find.descendant(of: newChat, matching: find.byIcon(Icons.lock_outline_rounded)),
      findsOneWidget,
    );
    expect(find.text('No recent chats'), findsNothing);
    await tester.tap(newChat);
    await _settle(tester);
    expect(_billing(), findsOneWidget);
    expect(_chat(), findsNothing);
  });

  testWidgets('verified active subscription unlocks everything',
      (tester) async {
    await _mount(
      tester,
      bootstrap: _bootstrap('org-verified'),
      transport: _transport(() => _verified),
    );

    expect(_home(), findsOneWidget);
    expect(_notice(), findsNothing);
    expect(_chat(), findsOneWidget);
    expect(_lockedChat(), findsNothing);
    expect(find.byKey(const ValueKey('plp-section-lock')), findsNothing);

    await _openDrawer(tester);
    expect(find.byKey(const ValueKey('plp-drawer-lock')), findsNothing);
    await _tapDrawer(tester, 'stays');
    expect(find.byKey(const ValueKey('plp-resort-stays')), findsOneWidget);

    await _openDrawer(tester);
    await _tapDrawer(tester, 'billing');
    expect(_billing(), findsOneWidget);
    expect(find.text('Change plan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending checkout stays locked and Billing shows Finish in PayPal',
      (tester) async {
    await _mount(
      tester,
      bootstrap: _bootstrap('org-pending'),
      transport: _transport(() => _pending),
    );
    expect(_home(), findsOneWidget);
    expect(_lockedChat(), findsOneWidget);
    await _openDrawer(tester);
    await _tapDrawer(tester, 'revenue');
    expect(find.text('Finish in PayPal · not active yet'), findsOneWidget);
    expect(find.text('Open PayPal'), findsOneWidget);
  });

  testWidgets('active but unconfirmed by PayPal stays locked', (tester) async {
    await _mount(
      tester,
      bootstrap: _bootstrap('org-unconfirmed'),
      transport: _transport(() => _unconfirmed),
    );
    expect(_lockedChat(), findsOneWidget);
    await _openDrawer(tester);
    expect(_lockIn('stays'), findsOneWidget);
  });

  testWidgets('staff of an unpaid org: free set, waiting notice on locked',
      (tester) async {
    await _mount(
      tester,
      bootstrap: _bootstrap('org-staff', role: 'operator'),
      entitlement: (_) async => false,
    );

    expect(_home(), findsOneWidget);
    expect(_notice(), findsNothing);
    expect(_lockedChat(), findsOneWidget);
    await _openDrawer(tester);
    expect(find.byKey(const ValueKey('plp-drawer-billing')), findsNothing);
    expect(_lockIn('guests'), findsOneWidget);
    expect(_lockIn('rooms'), findsNothing);

    await _tapDrawer(tester, 'guests');
    expect(find.text('Waiting for the owner to subscribe.'), findsOneWidget);
    expect(_billing(), findsNothing);
    expect(find.text('Launch'), findsNothing);

    await tester.tap(_lockedChat());
    await _settle(tester);
    expect(find.text('Waiting for the owner to subscribe.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('staff of a paid org are unlocked by the entitlement flag',
      (tester) async {
    final orgs = <String>[];
    await _mount(
      tester,
      bootstrap: _bootstrap('org-staff-paid', role: 'member'),
      entitlement: (org) async {
        orgs.add(org);
        return true;
      },
    );
    expect(orgs, ['org-staff-paid']);
    expect(_chat(), findsOneWidget);
    expect(_lockedChat(), findsNothing);
    await _openDrawer(tester);
    expect(find.byKey(const ValueKey('plp-drawer-lock')), findsNothing);
    await _tapDrawer(tester, 'guests');
    expect(find.byKey(const ValueKey('plp-resort-guests')), findsOneWidget);
  });

  testWidgets('status error: Couldn’t load + Retry on locked, Retry recovers',
      (tester) async {
    var fail = true;
    await _mount(
      tester,
      bootstrap: _bootstrap('org-error', role: 'operator'),
      entitlement: (_) async {
        if (fail) throw Exception('network down');
        return true;
      },
    );
    expect(_home(), findsOneWidget);
    await _openDrawer(tester);
    await _tapDrawer(tester, 'team');
    expect(find.text('Couldn’t load.'), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-capability-retry')), findsOneWidget);

    fail = false;
    await tester.tap(find.byKey(const ValueKey('plp-capability-retry')));
    await _settle(tester);
    expect(find.text('Couldn’t load.'), findsNothing);
    expect(_chat(), findsOneWidget);
  });

  testWidgets('owner falls back to the entitlement flag when owner-api fails',
      (tester) async {
    await _mount(
      tester,
      bootstrap: _bootstrap('org-owner-fallback'),
      transport: (path, {method = 'GET', body}) async =>
          throw Exception('owner-api down'),
      entitlement: (_) async => true,
    );
    expect(_chat(), findsOneWidget);
  });

  testWidgets('a verified org stays open when a later status read fails',
      (tester) async {
    await _mount(
      tester,
      bootstrap: _bootstrap('org-cached'),
      transport: _transport(() => _verified),
    );
    expect(_chat(), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await _mount(
      tester,
      bootstrap: _bootstrap('org-cached'),
      transport: (path, {method = 'GET', body}) async =>
          throw Exception('network down'),
    );
    expect(_chat(), findsOneWidget);
    expect(_lockedChat(), findsNothing);
  });

  testWidgets('owner confirming payment in Billing unlocks the workspace',
      (tester) async {
    var status = _unpaid;
    await _mount(
      tester,
      bootstrap: _bootstrap('org-unlock'),
      transport: (path, {method = 'GET', body}) async => status,
    );
    await tester.tap(_notice());
    await _settle(tester);
    expect(_billing(), findsOneWidget);

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
    expect(find.text('Change plan'), findsOneWidget);
    expect(_chat(), findsOneWidget);
    await _openDrawer(tester);
    expect(find.byKey(const ValueKey('plp-drawer-lock')), findsNothing);
  });
}
