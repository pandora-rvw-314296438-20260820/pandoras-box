import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/pandora_core_api.dart';
import 'package:pandora_mobile/core/data/pandora_enterprise_api.dart';
import 'package:pandora_mobile/features/enterprise/pandora_enterprise_workspace_screen.dart';

import '../../helpers/test_app.dart';

const _northId = '11111111-1111-4111-8111-111111111111';
const _southId = '22222222-2222-4222-8222-222222222222';
const _entryId = '33333333-3333-4333-8333-333333333333';
const _taskId = '44444444-4444-4444-8444-444444444444';
const _taskVersion = '2026-10-03T12:00:00.123456Z';

PandoraCoreRecord _task({
  String title = 'Review cargo manifest',
  String state = 'open',
}) =>
    <String, dynamic>{
      'id': _taskId,
      'title': title,
      'description': 'Confirm the shipment documentation.',
      'state': state,
      'due_at': null,
      'updated_at': _taskVersion,
      'editable': true,
    };

PandoraCoreRecord _workspace(
  String organizationId, {
  List<PandoraCoreRecord>? tasks,
  bool canManage = true,
  String? entryId,
}) =>
    <String, dynamic>{
      'schema_version': '1',
      'organization_id': organizationId,
      'workspace': <String, dynamic>{
        'organization_id': organizationId,
        'display_name': organizationId == _northId
            ? 'Northwind Traders'
            : 'Southwind Services',
        'industry': 'trade',
        'workspace_type': 'generic',
        'adapter': 'enterprise_core_v1',
        'lifecycle_state': 'active',
      },
      'actor_role': canManage ? 'admin' : 'viewer',
      'viewing_as': entryId == null ? 'member' : 'pandora_administrator',
      'entry_id': entryId,
      'permissions': <String, dynamic>{'can_manage_work': canManage},
      'counts': <String, dynamic>{
        'open_tasks': (tasks ?? [_task()]).length,
        'overdue_tasks': 0,
        'documents': 0,
      },
      'tasks': tasks ?? <PandoraCoreRecord>[_task()],
      'documents': <PandoraCoreRecord>[],
      'people': <PandoraCoreRecord>[],
      'activity': <PandoraCoreRecord>[],
      'sources': <PandoraCoreRecord>[],
      'generated_at': '2026-10-03T12:05:00Z',
    };

class _Read {
  const _Read(this.organizationId, this.section, this.entryId);
  final String organizationId;
  final String section;
  final String? entryId;
}

class _Write {
  const _Write(this.organizationId, this.operation, this.payload,
      this.idempotencyKey, this.entryId);
  final String organizationId;
  final String operation;
  final PandoraCoreRecord payload;
  final String idempotencyKey;
  final String? entryId;
}

class _Gateway implements PandoraEnterpriseGateway {
  final reads = <_Read>[];
  final writes = <_Write>[];
  Future<PandoraCoreRecord> Function(_Read)? onRead;
  Future<PandoraCoreRecord> Function(_Write)? onWrite;

  @override
  Future<PandoraCoreRecord> snapshot({
    required String organizationId,
    String section = 'overview',
    String? entryId,
  }) async {
    final request = _Read(organizationId, section, entryId);
    reads.add(request);
    return onRead == null
        ? _workspace(organizationId, entryId: entryId)
        : await onRead!(request);
  }

  @override
  Future<PandoraCoreRecord> operate({
    required String organizationId,
    required String operation,
    required PandoraCoreRecord payload,
    required String idempotencyKey,
    String? entryId,
  }) async {
    final request = _Write(organizationId, operation,
        Map<String, dynamic>.of(payload), idempotencyKey, entryId);
    writes.add(request);
    return onWrite == null
        ? <String, dynamic>{
            'status': 'completed',
            'organization_id': organizationId,
            'task': _task(),
            'receipt_id': '55555555-5555-4555-8555-555555555555',
            'replayed': false,
          }
        : await onWrite!(request);
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Gateway gateway, {
  String organizationId = _northId,
  String section = 'work',
  String? entryId,
  Size size = const Size(390, 844),
  double textScale = 1,
  ValueChanged<bool>? onPendingWorkChanged,
  ValueChanged<PandoraCoreRecord>? onContextChanged,
}) async {
  await setTestSurface(tester, logicalSize: size);
  await tester.pumpWidget(testApp(
    textScaler: TextScaler.linear(textScale),
    child: Scaffold(
        body: PandoraEnterpriseWorkspaceScreen(
      gateway: gateway,
      organizationId: organizationId,
      entryId: entryId,
      section: section,
      onPendingWorkChanged: onPendingWorkChanged,
      onContextChanged: onContextChanged,
    )),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _addTask(WidgetTester tester,
    {String title = 'Check customs release'}) async {
  await _tap(tester, find.byKey(const ValueKey('enterprise-add-task')));
  await tester.enterText(
      find.byKey(const ValueKey('enterprise-task-title')), title);
  await tester.enterText(
      find.byKey(const ValueKey('enterprise-task-description')),
      'Check the current source document.');
}

PandoraCoreRecord _receipt(_Write request, PandoraCoreRecord task) =>
    <String, dynamic>{
      'status': 'completed',
      'organization_id': request.organizationId,
      'task': task,
      'receipt_id': '55555555-5555-4555-8555-555555555555',
      'replayed': false,
    };

void main() {
  testWidgets('workspace reads carry exact tenant and administrator receipt',
      (tester) async {
    final gateway = _Gateway();
    await _mount(tester, gateway, entryId: _entryId);

    expect(gateway.reads.single.organizationId, _northId);
    expect(gateway.reads.single.section, 'work');
    expect(gateway.reads.single.entryId, _entryId);
    expect(find.text('Review cargo manifest'), findsOneWidget);
    expect(gateway.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a different tenant snapshot is never rendered', (tester) async {
    final gateway = _Gateway()
      ..onRead = (_) async => _workspace(_southId,
          tasks: <PandoraCoreRecord>[_task(title: 'Southwind private task')]);
    await _mount(tester, gateway);

    expect(find.text('Southwind private task'), findsNothing);
    expect(find.text('Southwind Services'), findsNothing);
    expect(gateway.reads.single.organizationId, _northId);
    expect(gateway.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late tenant snapshots cannot replace the newly selected client',
      (tester) async {
    final north = Completer<PandoraCoreRecord>();
    final gateway = _Gateway()
      ..onRead = (request) => request.organizationId == _northId
          ? north.future
          : Future<PandoraCoreRecord>.value(_workspace(_southId,
              tasks: <PandoraCoreRecord>[
                  _task(title: 'Southwind current task')
                ]));
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    Widget page(String organizationId) => testApp(
          child: Scaffold(
              body: PandoraEnterpriseWorkspaceScreen(
            gateway: gateway,
            organizationId: organizationId,
            section: 'work',
          )),
        );
    await tester.pumpWidget(page(_northId));
    await tester.pump();
    await tester.pumpWidget(page(_southId));
    await tester.pumpAndSettle();
    expect(find.text('Southwind current task'), findsOneWidget);

    north.complete(_workspace(_northId,
        tasks: <PandoraCoreRecord>[_task(title: 'Northwind late task')]));
    await tester.pumpAndSettle();
    expect(find.text('Northwind late task'), findsNothing);
    expect(find.text('Southwind current task'), findsOneWidget);
    expect(gateway.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('member workspace does not expose Pandora operator projections',
      (tester) async {
    final gateway = _Gateway()
      ..onRead = (request) async => <String, dynamic>{
            ..._workspace(request.organizationId),
            'operator': <String, dynamic>{'name': 'PRIVATE_OPERATOR_SENTINEL'},
            'clients': <PandoraCoreRecord>[
              <String, dynamic>{'display_name': 'OTHER_TENANT_SENTINEL'},
            ],
            'business': <String, dynamic>{'mrr': 'PRIVATE_REVENUE_SENTINEL'},
          };
    await _mount(tester, gateway, section: 'overview');

    expect(find.textContaining('PRIVATE_OPERATOR_SENTINEL'), findsNothing);
    expect(find.textContaining('OTHER_TENANT_SENTINEL'), findsNothing);
    expect(find.textContaining('PRIVATE_REVENUE_SENTINEL'), findsNothing);
    expect(find.text('Manage client'), findsNothing);
    expect(find.text('Add Enterprise Client'), findsNothing);
    expect(gateway.reads.single.entryId, isNull);
    expect(gateway.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final invalidProof in <String>[
    'nested tenant',
    'adapter',
    'entry identity',
    'entry authority'
  ]) {
    testWidgets('workspace rejects incorrect $invalidProof', (tester) async {
      final gateway = _Gateway()
        ..onRead = (request) async {
          final value =
              _workspace(request.organizationId, entryId: request.entryId);
          switch (invalidProof) {
            case 'nested tenant':
              (value['workspace'] as Map)['organization_id'] = _southId;
            case 'adapter':
              (value['workspace'] as Map)['adapter'] = 'unverified_adapter';
            case 'entry identity':
              value['entry_id'] = _southId;
            case 'entry authority':
              value['viewing_as'] = 'member';
          }
          return value;
        };
      final contexts = <PandoraCoreRecord>[];
      await _mount(tester, gateway,
          entryId: _entryId, onContextChanged: contexts.add);
      expect(find.text('Workspace unavailable'), findsOneWidget);
      expect(find.text('Review cargo manifest'), findsNothing);
      expect(find.byKey(const ValueKey('enterprise-add-task')), findsNothing);
      expect(contexts, isEmpty);
      expect(gateway.writes, isEmpty);
    });
  }

  testWidgets('authorization loss clears previously visible customer data',
      (tester) async {
    final gateway = _Gateway();
    await _mount(tester, gateway);
    expect(find.text('Review cargo manifest'), findsOneWidget);
    gateway.onRead = (_) async => throw const PandoraCoreFailure(
        'ACCESS_DENIED', 'Workspace access is no longer available.');
    await _tap(tester, find.byKey(const ValueKey('enterprise-refresh')));
    expect(find.text('Review cargo manifest'), findsNothing);
    expect(find.byKey(const ValueKey('enterprise-add-task')), findsNothing);
    expect(
        find.text('Workspace access is no longer available.'), findsOneWidget);
  });

  testWidgets('reader can inspect work but cannot open mutation controls',
      (tester) async {
    final gateway = _Gateway()
      ..onRead = (request) async =>
          _workspace(request.organizationId, canManage: false);
    await _mount(tester, gateway);
    expect(find.byKey(const ValueKey('enterprise-add-task')), findsNothing);
    await _tap(tester, find.byKey(const ValueKey('enterprise-task-$_taskId')));
    expect(find.text('Confirm the shipment documentation.'), findsOneWidget);
    expect(find.byType(PandoraEnterpriseTaskForm), findsNothing);
    expect(find.text('Save task'), findsNothing);
    expect(gateway.writes, isEmpty);
  });

  testWidgets('cancel discards a draft without creating customer work',
      (tester) async {
    final gateway = _Gateway();
    await _mount(tester, gateway);
    await _addTask(tester);
    await _tap(tester, find.text('Cancel'));
    expect(find.byType(PandoraEnterpriseTaskForm), findsNothing);
    expect(find.text('Check customs release'), findsNothing);
    expect(gateway.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'create retains tenant and request identity while pending and reads back the result',
      (tester) async {
    final pending = Completer<PandoraCoreRecord>();
    final states = <bool>[];
    var saved = <PandoraCoreRecord>[];
    final gateway = _Gateway()
      ..onRead = (request) async => _workspace(request.organizationId,
          entryId: request.entryId, tasks: saved);
    gateway.onWrite = (_) => pending.future;
    await _mount(tester, gateway,
        entryId: _entryId, onPendingWorkChanged: states.add);
    expect(find.text('No tasks yet.'), findsOneWidget);
    await _addTask(tester);
    await _tap(tester, find.byKey(const ValueKey('enterprise-task-save')));

    expect(gateway.writes, hasLength(1));
    final request = gateway.writes.single;
    expect(request.organizationId, _northId);
    expect(request.entryId, _entryId);
    expect(request.operation, 'task.create');
    expect(request.payload, <String, dynamic>{
      'title': 'Check customs release',
      'description': 'Check the current source document.'
    });
    expect(request.idempotencyKey, isNotEmpty);
    expect(states.last, isTrue);
    expect(find.text('Task saved and read back.'), findsNothing);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Close'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<TextFormField>(
                find.byKey(const ValueKey('enterprise-task-title')))
            .enabled,
        isFalse);
    await tester.tap(find.byKey(const ValueKey('enterprise-task-save')));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byType(PandoraEnterpriseTaskForm), findsOneWidget);
    expect(gateway.writes, hasLength(1));

    saved = <PandoraCoreRecord>[_task(title: 'Check customs release')];
    pending.complete(_receipt(request, saved.single));
    await tester.pumpAndSettle();
    expect(find.byType(PandoraEnterpriseTaskForm), findsNothing);
    expect(find.text('Check customs release'), findsOneWidget);
    expect(find.text('Task saved and read back.'), findsOneWidget);
    expect(gateway.reads, hasLength(2));
    expect(states.last, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retry after an unknown result reuses the exact request',
      (tester) async {
    var saved = <PandoraCoreRecord>[];
    final gateway = _Gateway()
      ..onRead =
          (request) async => _workspace(request.organizationId, tasks: saved);
    gateway.onWrite = (request) async {
      if (gateway.writes.length == 1) {
        throw StateError('PRIVATE_PROVIDER_FAILURE');
      }
      saved = <PandoraCoreRecord>[
        _task(title: request.payload['title'] as String)
      ];
      return <String, dynamic>{
        ..._receipt(request, saved.single),
        'replayed': true
      };
    };
    await _mount(tester, gateway);
    await _addTask(tester);
    await _tap(tester, find.byKey(const ValueKey('enterprise-task-save')));
    expect(find.textContaining('The result is not confirmed.'), findsOneWidget);
    expect(find.textContaining('PRIVATE_PROVIDER_FAILURE'), findsNothing);
    expect(find.text('Task saved and read back.'), findsNothing);
    expect(
        tester
            .widget<TextFormField>(
                find.byKey(const ValueKey('enterprise-task-title')))
            .enabled,
        isFalse);
    await _tap(tester, find.byKey(const ValueKey('enterprise-task-save')));
    expect(gateway.writes, hasLength(2));
    expect(gateway.writes[1].idempotencyKey, gateway.writes[0].idempotencyKey);
    expect(gateway.writes[1].payload, gateway.writes[0].payload);
    expect(gateway.writes[1].organizationId, gateway.writes[0].organizationId);
    expect(find.byType(PandoraEnterpriseTaskForm), findsNothing);
    expect(find.text('Check customs release'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('task update carries the read version and exact selected state',
      (tester) async {
    var current = _task();
    final gateway = _Gateway()
      ..onRead = (request) async => _workspace(request.organizationId,
          entryId: request.entryId, tasks: [current]);
    gateway.onWrite = (request) async {
      current = <String, dynamic>{
        ...current,
        ...request.payload,
        'updated_at': '2026-10-03T12:30:00Z'
      };
      return _receipt(request, current);
    };
    await _mount(tester, gateway, entryId: _entryId);
    await _tap(tester, find.byKey(const ValueKey('enterprise-task-$_taskId')));
    await _tap(tester, find.byKey(const ValueKey('enterprise-task-state')));
    await _tap(tester, find.text('Completed').last);
    await _tap(tester, find.byKey(const ValueKey('enterprise-task-save')));
    final request = gateway.writes.single;
    expect(request.operation, 'task.update');
    expect(request.organizationId, _northId);
    expect(request.entryId, _entryId);
    expect(request.payload['id'], _taskId);
    expect(request.payload['expected_updated_at'], _taskVersion);
    expect(request.payload['state'], 'completed');
    expect(find.text('Completed'), findsOneWidget);
    expect(find.byType(PandoraEnterpriseTaskForm), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a version conflict stays unresolved until the owner refreshes',
      (tester) async {
    final gateway = _Gateway()
      ..onWrite = (_) async =>
          throw const PandoraCoreFailure('CONFLICT', 'The task has changed.');
    await _mount(tester, gateway);
    await _tap(tester, find.byKey(const ValueKey('enterprise-task-$_taskId')));
    await tester.enterText(
        find.byKey(const ValueKey('enterprise-task-title')), 'My stale edit');
    await _tap(tester, find.byKey(const ValueKey('enterprise-task-save')));
    expect(
        find.text(
            'This task changed. Close and refresh before editing it again.'),
        findsOneWidget);
    expect(find.text('Task saved and read back.'), findsNothing);
    expect(gateway.reads, hasLength(1));
    await _tap(tester, find.text('Close'));
    expect(find.text('Review cargo manifest'), findsOneWidget);
    expect(find.text('My stale edit'), findsNothing);
  });

  for (final failure in <String>[
    'wrong tenant',
    'missing receipt',
    'blank receipt'
  ]) {
    testWidgets('task success requires a verified result: $failure',
        (tester) async {
      final gateway = _Gateway()
        ..onWrite = (request) async {
          final value =
              _receipt(request, _task(title: 'Check customs release'));
          if (failure == 'wrong tenant') value['organization_id'] = _southId;
          if (failure == 'missing receipt') value.remove('receipt_id');
          if (failure == 'blank receipt') value['receipt_id'] = '  ';
          return value;
        };
      await _mount(tester, gateway);
      await _addTask(tester);
      await _tap(tester, find.byKey(const ValueKey('enterprise-task-save')));
      expect(
          find.text(
              'Pandora could not verify the saved task. Refresh before continuing.'),
          findsOneWidget);
      expect(find.byType(PandoraEnterpriseTaskForm), findsOneWidget);
      expect(find.text('Task saved and read back.'), findsNothing);
      expect(gateway.reads, hasLength(1));
      expect(gateway.writes, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'workspace and task editor remain usable on small scaled displays',
      (tester) async {
    final gateway = _Gateway();
    await _mount(tester, gateway, size: const Size(320, 640), textScale: 1.6);
    expect(tester.takeException(), isNull);
    await _addTask(tester);
    expect(tester.takeException(), isNull);
    await _tap(tester, find.text('Cancel'));
    expect(find.byType(PandoraEnterpriseTaskForm), findsNothing);
    expect(gateway.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
