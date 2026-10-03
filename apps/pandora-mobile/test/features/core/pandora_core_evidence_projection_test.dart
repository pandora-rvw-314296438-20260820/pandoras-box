import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/pandora_core_api.dart';
import 'package:pandora_mobile/features/core/pandora_core_screen.dart';

import '../../helpers/test_app.dart';

const _harbor = '11111111-1111-4111-8111-111111111111';
const _valley = '22222222-2222-4222-8222-222222222222';

PandoraCoreRecord _snapshot() => <String, dynamic>{
      'clients': <PandoraCoreRecord>[
        <String, dynamic>{
          'organization_id': _harbor,
          'display_name': 'Harbor workspace',
        },
        <String, dynamic>{
          'organization_id': _valley,
          'display_name': 'Valley workspace',
        },
      ],
    };

class _EvidenceGateway implements PandoraCoreGateway {
  _EvidenceGateway(this.data);

  final PandoraCoreRecord data;
  final reads = <String>[];
  int writes = 0;

  @override
  Future<PandoraCoreRecord> snapshot(
    String section, {
    String? organizationId,
  }) async {
    reads.add(section);
    return data;
  }

  @override
  Future<PandoraCoreRecord> operate(
    String operation, {
    String? organizationId,
    required PandoraCoreRecord payload,
    required String idempotencyKey,
  }) async {
    writes++;
    throw StateError('Evidence inspection must not mutate records.');
  }

  @override
  Future<PandoraCoreRecord> enterClient(
    String organizationId, {
    required String reason,
  }) async {
    throw StateError('Evidence inspection must not enter a workspace.');
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _mount(
  WidgetTester tester,
  _EvidenceGateway gateway, {
  required String section,
  required String tab,
}) async {
  await setTestSurface(tester, logicalSize: const Size(520, 1000));
  await tester.pumpWidget(testApp(
    child: Scaffold(
      body: PandoraCoreScreen(gateway: gateway, section: section),
    ),
  ));
  await tester.pumpAndSettle();
  await _tap(tester, find.text(tab));
}

Finder _tile(String title) => find.ancestor(
      of: find.text(title),
      matching: find.byType(ListTile),
    );

void _expectSubtitle(String title, String subtitle) {
  final tile = _tile(title);
  expect(tile, findsOneWidget);
  expect(
      find.descendant(of: tile, matching: find.text(subtitle)), findsOneWidget);
}

void _expectStatus(String label, String value, {Finder? within}) {
  final labelFinder = within == null
      ? find.text(label)
      : find.descendant(of: within, matching: find.text(label));
  expect(labelFinder, findsOneWidget);
  final row = find.ancestor(of: labelFinder, matching: find.byType(Row)).first;
  expect(find.descendant(of: row, matching: find.text(value)), findsOneWidget);
}

void main() {
  testWidgets('usage names the model and preserves measured usage and costs',
      (tester) async {
    final gateway = _EvidenceGateway(<String, dynamic>{
      ..._snapshot(),
      'usage': <PandoraCoreRecord>[
        <String, dynamic>{
          'organization_id': _harbor,
          'provider': 'OpenAI',
          'model': 'model-estimated',
          'requests': 17,
          'input_tokens': 1234,
          'output_tokens': 567,
          'estimated_cost_micros': 1234567,
          'currency': 'USD',
        },
        <String, dynamic>{
          'organization_id': _harbor,
          'provider': 'Anthropic',
          'model': 'model-billed',
          'requests': 3,
          'tokens': 901,
          'billed_cost_micros': 2340000,
          'currency': 'PHP',
        },
        <String, dynamic>{
          'organization_id': _harbor,
          'provider': 'Local',
          'model': 'model-unpriced',
          'requests': 2,
          'tokens': 15,
        },
        <String, dynamic>{
          'organization_id': _harbor,
          'provider': 'Provider',
          'model': 'model-no-currency',
          'requests': 4,
          'tokens': 7,
          'estimated_cost_micros': 9870000,
        },
      ],
    });
    await _mount(tester, gateway, section: 'business', tab: 'Usage & Costs');

    _expectSubtitle(
      'OpenAI · model-estimated',
      'Harbor workspace · 17 requests · 1234 input tokens · 567 output tokens'
          ' · Estimated USD 1.234567',
    );
    _expectSubtitle(
      'Anthropic · model-billed',
      'Harbor workspace · 3 requests · 901 tokens · Billed PHP 2.34',
    );
    _expectSubtitle(
      'Local · model-unpriced',
      'Harbor workspace · 2 requests · 15 tokens · Cost unavailable',
    );
    _expectSubtitle(
      'Provider · model-no-currency',
      'Harbor workspace · 4 requests · 7 tokens · Cost currency unavailable',
    );
    expect(find.textContaining('Billed USD'), findsNothing);
    expect(find.textContaining('Estimated PHP'), findsNothing);
    expect(find.textContaining('0.00'), findsNothing);
    expect(gateway.reads, <String>['business']);
    expect(gateway.writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'allowances stay separate and unknown request counts stay unknown',
      (tester) async {
    final gateway = _EvidenceGateway(<String, dynamic>{
      ..._snapshot(),
      'usage': <PandoraCoreRecord>[
        <String, dynamic>{
          'organization_id': _harbor,
          'provider': 'Local',
          'model': 'measured-model',
          'requests': 5,
          'tokens': 1200,
        },
      ],
      'usage_allowances': <PandoraCoreRecord>[
        <String, dynamic>{
          'organization_id': _harbor,
          'request_limit': 50,
          'requests_admitted': 7,
          'requests_remaining': 43,
          'token_limit': 5000,
          'budget_micros': 10000000,
          'currency': 'USD',
          'request_admission_state': 'enforcing',
        },
        <String, dynamic>{
          'organization_id': _valley,
          'request_limit': 100,
          'requests_admitted': null,
          'requests_remaining': null,
          'request_admission_enabled': false,
          'request_admission_state': 'not_enrolled',
        },
      ],
    });
    await _mount(tester, gateway, section: 'business', tab: 'Usage & Costs');

    expect(find.text('Allowances'), findsOneWidget);
    _expectSubtitle(
      'Local · measured-model',
      'Harbor workspace · 5 requests · 1200 tokens · Cost unavailable',
    );
    _expectSubtitle(
      'Harbor workspace allowances',
      '50 monthly cloud-chat requests · 7 admitted · 43 remaining'
          ' · 5000 commercial tokens · Commercial cost allowance USD 10.00',
    );
    _expectSubtitle(
      'Valley workspace allowances',
      '100 monthly cloud-chat requests · Request blocking not enabled',
    );
    expect(find.text('Enforced'), findsOneWidget);
    expect(find.text('Not enabled'), findsOneWidget);
    expect(find.textContaining('0 admitted'), findsNothing);
    expect(find.textContaining('0 remaining'), findsNothing);

    await _tap(tester, find.text('Valley workspace allowances'));
    final sheet = find.byType(BottomSheet);
    _expectStatus('Admitted cloud-chat requests', 'Unknown', within: sheet);
    _expectStatus('Requests remaining', 'Unknown', within: sheet);
    expect(find.descendant(of: sheet, matching: find.text('0')), findsNothing);
    expect(gateway.writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('models preserve routing counts and distinct runtime evidence',
      (tester) async {
    final gateway = _EvidenceGateway(<String, dynamic>{
      'model_routing': <String, dynamic>{
        'enabled': true,
        'configured_eligible_models': 3,
        'verified_eligible_models': 2,
        'fresh_verified_eligible_models': 1,
      },
      'models': <PandoraCoreRecord>[
        <String, dynamic>{
          'display_name': 'Stale successful model',
          'provider_name': 'Provider Alpha',
          'model_id': 'alpha-model',
          'verification_state': 'passed',
          'runtime_evidence_state': 'stale',
        },
        <String, dynamic>{
          'display_name': 'Failed model',
          'provider_name': 'Provider Beta',
          'model_id': 'beta-model',
          'verification_state': 'failed',
          'runtime_evidence_state': 'fresh',
        },
        <String, dynamic>{
          'display_name': 'Untested model',
          'provider_name': 'Provider Gamma',
          'model_id': 'gamma-model',
          'verification_state': 'untested',
        },
      ],
    });
    await _mount(tester, gateway, section: 'platform', tab: 'Models');

    expect(find.text('Auto routing'), findsOneWidget);
    expect(find.text('Enabled'), findsOneWidget);
    _expectStatus('Eligible models', '3');
    _expectStatus('With runtime evidence', '2');
    _expectStatus('Verified within 24 hours', '1');
    _expectSubtitle(
      'Stale successful model',
      'Provider Alpha · alpha-model · Runtime passed · Stale runtime evidence',
    );
    _expectSubtitle(
      'Failed model',
      'Provider Beta · beta-model · Runtime failed · Evidence within 24 hours',
    );
    _expectSubtitle(
      'Untested model',
      'Provider Gamma · gamma-model · Runtime not verified · Evidence time unknown',
    );
    expect(gateway.reads, <String>['platform']);
    expect(gateway.writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing routing evidence never invents availability or counts',
      (tester) async {
    final missing = _EvidenceGateway(<String, dynamic>{});
    await _mount(tester, missing, section: 'platform', tab: 'Models');

    expect(find.text('Current model routing evidence is unavailable.'),
        findsOneWidget);
    expect(find.text('Auto routing'), findsNothing);
    expect(find.text('Enabled'), findsNothing);
    expect(find.text('Eligible models'), findsNothing);
    expect(find.text('With runtime evidence'), findsNothing);
    expect(find.text('Verified within 24 hours'), findsNothing);
    expect(find.text('0'), findsNothing);

    final partial = _EvidenceGateway(<String, dynamic>{
      'model_routing': <String, dynamic>{
        'policy_version': 'policy-without-observed-counts',
      },
    });
    await _mount(tester, partial, section: 'platform', tab: 'Models');

    expect(find.text('Auto routing'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
    expect(find.text('Enabled'), findsNothing);
    expect(find.text('Eligible models'), findsNothing);
    expect(find.text('With runtime evidence'), findsNothing);
    expect(find.text('Verified within 24 hours'), findsNothing);
    expect(find.text('0'), findsNothing);
    expect(find.text('No verified models state in this snapshot.'),
        findsOneWidget);
    expect(missing.writes, 0);
    expect(partial.writes, 0);
    expect(tester.takeException(), isNull);
  });
}
