import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/pandora_core_api.dart';
import 'package:pandora_mobile/features/core/pandora_core_screen.dart';

import '../../helpers/test_app.dart';

const _northClientId = '11111111-1111-4111-8111-111111111111';
const _southClientId = '22222222-2222-4222-8222-222222222222';
const _planId = '33333333-3333-4333-8333-333333333333';
const _subscriptionId = '44444444-4444-4444-8444-444444444444';
const _incidentId = '55555555-5555-4555-8555-555555555555';
const _prospectId = '66666666-6666-4666-8666-666666666666';
const _caseId = '77777777-7777-4777-8777-777777777777';
const _currentAssigneeId = '88888888-8888-4888-8888-888888888888';
const _availableAssigneeId = '99999999-9999-4999-8999-999999999999';

PandoraCoreRecord _plan() => <String, dynamic>{
      'id': _planId,
      'code': 'managed-growth',
      'name': 'Managed Growth',
      'state': 'active',
      'currency': 'PHP',
      'monthly_fee_micros': 1250000000,
      'request_admission_policy': 'block',
      'limits': <String, dynamic>{'monthly_requests': 4000},
    };

PandoraCoreRecord _commercialClient() => <String, dynamic>{
      ..._clientDetail(_client()),
      'plans': <PandoraCoreRecord>[_plan()],
      'subscription': <String, dynamic>{
        'id': _subscriptionId,
        'organization_id': _northClientId,
        'plan_id': _planId,
        'state': 'active',
        'currency': 'PHP',
        'monthly_fee_micros': 1250000000,
        'request_admission_enabled': false,
        'request_admission_started_at': '2026-10-01T00:00:00Z',
      },
    };

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

Future<Finder> _coreField(WidgetTester tester, String key) async {
  final field = find.byKey(ValueKey('core-field-$key'));
  final scroll = find
      .descendant(
        of: find.byType(PandoraCoreOperationForm),
        matching: find.byType(Scrollable),
      )
      .first;
  final position = tester.state<ScrollableState>(scroll).position;
  position.jumpTo(position.minScrollExtent);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(field, 200, scrollable: scroll);
  await tester.pumpAndSettle();
  return field;
}

Future<void> _enterCoreField(
    WidgetTester tester, String key, String value) async {
  final field = await _coreField(tester, key);
  await tester.enterText(field, value);
  await tester.pump();
}

Future<String> _chooseCoreField(
    WidgetTester tester, String key, String value) async {
  final field = await _coreField(tester, key);
  final dropdown = _renderedDropdown(tester, field);
  final option = dropdown.items!.singleWhere((item) => item.value == value);
  final label = (option.child as Text).data!;
  await _tap(tester, field);
  await _tap(tester, find.text(label).last);
  return label;
}

DropdownButton<String> _renderedDropdown(WidgetTester tester, Finder field) =>
    tester.widget<DropdownButton<String>>(find.descendant(
      of: field,
      matching: find.byType(DropdownButton<String>),
    ));

Future<void> _submitCoreForm(WidgetTester tester) async {
  final submit = find.byKey(const ValueKey('core-submit'));
  final scroll = find
      .descendant(
        of: find.byType(PandoraCoreOperationForm),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(submit, 240, scrollable: scroll);
  await _tap(tester, submit);
}

Future<void> _commercialDecision(WidgetTester tester, String label) => _tap(
      tester,
      find.descendant(of: find.byType(AlertDialog), matching: find.text(label)),
    );

Future<void> _openClientSubscription(
    WidgetTester tester, _FakeCoreGateway gateway) async {
  gateway.onSnapshot = (request) async =>
      request.organizationId == null ? _snapshot() : _commercialClient();
  await _mount(tester, gateway, section: 'clients', size: const Size(360, 740));
  await _tap(tester, find.byKey(const ValueKey('core-manage-$_northClientId')));
  await _tap(tester, find.text('Commercial'));
  await _tap(tester, find.text('Set subscription'));
}

PandoraCoreRecord _incidentSnapshot() => <String, dynamic>{
      ..._snapshot(),
      'incidents': <PandoraCoreRecord>[
        <String, dynamic>{
          'id': _incidentId,
          'organization_id': _northClientId,
          'title': 'Northwind connection interrupted',
          'severity': 'high',
          'state': 'investigating',
          'impact': 'New customer requests cannot reach the provider.',
          'diagnosis': 'The connected provider timed out.',
        },
      ],
    };

Future<void> _openIncident(
    WidgetTester tester, _FakeCoreGateway gateway) async {
  gateway.data = _incidentSnapshot();
  await _mount(tester, gateway, section: 'administration');
  await _tap(tester, find.text('Incidents'));
  await _tap(tester, find.text('Northwind connection interrupted'));
  expect(find.text('Update incident'), findsOneWidget);
}

PandoraCoreRecord _supportCase({String kind = 'access'}) => <String, dynamic>{
      'id': _caseId,
      'organization_id': _northClientId,
      'subject': 'Review Northwind access request',
      'kind': kind,
      'priority': 'low',
      'assigned_user_id': _currentAssigneeId,
      'description': 'Review the access needed for the reception team.',
      'state': 'open',
      'needs_owner': true,
      'due_at': '2026-10-15',
    };

Future<void> _openSupportCase(
  WidgetTester tester,
  _FakeCoreGateway gateway, {
  String kind = 'access',
  List<PandoraCoreRecord> members = const [],
}) async {
  gateway.data = <String, dynamic>{
    ..._clientDetail(_client()),
    'cases': <PandoraCoreRecord>[_supportCase(kind: kind)],
    'members': members,
  };
  await _mount(tester, gateway,
      section: 'client',
      organizationId: _northClientId,
      size: const Size(360, 740));
  await _tap(tester, find.text('Support'));
  await _tap(tester, find.text('Review Northwind access request'));
  expect(find.byType(PandoraCoreOperationForm), findsOneWidget);
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
  for (final kind in ['access', 'training']) {
    testWidgets(
        'editing a $kind case retains its low priority and existing assignee',
        (tester) async {
      final gateway = _FakeCoreGateway();
      await _openSupportCase(tester, gateway, kind: kind);
      final kindField = await _coreField(tester, 'kind');
      expect(_renderedDropdown(tester, kindField).value, kind);
      final priority = await _coreField(tester, 'priority');
      expect(_renderedDropdown(tester, priority).value, 'low');
      final assignee = await _coreField(tester, 'assigned_user_id');
      expect(_renderedDropdown(tester, assignee).value, _currentAssigneeId);
      expect(find.text('Current assignee (unchanged)'), findsOneWidget);

      await _enterCoreField(
          tester, 'subject', 'Reviewed Northwind reception access');
      await _submitCoreForm(tester);
      final request = gateway.operations.single;
      expect(request.operation, 'case.save');
      expect(request.organizationId, _northClientId);
      expect(request.payload['id'], _caseId);
      expect(request.payload['subject'], 'Reviewed Northwind reception access');
      expect(request.payload['kind'], kind);
      expect(request.payload['priority'], 'low');
      expect(request.payload['assigned_user_id'], _currentAssigneeId);
      expect(request.payload['needs_owner'], isTrue);
      expect(request.payload['state'], 'open');
      expect(request.payload['description'],
          'Review the access needed for the reception team.');
      expect(gateway.entries, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cancelling a case edit does not save changed classification',
      (tester) async {
    final gateway = _FakeCoreGateway();
    await _openSupportCase(tester, gateway);
    await _chooseCoreField(tester, 'kind', 'training');
    await _chooseCoreField(tester, 'priority', 'high');
    await _enterCoreField(tester, 'subject', 'Unsubmitted support changes');
    await tester.scrollUntilVisible(find.text('Cancel'), 240,
        scrollable: find
            .descendant(
              of: find.byType(PandoraCoreOperationForm),
              matching: find.byType(Scrollable),
            )
            .first);
    await _tap(tester, find.text('Cancel'));
    expect(gateway.operations, isEmpty);
    expect(find.byType(PandoraCoreOperationForm), findsNothing);
    expect(find.text('Review Northwind access request'), findsOneWidget);
    expect(find.text('Unsubmitted support changes'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uncertain case save retries the same assignment and payload',
      (tester) async {
    final gateway = _FakeCoreGateway();
    gateway.onOperate = (request) async {
      if (gateway.operations.length == 1) {
        throw StateError('PRIVATE_CASE_TRANSPORT_DETAILS');
      }
      return <String, dynamic>{
        'organization_id': _northClientId,
        'id': _caseId,
      };
    };
    await _openSupportCase(tester, gateway, kind: 'training');
    await _enterCoreField(
        tester, 'description', 'Confirmed the reception training time.');
    await _submitCoreForm(tester);
    expect(gateway.operations, hasLength(1));
    expect(find.textContaining('same request'), findsOneWidget);
    expect(find.textContaining('PRIVATE_CASE_TRANSPORT_DETAILS'), findsNothing);
    await _submitCoreForm(tester);
    expect(gateway.operations, hasLength(2));
    final first = gateway.operations.first;
    final retry = gateway.operations.last;
    expect(first.operation, 'case.save');
    expect(first.organizationId, _northClientId);
    expect(first.payload['id'], _caseId);
    expect(first.payload['assigned_user_id'], _currentAssigneeId);
    expect(first.payload['kind'], 'training');
    expect(first.payload['priority'], 'low');
    expect(
        first.payload['description'], 'Confirmed the reception training time.');
    expect(first.idempotencyKey, isNotEmpty);
    expect(retry.idempotencyKey, first.idempotencyKey);
    expect(retry.organizationId, first.organizationId);
    expect(retry.payload, first.payload);
    expect(find.byType(PandoraCoreOperationForm), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'rejected case assignee can be explicitly cleared before resubmitting',
      (tester) async {
    final gateway = _FakeCoreGateway();
    gateway.onOperate = (request) async {
      if (gateway.operations.length == 1) {
        throw PandoraCoreFailure.fromServer('22023', 'ASSIGNEE_NOT_AUTHORIZED');
      }
      return <String, dynamic>{
        'organization_id': _northClientId,
        'id': _caseId,
      };
    };
    await _openSupportCase(tester, gateway);
    await _submitCoreForm(tester);
    expect(gateway.operations, hasLength(1));
    expect(gateway.operations.single.payload['assigned_user_id'],
        _currentAssigneeId);
    expect(find.text('Choose an active client member or clear the assignment.'),
        findsOneWidget);
    expect(find.textContaining('ASSIGNEE_NOT_AUTHORIZED'), findsNothing);
    await _chooseCoreField(tester, 'assigned_user_id', '');
    await _submitCoreForm(tester);
    expect(gateway.operations, hasLength(2));
    final corrected = gateway.operations.last;
    expect(corrected.operation, 'case.save');
    expect(corrected.organizationId, _northClientId);
    expect(corrected.payload['id'], _caseId);
    expect(corrected.payload.containsKey('assigned_user_id'), isFalse,
        reason: 'The existing RPC treats explicit Unassigned as clearing it.');
    expect(corrected.payload['kind'], 'access');
    expect(corrected.payload['priority'], 'low');
    expect(find.byType(PandoraCoreOperationForm), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'case assignment offers active client members and excludes foreign or inactive users',
      (tester) async {
    const inactiveId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaab';
    const foreignId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaac';
    const scopedProjectionId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaad';
    final gateway = _FakeCoreGateway();
    await _openSupportCase(tester, gateway, members: [
      <String, dynamic>{
        'user_id': _availableAssigneeId,
        'organization_id': _northClientId,
        'name': 'Northwind active teammate',
        'status': 'active',
      },
      <String, dynamic>{
        'user_id': scopedProjectionId,
        'name': 'Member from the scoped client projection',
        'status': 'active',
      },
      <String, dynamic>{
        'user_id': inactiveId,
        'organization_id': _northClientId,
        'name': 'Suspended Northwind user',
        'status': 'suspended',
      },
      <String, dynamic>{
        'user_id': foreignId,
        'organization_id': _southClientId,
        'name': 'Foreign client user',
        'status': 'active',
      },
    ]);
    final assignee = await _coreField(tester, 'assigned_user_id');
    final available = _renderedDropdown(tester, assignee)
        .items!
        .map((item) => item.value)
        .toList();
    expect(available, contains(_currentAssigneeId));
    expect(available, contains(_availableAssigneeId));
    expect(available, contains(scopedProjectionId));
    expect(available, isNot(contains(inactiveId)));
    expect(available, isNot(contains(foreignId)));
    expect(_renderedDropdown(tester, assignee).value, _currentAssigneeId);
    await _chooseCoreField(tester, 'assigned_user_id', _availableAssigneeId);
    expect(gateway.operations, isEmpty,
        reason: 'Selecting an assignee alone must not send a write.');
    await _submitCoreForm(tester);
    final request = gateway.operations.single;
    expect(request.operation, 'case.save');
    expect(request.organizationId, _northClientId);
    expect(request.payload['id'], _caseId);
    expect(request.payload['assigned_user_id'], _availableAssigneeId);
    expect(request.payload['kind'], 'access');
    expect(request.payload['priority'], 'low');
    expect(gateway.snapshots.every((r) => r.organizationId == _northClientId),
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'client card access request requires a reason and cancel does not change authority',
      (tester) async {
    final clientWithoutEntryProof =
        _client(id: _southClientId, name: 'Harbor Logistics', canEnter: false)
          ..remove('can_enter');
    final gateway = _FakeCoreGateway()
      ..data = _snapshot(clients: [_client(), clientWithoutEntryProof]);
    final entered = <PandoraCoreRecord>[];
    await _mount(tester, gateway,
        section: 'clients',
        size: const Size(360, 740),
        onEnterClient: (client) async => entered.add(client));
    expect(find.byKey(const ValueKey('core-request-access-$_northClientId')),
        findsNothing);
    await _tap(tester,
        find.byKey(const ValueKey('core-request-access-$_southClientId')));
    expect(find.byType(PandoraCoreOperationForm), findsOneWidget);
    await _submitCoreForm(tester);
    expect(gateway.operations, isEmpty,
        reason: 'An unexplained request must not reach the server.');
    expect(find.byType(PandoraCoreOperationForm), findsOneWidget);
    await _enterCoreField(
        tester, 'reason', 'Investigate the Harbor support escalation.');
    await _tap(tester, find.text('Cancel'));
    expect(find.byType(PandoraCoreOperationForm), findsNothing);
    expect(gateway.operations, isEmpty);
    expect(gateway.entries, isEmpty);
    expect(entered, isEmpty);
    expect(
        tester
            .widget<TextButton>(
                find.byKey(const ValueKey('core-enter-$_southClientId')))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'client detail access request stays pending and never locally enables entry',
      (tester) async {
    final pending = Completer<PandoraCoreRecord>();
    final gateway = _FakeCoreGateway()
      ..data = _clientDetail(_client(
          id: _southClientId, name: 'Harbor Logistics', canEnter: false));
    gateway.onOperate = (_) => pending.future;
    final entered = <PandoraCoreRecord>[];
    await _mount(tester, gateway,
        section: 'client',
        organizationId: _southClientId,
        onEnterClient: (client) async => entered.add(client));
    final enter = find.widgetWithText(OutlinedButton, 'Enter client workspace');
    expect(tester.widget<OutlinedButton>(enter).onPressed, isNull);
    await _tap(tester,
        find.byKey(const ValueKey('core-request-access-$_southClientId')));
    await _enterCoreField(tester, 'reason',
        'Review the failed Harbor connection with customer approval.');
    await _submitCoreForm(tester);
    expect(gateway.operations, hasLength(1));
    final request = gateway.operations.single;
    expect(request.operation, 'access.request');
    expect(request.organizationId, _southClientId);
    expect(request.payload, <String, dynamic>{
      'reason': 'Review the failed Harbor connection with customer approval.'
    });
    expect(request.idempotencyKey, isNotEmpty);
    expect(entered, isEmpty);
    expect(gateway.entries, isEmpty);
    pending.complete(<String, dynamic>{
      'organization_id': _southClientId,
      'request_id': '77777777-7777-4777-8777-777777777777',
      'state': 'pending',
    });
    await tester.pumpAndSettle();
    expect(find.byType(PandoraCoreOperationForm), findsNothing);
    expect(find.textContaining(RegExp('pending review', caseSensitive: false)),
        findsOneWidget);
    expect(gateway.snapshots, hasLength(2));
    expect(
        gateway.snapshots.every((read) =>
            read.section == 'client' && read.organizationId == _southClientId),
        isTrue);
    expect(tester.widget<OutlinedButton>(enter).onPressed, isNull);
    expect(find.byKey(const ValueKey('core-request-access-$_southClientId')),
        findsOneWidget);
    expect(gateway.operations.map((operation) => operation.operation),
        ['access.request']);
    expect(gateway.entries, isEmpty);
    expect(entered, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'missing admission counts and coverage dates remain Unknown in readback',
      (tester) async {
    final gateway = _FakeCoreGateway()
      ..data = <String, dynamic>{
        ..._snapshot(),
        'usage_allowances': <PandoraCoreRecord>[
          <String, dynamic>{
            'title': 'Northwind request allowance',
            'organization_id': _northClientId,
            'request_admission_enabled': false,
            'requests_admitted': null,
            'requests_remaining': null,
            'request_admission_started_at': null,
            'request_effective_from': null,
            'request_window_start': null,
            'request_reset_at': null,
          },
        ],
      };
    await _mount(tester, gateway, section: 'business');
    await _tap(tester, find.text('Usage & Costs'));
    await _tap(tester, find.text('Northwind request allowance'));
    final sheet = find.byType(BottomSheet);
    final scroll =
        find.descendant(of: sheet, matching: find.byType(Scrollable)).first;
    for (final label in <String>[
      'Admitted cloud-chat requests',
      'Requests remaining',
      'First enabled (UTC)',
      'Counting from (UTC)',
      'Window starts (UTC)',
      'Resets (UTC)',
    ]) {
      final line = find.descendant(of: sheet, matching: find.text(label));
      final position = tester.state<ScrollableState>(scroll).position;
      position.jumpTo(position.minScrollExtent);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(line, 160, scrollable: scroll);
      final row = find.ancestor(of: line, matching: find.byType(Row)).first;
      expect(find.descendant(of: row, matching: find.text('Unknown')),
          findsOneWidget,
          reason: label);
    }
    expect(find.descendant(of: sheet, matching: find.text('0')), findsNothing);
    expect(gateway.operations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'quota decision opens the exact client Commercial tab without a mutation',
      (tester) async {
    final owner = <String, dynamic>{
      ..._snapshot(clients: [
        _client(),
        _client(id: _southClientId, name: 'Harbor Logistics')
      ]),
      'needs_you': <PandoraCoreRecord>[
        <String, dynamic>{
          'id': 'quota-harbor',
          'kind': 'usage_allowance',
          'organization_id': _southClientId,
          'client_name': 'Harbor Logistics',
          'title': 'Harbor cloud-chat request allowance reached',
          'why': 'Review the customer request allowance.',
          'risk': 'medium',
          'action': 'open_client_commercial',
        },
      ],
    };
    final gateway = _FakeCoreGateway()
      ..onSnapshot = (request) async => request.organizationId == null
          ? owner
          : _clientDetail(
              _client(id: request.organizationId!, name: 'Harbor Logistics'));
    await _mount(tester, gateway);
    await _tap(
        tester, find.text('Harbor cloud-chat request allowance reached'));
    await _tap(tester, find.text('Open action'));
    expect(gateway.snapshots.last.section, 'client');
    expect(gateway.snapshots.last.organizationId, _southClientId);
    expect(find.text('Harbor Logistics'), findsOneWidget);
    expect(find.text('Set subscription'), findsOneWidget);
    expect(find.byType(PandoraCoreOperationForm), findsNothing);
    expect(gateway.operations, isEmpty);
    expect(gateway.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'new plan defaults to recording requests and cancel does not save',
      (tester) async {
    final gateway = _FakeCoreGateway()..data = _snapshot();
    await _mount(tester, gateway,
        section: 'business', size: const Size(360, 740));
    await _tap(tester, find.text('Plans'));
    await _tap(tester, find.text('Create plan'));
    expect(find.textContaining('Only cloud-chat request blocking is enforced'),
        findsOneWidget);
    final policy = await _coreField(tester, 'request_admission_policy');
    expect(tester.widget<DropdownButtonFormField<String>>(policy).initialValue,
        'record_only');
    final overage = await _coreField(tester, 'overage_policy');
    final overageLabels = _renderedDropdown(tester, overage)
        .items!
        .map((item) => (item.child as Text).data)
        .toList();
    expect(overageLabels, isNot(contains('Block overage')));
    expect(find.byType(PandoraCoreOperationForm), findsOneWidget);
    await _tap(tester, find.text('Cancel'));
    expect(gateway.operations, isEmpty);
    expect(find.byType(PandoraCoreOperationForm), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'request-blocking plan saves the request ceiling only after commercial confirmation',
      (tester) async {
    final gateway = _FakeCoreGateway()..data = _snapshot();
    await _mount(tester, gateway,
        section: 'business', size: const Size(360, 740));
    await _tap(tester, find.text('Plans'));
    await _tap(tester, find.text('Create plan'));
    await _enterCoreField(tester, 'code', 'managed-growth');
    await _enterCoreField(tester, 'name', 'Managed Growth');
    await _enterCoreField(tester, 'monthly_fee_micros', '1250.00');
    await _enterCoreField(tester, 'limits.monthly_requests', '4000');
    final policyLabel =
        await _chooseCoreField(tester, 'request_admission_policy', 'block');
    await _submitCoreForm(tester);
    expect(find.text('Confirm commercial record'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining(policyLabel)),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining('4000')),
        findsOneWidget);
    expect(gateway.operations, isEmpty);
    await _commercialDecision(tester, 'Confirm');
    final request = gateway.operations.single;
    expect(request.operation, 'plan.save');
    expect(request.organizationId, isNull);
    expect(request.payload['code'], 'managed-growth');
    expect(request.payload['name'], 'Managed Growth');
    expect(request.payload['monthly_fee_micros'], 1250000000);
    expect(request.payload['request_admission_policy'], 'block');
    expect(
        request.payload['limits'], <String, dynamic>{'monthly_requests': 4000});
    expect(request.idempotencyKey, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'client request admission needs explicit enable and confirmation can be cancelled',
      (tester) async {
    final gateway = _FakeCoreGateway();
    await _openClientSubscription(tester, gateway);
    final admission = await _coreField(tester, 'request_admission_enabled');
    expect(
        tester.widget<DropdownButtonFormField<String>>(admission).initialValue,
        'false');
    expect(find.byKey(const ValueKey('core-field-started_at')), findsNothing);
    expect(
        find.byKey(const ValueKey('core-field-request_admission_started_at')),
        findsNothing);
    await _chooseCoreField(tester, 'request_admission_enabled', 'true');
    await _submitCoreForm(tester);
    expect(find.text('Confirm commercial record'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Northwind Guest House')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Apply cloud-chat request limit: On')),
        findsOneWidget);
    expect(gateway.operations, isEmpty);
    await _commercialDecision(tester, 'Cancel');
    expect(gateway.operations, isEmpty);
    expect(find.byType(PandoraCoreOperationForm), findsOneWidget);
    await _tap(tester, find.text('Cancel'));
    expect(gateway.operations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'uncertain subscription update retries the same explicit admission request',
      (tester) async {
    final gateway = _FakeCoreGateway();
    gateway.onOperate = (request) async {
      if (gateway.operations.length == 1) {
        throw StateError('PRIVATE_TRANSPORT_DETAILS');
      }
      return <String, dynamic>{
        'organization_id': _northClientId,
        'id': _subscriptionId
      };
    };
    await _openClientSubscription(tester, gateway);
    await _chooseCoreField(tester, 'request_admission_enabled', 'true');
    await _submitCoreForm(tester);
    expect(gateway.operations, isEmpty);
    await _commercialDecision(tester, 'Confirm');
    expect(gateway.operations, hasLength(1));
    expect(find.textContaining('same request'), findsOneWidget);
    expect(find.textContaining('PRIVATE_TRANSPORT_DETAILS'), findsNothing);
    await _submitCoreForm(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(gateway.operations, hasLength(2));
    final first = gateway.operations.first;
    final retry = gateway.operations.last;
    expect(first.operation, 'subscription.save');
    expect(first.organizationId, _northClientId);
    expect(first.payload['id'], _subscriptionId);
    expect(first.payload['plan_id'], _planId);
    expect(first.payload['request_admission_enabled'], isTrue);
    expect(first.payload.containsKey('started_at'), isFalse);
    expect(first.payload.containsKey('request_admission_started_at'), isFalse);
    expect(retry.idempotencyKey, first.idempotencyKey);
    expect(retry.payload, first.payload);
    expect(retry.organizationId, first.organizationId);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'resolving an existing incident requires resolution and verification before writing',
      (tester) async {
    final gateway = _FakeCoreGateway();
    await _openIncident(tester, gateway);
    await _chooseCoreField(tester, 'state', 'resolved');
    await _submitCoreForm(tester);
    expect(gateway.operations, isEmpty);
    await _enterCoreField(
        tester, 'resolution', 'Reauthorized the provider connection.');
    await _submitCoreForm(tester);
    expect(gateway.operations, isEmpty);
    await _enterCoreField(
        tester, 'verification_ref', 'evidence://connection-readback-42');
    await _submitCoreForm(tester);
    final request = gateway.operations.single;
    expect(request.operation, 'incident.save');
    expect(request.organizationId, _northClientId);
    expect(request.payload['id'], _incidentId);
    expect(request.payload['title'], 'Northwind connection interrupted');
    expect(request.payload['state'], 'resolved');
    expect(
        request.payload['resolution'], 'Reauthorized the provider connection.');
    expect(request.payload['verification_ref'],
        'evidence://connection-readback-42');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'cancelling an incident update leaves the existing incident unchanged',
      (tester) async {
    final gateway = _FakeCoreGateway();
    await _openIncident(tester, gateway);
    await _chooseCoreField(tester, 'state', 'recovering');
    await _enterCoreField(
        tester, 'diagnosis', 'Testing a new connection route.');
    await _tap(tester, find.text('Cancel'));
    expect(gateway.operations, isEmpty);
    expect(find.byType(PandoraCoreOperationForm), findsNothing);
    expect(find.text('Northwind connection interrupted'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'won prospect requires an existing client link and preserves the prospect identity',
      (tester) async {
    final gateway = _FakeCoreGateway()
      ..data = <String, dynamic>{
        ..._snapshot(clients: [
          _client(),
          _client(id: _southClientId, name: 'Harbor Logistics')
        ]),
        'pipeline': <PandoraCoreRecord>[
          <String, dynamic>{
            'id': _prospectId,
            'company_name': 'Harbor opportunity',
            'contact_name': 'Avery Owner',
            'stage': 'contracting',
            'next_action': 'Complete signed onboarding',
            'currency': 'PHP',
          },
        ],
      };
    await _mount(tester, gateway, section: 'business');
    await _tap(tester, find.text('Harbor opportunity'));
    expect(find.text('Update prospect'), findsOneWidget);
    await _chooseCoreField(tester, 'stage', 'won');
    await _submitCoreForm(tester);
    expect(gateway.operations, isEmpty);
    final target = await _coreField(tester, 'converted_organization_id');
    final clientOptions = _renderedDropdown(tester, target)
        .items!
        .map((item) => item.value)
        .where((id) => id != null && id.isNotEmpty)
        .toSet();
    expect(clientOptions, {_northClientId, _southClientId});
    await _chooseCoreField(tester, 'converted_organization_id', _southClientId);
    await _submitCoreForm(tester);
    final request = gateway.operations.single;
    expect(request.operation, 'prospect.save');
    expect(request.organizationId, isNull);
    expect(request.payload['id'], _prospectId);
    expect(request.payload['stage'], 'won');
    expect(request.payload['converted_organization_id'], _southClientId);
    expect(gateway.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('release facts keep candidate and production acceptance distinct',
      (tester) async {
    final data = _snapshot();
    data['deployments'] = <PandoraCoreRecord>[
      <String, dynamic>{
        'title': 'Canonical production',
        'release_observation_kind': 'canonical_production',
        'status': 'READY',
        'summary': 'Serving mcpmaster.vercel.app',
        'source_sha': 'a' * 40,
        'evidence_state': 'stale',
      },
      <String, dynamic>{
        'title': 'Latest candidate',
        'release_observation_kind': 'candidate',
        'status': 'READY',
        'summary': 'Candidate; canonical production remains separate',
        'source_sha': 'b' * 40,
        'source_tree_sha': 'c' * 40,
        'provider_deployment_id': 'dpl_test_candidate',
        'runtime_verified': false,
        'owner_flow_verified': false,
        'client_flow_verified': false,
        'production_verified': false,
        'supabase_migration_version': '20261003080000',
        'edge_functions': <PandoraCoreRecord>[
          <String, dynamic>{
            'slug': 'pandora-intelligence-chat',
            'version': 82,
            'source_sha': 'b' * 40,
            'observed_at': '2026-10-03T08:00:00Z',
            'unexpected_raw_payload': 'must-never-render',
          },
        ],
      },
    ];
    final gateway = _FakeCoreGateway()..data = data;
    await _mount(tester, gateway,
        section: 'platform', size: const Size(360, 740));
    await _tap(tester, find.text('Deployments'));
    expect(find.text('Canonical production'), findsOneWidget);
    expect(find.text('Latest candidate'), findsOneWidget);
    expect(find.text('READY'), findsNWidgets(2));
    expect(find.textContaining('Stale provider evidence'), findsOneWidget);
    expect(find.textContaining('Runtime and user flows not verified'),
        findsOneWidget);
    await _tap(tester, find.text('Latest candidate'));
    expect(find.text('Not verified'), findsNWidgets(4));
    expect(find.text('Verified'), findsNothing);
    expect(find.text('dpl_test_candidate'), findsOneWidget);
    expect(find.text('c' * 40), findsOneWidget);
    expect(find.text('20261003080000'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('pandora-intelligence-chat'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('pandora-intelligence-chat'), findsOneWidget);
    expect(find.text('82'), findsOneWidget);
    expect(find.text('must-never-render'), findsNothing);
    expect(gateway.operations, isEmpty);
    expect(tester.takeException(), isNull);
  });

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
