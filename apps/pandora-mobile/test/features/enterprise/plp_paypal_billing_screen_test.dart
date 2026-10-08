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
  'starts_on': '2026-06-08',
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
  VoidCallback? onBack,
  double height = 2200,
}) async {
  await setTestSurface(tester, logicalSize: Size(430, height));
  final launched = <Uri>[];
  await tester.pumpWidget(testApp(
    child: PlpPaypalBillingScreen(
      organizationId: organizationId,
      onOpenNavigation: () {},
      onBack: onBack,
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

Finder _rich(String text) => find.text(text, findRichText: true);

Map<String, Object?> _pendingCheckout([String plan = 'launch']) => {
      'status': 'approval_pending',
      'plan_code': plan,
      'approval_url':
          'https://www.paypal.com/webapps/billing/subscriptions?ba_token=BA-9',
      'expires_at': '2026-10-08T15:20:00Z',
    };

Future<void> _openPlan(WidgetTester tester, String code) async {
  await tester.tap(find.byKey(ValueKey('plp-billing-plan-$code')));
  await tester.pumpAndSettle();
}

Future<void> _openHandoff(WidgetTester tester) async {
  await tester.tap(
      find.textContaining('starts after PayPal approval', findRichText: true));
  await tester.pumpAndSettle();
}

int _count(_Backend backend, String path) =>
    backend.paths.where((p) => p == path).length;

void main() {
  testWidgets('inactive: two backend plans on the axis, no data columns',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [_json(_status())]
    });
    await _mount(tester, backend);
    expect(find.text('Pandora billing'), findsOneWidget);
    expect(_rich('Not subscribed'), findsOneWidget);
    expect(find.text('CHOOSE A PLAN'), findsOneWidget);
    expect(find.text('Launch'), findsOneWidget);
    expect(find.text('USD 51/mo'), findsOneWidget);
    expect(find.text('USD 151/mo'), findsOneWidget);
    expect(find.text('Billed monthly through PayPal.'), findsOneWidget);
    for (final column in ['Status', 'Plan', 'Renewal']) {
      expect(find.text(column), findsNothing);
    }
    expect(find.byKey(const ValueKey('plp-billing-hero-value')), findsNothing);
    expect(find.byKey(const ValueKey('plp-billing-playhead')), findsNothing);
    expect(find.byKey(const ValueKey('plp-billing-cancel')), findsNothing);
    expect(backend.paths, ['GET /billing/paypal/status']);
    final request = backend.calls.single;
    expect(request.headers['authorization'], 'Bearer session-token');
    expect(request.headers['x-organization-id'], _org);
    expect(
        request.headers.containsKey('x-pandora-billing-environment'), isFalse);
  });

  testWidgets('active: temporal hero, playhead and PayPal seal from backend',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () =>
          [_json(_status(subscription: _active))]
    });
    await _mount(tester, backend);
    expect(_rich('Active \u00b7 Launch \u00b7 USD 51/mo'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
    expect(find.text('days'), findsOneWidget);
    expect(_rich('renews 8 Nov 2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-billing-playhead')), findsOneWidget);
    expect(find.text('8 Oct'), findsOneWidget);
    expect(find.text('8 Nov'), findsOneWidget);
    // verified_at 14:00Z, clock 14:05Z: the backend's last PayPal check.
    expect(find.text('PayPal \u00b7 checked 5 min ago'), findsOneWidget);
    expect(find.text('PLAN'), findsOneWidget);
    expect(find.text('Cancel subscription'), findsOneWidget);
    expect(find.text('Refresh'), findsNothing);
    for (final column in ['Status', 'Renewal']) {
      expect(find.text(column), findsNothing);
    }
  });

  testWidgets('tapping the seal reconciles then reads status', (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [
            _json(_status(subscription: _active)),
            _json(_status(subscription: {
              ..._active,
              'verified_at': '2026-10-08T14:04:30Z'
            })),
          ],
      'POST /billing/paypal/reconcile': () => [
            _json({'verified': true})
          ],
    });
    await _mount(tester, backend);
    await tester.tap(find.byKey(const ValueKey('plp-billing-seal')));
    await tester.pumpAndSettle();
    expect(backend.paths.skip(1).toList(),
        ['POST /billing/paypal/reconcile', 'GET /billing/paypal/status']);
    expect(find.text('PayPal \u00b7 checked just now'), findsOneWidget);
  });

  testWidgets('plan axis shows the upgrade and downgrade difference line',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () =>
          [_json(_status(subscription: _active))]
    });
    await _mount(tester, backend);
    await _openPlan(tester, 'professional');
    expect(_rich('+ USD 100/mo \u00b7 starts after PayPal approval'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('plp-billing-cancel')), findsNothing);
    // Tapping the current plan again closes the preview.
    await _openPlan(tester, 'launch');
    expect(
        find.textContaining('starts after PayPal approval', findRichText: true),
        findsNothing);
    expect(backend.paths.where((p) => p.startsWith('POST')), isEmpty);
  });

  testWidgets('downgrade shows a minus difference', (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [
            _json(_status(
                subscription: {..._active, 'plan_code': 'professional'}))
          ]
    });
    await _mount(tester, backend);
    await _openPlan(tester, 'launch');
    expect(_rich('\u2212 USD 100/mo \u00b7 starts after PayPal approval'),
        findsOneWidget);
  });

  testWidgets(
      'handoff from active runs change-plan with its key and never claims the change',
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
    await _openPlan(tester, 'professional');
    await _openHandoff(tester);
    expect(find.byKey(const ValueKey('plp-billing-handoff')), findsOneWidget);
    expect(find.text('Professional'), findsNWidgets(2));
    expect(find.text('You\u2019ll approve this in PayPal.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plp-billing-continue')));
    await tester.pumpAndSettle();
    final change =
        backend.calls.firstWhere((c) => c.url.path.endsWith('/change-plan'));
    final body = jsonDecode(change.body) as Map<String, dynamic>;
    expect(body['planCode'], 'professional');
    expect(body['idempotencyKey'], startsWith('plp-plan-change-'));
    expect(Uri.parse(body['returnUrl'] as String).scheme, 'https');
    expect(Uri.parse(body['cancelUrl'] as String).scheme, 'https');
    expect(launched.single.host, 'www.sandbox.paypal.com');
    expect(find.byKey(const ValueKey('plp-billing-handoff')), findsNothing);
    expect(_rich('Active \u00b7 Launch \u00b7 USD 51/mo'), findsOneWidget);
  });

  testWidgets(
      'handoff from inactive runs checkout, then the workspace locks while PayPal waits',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [
            _json(_status()),
            _json(_status(checkout: _pendingCheckout())),
          ],
      'POST /billing/paypal/checkout': () => [
            _json({
              'approvalUrl':
                  'https://www.paypal.com/webapps/billing/subscriptions?ba_token=BA-1',
              'status': 'approval_pending'
            })
          ],
    });
    final launched = await _mount(tester, backend);
    await _openPlan(tester, 'launch');
    expect(
        _rich('USD 51/mo \u00b7 starts after PayPal approval'), findsOneWidget);
    await _openHandoff(tester);
    await tester.tap(find.byKey(const ValueKey('plp-billing-continue')));
    await tester.pumpAndSettle();
    final checkout =
        backend.calls.firstWhere((c) => c.url.path.endsWith('/checkout'));
    final body = jsonDecode(checkout.body) as Map<String, dynamic>;
    expect(body['planCode'], 'launch');
    expect(body['idempotencyKey'], startsWith('plp-checkout-'));
    expect(Uri.parse(body['returnUrl'] as String).scheme, 'https');
    expect(Uri.parse(body['cancelUrl'] as String).scheme, 'https');
    expect(launched.single.host, 'www.paypal.com');
    expect(find.byKey(const ValueKey('plp-billing-waiting')), findsOneWidget);
    expect(find.text('Waiting for PayPal'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('plp-billing-node-pending')), findsOneWidget);
    expect(_rich('Active'), findsNothing);
  });

  testWidgets('Not now lowers the handoff panel without any call',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [_json(_status())]
    });
    await _mount(tester, backend);
    await _openPlan(tester, 'professional');
    await _openHandoff(tester);
    await tester.tap(find.byKey(const ValueKey('plp-billing-not-now')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plp-billing-handoff')), findsNothing);
    expect(backend.paths.where((p) => p.startsWith('POST')), isEmpty);
  });

  testWidgets(
      'pending lock: workspace inert, Open PayPal reopens, Check again reconciles',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [
            _json(_status(checkout: _pendingCheckout('professional'))),
          ],
      'POST /billing/paypal/reconcile': () => [
            _json({'verified': false})
          ],
    });
    final launched = await _mount(tester, backend);
    expect(find.byKey(const ValueKey('plp-billing-waiting')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('plp-billing-node-pending')), findsOneWidget);
    // The dimmed workspace ignores taps.
    await tester.tap(find.byKey(const ValueKey('plp-billing-plan-launch')),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
        find.textContaining('starts after PayPal approval', findRichText: true),
        findsNothing);
    await tester.tap(find.byKey(const ValueKey('plp-billing-open-paypal')));
    await tester.pumpAndSettle();
    expect(launched.single.queryParameters['ba_token'], 'BA-9');
    expect(backend.paths.where((p) => p.startsWith('POST')), isEmpty);
    await tester.tap(find.byKey(const ValueKey('plp-billing-check-again')));
    await tester.pumpAndSettle();
    expect(backend.paths.skip(1).toList(),
        ['POST /billing/paypal/reconcile', 'GET /billing/paypal/status']);
  });

  testWidgets('pending plan change locks with a dashed ring on the target',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [
            _json(_status(subscription: _active, planChange: {
              'status': 'approval_pending',
              'to_plan_code': 'professional',
              'approval_url':
                  'https://www.sandbox.paypal.com/webapps/billing/subscriptions/update?ba_token=BA-2',
            })),
          ],
    });
    await _mount(tester, backend);
    expect(find.text('Waiting for PayPal'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('plp-billing-node-pending')), findsOneWidget);
    expect(_rich('Active \u00b7 Launch \u00b7 USD 51/mo'), findsOneWidget);
  });

  testWidgets('expired or untrusted approval links do not lock the workspace',
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
    expect(find.byKey(const ValueKey('plp-billing-waiting')), findsNothing);
  });

  group('hold to cancel', () {
    _Backend cancelBackend() => _Backend({
          'GET /billing/paypal/status': () => [
                _json(_status(subscription: _active)),
                _json(_status(subscription: {
                  ..._active,
                  'state': 'cancelled',
                  'ends_on': '2026-11-08',
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

    Future<void> openPanel(WidgetTester tester) async {
      await tester.tap(find.text('Cancel subscription'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plp-billing-cancel-panel')),
          findsOneWidget);
      expect(find.text('Access continues until 8 Nov 2026.'), findsOneWidget);
      expect(find.text('HOLD TO CANCEL'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    }

    testWidgets('releasing early makes no call', (tester) async {
      final backend = cancelBackend();
      await _mount(tester, backend);
      await openPanel(tester);
      final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('plp-billing-hold'))));
      await tester.pump();
      // Reduced motion is on in testApp; the hold must still take ~1.5 s.
      await tester.pump(const Duration(milliseconds: 1400));
      expect(_count(backend, 'POST /billing/paypal/cancel'), 0);
      await gesture.up();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(_count(backend, 'POST /billing/paypal/cancel'), 0);
      expect(find.text('HOLD TO CANCEL'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('plp-billing-keep')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('plp-billing-cancel-panel')), findsNothing);
      expect(backend.paths.where((p) => p.startsWith('POST')), isEmpty);
    });

    testWidgets(
        'completing the hold sends exactly one cancel, then reconcile + status',
        (tester) async {
      final backend = cancelBackend();
      await _mount(tester, backend);
      await openPanel(tester);
      final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('plp-billing-hold'))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_count(backend, 'POST /billing/paypal/cancel'), 1);
      expect(backend.paths, [
        'GET /billing/paypal/status',
        'POST /billing/paypal/cancel',
        'POST /billing/paypal/reconcile',
        'GET /billing/paypal/status',
      ]);
      expect(
          find.byKey(const ValueKey('plp-billing-cancel-panel')), findsNothing);
      expect(_rich('Cancelled \u00b7 Launch'), findsOneWidget);
    });

    testWidgets('screen readers get a custom action instead of the hold',
        (tester) async {
      final handle = tester.ensureSemantics();
      final backend = cancelBackend();
      await _mount(tester, backend);
      await openPanel(tester);
      final semantics = tester.widget<Semantics>(find.byWidgetPredicate((w) =>
          w is Semantics && w.properties.customSemanticsActions != null));
      final actions = semantics.properties.customSemanticsActions!;
      expect(actions.keys.single.label, 'Cancel subscription now');
      actions.values.single();
      await tester.pumpAndSettle();
      expect(_count(backend, 'POST /billing/paypal/cancel'), 1);
      handle.dispose();
    });
  });

  testWidgets('cancel PayPal has not confirmed stays active with a short note',
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
    final semantics = tester.widget<Semantics>(find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.customSemanticsActions != null));
    semantics.properties.customSemanticsActions!.values.single();
    await tester.pumpAndSettle();
    expect(
        _rich(
          'Cancelled',
        ),
        findsNothing);
    expect(
        find.byKey(const ValueKey('plp-billing-cancel-sent')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-billing-cancel')), findsNothing);
  });

  testWidgets('ghost state: dashed remainder, days left, Restart rail',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [
            _json(_status(subscription: {
              ..._active,
              'plan_code': 'professional',
              'state': 'cancelled',
              'ends_on': '2026-11-08',
              'renews_on': null,
            })),
          ],
    });
    await _mount(tester, backend);
    expect(_rich('Cancelled \u00b7 Professional'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
    expect(find.text('days left'), findsOneWidget);
    expect(find.text('Access until 8 Nov'), findsOneWidget);
    expect(find.text('RESTART'), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-billing-cancel')), findsNothing);
    // No marker on the rail: every node is hollow.
    final dots = tester.widgetList<AnimatedContainer>(find.descendant(
        of: find.byKey(const ValueKey('plp-billing-axis')),
        matching: find.byType(AnimatedContainer)));
    expect(dots, hasLength(2));
    for (final dot in dots) {
      expect((dot.decoration! as BoxDecoration).color, isNot(Colors.black));
      expect((dot.decoration! as BoxDecoration).color, const Color(0xFFFAF8F3));
    }
  });

  testWidgets('cancelled without a PayPal end date shows no invented access',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [
            _json(_status(subscription: {
              ..._active,
              'state': 'cancelled',
              'ends_on': null,
              'renews_on': null
            })),
          ],
    });
    await _mount(tester, backend);
    expect(_rich('Cancelled \u00b7 Launch'), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-billing-hero-value')), findsNothing);
    expect(find.byKey(const ValueKey('plp-billing-playhead')), findsNothing);
    expect(find.text('RESTART'), findsOneWidget);
  });

  testWidgets('missing renewal date shows a dash and hides the timeline',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [
            _json(_status(subscription: {..._active, 'renews_on': null}))
          ],
    });
    await _mount(tester, backend);
    expect(find.text('\u2014'), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-billing-hero-date')), findsNothing);
    expect(find.byKey(const ValueKey('plp-billing-playhead')), findsNothing);
    expect(find.byKey(const ValueKey('plp-billing-seal')), findsOneWidget);
  });

  testWidgets('unknown billing interval hides the timeline segment',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [
            _json({
              ..._status(subscription: _active),
              'plans': [
                for (final plan in _plans) {...plan}..remove('interval')
              ],
            })
          ],
    });
    await _mount(tester, backend);
    expect(find.text('31'), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-billing-playhead')), findsNothing);
  });

  testWidgets('account records are not presented as PayPal-verified',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [
            _json(_status(subscription: {
              ..._active,
              'source_kind': 'manual',
              'verified_at': null
            }))
          ],
    });
    await _mount(tester, backend);
    expect(find.textContaining('Account record'), findsOneWidget);
    expect(find.textContaining('PayPal \u00b7 checked'), findsNothing);
  });

  group('errors render short inside the PLP page', () {
    Future<void> expectProblem(
        WidgetTester tester, http.Response status, String text) async {
      final backend = _Backend({
        'GET /billing/paypal/status': () => [status]
      });
      await _mount(tester, backend);
      expect(find.byKey(const ValueKey('plp-billing-problem')), findsOneWidget);
      expect(find.textContaining(text), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
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
        'PayPal unavailable',
        (tester) => expectProblem(
            tester,
            _json({'code': 'PAYPAL_AUTH_FAILED', 'plainMessage': 'x'}, 503),
            'PayPal unavailable.'));
    testWidgets(
        'malformed response',
        (tester) => expectProblem(
            tester, http.Response('{"plans":"nope"}', 200), 'cannot read'));
    testWidgets(
        'non-json response',
        (tester) =>
            expectProblem(tester, http.Response('<html>', 200), 'cannot read'));

    testWidgets('load failure can be retried in place', (tester) async {
      final backend = _Backend({
        'GET /billing/paypal/status': () => [
              _json({'code': 'PAYPAL_AUTH_FAILED', 'plainMessage': 'x'}, 503),
              _json(_status()),
            ],
      });
      await _mount(tester, backend);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plp-billing-problem')), findsNothing);
      expect(_rich('Not subscribed'), findsOneWidget);
    });

    testWidgets('missing organization sends no request', (tester) async {
      final backend = _Backend({});
      await _mount(tester, backend, organizationId: null);
      expect(find.textContaining('no organization selected'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
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
      await _openPlan(tester, 'professional');
      await _openHandoff(tester);
      await tester.tap(find.byKey(const ValueKey('plp-billing-continue')));
      await tester.pumpAndSettle();
      expect(launched, isEmpty);
      expect(find.textContaining('did not return an approval link'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('plp-billing-handoff')), findsNothing);
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
      await _openPlan(tester, 'launch');
      await _openHandoff(tester);
      await tester.tap(find.byKey(const ValueKey('plp-billing-continue')));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not open PayPal'), findsOneWidget);
    });

    testWidgets('checkout failure from PayPal re-reads status', (tester) async {
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
      await _openPlan(tester, 'launch');
      await _openHandoff(tester);
      await tester.tap(find.byKey(const ValueKey('plp-billing-continue')));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not start checkout'), findsOneWidget);
      expect(backend.paths.last, 'GET /billing/paypal/status');
    });

    testWidgets('seal check with nothing linked', (tester) async {
      final backend = _Backend({
        'GET /billing/paypal/status': () =>
            [_json(_status(subscription: _active))],
        'POST /billing/paypal/reconcile': () => [
              _json(
                  {'code': 'SUBSCRIPTION_NOT_FOUND', 'plainMessage': 'x'}, 409)
            ],
      });
      await _mount(tester, backend);
      await tester.tap(find.byKey(const ValueKey('plp-billing-seal')));
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
      await _openPlan(tester, 'launch');
      await _openHandoff(tester);
      await tester.tap(find.byKey(const ValueKey('plp-billing-continue')));
      await tester.pumpAndSettle();
      expect(find.text('Confirm it is you.'), findsOneWidget);
      expect(find.text('Verify identity'), findsOneWidget);
    });
  });

  testWidgets('sandbox environment is labelled and sent explicitly',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () =>
          [_json(_status(environment: 'sandbox', subscription: _active))],
    });
    await _mount(tester, backend, environment: 'sandbox');
    expect(find.text('PayPal sandbox \u00b7 test mode'), findsOneWidget);
    expect(
        find.text('PayPal sandbox \u00b7 checked 5 min ago'), findsOneWidget);
    expect(backend.calls.single.headers['x-pandora-billing-environment'],
        'sandbox');
  });

  testWidgets('back button returns to the opening PLP surface', (tester) async {
    var backs = 0;
    final backend = _Backend({
      'GET /billing/paypal/status': () => [_json(_status())],
    });
    await _mount(tester, backend, onBack: () => backs++);
    await tester.tap(find.byKey(const ValueKey('plp-billing-back')));
    await tester.pump();
    expect(backs, 1);
  });

  testWidgets('phone size renders every state without overflow',
      (tester) async {
    for (final status in [
      _status(),
      _status(subscription: _active),
      _status(checkout: _pendingCheckout()),
      _status(subscription: {
        ..._active,
        'state': 'cancelled',
        'ends_on': '2026-11-08',
        'renews_on': null
      }),
    ]) {
      final backend = _Backend({
        'GET /billing/paypal/status': () => [_json(status)]
      });
      await _mount(tester, backend, height: 932);
      expect(tester.takeException(), isNull);
    }
  });

  group('Revenue entry line', () {
    Future<_Backend> mountEntry(
        WidgetTester tester, List<http.Response> responses,
        {String? org = _org}) async {
      final backend = _Backend({
        'GET /billing/paypal/status': () => responses,
      });
      await setTestSurface(tester, logicalSize: const Size(430, 400));
      await tester.pumpWidget(testApp(
        child: Scaffold(
          body: PlpBillingEntryLine(
            organizationId: org,
            onTap: () {},
            api: org == null
                ? null
                : PlpPaypalBillingApi.forOrganization(org,
                    tokenProvider: const _Token(), httpClient: backend.client),
            clock: () => DateTime.utc(2026, 10, 8, 14, 5),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('active subscription', (tester) async {
      await mountEntry(tester, [_json(_status(subscription: _active))]);
      expect(
          _rich('Pandora \u00b7 Launch \u00b7 renews 8 Nov'), findsOneWidget);
    });
    testWidgets('not subscribed', (tester) async {
      await mountEntry(tester, [_json(_status())]);
      expect(_rich('Pandora billing \u00b7 not subscribed'), findsOneWidget);
    });
    testWidgets('failed read stays neutral', (tester) async {
      await mountEntry(tester, [
        _json({'code': 'PAYPAL_AUTH_FAILED', 'plainMessage': 'x'}, 503)
      ]);
      expect(_rich('Pandora billing'), findsOneWidget);
    });
    testWidgets('no organization sends no request', (tester) async {
      final backend = await mountEntry(tester, const [], org: null);
      expect(_rich('Pandora billing'), findsOneWidget);
      expect(backend.calls, isEmpty);
    });
  });

  test('idempotency keys are unique and server-valid', () {
    final a = PlpPaypalBillingApi.idempotencyKey('plp-checkout');
    final b = PlpPaypalBillingApi.idempotencyKey('plp-checkout');
    expect(a, isNot(b));
    expect(RegExp(r'^[A-Za-z0-9._:-]{8,128}$').hasMatch(a), isTrue);
  });
}
