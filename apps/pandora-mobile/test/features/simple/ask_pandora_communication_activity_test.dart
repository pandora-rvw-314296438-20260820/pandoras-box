import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/chat/pandora_chat.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/local/pandora_device_activity_local_sync.dart';
import 'package:pandora_mobile/core/local/pandora_local_store.dart';
import 'package:pandora_mobile/core/local/pandora_local_store_stub.dart';
import 'package:pandora_mobile/core/local/pandora_local_sync_coordinator.dart';
import 'package:pandora_mobile/core/local_ai/pandora_local_ai.dart';
import 'package:pandora_mobile/features/simple/ask_pandora_screen.dart';

import '../../helpers/fake_chat_intelligence.dart';
import '../../helpers/fake_owner_api.dart';
import '../../helpers/test_app.dart';

class _CommunicationActivityApi extends FakeChatIntelligence {
  bool failFacts = false;
  bool failAdmission = false;
  Completer<void>? actingReport;
  final List<String> admissions = [];
  final List<Map<String, Object?>> facts = [];

  @override
  Future<PandoraDeviceActivityExecution> startDeviceActivity({
    required String requestId,
    String? threadId,
    String? projectId,
  }) async {
    admissions.add(requestId);
    if (failAdmission) {
      throw const PandoraIntelligenceException('Activity admission offline.');
    }
    return const PandoraDeviceActivityExecution(
        jobId: 'communication-activity', events: Stream.empty());
  }

  @override
  Future<void> recordDeviceActivity({
    required String jobId,
    required String operationId,
    required String capability,
    required String stage,
    required DateTime observedAt,
  }) async {
    facts.add({
      'jobId': jobId,
      'operationId': operationId,
      'capability': capability,
      'stage': stage,
      'observedAt': observedAt.toUtc().toIso8601String(),
    });
    if (stage == 'acting' && actingReport != null) {
      await actingReport!.future;
    }
    if (failFacts) {
      throw const PandoraIntelligenceException('Activity transport offline.');
    }
  }

  @override
  Future<PandoraChatModelPickerSnapshot> modelPicker(
          {String? threadId}) async =>
      const PandoraChatModelPickerSnapshot(
        models: [],
        selection: PandoraChatModelSelection.auto(),
        reasoningMode: PandoraIntelligenceMode.auto,
      );

  @override
  Future<PandoraCapabilityRegistry> capabilityRegistry() async =>
      PandoraCapabilityRegistry(
        contractVersion: 'fixture',
        observedAt: DateTime.utc(2026),
        projectRequired: false,
        providers: const [],
      );
}

void main() {
  const device = MethodChannel('pandora/device_agent');
  const phone = '+15555550123';
  late _CommunicationActivityApi api;
  late MemoryPandoraLocalStore store;
  late GlobalKey<AskPandoraScreenState> key;
  late List<MethodCall> nativeCalls;

  Future<void> mount(WidgetTester tester,
      {bool withIntelligence = true}) async {
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    key = GlobalKey<AskPandoraScreenState>();
    await tester.pumpWidget(testApp(
      child: PandoraDependencies(
        auth: const FakeAuth(),
        repository: FakeRepository(),
        diagnostics: DiagnosticsStore(),
        intelligence: withIntelligence ? api : null,
        localStore: store,
        child: AskPandoraScreen(key: key, enterpriseContext: const {}),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(
        find.byKey(const ValueKey<String>('ask-pandora-objective')), text);
    await tester.tap(find.byKey(const ValueKey<String>('ask-pandora-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
  }

  Future<List<PandoraOfflineOperation>> pending() => store.pendingOperations(
      now: DateTime.now().toUtc().add(const Duration(minutes: 1)));

  Future<void> expectQueuedFacts(List<Map<String, Object?>> facts) async {
    final queued = await pending();
    expect(queued, hasLength(facts.length));
    for (final fact in facts) {
      final identity = pandoraActivitySyncIdentity(
          '${fact['jobId']}|${fact['operationId']}|${fact['capability']}|${fact['stage']}');
      final operation = queued.singleWhere((o) => o.operationId == identity);
      expect(operation.idempotencyKey, identity);
      expect(operation.capability, 'activity.device.fact');
      expect(operation.state, PandoraOfflineOperationState.pending);
      expect(jsonDecode(operation.payloadJson), fact);
      expect(
          operation.createdAt, DateTime.parse(fact['observedAt']! as String));
    }
  }

  setUp(() {
    api = _CommunicationActivityApi();
    store = MemoryPandoraLocalStore();
    nativeCalls = [];
    PandoraLocalAiPreference.setCachedForTesting(false);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('pandora/local_ai'), (_) async => null);
    messenger.setMockMethodCallHandler(device, (call) async {
      nativeCalls.add(call);
      if (call.method != 'executeDirectCommunication') {
        throw StateError('Unexpected native operation: ${call.method}');
      }
      final args = call.arguments as Map<Object?, Object?>;
      return {
        'operationId': args['operationId'],
        'kind': args['kind'],
        'state': args['kind'] == 'sms' ? 'delivered' : 'initiated',
        'terminal': true,
        'acceptedByPlatform': true,
        'duplicatePrevented': false,
        'updatedAtEpochMs': DateTime.now().millisecondsSinceEpoch,
      };
    });
  });

  tearDown(() {
    PandoraLocalAiPreference.resetForTesting();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(device, null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('pandora/local_ai'), null);
  });

  for (final kind in ['call', 'sms']) {
    testWidgets(
        '$kind remote Activity failure queues the exact facts and sync never redispatches',
        (tester) async {
      api.failFacts = true;
      await mount(tester);
      await send(
          tester, kind == 'call' ? 'Call $phone' : 'Send $phone: Test message');
      await tester.pumpAndSettle();
      expect(api.dispatches, isEmpty);
      expect(nativeCalls, hasLength(1));
      expect(nativeCalls.single.method, 'executeDirectCommunication');
      expect(key.currentState!.debugChatState.turns.single.phase,
          PandoraChatPhase.completed);
      expect(api.facts.map((f) => f['stage']), ['acting', 'result']);
      expect(api.facts.every((f) => f['capability'] == 'communication.$kind'),
          isTrue);
      final originalFacts = List<Map<String, Object?>>.of(api.facts);
      final operationId = api.admissions.single;
      expect(
          originalFacts.every((f) => f['operationId'] == operationId), isTrue);
      expect((nativeCalls.single.arguments as Map)['operationId'], operationId);
      await expectQueuedFacts(originalFacts);

      // Reporting resumes through the existing durable-queue transport, after
      // the chat widget is gone. The transport has no native dispatch path.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      api.failFacts = false;
      final sync = await PandoraLocalSyncCoordinator(
        store: store,
        transport: PandoraDeviceActivityLocalSyncTransport(api),
        clock: () => DateTime.now().toUtc().add(const Duration(minutes: 1)),
      ).drain();
      expect(sync.applied, 2);
      expect(api.facts.skip(2).toList(), originalFacts);
      expect(await pending(), isEmpty);
      expect(nativeCalls, hasLength(1));
      expect(api.admissions, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'successful communication Activity reports create no queued facts',
      (tester) async {
    await mount(tester);
    await send(tester, 'Call $phone');
    await tester.pumpAndSettle();
    expect(api.facts.map((f) => f['stage']), ['acting', 'result']);
    expect(await pending(), isEmpty);
    expect(nativeCalls, hasLength(1));
    expect(key.currentState!.debugChatState.turns.single.phase,
        PandoraChatPhase.completed);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Stop before dispatch retains failed cancellation audit in queue',
      (tester) async {
    api.failFacts = true;
    api.actingReport = Completer<void>();
    await mount(tester);
    await send(tester, 'Call $phone');
    expect(api.facts.single['stage'], 'acting');
    expect(nativeCalls, isEmpty);
    await tester.tap(find.byKey(const ValueKey<String>('ask-pandora-stop')));
    await tester.pumpAndSettle();
    expect(key.currentState!.debugChatState.turns.single.phase,
        PandoraChatPhase.cancelled);
    api.actingReport!.complete();
    await tester.pumpAndSettle();
    expect(api.facts.map((f) => f['stage']), ['acting', 'cancelled']);
    await expectQueuedFacts(api.facts);
    expect(nativeCalls, isEmpty);
    expect(api.dispatches, isEmpty);
    expect(key.currentState!.debugChatState.turns.single.phase,
        PandoraChatPhase.cancelled);
    expect(tester.takeException(), isNull);
  });

  for (final missing in ['activity', 'intelligence']) {
    testWidgets('missing $missing retains no communication reporter',
        (tester) async {
      api.failAdmission = true;
      await mount(tester, withIntelligence: missing != 'intelligence');
      await send(tester, 'Call $phone');
      await tester.pumpAndSettle();
      expect(api.facts, isEmpty);
      expect(await pending(), isEmpty);
      expect(nativeCalls, hasLength(1));
      expect(api.admissions, hasLength(missing == 'activity' ? 1 : 0));
      expect(key.currentState!.debugChatState.turns.single.phase,
          PandoraChatPhase.completed);
      expect(tester.takeException(), isNull);
    });
  }
}
