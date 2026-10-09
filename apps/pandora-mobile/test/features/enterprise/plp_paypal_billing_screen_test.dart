import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pandora_mobile/core/analytics/owner_analytics.dart';
import 'package:pandora_mobile/core/data/plp_paypal_billing_api.dart';
import 'package:pandora_mobile/features/enterprise/plp_paypal_billing_screen.dart';

import '../../helpers/test_app.dart';

const _plans = [
  {'code': 'launch', 'name': 'Launch', 'currency': 'USD', 'monthly_fee_micros': 49000000},
  {
    'code': 'professional',
    'name': 'Professional',
    'currency': 'USD',
    'monthly_fee_micros': 149000000
  },
];

final _year = DateTime.now().year;

Map<String, dynamic> _active({
  bool verified = true,
  Object? activity = const [],
}) =>
    {
      'subscription': {
        'plan_code': 'launch',
        'plan_name': 'Launch',
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

class _RecordedEvent {
  const _RecordedEvent(
    this.event, {
    this.origin,
    this.plan,
    this.reason,
    this.attempt,
    this.sinceView,
  });

  final OwnerAnalyticsEvent event;
  final String? origin;
  final String? plan;
  final String? reason;
  final int? attempt;
  final Duration? sinceView;
}

class _Fake {
  _Fake(this.status);
  Map<String, dynamic> Function() status;
  final calls = <String>[];
  final opened = <Uri>[];
  final bodies = <String, Map<String, dynamic>>{};
  Object? failOn;
  Object? Function(String path)? customFail;
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
    if (customFail != null) {
      final err = customFail!(path);
      if (err != null) throw err;
    }
    if (failOn != null && path.endsWith(failOn.toString())) {
      throw Exception('PAYPAL_TIMEOUT');
    }
    if (path.endsWith('/checkout') || path.endsWith('/change-plan')) {
      return {'approvalUrl': 'https://www.paypal.com/approve'};
    }
    if (path.endsWith('/cancel')) return cancelResult;
    if (path.endsWith('/reconcile')) return {'reconciled': true};
    return status();
  }
}

Future<_Fake> _pump(
  WidgetTester tester,
  Map<String, dynamic> Function() s, {
  bool? isWeb,
  Uri? appBaseUri,
  String? origin,
  String? originLabel,
  Map<String, dynamic>? initialStatus,
  PlpCheckoutReturn? paypalReturn,
  List<_RecordedEvent>? recordedEvents,
  VoidCallback? onActivated,
  Duration confirmPollInterval = const Duration(milliseconds: 10),
  int confirmPollAttempts = 3,
  Duration successHold = const Duration(milliseconds: 50),
  bool applyDefaultSurface = true,
}) async {
  final fake = _Fake(s);
  if (applyDefaultSurface) {
    await setTestSurface(tester, logicalSize: const Size(390, 1400));
  }
  await tester.pumpWidget(
    testApp(
      child: PlpPaypalBillingScreen(
        organizationId: 'org-1',
        onOpenNavigation: () {},
        transport: fake.call,
        isWeb: isWeb,
        appBaseUri: appBaseUri,
        origin: origin,
        originLabel: originLabel,
        initialStatus: initialStatus,
        paypalReturn: paypalReturn,
        onEvent: recordedEvents == null
            ? null
            : (event, {origin, plan, reason, attempt, sinceView}) {
                recordedEvents.add(_RecordedEvent(
                  event,
                  origin: origin,
                  plan: plan,
                  reason: reason,
                  attempt: attempt,
                  sinceView: sinceView,
                ));
              },
        onActivated: onActivated,
        confirmPollInterval: confirmPollInterval,
        confirmPollAttempts: confirmPollAttempts,
        successHold: successHold,
        urlLauncher: (uri) async {
          fake.opened.add(uri);
          return true;
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

Future<void> _tap(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('plp-capability-$id')));
  await tester.pumpAndSettle();
}

void main() {
  group('Unit helpers', () {
    test('monthly price reads micros with currency and interval', () {
      expect(
        plpBillingMonthlyPrice({'monthly_fee_micros': 49000000}),
        'USD 49 / month',
      );
      expect(
        plpBillingMonthlyPrice({'monthly_fee_micros': '149000000'}),
        'USD 149 / month',
      );
      expect(
        plpBillingMonthlyPrice({
          'monthly_fee_micros': 149000000,
          'discount_micros': 10500000,
        }),
        'USD 138.50 / month',
      );
      expect(
        plpBillingMonthlyPrice({'monthly_fee': '49.00'}),
        'USD 49 / month',
      );
      expect(
        plpBillingMonthlyPrice(
            {'currency': 'PHP', 'monthly_fee_micros': 1250000000}),
        'PHP 1,250 / month',
      );
      expect(
        plpBillingMonthlyPrice({'monthly_fee': null}),
        'Price unavailable',
      );
      expect(
        plpBillingMonthlyPrice({
          'net_monthly_fee_micros': 99000000,
          'monthly_fee_micros': 149000000,
        }),
        'USD 99 / month',
      );
      expect(
        plpBillingMonthlyPrice({
          'monthly_fee_micros': 1000000,
          'discount_micros': 2000000,
        }),
        'Price unavailable',
      );
    });

    test('plpBillingTransientError returns true for transient errors', () {
      expect(plpBillingTransientError(TimeoutException('timeout')), isTrue);
      expect(plpBillingTransientError(http.ClientException('network')), isTrue);
      expect(
        plpBillingTransientError(const PlpBillingRequestException(
          statusCode: 429,
          code: 'RATE_LIMIT',
          message: 'slow down',
        )),
        isTrue,
      );
      expect(
        plpBillingTransientError(const PlpBillingRequestException(
          statusCode: 500,
          code: 'INTERNAL',
          message: 'error',
        )),
        isTrue,
      );
      expect(
        plpBillingTransientError(const PlpBillingRequestException(
          statusCode: 503,
          code: 'UNAVAILABLE',
          message: 'service down',
        )),
        isTrue,
      );
      expect(
        plpBillingTransientError(const PlpBillingRequestException(
          statusCode: 400,
          code: 'BAD_REQUEST',
          message: 'invalid',
        )),
        isFalse,
      );
      expect(plpBillingTransientError(FormatException('json')), isFalse);
    });

    test('plpCheckoutReturnFromUri extracts return/cancel and origin', () {
      final ret = plpCheckoutReturnFromUri(Uri.parse(
        'https://mcpmaster.vercel.app/#/enterprise/paypal-return?from=stays&subscription_id=I-1',
      ));
      expect(ret, isNotNull);
      expect(ret!.cancelled, isFalse);
      expect(ret.origin, 'stays');

      final cancel = plpCheckoutReturnFromUri(Uri.parse(
        'https://mcpmaster.vercel.app/#/enterprise/paypal-cancel?from=revenue',
      ));
      expect(cancel, isNotNull);
      expect(cancel!.cancelled, isTrue);
      expect(cancel.origin, 'revenue');

      final unknownOrigin = plpCheckoutReturnFromUri(Uri.parse(
        'https://mcpmaster.vercel.app/#/enterprise/paypal-return?from=unauthorized',
      ));
      expect(unknownOrigin, isNotNull);
      expect(unknownOrigin!.cancelled, isFalse);
      expect(unknownOrigin.origin, isNull);

      final noQuery = plpCheckoutReturnFromUri(Uri.parse(
        'https://mcpmaster.vercel.app/#/enterprise/paypal-return',
      ));
      expect(noQuery, isNotNull);
      expect(noQuery!.cancelled, isFalse);
      expect(noQuery.origin, isNull);

      final queryParamInPath = plpCheckoutReturnFromUri(Uri.parse(
        'https://mcpmaster.vercel.app/enterprise/paypal-return?from=team',
      ));
      expect(queryParamInPath, isNotNull);
      expect(queryParamInPath!.origin, 'team');

      final nonReturn = plpCheckoutReturnFromUri(Uri.parse(
        'https://mcpmaster.vercel.app/#/enterprise/other',
      ));
      expect(nonReturn, isNull);
    });

    test('plpPaypalReturnUrls handles origin parameter correctly', () {
      final withOrigin = plpPaypalReturnUrls(
        isWeb: true,
        base: Uri.parse('https://enterprise-omega-five.vercel.app/#/enterprise'),
        origin: 'stays',
      );
      expect(
        withOrigin.returnUrl,
        'https://enterprise-omega-five.vercel.app/#/enterprise/paypal-return?from=stays',
      );
      expect(
        withOrigin.cancelUrl,
        'https://enterprise-omega-five.vercel.app/#/enterprise/paypal-cancel?from=stays',
      );

      final withNonAllowlisted = plpPaypalReturnUrls(
        isWeb: true,
        base: Uri.parse('https://enterprise-omega-five.vercel.app/#/enterprise'),
        origin: 'unknown_origin',
      );
      expect(
        withNonAllowlisted.returnUrl,
        'https://enterprise-omega-five.vercel.app/#/enterprise/paypal-return',
      );

      final withoutOrigin = plpPaypalReturnUrls(
        isWeb: true,
        base: Uri.parse('https://enterprise-omega-five.vercel.app/#/enterprise'),
      );
      expect(
        withoutOrigin.returnUrl,
        'https://enterprise-omega-five.vercel.app/#/enterprise/paypal-return',
      );
    });

    test('analytics allowlist filters invalid origin, plan, and reason', () {
      // Allowlist verification
      expect(plpCheckoutOrigins.contains('stays'), isTrue);
      expect(plpCheckoutOrigins.contains('unknown'), isFalse);
    });
  });

  group('SPEC A Unpaid & Checkout journey', () {
    testWidgets('landing view renders value rows, recommended Launch, prices, terms',
        (tester) async {
      final events = <_RecordedEvent>[];
      await _pump(
        tester,
        () => {'subscription': null, 'plans': _plans},
        recordedEvents: events,
      );

      // Headline and subtitle
      expect(find.text('Run the whole resort from PLP'), findsOneWidget);
      expect(
        find.text('One subscription unlocks every workspace for your team.'),
        findsOneWidget,
      );
      expect(find.text('WHAT UNLOCKS'), findsOneWidget);

      // Value rows
      expect(find.text('Stays & Guests'), findsOneWidget);
      expect(find.text('Operations & Experiences'), findsOneWidget);
      expect(find.text('Revenue'), findsOneWidget);
      expect(find.text('Team & the PLP assistant'), findsOneWidget);
      expect(
        find.text('Free without a plan: Today, Rooms & Housekeeping, Activity.'),
        findsOneWidget,
      );

      // Plan cards
      expect(find.text('RECOMMENDED'), findsOneWidget);
      expect(find.text('Launch'), findsOneWidget);
      expect(find.text('Professional'), findsOneWidget);
      expect(find.text('USD 49'), findsOneWidget);
      expect(find.text('USD 149'), findsOneWidget);

      // Terms line
      expect(
        find.text(
            'Billed monthly by PayPal. Renews until you cancel — cancel anytime in Billing.'),
        findsOneWidget,
      );

      // Primary CTA
      expect(
        find.byKey(const ValueKey('plp-checkout-continue')),
        findsOneWidget,
      );
      expect(find.text('Continue with Launch · USD 49/mo'), findsOneWidget);

      // Paywall viewed event emitted once
      expect(events.map((e) => e.event), [OwnerAnalyticsEvent.paywallViewed]);
    });

    testWidgets(
        'landing CTA renders above launcher zone at 390x844 without scrolling',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
      tester.view.viewPadding =
          const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);

      await _pump(
        tester,
        () => {'subscription': null, 'plans': _plans},
        applyDefaultSurface: false,
      );

      final continueButton =
          find.byKey(const ValueKey('plp-checkout-continue'));
      expect(continueButton, findsOneWidget);

      final buttonBottom = tester.getBottomLeft(continueButton).dy;
      expect(buttonBottom, lessThanOrEqualTo(844 - 34 - 58 - 16));

      final scrollable =
          tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scrollable.position.pixels, 0.0);
    });

    testWidgets('origin moves matching value row first and sets headline',
        (tester) async {
      await _pump(
        tester,
        () => {'subscription': null, 'plans': _plans},
        origin: 'revenue',
        originLabel: 'Revenue',
      );

      expect(find.text('Revenue is part of PLP Enterprise'), findsOneWidget);

      // Revenue value row is moved first
      final revenueFinder = find.text('Revenue');
      final staysFinder = find.text('Stays & Guests');
      expect(tester.getTopLeft(revenueFinder).dy,
          lessThan(tester.getTopLeft(staysFinder).dy));
    });

    testWidgets('tapping a plan card selects it and emits plan_select without navigating',
        (tester) async {
      final events = <_RecordedEvent>[];
      await _pump(
        tester,
        () => {'subscription': null, 'plans': _plans},
        origin: 'stays',
        recordedEvents: events,
      );

      await tester.tap(find.byKey(const ValueKey('plp-plan-professional')));
      await tester.pumpAndSettle();

      // CTA updates to Professional
      expect(find.text('Continue with Professional · USD 149/mo'), findsOneWidget);
      expect(
        events.any((e) =>
            e.event == OwnerAnalyticsEvent.planSelected &&
            e.plan == 'professional' &&
            e.origin == 'stays'),
        isTrue,
      );
    });

    testWidgets('provider unavailable disables continue CTA with notice and Retry tile',
        (tester) async {
      await _pump(
        tester,
        () => {
          'subscription': null,
          'plans': _plans,
          'provider': {'configured': false},
        },
      );

      expect(
        find.text('PayPal is unavailable right now. Nothing was charged.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);

      // CTA is disabled
      final continueCta = find.byKey(const ValueKey('plp-checkout-continue'));
      expect(continueCta, findsOneWidget);
      await tester.tap(continueCta);
      await tester.pumpAndSettle();
      // Still on landing
      expect(find.text('Run the whole resort from PLP'), findsOneWidget);
    });

    testWidgets('continue navigates to Review view with 3 steps and terms box',
        (tester) async {
      final events = <_RecordedEvent>[];
      await _pump(
        tester,
        () => {'subscription': null, 'plans': _plans},
        origin: 'stays',
        originLabel: 'Stays',
        recordedEvents: events,
      );

      await tester.tap(find.byKey(const ValueKey('plp-checkout-continue')));
      await tester.pumpAndSettle();

      expect(find.text('REVIEW'), findsOneWidget);
      expect(find.text('USD 49 per month'), findsOneWidget);
      expect(find.text('PayPal opens so you can approve the subscription.'),
          findsOneWidget);
      expect(find.text('Come back here — PLP checks with PayPal.'), findsOneWidget);
      expect(
        find.text(
            'Everything unlocks once PayPal confirms, then we take you back to Stays.'),
        findsOneWidget,
      );
      expect(find.text('USD 49 every month until you cancel.'), findsOneWidget);
      expect(
        find.text(
            'Cancel anytime in Billing — no further charges. Access ends when the cancellation is confirmed.'),
        findsOneWidget,
      );
      expect(find.text('Charges and receipts come from PayPal.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('plp-checkout-paypal')),
        findsOneWidget,
      );

      expect(
        events.any((e) =>
            e.event == OwnerAnalyticsEvent.checkoutStarted &&
            e.plan == 'launch' &&
            e.origin == 'stays'),
        isTrue,
      );
    });

    testWidgets('Continue to PayPal calls checkout with returnUrls and emits handoff',
        (tester) async {
      final events = <_RecordedEvent>[];
      final fake = await _pump(
        tester,
        () => {'subscription': null, 'plans': _plans},
        origin: 'stays',
        originLabel: 'Stays',
        recordedEvents: events,
      );

      await tester.tap(find.byKey(const ValueKey('plp-checkout-continue')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('plp-checkout-paypal')));
      await tester.pumpAndSettle();

      final body = fake.bodies['/billing/paypal/checkout']!;
      expect(body['planCode'], 'launch');
      expect((body['idempotencyKey'] ?? '').toString().isNotEmpty, isTrue);
      expect((body['returnUrl'] ?? '').toString(),
          contains('paypal-return?from=stays'));
      expect((body['cancelUrl'] ?? '').toString(),
          contains('paypal-cancel?from=stays'));

      expect(fake.opened.single.host, 'www.paypal.com');
      expect(
        events.any((e) =>
            e.event == OwnerAnalyticsEvent.paypalHandoff &&
            e.plan == 'launch' &&
            e.origin == 'stays'),
        isTrue,
      );

      // Now on HANDED OFF
      expect(
        find.text('Approve in PayPal, then come back here.'),
        findsOneWidget,
      );
    });

    testWidgets('retry after failure reuses the same idempotency key',
        (tester) async {
      var fail = true;
      final fake = await _pump(
        tester,
        () => {'subscription': null, 'plans': _plans},
      );
      fake.customFail =
          (path) => fail && path.endsWith('/checkout') ? Exception('500') : null;

      await tester.tap(find.byKey(const ValueKey('plp-checkout-continue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plp-checkout-paypal')));
      await tester.pumpAndSettle();

      expect(find.text('Checkout couldn’t start. Nothing was charged.'),
          findsOneWidget);
      final key1 = fake.bodies['/billing/paypal/checkout']!['idempotencyKey'];

      fail = false;
      await _tap(tester, 'try-again');
      expect(find.text('Approve in PayPal, then come back here.'),
          findsOneWidget);
      final key2 = fake.bodies['/billing/paypal/checkout']!['idempotencyKey'];
      expect(key2, key1);
    });

    testWidgets('existing approval is resumed without a second POST',
        (tester) async {
      final fake = await _pump(
        tester,
        () => {
          'subscription': null,
          'plans': _plans,
          'checkout': {
            'plan_code': 'launch',
            'status': 'approval_pending',
            'approval_url': 'https://www.paypal.com/approve?ba_token=EXISTING',
          },
        },
      );

      expect(
        find.text(
            'You started checkout for Launch. Finish in PayPal or choose again.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Finish in PayPal'));
      await tester.pumpAndSettle();

      expect(fake.opened.single.queryParameters['ba_token'], 'EXISTING');
      expect(fake.calls.where((c) => c.contains('POST /billing/paypal/checkout')),
          isEmpty);
    });

    testWidgets('checkout failure mapping for 503, AAL2, open error, and network',
        (tester) async {
      final events = <_RecordedEvent>[];
      final fake = await _pump(
        tester,
        () => {'subscription': null, 'plans': _plans},
        recordedEvents: events,
      );

      // Test 503
      fake.customFail = (_) => const PlpBillingRequestException(
            statusCode: 503,
            code: 'SERVICE_UNAVAILABLE',
            message: 'down',
          );
      await tester.tap(find.byKey(const ValueKey('plp-checkout-continue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plp-checkout-paypal')));
      await tester.pumpAndSettle();

      expect(
        find.text('PayPal is unavailable right now. Nothing was charged.'),
        findsOneWidget,
      );
      expect(events.last.reason, 'paypal_unavailable');
    });

    testWidgets('checkout failure mapping for 502 PAYPAL_CHECKOUT_FAILED',
        (tester) async {
      final events = <_RecordedEvent>[];
      final fake = await _pump(
        tester,
        () => {'subscription': null, 'plans': _plans},
        recordedEvents: events,
      );

      fake.customFail = (_) => const PlpBillingRequestException(
            statusCode: 502,
            code: 'PAYPAL_CHECKOUT_FAILED',
            message: 'PayPal checkout failed',
          );
      await tester.tap(find.byKey(const ValueKey('plp-checkout-continue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plp-checkout-paypal')));
      await tester.pumpAndSettle();

      expect(
        find.text('PayPal didn’t start checkout. Nothing was charged.'),
        findsOneWidget,
      );
      expect(events.last.reason, 'paypal_unavailable');
    });

    testWidgets('checkout failure mapping for 500 with empty code',
        (tester) async {
      final events = <_RecordedEvent>[];
      final fake = await _pump(
        tester,
        () => {'subscription': null, 'plans': _plans},
        recordedEvents: events,
      );

      fake.customFail = (_) => const PlpBillingRequestException(
            statusCode: 500,
            code: '',
            message: 'Internal error',
          );
      await tester.tap(find.byKey(const ValueKey('plp-checkout-continue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plp-checkout-paypal')));
      await tester.pumpAndSettle();

      expect(
        find.text('Checkout couldn’t start. Nothing was charged.'),
        findsOneWidget,
      );
      expect(events.last.reason, 'server_error');
    });

    testWidgets('checkout failure mapping for 429',
        (tester) async {
      final events = <_RecordedEvent>[];
      final fake = await _pump(
        tester,
        () => {'subscription': null, 'plans': _plans},
        recordedEvents: events,
      );

      fake.customFail = (_) => const PlpBillingRequestException(
            statusCode: 429,
            code: 'RATE_LIMITED',
            message: 'Too many requests',
          );
      await tester.tap(find.byKey(const ValueKey('plp-checkout-continue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plp-checkout-paypal')));
      await tester.pumpAndSettle();

      expect(
        find.text('Too many attempts. Wait a moment, then try again.'),
        findsOneWidget,
      );
      expect(events.last.reason, 'server_error');
    });

    testWidgets('checkout failure mapping for TimeoutException',
        (tester) async {
      final events = <_RecordedEvent>[];
      final fake = await _pump(
        tester,
        () => {'subscription': null, 'plans': _plans},
        recordedEvents: events,
      );

      fake.customFail = (_) => TimeoutException('Connection timed out');
      await tester.tap(find.byKey(const ValueKey('plp-checkout-continue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plp-checkout-paypal')));
      await tester.pumpAndSettle();

      expect(
        find.text('No connection to PLP. Nothing was charged.'),
        findsOneWidget,
      );
      expect(events.last.reason, 'network');
    });

    testWidgets('confirming succeeds only when active and verified',
        (tester) async {
      const state = 'active';
      await _pump(
        tester,
        () => {
          'subscription': {
            'plan_code': 'launch',
            'state': state,
            'currency': 'USD',
            'monthly_fee_micros': 49000000,
          },
          'plans': _plans,
        },
        paypalReturn: const PlpCheckoutReturn(cancelled: false, origin: 'stays'),
        confirmPollAttempts: 2,
      );

      // Unverified active subscription does NOT succeed -> pending
      expect(find.text('PayPal hasn’t confirmed yet.'), findsOneWidget);
    });

    testWidgets('paypalReturn success starts in confirming view and reaches success',
        (tester) async {
      final events = <_RecordedEvent>[];
      var activatedCount = 0;
      await _pump(
        tester,
        () => _active(verified: true),
        origin: 'stays',
        originLabel: 'Stays',
        paypalReturn: const PlpCheckoutReturn(cancelled: false, origin: 'stays'),
        recordedEvents: events,
        onActivated: () => activatedCount++,
      );

      expect(find.text('PLP Enterprise is unlocked'), findsOneWidget);
      expect(find.text('Verified with PayPal.'), findsOneWidget);
      expect(find.text('Open Stays'), findsOneWidget);

      expect(
        events.where((e) => e.event == OwnerAnalyticsEvent.activationVerified).length,
        1,
      );

      // Tap CTA triggers onActivated
      await tester.tap(find.byKey(const ValueKey('plp-checkout-done')));
      await tester.pumpAndSettle();
      expect(activatedCount, 1);

      // Timer expiration will not call onActivated a second time
      await tester.pump(const Duration(milliseconds: 100));
      expect(activatedCount, 1);
    });

    testWidgets('paypalReturn cancelled shows cancelled notice and emits abandon',
        (tester) async {
      final events = <_RecordedEvent>[];
      await _pump(
        tester,
        () => {'subscription': null, 'plans': _plans},
        origin: 'stays',
        paypalReturn: const PlpCheckoutReturn(cancelled: true, origin: 'stays'),
        recordedEvents: events,
      );

      expect(
        find.text('You left PayPal before approving. Nothing was charged.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(
        events.any((e) =>
            e.event == OwnerAnalyticsEvent.checkoutAbandoned &&
            e.reason == 'paypal_cancel'),
        isTrue,
      );
    });

    testWidgets('initialStatus renders without loading state', (tester) async {
      await _pump(
        tester,
        () => {'subscription': null, 'plans': _plans},
        initialStatus: {'subscription': null, 'plans': _plans},
      );

      expect(find.text('Loading…'), findsNothing);
      expect(find.text('Couldn’t load billing.'), findsNothing);
      expect(find.text('Run the whole resort from PLP'), findsOneWidget);
    });

    testWidgets('persistent load failure shows Couldn’t load billing and Retry',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PlpPaypalBillingScreen(
          organizationId: 'org-1',
          onOpenNavigation: () {},
          transport: (path, {method = 'GET', body}) async =>
              throw Exception('BILLING_REQUEST_FAILED'),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Couldn’t load billing.'), findsOneWidget);
      expect(find.byKey(const ValueKey('plp-capability-retry')), findsOneWidget);
    });

    testWidgets('app resume in HANDED OFF triggers confirming', (tester) async {
      await _pump(
        tester,
        () => {'subscription': null, 'plans': _plans},
      );

      await tester.tap(find.byKey(const ValueKey('plp-checkout-continue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plp-checkout-paypal')));
      await tester.pumpAndSettle();

      expect(find.text('Approve in PayPal, then come back here.'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.text('Confirming with PayPal…'), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  group('Active subscription management', () {
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
        'change plan confirm names the change; plan shown only from reconciled status',
        (tester) async {
      final fake = await _pump(tester, _active);
      await _tap(tester, 'change-plan');
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Launch to Professional · USD 149 / month from Nov 8'),
          findsOneWidget);
      await _tap(tester, 'switch-to-professional');
      expect(
        fake.calls,
        contains('POST /billing/paypal/change-plan professional'),
      );
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
      expect(
        find.byKey(const ValueKey('plp-capability-change-plan')),
        findsOneWidget,
      );
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
        ]),
      );
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

    testWidgets('unknown renewal is never guessed', (tester) async {
      await _pump(tester, () {
        final status = _active();
        (status['subscription'] as Map).remove('renews_on');
        return status;
      });
      expect(find.text('Launch · USD 49 / month'), findsOneWidget);
      await _tap(tester, 'change-plan');
      expect(
        find.text('Launch to Professional · USD 149 / month'),
        findsOneWidget,
      );
    });

    testWidgets('cancelled without an end date still says Cancelled',
        (tester) async {
      await _pump(
        tester,
        () => {
          'subscription': {'plan_code': 'launch', 'state': 'cancelled'},
          'plans': _plans,
          'provider': {'configured': false},
        },
      );
      expect(find.text('Cancelled'), findsOneWidget);
    });
  });
}
