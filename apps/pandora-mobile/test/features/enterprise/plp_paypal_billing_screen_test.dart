import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pandora_mobile/core/data/plp_paypal_billing_api.dart';
import 'package:pandora_mobile/core/network/session_token_provider.dart';
import 'package:pandora_mobile/features/enterprise/plp_paypal_billing_screen.dart';

import '../../helpers/test_app.dart';

class _Token implements SessionTokenProvider {
  const _Token();
  @override
  Future<String?> accessToken() async => 'session-token';
}

const _org = '11111111-2222-3333-4444-555555555555';

// Deliberately not 49/149 so the test proves prices come from the backend.
const _plans = [
  {
    'code': 'launch',
    'name': 'Launch',
    'currency': 'USD',
    'monthlyAmount': '51.00',
    'interval': 'month'
  },
  {
    'code': 'professional',
    'name': 'Professional',
    'currency': 'USD',
    'monthlyAmount': '151.00',
    'interval': 'month'
  },
];

Map<String, Object?> _status({
  Map<String, Object?>? subscription,
  Map<String, Object?>? checkout,
  Map<String, Object?>? planChange,
  String environment = 'live',
}) =>
    {
      'environment': environment,
      'plans': _plans,
      'subscription': subscription,
      'checkout': checkout,
      'planChange': planChange,
    };

const _active = <String, Object?>{
  'plan_id': 'p1',
  'plan_code': 'launch',
  'state': 'active',
  'currency': 'USD',
  'renews_on': '2026-11-08',
  'source_kind': 'provider_verified',
  'provider_reference': 'I-ABCDEF123456',
  'verified_at': '2026-10-08T14:00:00Z',
};

class _Backend {
  _Backend(this.handlers);
  final Map<String, List<http.Response> Function()> handlers;
  final calls = <http.Request>[];
  final _cursor = <String, int>{};

  MockClient get client => MockClient((request) async {
        calls.add(request);
        final key =
            '${request.method} ${request.url.path.split('/pandora-owner-api').last}';
        final responses = handlers[key]?.call();
        if (responses == null) return http.Response('{}', 404);
        final index = _cursor[key] ?? 0;
        _cursor[key] = index + 1;
        return responses[
            index < responses.length ? index : responses.length - 1];
      });

  List<String> get paths => calls
      .map((c) => '${c.method} ${c.url.path.split('/pandora-owner-api').last}')
      .toList();
}

http.Response _json(Object? body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Future<List<Uri>> _mount(
  WidgetTester tester,
  _Backend backend, {
  String? organizationId = _org,
  bool launchSucceeds = true,
  String environment = 'live',
}) async {
  await setTestSurface(tester, logicalSize: const Size(430, 2200));
  final launched = <Uri>[];
  await tester.pumpWidget(testApp(
    child: PlpPaypalBillingScreen(
      organizationId: organizationId,
      onOpenNavigation: () {},
      api: organizationId == null
          ? null
          : PlpPaypalBillingApi.forOrganization(
              organizationId,
              tokenProvider: const _Token(),
              httpClient: backend.client,
              environment: environment,
            ),
      launchApproval: (uri) async {
        launched.add(uri);
        return launchSucceeds;
      },
      clock: () => DateTime.utc(2026, 10, 8, 14, 5),
    ),
  ));
  await tester.pumpAndSettle();
  return launched;
}

void main() {
  testWidgets(
      'renders backend plans and inactive state without inventing a subscription',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [_json(_status())]
    });
    await _mount(tester, backend);
    expect(find.text('Pandora billing.'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);
    expect(find.text('no subscription on record'), findsOneWidget);
    expect(find.text('Launch'), findsOneWidget);
    expect(find.textContaining('USD 51 / month'), findsOneWidget);
    expect(find.textContaining('USD 151 / month'), findsOneWidget);
    expect(find.textContaining('USD 49'), findsNothing);
    expect(find.text('No subscription record'), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-billing-handoff')), findsNothing);
    expect(find.byKey(const ValueKey('plp-billing-cancel')), findsNothing);
    final status = backend.calls.single;
    expect(status.headers['Authorization'], 'Bearer session-token');
    expect(status.headers['X-Organization-Id'], _org);
    expect(status.headers['apikey'], isNotEmpty);
    expect(
        status.headers.containsKey('x-pandora-billing-environment'), isFalse);
  });

  testWidgets(
      'select plan, checkout with idempotency key, open PayPal approval',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [
            _json(_status()),
            _json(_status(checkout: {
              'status': 'approval_pending',
              'plan_code': 'launch',
              'approval_url':
                  'https://www.paypal.com/webapps/billing/subscriptions?ba_token=BA-1',
              'expires_at': '2026-10-08T14:30:00Z',
            })),
          ],
      'POST /billing/paypal/checkout': () => [
            _json({
              'approvalUrl':
                  'https://www.paypal.com/webapps/billing/subscriptions?ba_token=BA-1',
              'status': 'approval_pending'
            }),
          ],
    });
    final launched = await _mount(tester, backend);
    await tester.tap(find.text('Launch'));
    await tester.pumpAndSettle();
    expect(find.text('CONTINUE TO PAYPAL'), findsOneWidget);
    await tester.tap(find.text('CONTINUE TO PAYPAL'));
    await tester.pumpAndSettle();
    final checkout =
        backend.calls.firstWhere((c) => c.url.path.endsWith('/checkout'));
    final body = jsonDecode(checkout.body) as Map<String, dynamic>;
    expect(body['planCode'], 'launch');
    expect(body['idempotencyKey'], startsWith('plp-checkout-'));
    expect(Uri.parse(body['returnUrl'] as String).scheme, 'https');
    expect(Uri.parse(body['cancelUrl'] as String).scheme, 'https');
    expect(launched.single.host, 'www.paypal.com');
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('PayPal approval is waiting.'), findsOneWidget);
    expect(find.text('Active'), findsNothing);
  });

  testWidgets(
      'active provider-verified subscription, cancel dialog can be dismissed',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () =>
          [_json(_status(subscription: _active))]
    });
    await _mount(tester, backend);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('2026-11-08'), findsOneWidget);
    expect(find.text('Verified by PayPal'), findsOneWidget);
    expect(find.text('Switch to Professional'), findsOneWidget);
    expect(find.text('Choose a plan'), findsNothing);
    await tester.tap(find.text('Cancel subscription'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plp-billing-cancel-dialog')),
        findsOneWidget);
    expect(
        find.textContaining('send the cancellation to PayPal'), findsOneWidget);
    await tester.tap(find.text('Keep subscription'));
    await tester.pumpAndSettle();
    expect(backend.paths.where((p) => p.startsWith('POST')), isEmpty);
  });

  testWidgets(
      'confirmed cancel runs cancel, reconcile, status and shows cancelled only when confirmed',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [
            _json(_status(subscription: _active)),
            _json(_status(subscription: {
              ..._active,
              'state': 'cancelled',
              'ends_on': '2026-10-08',
              'renews_on': null
            })),
          ],
      'POST /billing/paypal/cancel': () => [
            _json({'status': 'cancel_requested'})
          ],
      'POST /billing/paypal/reconcile': () => [
            _json({'verified': true, 'state': 'cancelled'})
          ],
    });
    await _mount(tester, backend);
    await tester.tap(find.text('Cancel subscription'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send cancellation to PayPal'));
    await tester.pumpAndSettle();
    expect(backend.paths, [
      'GET /billing/paypal/status',
      'POST /billing/paypal/cancel',
      'POST /billing/paypal/reconcile',
      'GET /billing/paypal/status',
    ]);
    expect(find.text('Cancelled'), findsOneWidget);
  });

  testWidgets(
      'cancel that PayPal has not confirmed stays active with cancellation pending',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [
            _json(_status(subscription: _active)),
            _json(_status(subscription: _active, checkout: {
              'status': 'cancel_requested',
              'plan_code': 'launch'
            })),
          ],
      'POST /billing/paypal/cancel': () => [
            _json({'status': 'cancel_requested'})
          ],
      'POST /billing/paypal/reconcile': () => [
            _json({'verified': true, 'state': 'active'})
          ],
    });
    await _mount(tester, backend);
    await tester.tap(find.text('Cancel subscription'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send cancellation to PayPal'));
    await tester.pumpAndSettle();
    expect(find.text('Cancelled'), findsNothing);
    expect(find.text('cancellation pending'), findsOneWidget);
    expect(find.text('Cancellation sent'), findsOneWidget);
  });

  testWidgets(
      'change plan posts plan-change key, opens approval, never claims the change',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () =>
          [_json(_status(subscription: _active))],
      'POST /billing/paypal/change-plan': () => [
            _json({
              'approvalUrl':
                  'https://www.sandbox.paypal.com/webapps/billing/subscriptions/update?ba_token=BA-2',
              'status': 'approval_pending'
            }),
          ],
    });
    final launched = await _mount(tester, backend);
    await tester.tap(find.text('Switch to Professional'));
    await tester.pumpAndSettle();
    final change =
        backend.calls.firstWhere((c) => c.url.path.endsWith('/change-plan'));
    final body = jsonDecode(change.body) as Map<String, dynamic>;
    expect(body['planCode'], 'professional');
    expect(body['idempotencyKey'], startsWith('plp-plan-change-'));
    expect(Uri.parse(body['returnUrl'] as String).scheme, 'https');
    expect(launched.single.host, 'www.sandbox.paypal.com');
    expect(find.text('Launch'), findsOneWidget);
  });

  testWidgets('refresh payment state runs reconcile then status',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () =>
          [_json(_status(subscription: _active))],
      'POST /billing/paypal/reconcile': () => [
            _json({'verified': true})
          ],
    });
    await _mount(tester, backend);
    await tester.tap(find.text('Refresh payment state'));
    await tester.pumpAndSettle();
    expect(backend.paths.skip(1).toList(),
        ['POST /billing/paypal/reconcile', 'GET /billing/paypal/status']);
  });

  testWidgets('pending approval panel reopens the existing link',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [
            _json(_status(checkout: {
              'status': 'approval_pending',
              'plan_code': 'professional',
              'approval_url':
                  'https://www.paypal.com/webapps/billing/subscriptions?ba_token=BA-9',
              'expires_at': '2026-10-08T14:20:00Z',
            })),
          ],
    });
    final launched = await _mount(tester, backend);
    expect(find.text('Payment handoff'.toUpperCase()), findsOneWidget);
    await tester.tap(find.text('OPEN PAYPAL APPROVAL'));
    await tester.pumpAndSettle();
    expect(launched.single.queryParameters['ba_token'], 'BA-9');
    expect(backend.paths.where((p) => p.startsWith('POST')), isEmpty);
  });

  testWidgets('expired or untrusted approval links are not offered',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [
            _json(_status(checkout: {
              'status': 'approval_pending',
              'approval_url': 'https://evil.example/paypal.com',
              'expires_at': '2026-10-08T15:00:00Z',
            })),
          ],
    });
    await _mount(tester, backend);
    expect(find.byKey(const ValueKey('plp-billing-handoff')), findsNothing);
  });

  group('errors render inside the PLP page', () {
    Future<void> expectProblem(
        WidgetTester tester, http.Response status, String text) async {
      final backend = _Backend({
        'GET /billing/paypal/status': () => [status]
      });
      await _mount(tester, backend);
      expect(find.byKey(const ValueKey('plp-billing-problem')), findsOneWidget);
      expect(find.textContaining(text), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
    }

    testWidgets(
        'unauthenticated',
        (tester) => expectProblem(
            tester,
            _json({
              'code': 'SIGN_IN_REQUIRED',
              'plainMessage': 'Please sign in again.'
            }, 401),
            'session has expired'));
    testWidgets(
        'no org access',
        (tester) => expectProblem(
            tester,
            _json({'code': 'ORGANIZATION_ACCESS_REQUIRED', 'plainMessage': 'x'},
                403),
            'Only owners and admins'));
    testWidgets(
        'PayPal OAuth failure',
        (tester) => expectProblem(
            tester,
            _json({'code': 'PAYPAL_AUTH_FAILED', 'plainMessage': 'x'}, 503),
            'could not authenticate with PayPal'));
    testWidgets(
        'malformed response',
        (tester) => expectProblem(
            tester, http.Response('{"plans":"nope"}', 200), 'cannot read'));
    testWidgets(
        'non-json response',
        (tester) =>
            expectProblem(tester, http.Response('<html>', 200), 'cannot read'));

    testWidgets('missing organization sends no request', (tester) async {
      final backend = _Backend({});
      await _mount(tester, backend, organizationId: null);
      expect(find.textContaining('no organization selected'), findsOneWidget);
      expect(backend.calls, isEmpty);
    });

    testWidgets('approval URL missing', (tester) async {
      final backend = _Backend({
        'GET /billing/paypal/status': () => [_json(_status())],
        'POST /billing/paypal/checkout': () => [
              _json({'status': 'approval_pending'})
            ],
      });
      final launched = await _mount(tester, backend);
      await tester.tap(find.text('Professional'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONTINUE TO PAYPAL'));
      await tester.pumpAndSettle();
      expect(launched, isEmpty);
      expect(find.textContaining('did not return an approval link'),
          findsOneWidget);
    });

    testWidgets('launch failure', (tester) async {
      final backend = _Backend({
        'GET /billing/paypal/status': () => [_json(_status())],
        'POST /billing/paypal/checkout': () => [
              _json({
                'approvalUrl': 'https://www.paypal.com/x',
                'status': 'approval_pending'
              })
            ],
      });
      await _mount(tester, backend, launchSucceeds: false);
      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONTINUE TO PAYPAL'));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not open PayPal'), findsOneWidget);
    });

    testWidgets('checkout failure from PayPal', (tester) async {
      final backend = _Backend({
        'GET /billing/paypal/status': () => [_json(_status())],
        'POST /billing/paypal/checkout': () => [
              _json({
                'code': 'PAYPAL_SUBSCRIPTION_CREATE_FAILED',
                'plainMessage': 'x'
              }, 502)
            ],
      });
      await _mount(tester, backend);
      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONTINUE TO PAYPAL'));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not start checkout'), findsOneWidget);
      expect(backend.paths.last, 'GET /billing/paypal/status');
    });

    testWidgets('reconcile with nothing linked', (tester) async {
      final backend = _Backend({
        'GET /billing/paypal/status': () => [_json(_status())],
        'POST /billing/paypal/reconcile': () => [
              _json(
                  {'code': 'SUBSCRIPTION_NOT_FOUND', 'plainMessage': 'x'}, 409)
            ],
      });
      await _mount(tester, backend);
      await tester.tap(find.text('Refresh payment state'));
      await tester.pumpAndSettle();
      expect(find.text('No PayPal subscription yet.'), findsOneWidget);
      expect(backend.paths.last, 'GET /billing/paypal/status');
    });

    testWidgets('extra identity check offers verification', (tester) async {
      final backend = _Backend({
        'GET /billing/paypal/status': () => [_json(_status())],
        'POST /billing/paypal/checkout': () => [
              _json({'code': 'AAL2_REQUIRED', 'plainMessage': 'x'}, 403)
            ],
      });
      await _mount(tester, backend);
      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONTINUE TO PAYPAL'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm it is you.'), findsOneWidget);
      expect(find.text('VERIFY IDENTITY'), findsOneWidget);
    });
  });

  testWidgets('sandbox environment is labelled and sent explicitly',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () =>
          [_json(_status(environment: 'sandbox', subscription: _active))],
    });
    await _mount(tester, backend, environment: 'sandbox');
    expect(find.text('PayPal sandbox'), findsOneWidget);
    expect(find.text('Verified by PayPal sandbox'), findsOneWidget);
    expect(backend.calls.single.headers['x-pandora-billing-environment'],
        'sandbox');
  });

  test('idempotency keys are unique and server-valid', () {
    final a = PlpPaypalBillingApi.idempotencyKey('plp-checkout');
    final b = PlpPaypalBillingApi.idempotencyKey('plp-checkout');
    expect(a, isNot(b));
    expect(RegExp(r'^[A-Za-z0-9._:-]{8,128}$').hasMatch(a), isTrue);
  });
}
