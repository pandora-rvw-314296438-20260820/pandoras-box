import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_chat_shell.dart';
import 'package:pandora_mobile/app/pandora_core_client_scope.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/data/pandora_core_api.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/local_ai/pandora_local_ai.dart';
import 'package:pandora_mobile/core/platform/pandora_native_io.dart';
import 'package:pandora_mobile/features/simple/ask_pandora_screen.dart';
import 'package:pandora_mobile/pandora_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/fake_owner_api.dart';
import '../helpers/test_app.dart';

class _CoreGateway implements PandoraCoreGateway {
  final entered = <String>[];
  final reasons = <String>[];

  @override
  Future<PandoraCoreRecord> snapshot(String section,
          {String? organizationId}) async =>
      <String, dynamic>{
        'clients': <PandoraCoreRecord>[
          <String, dynamic>{
            'organization_id': PandoraConfig.plpOrganizationId,
            'display_name': 'Scoped resort fixture',
            'industry': 'Hospitality',
            'workspace_type': 'plp',
            'lifecycle_state': 'active',
            'can_enter': true,
          },
        ],
      };

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
    return <String, dynamic>{
      'entry_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'organization_id': organizationId,
      'property_id': 'ada9befb-b821-4ae6-86bf-a6d93376815b',
      'workspace_type': 'plp',
      'display_name': 'Scoped resort fixture',
      'expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 1))
          .toIso8601String(),
    };
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
      auth: const FakeAuth(),
      repository: repository ?? FakeRepository(),
      diagnostics: DiagnosticsStore(),
      intelligence: intelligence,
      child:
          PandoraChatShell(coreGateway: gateway, clientRuntimeFactory: factory),
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

Future<void> _enter(WidgetTester tester) async {
  final button =
      find.byKey(ValueKey('core-enter-${PandoraConfig.plpOrganizationId}'));
  await tester.ensureVisible(button);
  await tester.tap(button);
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
}
