import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pandora_mobile/core/data/plp_paypal_billing_api.dart';
import 'package:pandora_mobile/core/network/session_token_provider.dart';
import 'package:pandora_mobile/core/widgets/pandora_navigation.dart';
import 'package:pandora_mobile/features/enterprise/plp_paypal_billing_screen.dart';
import 'package:pandora_mobile/features/enterprise/plp_resort_workspace.dart';

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
  double height = 1400,
}) async {
  await setTestSurface(tester, logicalSize: Size(430, height));
  final launched = <Uri>[];
  await tester.pumpWidget(testApp(
    child: PlpPaypalBillingScreen(
      organizationId: organizationId,
      onOpenNavigation: () {},
      onBack: () {},
      billingEnvironment: environment,
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

Map<String, Object?> _pendingCheckout([String plan = 'launch']) => {
      'status': 'approval_pending',
      'plan_code': plan,
      'approval_url':
          'https://www.paypal.com/webapps/billing/subscriptions?ba_token=BA-9',
      'expires_at': '2026-10-08T15:20:00Z',
    };

const _pendingChange = <String, Object?>{
  'status': 'approval_pending',
  'to_plan_code': 'professional',
  'approval_url':
      'https://www.sandbox.paypal.com/webapps/billing/subscriptions/update?ba_token=BA-2',
};

final _cancelledVerified = <String, Object?>{
  ..._active,
  'state': 'cancelled',
  'ends_on': '2026-11-08',
  'renews_on': null,
};

Finder _rich(String text) => find.text(text, findRichText: true);

Finder _tile(String id) => find.byKey(ValueKey('plp-capability-$id'));
final _notice = find.byKey(const ValueKey('plp-billing-notice'));

String _noticeText(WidgetTester tester) => tester
    .widget<Text>(find.descendant(of: _notice, matching: find.byType(Text)))
    .data!;

/// Labels of the capability tiles, in order.
List<String> _tiles(WidgetTester tester) {
  final grid = find.byKey(const ValueKey('plp-billing-tiles'));
  if (grid.evaluate().isEmpty) return const [];
  return tester
      .widget<PlpCapabilityGrid>(grid)
      .items
      .map((item) => item.label)
      .toList();
}

/// Title, notice and tiles: the Rooms page pattern, nothing else.
void _expectTilePage(WidgetTester tester, String notice, List<String> tiles) {
  expect(find.byType(PlpPageTitle), findsOneWidget);
  expect(find.text('BILLING'), findsOneWidget);
  expect(find.byType(PlpNoticeBox), findsOneWidget);
  expect(_noticeText(tester), notice);
  expect(_tiles(tester), tiles);
  final texts = find.descendant(
      of: find.byKey(const ValueKey('plp-billing-page')),
      matching: find.byType(Text));
  expect(texts.evaluate().length, lessThanOrEqualTo(6));
  // The rejected temporal design is gone.
  for (final key in [
    'plp-billing-hero-value',
    'plp-billing-playhead',
    'plp-billing-axis',
    'plp-billing-seal',
    'plp-billing-waiting',
    'plp-billing-cancel-panel',
    'plp-billing-handoff',
    'plp-billing-hold',
    'plp-billing-back',
  ]) {
    expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
  }
  expect(find.text('HOLD TO CANCEL'), findsNothing);
  expect(find.byType(Divider), findsNothing);
  // Shell-owned chrome is never drawn by the page.
  expect(find.byType(PandoraMenuButton), findsNothing);
}

Future<void> _tapTile(WidgetTester tester, String id) async {
  await tester.tap(_tile(id));
  await tester.pumpAndSettle();
}

int _count(_Backend backend, String path) =>
    backend.paths.where((p) => p == path).length;

void main() {
  testWidgets('no plan: BILLING tile page with the backend plans as tiles',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [_json(_status())]
    });
    await _mount(tester, backend);
    _expectTilePage(
        tester, 'No PayPal plan yet.', ['Launch', 'Professional']);
    // Labels only: no price essay on the tiles.
    expect(find.textContaining('USD'), findsNothing);
    expect(find.byKey(const ValueKey('plp-billing-sandbox')), findsNothing);
    expect(backend.paths, ['GET /billing/paypal/status']);
    final request = backend.calls.single;
    expect(request.headers['authorization'], 'Bearer session-token');
    expect(request.headers['x-organization-id'], _org);
    expect(
        request.headers.containsKey('x-pandora-billing-environment'), isFalse);
  });

  testWidgets('tiles are the Rooms capability tiles: 2 columns, 88 px',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [_json(_status())]
    });
    await _mount(tester, backend, height: 932);
    final launch = tester.getRect(find.descendant(
        of: _tile('launch'), matching: find.byType(Container)).first);
    final pro = tester.getRect(find.descendant(
        of: _tile('professional'), matching: find.byType(Container)).first);
    expect(launch.height, 88);
    expect(pro.height, 88);
    expect(launch.top, pro.top, reason: 'two columns, same row');
    expect(launch.right, lessThan(pro.left));
    expect(
        find.descendant(
            of: _tile('launch'),
            matching: find.byIcon(Icons.arrow_forward_rounded)),
        findsOneWidget);
  });

  testWidgets(
      'tapping a plan starts checkout, hands off to PayPal, then waits',
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
    await _tapTile(tester, 'launch');
    final checkout =
        backend.calls.firstWhere((c) => c.url.path.endsWith('/checkout'));
    final body = jsonDecode(checkout.body) as Map<String, dynamic>;
    expect(body['planCode'], 'launch');
    expect(body['idempotencyKey'], startsWith('plp-checkout-'));
    expect(Uri.parse(body['returnUrl'] as String).scheme, 'https');
    expect(Uri.parse(body['cancelUrl'] as String).scheme, 'https');
    expect(launched.single.host, 'www.paypal.com');
    _expectTilePage(tester, 'Waiting for PayPal.', ['Open PayPal', 'Refresh']);
    expect(_tile('cancel'), findsNothing);
  });

  testWidgets('returning from PayPal reconciles, then reads status',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [
            _json(_status()),
            _json(_status(checkout: _pendingCheckout())),
            _json(_status(subscription: _active)),
          ],
      'POST /billing/paypal/checkout': () => [
            _json({
              'approvalUrl':
                  'https://www.paypal.com/webapps/billing/subscriptions?ba_token=BA-1',
              'status': 'approval_pending'
            })
          ],
      'POST /billing/paypal/reconcile': () => [
            _json({'verified': true})
          ],
    });
    await _mount(tester, backend);
    await _tapTile(tester, 'launch');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(backend.paths.skip(3).toList(),
        ['POST /billing/paypal/reconcile', 'GET /billing/paypal/status']);
    _expectTilePage(tester, 'Launch is active, confirmed by PayPal.',
        ['Change plan', 'Refresh', 'Cancel']);
  });

  testWidgets(
      'approval pending: Open PayPal and Refresh, Cancel absent, Refresh reconciles',
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
    _expectTilePage(tester, 'Waiting for PayPal.', ['Open PayPal', 'Refresh']);
    expect(_tile('cancel'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    await _tapTile(tester, 'open-paypal');
    expect(launched.single.queryParameters['ba_token'], 'BA-9');
    expect(backend.paths.where((p) => p.startsWith('POST')), isEmpty);
    await _tapTile(tester, 'refresh');
    expect(backend.paths.skip(1).toList(),
        ['POST /billing/paypal/reconcile', 'GET /billing/paypal/status']);
    expect(_tile('cancel'), findsNothing);
  });

  testWidgets('pending plan change waits and offers no Cancel or Change plan',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [
            _json(_status(subscription: _active, planChange: _pendingChange)),
          ],
    });
    await _mount(tester, backend);
    _expectTilePage(tester, 'Waiting for PayPal.', ['Open PayPal', 'Refresh']);
    expect(_tile('cancel'), findsNothing);
    expect(_tile('change-plan'), findsNothing);
  });

  testWidgets('a plan PayPal has not verified waits; Cancel stays blocked',
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
    _expectTilePage(tester, 'Waiting for PayPal.', ['Refresh']);
    expect(_tile('cancel'), findsNothing);
  });

  testWidgets('expired or untrusted approval links do not wait',
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
    _expectTilePage(
        tester, 'No PayPal plan yet.', ['Launch', 'Professional']);
  });

  testWidgets('active: one-line notice, Change plan, Refresh, Cancel',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [
            _json(_status(subscription: _active)),
            _json(_status(subscription: _active)),
          ],
      'POST /billing/paypal/reconcile': () => [
            _json({'verified': true})
          ],
    });
    await _mount(tester, backend);
    _expectTilePage(tester, 'Launch is active, confirmed by PayPal.',
        ['Change plan', 'Refresh', 'Cancel']);
    await _tapTile(tester, 'refresh');
    expect(backend.paths.skip(1).toList(),
        ['POST /billing/paypal/reconcile', 'GET /billing/paypal/status']);
  });

  testWidgets('change plan: other catalog plans, change-plan with its key',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [
            _json(_status(subscription: _active)),
            _json(_status(subscription: _active, planChange: _pendingChange)),
          ],
      'POST /billing/paypal/change-plan': () => [
            _json({
              'approvalUrl': _pendingChange['approval_url'],
              'status': 'approval_pending'
            }),
          ],
    });
    final launched = await _mount(tester, backend);
    await _tapTile(tester, 'change-plan');
    _expectTilePage(tester, 'Choose a plan.', ['Professional']);
    expect(backend.paths.where((p) => p.startsWith('POST')), isEmpty);
    await _tapTile(tester, 'professional');
    final change =
        backend.calls.firstWhere((c) => c.url.path.endsWith('/change-plan'));
    final body = jsonDecode(change.body) as Map<String, dynamic>;
    expect(body['planCode'], 'professional');
    expect(body['idempotencyKey'], startsWith('plp-plan-change-'));
    expect(Uri.parse(body['returnUrl'] as String).scheme, 'https');
    expect(Uri.parse(body['cancelUrl'] as String).scheme, 'https');
    expect(launched.single.host, 'www.sandbox.paypal.com');
    // Never claims the change: PayPal approval is still pending.
    _expectTilePage(tester, 'Waiting for PayPal.', ['Open PayPal', 'Refresh']);
  });

  testWidgets('sandbox refuses plan changes and the notice says so',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [
            _json(_status(environment: 'sandbox', subscription: _active)),
          ],
      'POST /billing/paypal/change-plan': () => [
            _json({
              'code': 'SANDBOX_PLAN_CHANGE_UNAVAILABLE',
              'plainMessage':
                  'Plan changes are not available in PayPal sandbox. Nothing was sent to PayPal.'
            }, 409),
          ],
    });
    final launched = await _mount(tester, backend, environment: 'sandbox');
    await _tapTile(tester, 'change-plan');
    await _tapTile(tester, 'professional');
    expect(launched, isEmpty);
    expect(_noticeText(tester), 'Plan changes are not available in sandbox.');
    expect(backend.paths.last, 'GET /billing/paypal/status');
  });

  group('cancel', () {
    testWidgets('confirm is the same tile page, not a sheet or a hold',
        (tester) async {
      final backend = _Backend({
        'GET /billing/paypal/status': () =>
            [_json(_status(subscription: _active))],
      });
      await _mount(tester, backend);
      await _tapTile(tester, 'cancel');
      _expectTilePage(
          tester, 'Cancel this plan. PayPal must confirm.', ['Confirm cancel']);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(backend.paths.where((p) => p.startsWith('POST')), isEmpty);
    });

    testWidgets(
        'Confirm cancel: cancel, reconcile, status; CANCELLED readback shows Cancelled',
        (tester) async {
      final backend = _Backend({
        'GET /billing/paypal/status': () => [
              _json(_status(subscription: _active)),
              _json(_status(subscription: _cancelledVerified)),
            ],
        'POST /billing/paypal/cancel': () => [
              _json({
                'status': 'cancelled',
                'cancelled': true,
                'verified': true,
                'providerStatus': 'CANCELLED'
              })
            ],
        'POST /billing/paypal/reconcile': () => [
              _json({'verified': true, 'state': 'cancelled'})
            ],
      });
      await _mount(tester, backend);
      await _tapTile(tester, 'cancel');
      await _tapTile(tester, 'confirm-cancel');
      expect(backend.paths, [
        'GET /billing/paypal/status',
        'POST /billing/paypal/cancel',
        'POST /billing/paypal/reconcile',
        'GET /billing/paypal/status',
      ]);
      _expectTilePage(tester, 'Cancelled.', ['Choose a plan']);
      await _tapTile(tester, 'choose-a-plan');
      _expectTilePage(
          tester, 'No PayPal plan yet.', ['Launch', 'Professional']);
    });

    testWidgets(
        'AWAITING_BUYER_APPROVAL stays on waiting and never shows Cancelled',
        (tester) async {
      final backend = _Backend({
        'GET /billing/paypal/status': () => [
              _json(_status(subscription: _active)),
              _json(_status(subscription: _active)),
            ],
        'POST /billing/paypal/cancel': () => [
              _json({
                'status': 'blocked',
                'cancelRequested': false,
                'cancelled': false,
                'verified': false,
                'providerStatus': 'APPROVAL_PENDING',
                'reason': 'AWAITING_BUYER_APPROVAL'
              })
            ],
      });
      await _mount(tester, backend);
      await _tapTile(tester, 'cancel');
      await _tapTile(tester, 'confirm-cancel');
      expect(_count(backend, 'POST /billing/paypal/cancel'), 1);
      expect(_count(backend, 'POST /billing/paypal/reconcile'), 0);
      _expectTilePage(tester, 'Waiting for PayPal.', ['Refresh']);
      expect(find.text('Cancelled.'), findsNothing);
      expect(find.textContaining('Cancelled'), findsNothing);
      expect(_tile('cancel'), findsNothing);
      expect(_tile('confirm-cancel'), findsNothing);
    });

    testWidgets('unconfirmed cancel waits for PayPal, not Cancelled',
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
              _json({
                'status': 'cancel_unconfirmed',
                'cancelRequested': true,
                'cancelled': false,
                'verified': false,
                'providerStatus': 'ACTIVE',
                'reason': 'CANCELLATION_NOT_CONFIRMED'
              })
            ],
        'POST /billing/paypal/reconcile': () => [
              _json({'verified': true, 'state': 'active'})
            ],
      });
      await _mount(tester, backend);
      await _tapTile(tester, 'cancel');
      await _tapTile(tester, 'confirm-cancel');
      _expectTilePage(tester, 'Waiting for PayPal.', ['Refresh']);
      expect(find.textContaining('Cancelled'), findsNothing);
      expect(_tile('cancel'), findsNothing);
    });

    testWidgets('a cancelled response without a CANCELLED readback is not shown',
        (tester) async {
      final backend = _Backend({
        'GET /billing/paypal/status': () => [
              _json(_status(subscription: _active)),
              _json(_status(subscription: _active)),
            ],
        'POST /billing/paypal/cancel': () => [
              _json({'status': 'cancelled'})
            ],
        'POST /billing/paypal/reconcile': () => [
              _json({'verified': true, 'state': 'active'})
            ],
      });
      await _mount(tester, backend);
      await _tapTile(tester, 'cancel');
      await _tapTile(tester, 'confirm-cancel');
      expect(find.textContaining('Cancelled'), findsNothing);
      expect(_noticeText(tester), 'Launch is active, confirmed by PayPal.');
    });

    testWidgets('other blocked reasons keep the plan and say so',
        (tester) async {
      final backend = _Backend({
        'GET /billing/paypal/status': () =>
            [_json(_status(subscription: _active))],
        'POST /billing/paypal/cancel': () => [
              _json({'status': 'blocked', 'reason': 'RECONCILIATION_REQUIRED'})
            ],
      });
      await _mount(tester, backend);
      await _tapTile(tester, 'cancel');
      await _tapTile(tester, 'confirm-cancel');
      expect(_noticeText(tester), contains('Nothing was cancelled'));
      expect(find.textContaining('Cancelled'), findsNothing);
    });
  });

  testWidgets('cancelled from status: Cancelled. and Choose a plan',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () =>
          [_json(_status(subscription: _cancelledVerified))],
    });
    await _mount(tester, backend);
    _expectTilePage(tester, 'Cancelled.', ['Choose a plan']);
  });

  testWidgets('a cancelled record PayPal has not verified is not Cancelled',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () => [
            _json(_status(subscription: {
              ..._cancelledVerified,
              'source_kind': 'manual',
              'verified_at': null,
            }))
          ],
    });
    await _mount(tester, backend);
    _expectTilePage(tester, 'Waiting for PayPal.', ['Refresh']);
  });

  group('errors render as the one notice', () {
    Future<void> expectProblem(
        WidgetTester tester, http.Response status, String text) async {
      final backend = _Backend({
        'GET /billing/paypal/status': () => [status]
      });
      await _mount(tester, backend);
      _expectTilePage(tester, _noticeText(tester), ['Try again']);
      expect(_noticeText(tester), contains(text));
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
            'PayPal is unavailable'));
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
      await _tapTile(tester, 'try-again');
      _expectTilePage(
          tester, 'No PayPal plan yet.', ['Launch', 'Professional']);
    });

    testWidgets('missing organization sends no request', (tester) async {
      final backend = _Backend({});
      await _mount(tester, backend, organizationId: null);
      _expectTilePage(tester, 'No organization is selected.', []);
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
      await _tapTile(tester, 'professional');
      expect(launched, isEmpty);
      expect(_noticeText(tester), contains('did not return an approval link'));
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
      await _tapTile(tester, 'launch');
      expect(_noticeText(tester), contains('could not open PayPal'));
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
      await _tapTile(tester, 'launch');
      expect(_noticeText(tester), contains('could not start checkout'));
      expect(_tiles(tester), ['Launch', 'Professional']);
      expect(backend.paths.last, 'GET /billing/paypal/status');
    });

    testWidgets('refresh with nothing linked', (tester) async {
      final backend = _Backend({
        'GET /billing/paypal/status': () =>
            [_json(_status(subscription: _active))],
        'POST /billing/paypal/reconcile': () => [
              _json(
                  {'code': 'SUBSCRIPTION_NOT_FOUND', 'plainMessage': 'x'}, 409)
            ],
      });
      await _mount(tester, backend);
      await _tapTile(tester, 'refresh');
      expect(_noticeText(tester), contains('No PayPal subscription is linked'));
      expect(backend.paths.last, 'GET /billing/paypal/status');
    });

    testWidgets('extra identity check offers a Verify identity tile',
        (tester) async {
      final backend = _Backend({
        'GET /billing/paypal/status': () => [_json(_status())],
        'POST /billing/paypal/checkout': () => [
              _json({'code': 'AAL2_REQUIRED', 'plainMessage': 'x'}, 403)
            ],
      });
      await _mount(tester, backend);
      await _tapTile(tester, 'launch');
      expect(_noticeText(tester), contains('authenticator code'));
      expect(_tiles(tester), ['Verify identity']);
    });
  });

  testWidgets('sandbox header only for the sandbox billing environment',
      (tester) async {
    final backend = _Backend({
      'GET /billing/paypal/status': () =>
          [_json(_status(environment: 'sandbox', subscription: _active))],
    });
    await _mount(tester, backend, environment: 'sandbox');
    expect(find.byKey(const ValueKey('plp-billing-sandbox')), findsOneWidget);
    expect(backend.calls.single.headers['x-pandora-billing-environment'],
        'sandbox');
    _expectTilePage(tester, 'Launch is active, confirmed by PayPal.',
        ['Change plan', 'Refresh', 'Cancel']);
  });

  testWidgets('phone size renders every state without overflow',
      (tester) async {
    for (final status in [
      _status(),
      _status(subscription: _active),
      _status(checkout: _pendingCheckout()),
      _status(subscription: _active, planChange: _pendingChange),
      _status(subscription: _cancelledVerified),
    ]) {
      final backend = _Backend({
        'GET /billing/paypal/status': () => [_json(status)]
      });
      await _mount(tester, backend, height: 700);
      expect(tester.takeException(), isNull);
      expect(find.byType(PlpCapabilityGrid), findsOneWidget);
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
