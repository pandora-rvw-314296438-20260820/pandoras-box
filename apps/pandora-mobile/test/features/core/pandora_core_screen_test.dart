import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/pandora_core_api.dart';
import 'package:pandora_mobile/features/core/pandora_core_screen.dart';

import '../../helpers/test_app.dart';

const _northClientId = '11111111-1111-4111-8111-111111111111';
const _southClientId = '22222222-2222-4222-8222-222222222222';

PandoraCoreRecord _client({
  String id = _northClientId,
  String name = 'Northwind Guest House',
  String health = 'healthy',
  bool canEnter = true,
}) =>
    <String, dynamic>{
      'organization_id': id,
      'display_name': name,
      'slug': id == _northClientId ? 'northwind' : 'harbor',
      'industry': 'Hospitality',
      'workspace_type': 'plp',
      'lifecycle_state': 'active',
      'onboarding_state': 'complete',
      'users': 12,
      'admins': 2,
      'connections': 5,
      'connections_healthy': 5,
      'devices': 2,
      'health': health,
      'last_active': '2026-10-03T04:00:00Z',
      'created_at': '2026-09-01T04:00:00Z',
      'can_enter': canEnter,
      // Customer operating metrics never belong in the owner directory.
      'revenue': 987654321,
      'occupancy': 81,
      'legal_hearings': 9,
      'restaurant_sales': 123456789,
    };

PandoraCoreRecord _snapshot({List<PandoraCoreRecord>? clients}) =>
    <String, dynamic>{
      'schema_version': '1',
      'generated_at': '2026-10-03T04:00:00Z',
      'operator': <String, dynamic>{
        'role': 'owner',
        'platform_organization_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      },
      'clients': clients ?? <PandoraCoreRecord>[_client()],
      'needs_you': <PandoraCoreRecord>[],
      'handling': <PandoraCoreRecord>[],
      'health': <String, dynamic>{
        'clients': (clients ?? <PandoraCoreRecord>[_client()]).length,
        'active_clients': (clients ?? <PandoraCoreRecord>[_client()]).length,
        'attention_clients': 0,
        'connections': 5,
        'connections_healthy': 5,
        'devices': 2,
        'incidents': 0,
        'state': 'healthy',
      },
      'business': <String, dynamic>{
        'subscriptions': <PandoraCoreRecord>[],
        'invoices': <PandoraCoreRecord>[],
        'pipeline': <PandoraCoreRecord>[],
        'usage': <PandoraCoreRecord>[],
        'currencies': <String>[],
        'coverage': 'No billing provider connected',
      },
      'outcomes': <PandoraCoreRecord>[],
      'plans': <PandoraCoreRecord>[],
    };

PandoraCoreRecord _clientDetail(PandoraCoreRecord client) => <String, dynamic>{
      ..._snapshot(clients: <PandoraCoreRecord>[]),
      'client': client,
      'onboarding': <PandoraCoreRecord>[],
      'members': <PandoraCoreRecord>[],
      'connections': <PandoraCoreRecord>[],
      'devices': <PandoraCoreRecord>[],
      'usage': <PandoraCoreRecord>[],
      'deployments': <PandoraCoreRecord>[],
      'cases': <PandoraCoreRecord>[],
      'contracts': <PandoraCoreRecord>[],
      'subscription': null,
    };

class _SnapshotRequest {
  const _SnapshotRequest(this.section, this.organizationId);

  final String section;
  final String? organizationId;
}

class _OperationRequest {
  const _OperationRequest({
    required this.operation,
    required this.organizationId,
    required this.payload,
    required this.idempotencyKey,
  });

  final String operation;
  final String? organizationId;
  final PandoraCoreRecord payload;
  final String idempotencyKey;
}

class _FakeCoreGateway implements PandoraCoreGateway {
  PandoraCoreRecord data = <String, dynamic>{};
  final snapshots = <_SnapshotRequest>[];
  final operations = <_OperationRequest>[];
  final entries = <String>[];
  Future<PandoraCoreRecord> Function(_SnapshotRequest)? onSnapshot;
  Future<PandoraCoreRecord> Function(_OperationRequest)? onOperate;

  @override
  Future<PandoraCoreRecord> snapshot(
    String section, {
    String? organizationId,
  }) async {
    final request = _SnapshotRequest(section, organizationId);
    snapshots.add(request);
    return onSnapshot == null ? data : await onSnapshot!(request);
  }

  @override
  Future<PandoraCoreRecord> operate(
    String operation, {
    String? organizationId,
    required PandoraCoreRecord payload,
    required String idempotencyKey,
  }) async {
    final request = _OperationRequest(
      operation: operation,
      organizationId: organizationId,
      payload: Map<String, dynamic>.of(payload),
      idempotencyKey: idempotencyKey,
    );
    operations.add(request);
    return onOperate == null
        ? <String, dynamic>{'organization_id': _northClientId}
        : await onOperate!(request);
  }

  @override
  Future<PandoraCoreRecord> enterClient(
    String organizationId, {
    required String reason,
  }) async {
    entries.add(organizationId);
    throw StateError('The owning shell must authorize workspace entry.');
  }
}

Future<void> _mount(
  WidgetTester tester,
  _FakeCoreGateway gateway, {
  String section = 'home',
  String? organizationId,
  Size size = const Size(390, 844),
  double textScale = 1,
  ValueChanged<String>? onNavigate,
  Future<void> Function(PandoraCoreRecord)? onEnterClient,
  ValueChanged<PandoraCoreRecord>? onContextChanged,
  String? initialAction,
}) async {
  await setTestSurface(tester, logicalSize: size);
  await tester.pumpWidget(
    testApp(
      textScaler: TextScaler.linear(textScale),
      child: Scaffold(
        body: PandoraCoreScreen(
          gateway: gateway,
          section: section,
          organizationId: organizationId,
          onNavigate: onNavigate,
          onEnterClient: onEnterClient,
          onContextChanged: onContextChanged,
          initialAction: initialAction,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _fillRegistration(WidgetTester tester) async {
  for (final entry in <String, String>{
    'name': 'Mistral Hotel',
    'slug': 'mistral-hotel',
    'primary_contact_name': 'Ada Owner',
    'primary_contact_email': 'ada@example.invalid',
  }.entries) {
    final field = find.byKey(ValueKey('core-field-${entry.key}'));
    await tester.scrollUntilVisible(
      field,
      200,
      scrollable: find
          .descendant(
            of: find.byType(PandoraCoreOperationForm),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(field, findsOneWidget, reason: 'Registration field ${entry.key}');
    expect(
      find.descendant(of: field, matching: find.byType(EditableText)),
      findsOneWidget,
      reason: 'Editable registration field ${entry.key}',
    );
    await tester.enterText(field, entry.value);
    await tester.pump();
  }
  for (final entry in <String, String>{
    'industry': 'Hospitality',
    'workspace_type': 'Resort / hospitality',
  }.entries) {
    await _tap(tester, find.byKey(ValueKey('core-field-${entry.key}')));
    await _tap(tester, find.text(entry.value).last);
  }
}

void main() {
  testWidgets(
      'commercial confirmation shows the exact client currency and amount',
      (tester) async {
    final gateway = _FakeCoreGateway();
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    await tester.pumpWidget(testApp(
        child: Scaffold(
      body: PandoraCoreOperationForm(
        gateway: gateway,
        operation: 'invoice.record',
        organizationId: _northClientId,
        scopeLabel: 'Northwind Guest House',
        title: 'Record invoice',
        financial: true,
        fields: const <CoreFormField>[
          CoreFormField('amount_micros', 'Amount', money: true, required: true),
          CoreFormField('currency', 'Currency',
              options: {'PHP': 'PHP', 'USD': 'USD'}),
        ],
        initial: const <String, dynamic>{
          'amount_micros': 12345678901,
          'currency': 'PHP',
        },
      ),
    )));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('core-submit')));

    expect(find.text('Confirm commercial record'), findsOneWidget);
    expect(find.text('Northwind Guest House'), findsOneWidget);
    expect(find.text('Amount: PHP 12345.678901'), findsOneWidget);
    expect(find.text('Currency: PHP'), findsOneWidget);
    expect(gateway.operations, isEmpty);
    await _tap(
        tester,
        find.descendant(
            of: find.byType(AlertDialog), matching: find.text('Cancel')));
    expect(gateway.operations, isEmpty);
    expect(find.byType(PandoraCoreOperationForm), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a create-client handoff opens once and refresh does not repeat it',
      (tester) async {
    final gateway = _FakeCoreGateway()..data = _snapshot(clients: []);
    await _mount(tester, gateway,
        section: 'clients', initialAction: 'create_client');
    expect(find.byType(PandoraCoreOperationForm), findsOneWidget);
    await _tap(tester, find.text('Cancel'));
    await _tap(tester, find.byKey(const ValueKey('core-refresh')));
    expect(find.byType(PandoraCoreOperationForm), findsNothing);
    expect(gateway.operations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Manage and Back publish an explicit command scope transition',
      (tester) async {
    final gateway = _FakeCoreGateway()
      ..onSnapshot = (request) async => request.organizationId == null
          ? _snapshot()
          : _clientDetail(_client());
    final contexts = <PandoraCoreRecord>[];
    await _mount(tester, gateway,
        section: 'clients', onContextChanged: contexts.add);
    expect(contexts.last, <String, dynamic>{'coreSection': 'clients'});

    await _tap(
        tester, find.byKey(const ValueKey('core-manage-$_northClientId')));
    expect(contexts.last, <String, dynamic>{
      'coreSection': 'client',
      'organizationId': _northClientId,
    });
    await _tap(tester, find.byKey(const ValueKey('core-back')));
    expect(contexts.last, <String, dynamic>{'coreSection': 'clients'});
    expect(contexts.last.containsKey('organizationId'), isFalse);
    expect(gateway.operations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home uses current platform totals and meaningful work records',
      (tester) async {
    final data = _snapshot();
    data['health'] = <String, dynamic>{
      'clients': 47,
      'active_clients': 43,
      'attention_clients': 2,
      'connections': 79,
      'connections_healthy': 77,
      'devices': 23,
      'incidents': 1,
      'state': 'attention',
    };
    data['needs_you'] = <PandoraCoreRecord>[
      <String, dynamic>{
        'id': 'decision-1',
        'kind': 'connection',
        'organization_id': _southClientId,
        'client_name': 'Harbor Logistics',
        'title': 'Authorize Harbor connection renewal',
        'why': 'The accounting connection needs a new authorization.',
        'risk': 'medium',
        'action': 'review',
        'evidence': <String, dynamic>{'verified_at': '2026-10-03T04:00:00Z'},
      },
    ];
    data['handling'] = <PandoraCoreRecord>[
      <String, dynamic>{
        'id': 'job-1',
        'organization_id': _northClientId,
        'title': 'Verify Northwind device enrollment',
        'state': 'running',
        'updated_at': '2026-10-03T04:00:00Z',
      },
    ];
    data['outcomes'] = <PandoraCoreRecord>[
      <String, dynamic>{
        'id': 'outcome-1',
        'title': 'Northwind administrator access updated',
        'organization_id': _northClientId,
        'occurred_at': '2026-10-03T03:30:00Z',
        'outcome': 'verified',
      },
    ];
    final gateway = _FakeCoreGateway()..data = data;
    await _mount(tester, gateway);

    expect(find.text('Pandora'), findsWidgets);
    expect(find.textContaining('47'), findsWidgets,
        reason: 'The total comes from the live aggregate, not a Dart list.');
    expect(find.textContaining('43'), findsWidgets);
    for (final title in <String>[
      'Authorize Harbor connection renewal',
      'Verify Northwind device enrollment',
      'Northwind administrator access updated',
    ]) {
      await tester.scrollUntilVisible(
        find.text(title),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
    }
    expect(find.textContaining('Tax & Compliance'), findsNothing);
    expect(find.textContaining('987654321'), findsNothing);
    expect(find.text('Platform healthy'), findsNothing);
    expect(gateway.snapshots.single.section, 'home');
    expect(gateway.operations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Clients is the current server registry without customer KPIs', (
    tester,
  ) async {
    final gateway = _FakeCoreGateway()
      ..data = _snapshot(
        clients: <PandoraCoreRecord>[
          _client(),
          _client(id: _southClientId, name: 'Harbor Logistics'),
        ],
      );
    await _mount(tester, gateway, section: 'clients');

    expect(find.text('Northwind Guest House'), findsOneWidget);
    expect(find.text('Harbor Logistics'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('core-client-$_northClientId')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('core-client-$_southClientId')),
      findsOneWidget,
    );
    expect(find.text('PLP Boracay'), findsNothing);
    expect(find.text('1064 Euro-Fish Traders'), findsNothing);
    expect(find.text('BOK'), findsNothing);
    expect(find.text('Marketing & Growth'), findsNothing);
    expect(find.textContaining('Tax & Compliance'), findsNothing);
    expect(find.textContaining('987654321'), findsNothing);
    expect(find.textContaining('123456789'), findsNothing);
    expect(find.textContaining('Occupancy'), findsNothing);
    expect(find.textContaining('Hearings'), findsNothing);
    expect(gateway.snapshots.single.section, 'clients');
    expect(gateway.snapshots.single.organizationId, isNull);
    expect(gateway.operations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'workspace entry identifies the selected server client explicitly',
    (tester) async {
      final gateway = _FakeCoreGateway()
        ..data = _snapshot(
          clients: <PandoraCoreRecord>[
            _client(),
            _client(id: _southClientId, name: 'Harbor Logistics'),
          ],
        );
      final entered = <PandoraCoreRecord>[];
      await _mount(
        tester,
        gateway,
        section: 'clients',
        onEnterClient: (client) async => entered.add(client),
      );

      await _tap(
        tester,
        find.byKey(const ValueKey('core-enter-$_southClientId')),
      );

      expect(entered, hasLength(1));
      expect(entered.single['organization_id'], _southClientId);
      expect(entered.single['display_name'], 'Harbor Logistics');
      expect(gateway.operations, isEmpty);
      expect(
        gateway.entries,
        isEmpty,
        reason: 'The shell owns authorization and the tenant transition.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Manage client stays in Core and back returns to the registry',
      (tester) async {
    final gateway = _FakeCoreGateway()
      ..onSnapshot = (request) async =>
          request.section == 'client' ? _clientDetail(_client()) : _snapshot();
    final entered = <PandoraCoreRecord>[];
    await _mount(tester, gateway,
        section: 'clients',
        onEnterClient: (client) async => entered.add(client));

    await _tap(
        tester, find.byKey(const ValueKey('core-manage-$_northClientId')));

    expect(gateway.snapshots.last.section, 'client');
    expect(gateway.snapshots.last.organizationId, _northClientId);
    expect(find.text('Northwind Guest House'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
    expect(entered, isEmpty,
        reason: 'Managing a client must not enter the customer workspace.');

    await _tap(tester, find.byKey(const ValueKey('core-back')));

    expect(gateway.snapshots.last.section, 'clients');
    expect(gateway.snapshots.last.organizationId, isNull);
    expect(find.byKey(const ValueKey('core-manage-$_northClientId')),
        findsOneWidget);
    expect(entered, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace entry stays disabled without verified client access',
      (tester) async {
    final gateway = _FakeCoreGateway()
      ..data = _snapshot(clients: <PandoraCoreRecord>[
        _client(canEnter: false),
      ]);
    var entryCalls = 0;
    await _mount(tester, gateway,
        section: 'clients', onEnterClient: (_) async => entryCalls++);

    final entry = find.byKey(const ValueKey('core-enter-$_northClientId'));
    final button = tester.widget<TextButton>(entry);
    expect(button.onPressed, isNull);
    await _tap(tester, entry);

    expect(entryCalls, 0);
    expect(find.byKey(const ValueKey('core-manage-$_northClientId')),
        findsOneWidget);
    expect(gateway.operations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a client response for a different organization is rejected',
      (tester) async {
    final gateway = _FakeCoreGateway()
      ..data =
          _clientDetail(_client(id: _southClientId, name: 'Harbor Logistics'));
    await _mount(tester, gateway,
        section: 'client', organizationId: _northClientId);

    expect(gateway.snapshots.single.organizationId, _northClientId);
    expect(find.text('Harbor Logistics'), findsNothing);
    expect(
        find.text(
            'Pandora could not verify this client. Return to Clients and refresh.'),
        findsOneWidget);
    expect(find.text('Edit client'), findsNothing);
    expect(gateway.operations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty registry stays empty and still offers registration',
      (tester) async {
    final gateway = _FakeCoreGateway()
      ..data = _snapshot(clients: <PandoraCoreRecord>[]);
    await _mount(tester, gateway, section: 'clients');

    expect(find.byKey(const ValueKey('core-add-client')), findsOneWidget);
    expect(find.text('Manage client'), findsNothing);
    expect(find.text('Enter client workspace'), findsNothing);
    expect(find.text('PLP Boracay'), findsNothing);
    expect(find.text('BOK'), findsNothing);
    expect(gateway.operations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late client snapshot cannot overwrite a newer organization',
      (tester) async {
    final delayedNorth = Completer<PandoraCoreRecord>();
    PandoraCoreRecord detail(PandoraCoreRecord client) => <String, dynamic>{
          ..._snapshot(clients: <PandoraCoreRecord>[]),
          'client': client,
          'onboarding': <PandoraCoreRecord>[],
          'members': <PandoraCoreRecord>[],
          'connections': <PandoraCoreRecord>[],
          'devices': <PandoraCoreRecord>[],
          'usage': <PandoraCoreRecord>[],
          'deployments': <PandoraCoreRecord>[],
          'cases': <PandoraCoreRecord>[],
          'contracts': <PandoraCoreRecord>[],
          'subscription': null,
        };
    final gateway = _FakeCoreGateway()
      ..onSnapshot = (request) => request.organizationId == _northClientId
          ? delayedNorth.future
          : Future<PandoraCoreRecord>.value(detail(
              _client(id: _southClientId, name: 'Harbor Logistics'),
            ));
    await setTestSurface(tester, logicalSize: const Size(390, 844));

    Widget page(String organizationId) => testApp(
          child: PandoraCoreScreen(
            gateway: gateway,
            section: 'client',
            organizationId: organizationId,
          ),
        );

    await tester.pumpWidget(page(_northClientId));
    await tester.pump();
    expect(gateway.snapshots.single.organizationId, _northClientId);

    await tester.pumpWidget(page(_southClientId));
    await tester.pumpAndSettle();
    expect(gateway.snapshots.last.organizationId, _southClientId);
    expect(find.text('Harbor Logistics'), findsWidgets);

    delayedNorth.complete(detail(_client()));
    await tester.pumpAndSettle();

    expect(find.text('Harbor Logistics'), findsWidgets);
    expect(find.text('Northwind Guest House'), findsNothing,
        reason: 'An old tenant request must not replace the current tenant.');
    expect(gateway.operations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an unavailable owner snapshot can be retried without fake clients',
    (tester) async {
      final gateway = _FakeCoreGateway()
        ..onSnapshot = (_) async => throw const PandoraCoreFailure(
              'UNAVAILABLE',
              'Pandora could not connect. Check your connection and try again.',
            );
      await _mount(tester, gateway);

      expect(
        find.text(
          'Pandora could not connect. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('PLP Boracay'), findsNothing);
      expect(find.text('1064 Euro-Fish Traders'), findsNothing);
      expect(find.text('Platform healthy'), findsNothing);

      gateway.onSnapshot = null;
      await _tap(tester, find.byKey(const ValueKey('core-refresh')));

      expect(gateway.snapshots, hasLength(2));
      expect(find.textContaining('Pandora could not connect.'), findsNothing);
      expect(gateway.operations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a revoked read hides previously loaded owner information',
      (tester) async {
    final gateway = _FakeCoreGateway()..data = _snapshot();
    await _mount(tester, gateway, section: 'clients');
    expect(find.text('Northwind Guest House'), findsOneWidget);

    gateway.onSnapshot = (_) async => throw const PandoraCoreFailure(
          'ACCESS_DENIED',
          'Your account is not authorized for this action.',
        );
    await _tap(tester, find.byKey(const ValueKey('core-refresh')));

    expect(find.text('Northwind Guest House'), findsNothing);
    expect(find.text('Manage client'), findsNothing);
    expect(find.text('Your account is not authorized for this action.'),
        findsOneWidget);
    expect(gateway.operations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unexpected snapshot errors do not expose internal details',
      (tester) async {
    final gateway = _FakeCoreGateway()
      ..onSnapshot = (_) async =>
          throw StateError('internal_database_detail_do_not_display');
    await _mount(tester, gateway);

    expect(find.textContaining('internal_database_detail'), findsNothing);
    expect(find.byKey(const ValueKey('core-refresh')), findsOneWidget);
    expect(find.text('Manage client'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final section in <String>['home', 'clients']) {
    testWidgets('$section remains usable on a small screen with larger text',
        (tester) async {
      final gateway = _FakeCoreGateway()
        ..data = _snapshot(clients: <PandoraCoreRecord>[
          _client(name: 'Northwind Guest House and Conference Center'),
          _client(
            id: _southClientId,
            name: 'Harbor Import and Export Logistics',
            health: 'attention',
          ),
        ]);
      await _mount(
        tester,
        gateway,
        section: section,
        size: const Size(320, 640),
        textScale: 1.6,
      );

      expect(tester.takeException(), isNull);
      for (var scroll = 0; scroll < 4; scroll++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -420));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason:
                'All owner sections must lay out within the mobile viewport.');
      }
      expect(gateway.operations, isEmpty);
    });
  }

  testWidgets(
      'registration submits once and opens the created client onboarding',
      (tester) async {
    final pending = Completer<PandoraCoreRecord>();
    final gateway = _FakeCoreGateway()
      ..onSnapshot = (request) async => request.section == 'client'
          ? _clientDetail(<String, dynamic>{
              ..._client(name: 'Mistral Hotel', canEnter: false),
              'lifecycle_state': 'onboarding',
              'onboarding_state': 'in_progress',
            })
          : _snapshot(clients: <PandoraCoreRecord>[]);
    gateway.onOperate = (_) => pending.future;
    await _mount(tester, gateway, section: 'clients');

    await _tap(tester, find.byKey(const ValueKey('core-add-client')));
    await _fillRegistration(tester);
    await _tap(tester, find.byKey(const ValueKey('core-submit')));

    expect(gateway.operations, hasLength(1));
    final request = gateway.operations.single;
    expect(request.operation, 'client.register');
    expect(request.organizationId, isNull);
    expect(request.payload, <String, dynamic>{
      'name': 'Mistral Hotel',
      'slug': 'mistral-hotel',
      'industry': 'hospitality',
      'workspace_type': 'plp',
      'primary_contact_name': 'Ada Owner',
      'primary_contact_email': 'ada@example.invalid',
    });
    expect(
        request.idempotencyKey,
        matches(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'));
    await tester.tap(find.byKey(const ValueKey('core-submit')));
    await tester.pump();
    expect(gateway.operations, hasLength(1),
        reason: 'Repeated taps must not start another tenant registration.');

    pending.complete(<String, dynamic>{
      'organization_id': _northClientId,
      'next_action': 'Complete the required onboarding steps.',
    });
    await tester.pumpAndSettle();

    expect(gateway.snapshots.last.section, 'client');
    expect(gateway.snapshots.last.organizationId, _northClientId);
    expect(find.text('Mistral Hotel'), findsOneWidget);
    expect(find.text('Verify onboarding'), findsOneWidget);
    expect(find.text('Create client'), findsNothing);
    expect(gateway.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retry after an uncertain registration result reuses its request',
      (tester) async {
    final gateway = _FakeCoreGateway()
      ..onSnapshot = (request) async => request.section == 'client'
          ? _clientDetail(_client(name: 'Mistral Hotel', canEnter: false))
          : _snapshot(clients: <PandoraCoreRecord>[]);
    gateway.onOperate = (request) async {
      if (gateway.operations.length == 1) {
        throw StateError('simulated_lost_response_after_server_commit');
      }
      return <String, dynamic>{'organization_id': _northClientId};
    };
    await _mount(tester, gateway, section: 'clients');

    await _tap(tester, find.byKey(const ValueKey('core-add-client')));
    await _fillRegistration(tester);
    await _tap(tester, find.byKey(const ValueKey('core-submit')));

    expect(gateway.operations, hasLength(1));
    expect(find.textContaining('simulated_lost_response'), findsNothing);
    expect(find.textContaining('same request'), findsOneWidget);
    expect(find.byType(PandoraCoreOperationForm), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('core-submit')));

    expect(gateway.operations, hasLength(2));
    expect(gateway.operations[1].idempotencyKey,
        gateway.operations[0].idempotencyKey);
    expect(gateway.operations[1].payload, gateway.operations[0].payload);
    expect(find.text('Mistral Hotel'), findsOneWidget);
    expect(find.byType(PandoraCoreOperationForm), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('incomplete registration cannot create an ambiguous client',
      (tester) async {
    final gateway = _FakeCoreGateway();
    await _mount(tester, gateway, section: 'clients');

    await _tap(tester, find.byKey(const ValueKey('core-add-client')));
    await _tap(tester, find.text('Create client'));

    expect(find.widgetWithText(TextFormField, 'Business name'), findsOneWidget);
    expect(gateway.operations, isEmpty);
    expect(gateway.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('canceling client registration performs no provisioning write', (
    tester,
  ) async {
    final gateway = _FakeCoreGateway();
    await _mount(tester, gateway, section: 'clients');

    await _tap(tester, find.byKey(const ValueKey('core-add-client')));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Business name'),
      'Unsubmitted customer',
    );
    await _tap(tester, find.text('Cancel'));

    expect(find.text('Create client'), findsNothing);
    expect(gateway.operations, isEmpty);
    expect(gateway.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
