import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_chat_shell.dart';
import 'package:pandora_mobile/app/pandora_core_client_scope.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/app/pandora_member_workspace_gate.dart';
import 'package:pandora_mobile/core/data/pandora_core_api.dart';
import 'package:pandora_mobile/core/data/pandora_enterprise_api.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/local_ai/pandora_local_ai.dart';
import 'package:pandora_mobile/core/platform/pandora_native_io.dart';
import 'package:pandora_mobile/core/security/pandora_auth.dart';
import 'package:pandora_mobile/features/enterprise/pandora_enterprise_workspace_screen.dart';
import 'package:pandora_mobile/features/simple/ask_pandora_screen.dart';
import 'package:pandora_mobile/pandora_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/fake_owner_api.dart';
import '../helpers/test_app.dart';

class _CoreGateway implements PandoraCoreGateway, PandoraCoreEntryGateway {
  _CoreGateway(
      {this.organizationId = PandoraConfig.plpOrganizationId,
      this.displayName = 'Scoped resort fixture',
      this.adapter = 'plp_v1'});
  final String organizationId;
  final String displayName;
  final String adapter;
  final entered = <String>[];
  final reasons = <String>[];
  final snapshots = <String>[];
  final validated = <String>[];
  final left = <String>[];
  bool entryValid = true;
  PandoraCoreFailure? entryFailure;

  @override
  Future<bool> validateEntry(String entryId, String organizationId) async {
    validated.add('$entryId:$organizationId');
    return entryValid;
  }

  @override
  Future<void> leaveClient(String entryId) async => left.add(entryId);

  @override
  Future<PandoraCoreRecord> snapshot(String section,
      {String? organizationId}) async {
    snapshots.add(section);
    return <String, dynamic>{
      'clients': <PandoraCoreRecord>[
        <String, dynamic>{
          'organization_id': this.organizationId,
          'display_name': displayName,
          'industry': 'Hospitality',
          'workspace_type': adapter == 'plp_v1' ? 'plp' : 'generic',
          'lifecycle_state': 'active',
          'can_enter': true,
        },
      ],
    };
  }

  @override
  Future<PandoraCoreRecord> operate(String operation,
          {String? organizationId,
          required PandoraCoreRecord payload,
          required String idempotencyKey}) =>
      throw StateError('No Core mutation is expected in scope tests.');

  @override
  Future<PandoraCoreRecord> enterClient(String organizationId,
      {required String reason}) async {
    entered.add(organizationId);
    reasons.add(reason);
    if (entryFailure != null) throw entryFailure!;
    return <String, dynamic>{
      'entry_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'organization_id': organizationId,
      if (adapter == 'plp_v1')
        'property_id': 'ada9befb-b821-4ae6-86bf-a6d93376815b',
      'workspace_type': adapter == 'plp_v1' ? 'plp' : 'generic',
      'adapter': adapter,
      'display_name': displayName,
      'expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 1))
          .toIso8601String(),
    };
  }
}

const _genericOrganizationId = '11111111-1111-4111-8111-111111111111';
const _genericTaskId = '22222222-2222-4222-8222-222222222222';

PandoraEnterpriseMembership _membership({bool requiresEntry = false}) =>
    PandoraEnterpriseMembership(
      organizationId: _genericOrganizationId,
      displayName: 'Scoped trading fixture',
      slug: 'scoped-trading',
      workspaceType: 'generic',
      adapter: 'enterprise_core_v1',
      role: 'admin',
      requiresOperatorEntry: requiresEntry,
    );

class _WorkspaceAccess implements PandoraWorkspaceAccessSource {
  _WorkspaceAccess(this.workspaces);
  List<PandoraEnterpriseMembership> workspaces;
  int calls = 0;
  @override
  Future<PandoraWorkspaceAccess> loadWorkspaceAccess() async {
    calls++;
    return PandoraWorkspaceAccess(operatorMode: false, workspaces: workspaces);
  }
}

class _MemberAuth extends FakeAuth {
  PandoraSession? session = const PandoraSession(userId: 'fixture-member');
  int signOutCalls = 0;
  @override
  PandoraSession? get currentSession => session;
  @override
  Future<bool> hasActiveOwnerAccess() async => false;
  @override
  Future<void> signOut() async {
    signOutCalls++;
    session = null;
  }
}

class _EnterpriseGateway implements PandoraEnterpriseGateway {
  final reads = <PandoraCoreRecord>[];
  final writes = <PandoraCoreRecord>[];
  final pending = Completer<PandoraCoreRecord>();

  @override
  Future<PandoraCoreRecord> snapshot(
      {required String organizationId,
      String section = 'overview',
      String? entryId}) async {
    reads.add({
      'organization_id': organizationId,
      'section': section,
      'entry_id': entryId
    });
    return {
      'schema_version': '1',
      'organization_id': organizationId,
      'workspace': {
        'organization_id': organizationId,
        'display_name': 'Scoped trading fixture',
        'adapter': 'enterprise_core_v1',
        'industry': 'Trade',
        'workspace_type': 'generic'
      },
      'actor_role': 'admin',
      'viewing_as': entryId == null ? 'member' : 'pandora_administrator',
      'entry_id': entryId,
      'permissions': {'can_manage_work': true},
      'counts': {'open_tasks': 1, 'overdue_tasks': 0, 'documents': 0},
      'tasks': [
        {
          'id': _genericTaskId,
          'title': 'Customer private shipment review',
          'description': 'Scoped work',
          'state': 'open',
          'editable': true,
          'updated_at': '2026-10-03T12:00:00Z'
        }
      ],
      'documents': <PandoraCoreRecord>[],
      'people': <PandoraCoreRecord>[],
      'activity': <PandoraCoreRecord>[],
      'sources': <PandoraCoreRecord>[],
    };
  }

  @override
  Future<PandoraCoreRecord> operate(
      {required String organizationId,
      required String operation,
      required PandoraCoreRecord payload,
      required String idempotencyKey,
      String? entryId}) {
    writes.add({
      'organization_id': organizationId,
      'operation': operation,
      'payload': payload,
      'idempotency_key': idempotencyKey,
      'entry_id': entryId
    });
    return pending.future;
  }
}

class _PendingIntelligence extends _History {
  _PendingIntelligence() : super('Owner pending');
  final pending = Completer<PandoraIntelligenceTurn>();

  @override
  Future<PandoraIntelligenceExecution> startChatExecution({
    required String message,
    required String requestId,
    String? threadId,
    String? projectId,
    Map<String, Object?>? enterpriseContext,
    PandoraTextAttachment? textAttachment,
    PandoraImageAttachment? imageAttachment,
    PandoraIntelligenceMode mode = PandoraIntelligenceMode.auto,
    PandoraChatModelSelection modelSelection =
        const PandoraChatModelSelection.auto(),
  }) async =>
      PandoraIntelligenceExecution(
        jobId: 'scope-pending-operation',
        events: const Stream<Map<String, dynamic>>.empty(),
        turn: pending.future,
      );

  void complete() {
    if (pending.isCompleted) return;
    pending.complete(const PandoraIntelligenceTurn(
      threadId: 'scope-pending-thread',
      reply: 'Owner operation completed.',
      intent: 'runtime_check',
      confidence: 1,
      needsClarification: false,
    ));
  }
}

class _History extends PandoraIntelligenceApi {
  _History(this.label)
      : super(
          client: SupabaseClient(
            'https://example.supabase.co',
            'fixture-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
          organizationId: label,
        );
  final String label;
  int calls = 0;

  @override
  Future<List<PandoraIntelligenceThread>> recentThreads(
      {int limit = 30}) async {
    calls++;
    return <PandoraIntelligenceThread>[
      PandoraIntelligenceThread(
        id: '$label-thread',
        title: '$label private conversation',
        status: 'active',
        lastMessageAt: DateTime.utc(2026, 10, 3),
        createdAt: DateTime.utc(2026, 10, 3),
      ),
    ];
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> _mount(
  WidgetTester tester,
  _CoreGateway gateway, {
  FakeRepository? repository,
  PandoraIntelligenceApi? intelligence,
  PandoraClientRuntimeFactory? factory,
  PandoraEnterpriseGateway? enterpriseGateway,
  PandoraEnterpriseMembership? memberWorkspace,
  PandoraWorkspaceAccessSource? workspaceAccess,
  PandoraAuth? auth,
}) async {
  PandoraLocalAiPreference.setCachedForTesting(false);
  addTearDown(PandoraLocalAiPreference.resetForTesting);
  await setTestSurface(tester, logicalSize: const Size(390, 844));
  const channel = MethodChannel('pandora/local_ai');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'status'
              ? <String, Object?>{
                  'supported': false,
                  'configured': false,
                  'loaded': false
                }
              : null);
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  await tester.pumpWidget(testApp(
    themeMode: ThemeMode.dark,
    child: PandoraDependencies(
      auth: auth ?? const FakeAuth(),
      repository: repository ?? FakeRepository(),
      diagnostics: DiagnosticsStore(),
      intelligence: intelligence,
      child: workspaceAccess != null
          ? PandoraMemberWorkspaceGate(
              auth: auth ?? const FakeAuth(),
              accessSource: workspaceAccess,
              coreGateway: gateway,
              enterpriseGateway: enterpriseGateway,
              clientRuntimeFactory: factory,
            )
          : PandoraChatShell(
              coreGateway: gateway,
              clientRuntimeFactory: factory,
              enterpriseGateway: enterpriseGateway,
              memberWorkspace: memberWorkspace),
    ),
  ));
  await _settle(tester);
}

Future<void> _clients(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Open navigation'));
  await _settle(tester);
  final drawer =
      find.byKey(const ValueKey('pandora-primary-navigation-drawer'));
  final tile = find.descendant(
      of: drawer, matching: find.widgetWithText(ListTile, 'Clients'));
  final scroll =
      find.descendant(of: drawer, matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(tile, 180, scrollable: scroll);
  await tester.tap(tile);
  await _settle(tester);
}

Future<void> _enter(WidgetTester tester,
    {String organizationId = PandoraConfig.plpOrganizationId}) async {
  final button = find.byKey(ValueKey('core-enter-$organizationId'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await _settle(tester);
}

PandoraClientRuntime _genericRuntime(String organizationId) =>
    PandoraClientRuntime(
      dependencies: PandoraDependencies(
        auth: const FakeAuth(),
        repository: FakeRepository(),
        intelligence: _History('Customer'),
        diagnostics: DiagnosticsStore(),
        child: const SizedBox.shrink(),
      ),
      dispose: () {},
    );

Future<void> _openGeneric(WidgetTester tester, _CoreGateway gateway,
    _EnterpriseGateway enterprise) async {
  await _mount(tester, gateway,
      enterpriseGateway: enterprise,
      intelligence: _History('Owner'),
      factory: _genericRuntime);
  await _clients(tester);
  await _enter(tester, organizationId: _genericOrganizationId);
  await tester.enterText(
      find.widgetWithText(TextField, 'Reason for administrator access'),
      'Resolve customer request');
  await tester.tap(find.text('Continue'));
  await _settle(tester);
}

void main() {
  testWidgets(
      'an unresolved owner action prevents client entry before authorization',
      (tester) async {
    final intelligence = _PendingIntelligence();
    final gateway = _CoreGateway();
    await _mount(tester, gateway, intelligence: intelligence);
    await tester.enterText(find.byKey(const ValueKey('ask-pandora-objective')),
        'Inspect the current runtime');
    await tester.tap(find.byKey(const ValueKey('ask-pandora-submit')));
    await _settle(tester);
    expect(
        tester
            .state<AskPandoraScreenState>(find.byType(AskPandoraScreen))
            .hasPendingScopeWork,
        isTrue);

    await _clients(tester);
    await _enter(tester);

    expect(gateway.entered, isEmpty);
    expect(find.text('Reason for administrator access'), findsNothing);
    expect(
        find.text(
            'Finish or reconcile the current action before changing client.'),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('core-client-context-banner')), findsNothing);
    intelligence.complete();
    await _settle(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('entry and return recreate composer context and isolate history',
      (tester) async {
    final gateway = _CoreGateway();
    final ownerHistory = _History('Owner');
    final clientHistory = _History('Client');
    final boundOrganizations = <String>[];
    var disposed = 0;
    await _mount(tester, gateway, intelligence: ownerHistory, factory: (id) {
      boundOrganizations.add(id);
      return PandoraClientRuntime(
        dependencies: PandoraDependencies(
          auth: const FakeAuth(),
          repository: FakeRepository(),
          intelligence: clientHistory,
          diagnostics: DiagnosticsStore(),
          child: const SizedBox.shrink(),
        ),
        dispose: () => disposed++,
      );
    });
    final ownerState =
        tester.state<AskPandoraScreenState>(find.byType(AskPandoraScreen));
    await tester.enterText(find.byKey(const ValueKey('ask-pandora-objective')),
        'Owner private draft');
    await _clients(tester);
    await _enter(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'Reason for administrator access'),
        'Investigate support request');
    await tester.tap(find.text('Continue'));
    await _settle(tester);

    expect(gateway.entered, <String>[PandoraConfig.plpOrganizationId]);
    expect(gateway.reasons.single, 'Investigate support request');
    expect(boundOrganizations, <String>[PandoraConfig.plpOrganizationId]);
    expect(find.text('Viewing Scoped resort fixture as Pandora Administrator'),
        findsOneWidget);
    final clientState =
        tester.state<AskPandoraScreenState>(find.byType(AskPandoraScreen));
    expect(identical(ownerState, clientState), isFalse);
    expect(find.text('Owner private draft'), findsNothing);
    final clientChat =
        tester.widget<AskPandoraScreen>(find.byType(AskPandoraScreen));
    expect((clientChat.enterpriseContext!['organization'] as Map)['id'],
        PandoraConfig.plpOrganizationId);
    expect(clientHistory.calls, greaterThan(0));

    clientChat.onSearchChats!();
    await _settle(tester);
    expect(find.text('Client private conversation'), findsOneWidget);
    expect(find.text('Owner private conversation'), findsNothing);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    await tester.enterText(find.byKey(const ValueKey('ask-pandora-objective')),
        'Client private draft');
    await tester.tap(find.byKey(const ValueKey('core-return-pandora')));
    await _settle(tester);

    expect(disposed, 1);
    expect(
        find.byKey(const ValueKey('core-client-context-banner')), findsNothing);
    expect(find.text('Client private draft'), findsNothing);
    final returned =
        tester.widget<AskPandoraScreen>(find.byType(AskPandoraScreen));
    expect((returned.enterpriseContext?['organization'] as Map?)?['id'],
        isNot(PandoraConfig.plpOrganizationId));
    returned.onSearchChats!();
    await _settle(tester);
    expect(find.text('Owner private conversation'), findsOneWidget);
    expect(find.text('Client private conversation'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a generic client opens scoped operational UI and returns to owner context',
      (tester) async {
    final gateway = _CoreGateway(
        organizationId: _genericOrganizationId,
        displayName: 'Scoped trading fixture',
        adapter: 'enterprise_core_v1');
    final enterprise = _EnterpriseGateway();
    await _openGeneric(tester, gateway, enterprise);
    expect(find.byType(PandoraEnterpriseWorkspaceScreen), findsOneWidget);
    expect(find.text('Customer private shipment review'), findsOneWidget);
    expect(find.text('Viewing Scoped trading fixture as Pandora Administrator'),
        findsOneWidget);
    expect(enterprise.reads.single['organization_id'], _genericOrganizationId);
    expect(enterprise.reads.single['entry_id'],
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    final clientChat =
        tester.widget<AskPandoraScreen>(find.byType(AskPandoraScreen));
    final selected = clientChat.enterpriseContext!['selectedObject'] as Map;
    expect((clientChat.enterpriseContext!['organization'] as Map)['id'],
        _genericOrganizationId);
    expect(selected['workspaceMode'], 'administrator');
    expect(selected['adapterKey'], 'enterprise_core_v1');
    expect(selected['entryId'], enterprise.reads.single['entry_id']);
    await tester.enterText(find.byKey(const ValueKey('ask-pandora-objective')),
        'Customer scoped draft');
    await tester.tap(find.byKey(const ValueKey('core-return-pandora')));
    await _settle(tester);
    expect(find.byType(PandoraEnterpriseWorkspaceScreen), findsNothing);
    expect(find.text('Customer private shipment review'), findsNothing);
    expect(find.text('Customer scoped draft'), findsNothing);
    final ownerChat =
        tester.widget<AskPandoraScreen>(find.byType(AskPandoraScreen));
    expect((ownerChat.enterpriseContext!['selectedObject'] as Map)['coreMode'],
        'owner');
    expect(enterprise.writes, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
  });

  testWidgets(
      'pending customer task prevents return until the response is reconciled',
      (tester) async {
    final gateway = _CoreGateway(
        organizationId: _genericOrganizationId,
        displayName: 'Scoped trading fixture',
        adapter: 'enterprise_core_v1');
    final enterprise = _EnterpriseGateway();
    await _openGeneric(tester, gateway, enterprise);
    await tester.tap(find.byKey(const ValueKey('enterprise-add-task')));
    await _settle(tester);
    await tester.enterText(find.byKey(const ValueKey('enterprise-task-title')),
        'Confirm customer order');
    final save = find.byKey(const ValueKey('enterprise-task-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await _settle(tester);
    expect(enterprise.writes, hasLength(1));
    expect(enterprise.writes.single['organization_id'], _genericOrganizationId);
    expect(enterprise.writes.single['entry_id'],
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    // The sheet prevents a pointer reaching the banner. Also verify the shell's
    // scope guard protects the same action if another route triggers it.
    tester
        .widget<TextButton>(find.byKey(const ValueKey('core-return-pandora')))
        .onPressed!();
    await _settle(tester);
    expect(
        find.text(
            'Finish or reconcile the current client action before returning.'),
        findsOneWidget);
    expect(find.byType(PandoraEnterpriseTaskForm), findsOneWidget);
    expect(find.byKey(const ValueKey('core-client-context-banner')),
        findsOneWidget);
    enterprise.pending.complete({
      'organization_id': _genericOrganizationId,
      'status': 'completed',
      'task': {'id': _genericTaskId},
      'receipt_id': '33333333-3333-4333-8333-333333333333',
    });
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('core-return-pandora')));
    await _settle(tester);
    expect(
        find.byKey(const ValueKey('core-client-context-banner')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
  });

  testWidgets(
      'member launch exposes only that customer workspace and navigation',
      (tester) async {
    final gateway = _CoreGateway();
    final enterprise = _EnterpriseGateway();
    await _mount(tester, gateway,
        enterpriseGateway: enterprise,
        factory: _genericRuntime,
        memberWorkspace: const PandoraEnterpriseMembership(
          organizationId: _genericOrganizationId,
          displayName: 'Scoped trading fixture',
          slug: 'scoped-trading',
          workspaceType: 'generic',
          adapter: 'enterprise_core_v1',
          role: 'admin',
        ));
    expect(find.byType(PandoraEnterpriseWorkspaceScreen), findsOneWidget);
    expect(find.text('Customer private shipment review'), findsOneWidget);
    expect(enterprise.reads.single['organization_id'], _genericOrganizationId);
    expect(enterprise.reads.single['entry_id'], isNull);
    final chat = tester.widget<AskPandoraScreen>(find.byType(AskPandoraScreen));
    final selected = chat.enterpriseContext!['selectedObject'] as Map;
    expect(selected['workspaceMode'], 'member');
    expect(selected['coreMode'], isNull);
    expect(selected['entryId'], isNull);
    await tester.tap(find.byTooltip('Open navigation'));
    await _settle(tester);
    final drawer =
        find.byKey(const ValueKey('pandora-primary-navigation-drawer'));
    for (final label in [
      'Clients',
      'Plans & Entitlements',
      'Business',
      'Pandora Core',
      'Usage & Costs'
    ]) {
      expect(
          find.descendant(
              of: drawer, matching: find.widgetWithText(ListTile, label)),
          findsNothing);
    }
    expect(
        find.descendant(
            of: drawer, matching: find.widgetWithText(ListTile, 'Work')),
        findsOneWidget);
    expect(gateway.entered, isEmpty);
    expect(enterprise.writes, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
  });

  testWidgets(
      'member chooser opens authoritative membership and recreates runtime without customer draft',
      (tester) async {
    final access = _WorkspaceAccess([_membership()]);
    final enterprise = _EnterpriseGateway();
    final gateway = _CoreGateway();
    var disposed = 0;
    final bound = <String>[];
    await _mount(tester, gateway, enterpriseGateway: enterprise, factory: (id) {
      bound.add(id);
      final runtime = _genericRuntime(id);
      return PandoraClientRuntime(
          dependencies: runtime.dependencies,
          dispose: () {
            disposed++;
            runtime.dispose();
          });
    }, workspaceAccess: access);
    expect(find.text('My workspaces'), findsOneWidget);
    expect(find.byType(AskPandoraScreen), findsNothing);
    expect(enterprise.reads, isEmpty);
    await tester.tap(
        find.byKey(const ValueKey('member-workspace-$_genericOrganizationId')));
    await _settle(tester);
    expect(find.text('Customer private shipment review'), findsOneWidget);
    expect(enterprise.reads.single['organization_id'], _genericOrganizationId);
    expect(enterprise.reads.single['entry_id'], isNull);
    expect(gateway.entered, isEmpty);
    expect(gateway.snapshots, isEmpty);
    final firstChat =
        tester.state<AskPandoraScreenState>(find.byType(AskPandoraScreen));
    expect(
        find.byKey(const ValueKey('ask-pandora-model-control')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('ask-pandora-objective')),
        'Member private draft');
    await tester.tap(find.byKey(const ValueKey('core-return-pandora')));
    await _settle(tester);
    expect(find.text('My workspaces'), findsOneWidget);
    expect(find.text('Member private draft'), findsNothing);
    expect(find.byType(AskPandoraScreen), findsNothing);
    expect(access.calls, 2);
    expect(disposed, 1);
    await tester.tap(
        find.byKey(const ValueKey('member-workspace-$_genericOrganizationId')));
    await _settle(tester);
    expect(bound, [_genericOrganizationId, _genericOrganizationId]);
    expect(
        identical(firstChat,
            tester.state<AskPandoraScreenState>(find.byType(AskPandoraScreen))),
        isFalse);
    expect(find.text('Member private draft'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
  });

  testWidgets(
      'support membership requires a reason and matching adapter receipt',
      (tester) async {
    final access = _WorkspaceAccess([_membership(requiresEntry: true)]);
    final enterprise = _EnterpriseGateway();
    // This gateway returns a PLP adapter; it cannot authorize a generic workspace.
    final gateway = _CoreGateway();
    await _mount(tester, gateway,
        enterpriseGateway: enterprise,
        factory: _genericRuntime,
        workspaceAccess: access);
    final workspace =
        find.byKey(const ValueKey('member-workspace-$_genericOrganizationId'));
    await tester.tap(workspace);
    await _settle(tester);
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(gateway.entered, isEmpty);
    expect(enterprise.reads, isEmpty);
    await tester.tap(workspace);
    await _settle(tester);
    await tester.enterText(find.byKey(const ValueKey('member-entry-reason')),
        'Review customer support escalation');
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(gateway.entered, [_genericOrganizationId]);
    expect(gateway.reasons.single, 'Review customer support escalation');
    expect(find.text('The workspace changed. Refresh access before entering.'),
        findsOneWidget);
    expect(enterprise.reads, isEmpty);
    expect(find.byType(AskPandoraScreen), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
  });

  testWidgets(
      'revoked membership removes customer routes and late task completion on resume',
      (tester) async {
    final access = _WorkspaceAccess([_membership()]);
    final enterprise = _EnterpriseGateway();
    await _mount(tester, _CoreGateway(),
        enterpriseGateway: enterprise,
        factory: _genericRuntime,
        workspaceAccess: access);
    await tester.tap(
        find.byKey(const ValueKey('member-workspace-$_genericOrganizationId')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('enterprise-add-task')));
    await _settle(tester);
    await tester.enterText(find.byKey(const ValueKey('enterprise-task-title')),
        'Scoped request still in flight');
    final save = find.byKey(const ValueKey('enterprise-task-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await _settle(tester);
    expect(enterprise.writes, hasLength(1));
    access.workspaces = [];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(find.text('My workspaces'), findsOneWidget);
    expect(find.byType(PandoraEnterpriseTaskForm), findsNothing);
    expect(find.byType(AskPandoraScreen), findsNothing);
    expect(find.text('Customer private shipment review'), findsNothing);
    enterprise.pending.complete({
      'organization_id': _genericOrganizationId,
      'status': 'completed',
      'task': {'id': _genericTaskId},
      'receipt_id': '33333333-3333-4333-8333-333333333333'
    });
    await _settle(tester);
    expect(find.text('Task saved and read back.'), findsNothing);
    expect(find.text('My workspaces'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
  });

  for (final denied in [false, true]) {
    testWidgets(
        denied
            ? 'denied support access stays in the member chooser'
            : 'support entry carries the audited receipt into the customer workspace',
        (tester) async {
      final access = _WorkspaceAccess([_membership(requiresEntry: true)]);
      final enterprise = _EnterpriseGateway();
      final gateway = _CoreGateway(
          organizationId: _genericOrganizationId,
          displayName: 'Scoped trading fixture',
          adapter: 'enterprise_core_v1');
      if (denied) {
        gateway.entryFailure = const PandoraCoreFailure(
            'ACCESS_DENIED', 'Workspace access was denied.');
      }
      await _mount(tester, gateway,
          enterpriseGateway: enterprise,
          factory: _genericRuntime,
          workspaceAccess: access);
      await tester.tap(find
          .byKey(const ValueKey('member-workspace-$_genericOrganizationId')));
      await _settle(tester);
      await tester.enterText(find.byKey(const ValueKey('member-entry-reason')),
          'Investigate the customer support request');
      await tester.tap(find.text('Continue'));
      await _settle(tester);
      expect(gateway.entered, [_genericOrganizationId]);
      expect(
          gateway.reasons.single, 'Investigate the customer support request');
      expect(gateway.snapshots, isEmpty);
      if (denied) {
        expect(find.text('Workspace access was denied.'), findsOneWidget);
        expect(find.text('My workspaces'), findsOneWidget);
        expect(find.byType(AskPandoraScreen), findsNothing);
        expect(enterprise.reads, isEmpty);
      } else {
        expect(
            find.text(
                'Viewing Scoped trading fixture as Pandora Administrator'),
            findsOneWidget);
        expect(
            enterprise.reads.single['organization_id'], _genericOrganizationId);
        expect(enterprise.reads.single['entry_id'],
            'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
        await tester.tap(find.byKey(const ValueKey('core-return-pandora')));
        await _settle(tester);
        expect(find.text('My workspaces'), findsOneWidget);
        expect(gateway.left, ['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa']);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
    });
  }

  testWidgets(
      'signing out removes the selected customer shell and private draft',
      (tester) async {
    final auth = _MemberAuth();
    final access = _WorkspaceAccess([_membership()]);
    final enterprise = _EnterpriseGateway();
    await _mount(tester, _CoreGateway(),
        auth: auth,
        enterpriseGateway: enterprise,
        factory: _genericRuntime,
        workspaceAccess: access);
    await tester.tap(
        find.byKey(const ValueKey('member-workspace-$_genericOrganizationId')));
    await _settle(tester);
    await tester.enterText(find.byKey(const ValueKey('ask-pandora-objective')),
        'Private member draft at sign-out');
    await tester.tap(find.byTooltip('Open navigation'));
    await _settle(tester);
    final drawer =
        find.byKey(const ValueKey('pandora-primary-navigation-drawer'));
    final signOut = find.descendant(
        of: drawer, matching: find.widgetWithText(ListTile, 'Sign out'));
    await tester.ensureVisible(signOut);
    await tester.tap(signOut);
    await _settle(tester);
    expect(auth.signOutCalls, 1);
    expect(auth.currentSession, isNull);
    expect(find.byType(AskPandoraScreen), findsNothing);
    expect(find.byType(PandoraEnterpriseWorkspaceScreen), findsNothing);
    expect(find.text('Private member draft at sign-out'), findsNothing);
    expect(
        find.byKey(const ValueKey('member-workspace-$_genericOrganizationId')),
        findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
  });

  testWidgets(
      'revoked administrator receipt removes the open customer modal on resume',
      (tester) async {
    final gateway = _CoreGateway(
        organizationId: _genericOrganizationId,
        displayName: 'Scoped trading fixture',
        adapter: 'enterprise_core_v1');
    final enterprise = _EnterpriseGateway();
    await _openGeneric(tester, gateway, enterprise);
    await tester.tap(find.byKey(const ValueKey('enterprise-add-task')));
    await _settle(tester);
    await tester.enterText(find.byKey(const ValueKey('enterprise-task-title')),
        'Customer modal draft');
    gateway.entryValid = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(gateway.validated,
        ['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa:$_genericOrganizationId']);
    expect(find.byType(PandoraEnterpriseTaskForm), findsNothing);
    expect(find.byType(PandoraEnterpriseWorkspaceScreen), findsNothing);
    expect(find.text('Customer modal draft'), findsNothing);
    expect(
        find.byKey(const ValueKey('core-client-context-banner')), findsNothing);
    final chat = tester.widget<AskPandoraScreen>(find.byType(AskPandoraScreen));
    expect((chat.enterpriseContext!['selectedObject'] as Map)['coreMode'],
        'owner');
    expect(enterprise.writes, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
  });
}
