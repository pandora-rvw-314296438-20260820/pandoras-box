import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/chat/pandora_chat.dart';
import 'package:pandora_mobile/core/data/pandora_activity_stream_api.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/local/pandora_local_store.dart';
import 'package:pandora_mobile/core/local/pandora_local_store_stub.dart';
import 'package:pandora_mobile/core/local_ai/pandora_local_ai.dart';
import 'package:pandora_mobile/features/simple/ask_pandora_screen.dart';
import 'package:pandora_mobile/features/simple/chat/pandora_chat_presentation_controller.dart';
import 'package:pandora_mobile/features/simple/chat/pandora_chat_viewport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fake_owner_api.dart';
import '../../helpers/test_app.dart';

class _LifecycleApi extends PandoraIntelligenceApi {
  _LifecycleApi()
      : super(
            client: SupabaseClient('https://example.supabase.co', 'fixture-key',
                authOptions: const AuthClientOptions(autoRefreshToken: false)),
            organizationId: 'fixture-org');
  final List<PandoraChatDispatch> dispatches = [];
  final List<StreamController<PandoraChatWireEvent>> deliveries = [];
  final Map<String, PandoraChatWireEvent> receipts = {};
  final Map<String, Completer<List<PandoraIntelligenceMessage>>> histories = {};
  bool autoAccept = true;
  Completer<PandoraChatWireEvent>? cancellation;
  int activitySubscriptions = 0;
  int deviceAdmissions = 0;
  final List<({String jobId, String operationId, String stage})> deviceFacts =
      [];
  Completer<PandoraDeviceActivityExecution>? deviceAdmission;
  Completer<PandoraCapabilityRegistry>? registry;
  final List<
      ({
        String jobId,
        String requestId,
        PandoraActivityControlType type,
        String? instruction
      })> controls = [];
  final List<({String turnId, String? attemptId, int generation})>
      cancelRequests = [];

  PandoraChatWireEvent event(int index, String status,
      {int sequence = 2,
      int? streamSequence,
      String? reply,
      String? delta,
      Map<String, Object?> extra = const {}}) {
    final dispatch = dispatches[index];
    return PandoraChatWireEvent.fromJson({
      'protocolVersion': 2,
      'organizationId': organizationId,
      'threadId': dispatch.threadId ?? 'thread-core',
      'turnId': dispatch.token.turnId,
      'attemptId': dispatch.token.attemptId,
      'activityJobId': 'activity-${dispatch.token.turnId}',
      'userMessageId': 'user-${dispatch.token.turnId}',
      'generation': dispatch.token.generation,
      'sequence': sequence,
      if (streamSequence != null) 'streamSequence': streamSequence,
      'status': status,
      'type': delta == null ? status : 'delta',
      if (reply != null) 'reply': reply,
      if (delta != null) 'textDelta': delta,
      if (status == 'completed')
        'assistantMessageId': 'assistant-${dispatch.token.turnId}',
      if (status == 'completed')
        'routing': {
          'executedProvider': 'fixture-provider',
          'executedModel': 'fixture-execution'
        },
      if (status == 'failed_recoverably')
        'plainMessage':
            'This message could not be completed. You can retry it.',
      ...extra,
    });
  }

  void emit(int index, String status,
      {int sequence = 2,
      int? streamSequence,
      String? reply,
      String? delta,
      Map<String, Object?> extra = const {}}) {
    final value = event(index, status,
        sequence: sequence,
        streamSequence: streamSequence,
        reply: reply,
        delta: delta,
        extra: extra);
    receipts[value.turnId] = value;
    deliveries[index].add(value);
  }

  @override
  Stream<PandoraChatWireEvent> executeChatTurn(
      PandoraChatDispatch dispatch) async* {
    final index = dispatches.length;
    dispatches.add(dispatch);
    final controller = StreamController<PandoraChatWireEvent>();
    deliveries.add(controller);
    if (autoAccept) {
      final accepted = event(index, 'accepted', sequence: 1);
      receipts[dispatch.token.turnId] = accepted;
      yield accepted;
    }
    await for (final value in controller.stream) {
      yield value;
      if (value.isTerminal) break;
    }
  }

  @override
  Future<PandoraChatWireEvent?> readChatTurn({required String turnId}) async =>
      receipts[turnId];
  @override
  Future<PandoraChatWireEvent> cancelChatTurn(
      {required String turnId,
      required int generation,
      String? attemptId}) async {
    cancelRequests
        .add((turnId: turnId, attemptId: attemptId, generation: generation));
    if (cancellation != null) return cancellation!.future;
    final index = dispatches.lastIndexWhere((d) => d.token.turnId == turnId);
    final value = event(index, 'cancelled', sequence: 3);
    receipts[turnId] = value;
    return value;
  }

  @override
  Future<void> controlActivityJob(
      {required String jobId,
      required String requestId,
      required PandoraActivityControlType type,
      String? instruction}) async {
    controls.add((
      jobId: jobId,
      requestId: requestId,
      type: type,
      instruction: instruction
    ));
  }

  @override
  Future<PandoraDeviceActivityExecution> startDeviceActivity(
      {required String requestId, String? threadId, String? projectId}) async {
    deviceAdmissions += 1;
    if (deviceAdmission != null) return deviceAdmission!.future;
    return const PandoraDeviceActivityExecution(
        jobId: 'device-activity', events: Stream.empty());
  }

  @override
  Future<void> recordDeviceActivity(
      {required String jobId,
      required String operationId,
      required String capability,
      required String stage,
      required DateTime observedAt}) async {
    deviceFacts.add((jobId: jobId, operationId: operationId, stage: stage));
  }

  @override
  Future<PandoraCapabilityRegistry> capabilityRegistry() async =>
      registry?.future ??
      PandoraCapabilityRegistry(
          contractVersion: 'fixture',
          observedAt: DateTime.utc(2026),
          projectRequired: false,
          providers: const []);
  @override
  Stream<Map<String, dynamic>> watchChatActivity(String activityJobId) {
    activitySubscriptions += 1;
    return const Stream.empty();
  }

  @override
  Future<PandoraChatModelPickerSnapshot> modelPicker(
          {String? threadId}) async =>
      const PandoraChatModelPickerSnapshot(
          models: [],
          selection: PandoraChatModelSelection.auto(),
          reasoningMode: PandoraIntelligenceMode.auto);
  @override
  Future<List<PandoraIntelligenceMessage>> messages(String threadId,
          {int limit = 100}) =>
      histories.putIfAbsent(threadId, Completer.new).future;
  Future<void> close() async {
    for (final stream in deliveries) {
      if (!stream.isClosed) await stream.close();
    }
  }
}

void main() {
  const field = ValueKey<String>('ask-pandora-objective');
  const send = ValueKey<String>('ask-pandora-submit');
  late _LifecycleApi api;
  late GlobalKey<AskPandoraScreenState> key;
  late DiagnosticsStore diagnostics;

  Future<void> mount(WidgetTester tester,
      {PandoraLocalStore? store,
      Size size = const Size(390, 844),
      Map<String, Object?>? enterpriseContext = const {
        'selectedObject': {'coreMode': 'owner'}
      }}) async {
    await setTestSurface(tester, logicalSize: size);
    key = GlobalKey<AskPandoraScreenState>();
    await tester.pumpWidget(testApp(
        child: PandoraDependencies(
            auth: const FakeAuth(),
            repository: FakeRepository(),
            intelligence: api,
            diagnostics: diagnostics,
            localStore: store,
            child: AskPandoraScreen(
                key: key, enterpriseContext: enterpriseContext))));
    await tester.pumpAndSettle();
  }

  Future<void> sendText(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(field), text);
    await tester.tap(find.byKey(send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
  }

  setUp(() {
    api = _LifecycleApi();
    diagnostics = DiagnosticsStore();
    PandoraLocalAiPreference.setCachedForTesting(false);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('pandora/local_ai'), (call) async => null);
  });
  tearDown(() async {
    await api.close();
    PandoraLocalAiPreference.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('pandora/local_ai'), null);
  });

  testWidgets(
      'continuous greetings share one thread through keyboard and picker transitions',
      (tester) async {
    await mount(tester);
    for (final (index, prompt) in [
      'Hi',
      'Hello',
      'Hi',
      "What's up?",
      'What can you do for me?'
    ].indexed) {
      await sendText(tester, prompt);
      expect(api.dispatches.length, index + 1);
      if (index > 0) expect(api.dispatches.last.threadId, 'thread-core');
      api.emit(index, 'completed', reply: 'Contextual answer ${index + 1}.');
      await tester.pumpAndSettle();
    }
    final state = key.currentState!.debugChatState;
    final identity = state.conversationId;
    expect(state.turns.map((t) => t.text).toList(),
        ['Hi', 'Hello', 'Hi', "What's up?", 'What can you do for me?']);
    expect(state.turns.every((t) => t.phase == PandoraChatPhase.completed),
        isTrue);
    expect(state.turns.map((t) => t.id).toSet().length, 5);
    expect(api.activitySubscriptions, 0);
    final presentation = key.currentState!.presentationController;
    tester.view.viewInsets =
        FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    final picker = presentation.showPicker();
    expect(presentation.value.surface, PandoraChatSurface.none);
    tester.view.resetViewInsets();
    await tester.pump();
    expect(await picker, isTrue);
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier('pandora.chat.model-picker'),
        findsOneWidget);
    presentation.closeSurface();
    await tester.pumpAndSettle();
    expect(key.currentState!.debugChatState.conversationId, identity);
    expect(key.currentState!.debugChatState.threadId, 'thread-core');
    expect(
        diagnostics.events
            .any((e) => e.operation == 'chat.first_rendered_frame'),
        isTrue);
    expect(
        diagnostics.events.every(
            (e) => !e.toSafeJson().toString().contains('Contextual answer')),
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'send admits synchronously, preserves new typing, queues one visible follow-up',
      (tester) async {
    await mount(tester);
    await sendText(tester, 'First');
    await tester.enterText(find.byKey(field), 'Second');
    await tester.tap(find.byKey(send));
    await tester.pump();
    expect(api.dispatches.length, 1);
    expect(key.currentState!.debugChatState.queuedTurn?.text, 'Second');
    expect(find.text('Ready to send next'), findsOneWidget);
    await tester.enterText(find.byKey(field), 'Third draft');
    api.emit(0, 'completed', reply: 'First answer');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(api.dispatches.length, 2);
    expect(api.dispatches.last.message, 'Second');
    expect(api.dispatches.last.threadId, 'thread-core');
    expect(key.currentState!.debugChatState.draft.text, 'Third draft');
    api.emit(1, 'completed', reply: 'Second answer');
    await tester.pumpAndSettle();
    expect(key.currentState!.debugChatState.turns.length, 2);
  });

  testWidgets(
      'failure belongs to one logical turn and successful retry resolves it',
      (tester) async {
    await mount(tester);
    await sendText(tester, 'Try this');
    final original = api.dispatches.single;
    api.emit(0, 'failed_recoverably');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('pandora-chat-retry')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('pandora-chat-retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    final retry = api.dispatches.last;
    expect(retry.token.turnId, original.token.turnId);
    expect(retry.token.attemptId, isNot(original.token.attemptId));
    expect(retry.token.generation, 2);
    expect(retry.request, original.request);
    api.emit(1, 'completed', reply: 'Recovered');
    await tester.pumpAndSettle();
    expect(find.text('Recovered'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('pandora-chat-message-error')),
        findsNothing);
    expect(key.currentState!.debugChatState.turns.length, 1);
    expect(key.currentState!.debugChatState.turns.single.attempts.length, 2);
  });

  testWidgets(
      'later success de-emphasizes earlier failure without claiming it recovered',
      (tester) async {
    await mount(tester);
    await sendText(tester, 'Fail once');
    api.emit(0, 'failed_recoverably');
    await tester.pumpAndSettle();
    await sendText(tester, 'Next message');
    api.emit(1, 'completed', reply: 'Next succeeded');
    await tester.pumpAndSettle();
    expect(key.currentState!.debugChatState.turns.first.phase,
        PandoraChatPhase.failedRecoverably);
    expect(
        find.text('This earlier message was not completed.'), findsOneWidget);
    expect(find.text('This message could not be completed. You can retry it.'),
        findsNothing);
  });

  testWidgets(
      'stream chunks use independent offsets and Auto remains routing preference',
      (tester) async {
    await mount(tester);
    await sendText(tester, 'Stream');
    api.emit(0, 'streaming', sequence: 2, streamSequence: 1, delta: 'One');
    api.emit(0, 'streaming', sequence: 2, streamSequence: 2, delta: ' two');
    api.emit(0, 'streaming',
        sequence: 2, streamSequence: 2, delta: ' duplicate');
    await tester.pump();
    expect(key.currentState!.debugChatState.turns.single.reply, 'One two');
    expect(key.currentState!.debugChatState.turns.single.phase,
        PandoraChatPhase.streaming);
    api.emit(0, 'completed', sequence: 3, reply: 'One two.');
    await tester.pumpAndSettle();
    expect(key.currentState!.debugChatState.preferences.isAuto, isTrue);
    expect(key.currentState!.debugChatState.turns.single.receipt?.model,
        'fixture-execution');
    expect(find.text('fixture-execution'), findsNothing);
  });

  testWidgets(
      'cancel waits for acknowledgement then dispatches queued message without old text',
      (tester) async {
    await mount(tester);
    api.cancellation = Completer<PandoraChatWireEvent>();
    await sendText(tester, 'First');
    await tester.tap(find.byKey(const ValueKey<String>('ask-pandora-stop')));
    await tester.pump();
    expect(key.currentState!.debugChatState.activeTurn?.phase,
        PandoraChatPhase.cancelling);
    api.emit(0, 'streaming',
        sequence: 2, streamSequence: 1, delta: 'Late old text');
    await tester.pump();
    expect(find.text('Late old text'), findsNothing);
    api.cancellation!.complete(api.event(0, 'cancelled', sequence: 3));
    await tester.pumpAndSettle();
    await sendText(tester, 'After stop');
    expect(api.dispatches.length, 2);
    api.emit(1, 'completed', reply: 'New answer');
    await tester.pumpAndSettle();
    expect(key.currentState!.debugChatState.turns.first.phase,
        PandoraChatPhase.cancelled);
    expect(key.currentState!.debugChatState.turns.last.reply, 'New answer');
    expect(tester.takeException(), isNull);
  });

  testWidgets('late history response cannot paint into New Chat',
      (tester) async {
    await mount(tester);
    final loading = key.currentState!.loadThread('old-thread');
    await tester.pump();
    key.currentState!.newChat();
    await tester.pump();
    api.histories['old-thread']!.complete([
      PandoraIntelligenceMessage(
          id: 'old-message',
          threadId: 'old-thread',
          authorRole: 'assistant',
          content: 'Old thread text',
          createdAt: DateTime.utc(2026))
    ]);
    await loading;
    await tester.pumpAndSettle();
    expect(key.currentState!.debugChatState.threadId, isNull);
    expect(key.currentState!.debugChatState.history, isEmpty);
    expect(find.text('Old thread text'), findsNothing);
  });

  testWidgets(
      'restart restores the same thread and draft without an extra dispatch',
      (tester) async {
    final store = MemoryPandoraLocalStore();
    await mount(tester, store: store);
    await sendText(tester, 'Remember');
    api.emit(0, 'completed', reply: 'Remembered');
    await tester.pumpAndSettle();
    final before = key.currentState!.debugChatState;
    await tester.enterText(find.byKey(field), 'Saved draft');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await mount(tester, store: store);
    final after = key.currentState!.debugChatState;
    expect(after.threadId, before.threadId);
    expect(after.conversationId, before.conversationId);
    expect(after.turns.single.id, before.turns.single.id);
    expect(after.draft.text, 'Saved draft');
    expect(api.dispatches.length, 1);
  });

  testWidgets(
      'offline before acceptance resends the same operation and releases the queued follow-up only after binding',
      (tester) async {
    api.autoAccept = false;
    await mount(tester);
    await sendText(tester, 'Offline first');
    final original = api.dispatches.single;
    await sendText(tester, 'Queued continuation');
    api.deliveries.single.addError(const PandoraIntelligenceException(
        'Connection interrupted',
        outcomeUnknown: true));
    await tester.pumpAndSettle();
    expect(key.currentState!.debugChatState.turns.first.failure?.code,
        'CHAT_NOT_ADMITTED');
    expect(api.dispatches.length, 1);
    expect(key.currentState!.debugChatState.queuedTurn?.text,
        'Queued continuation');
    api.autoAccept = true;
    await tester.tap(find.byKey(const ValueKey<String>('pandora-chat-retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    final resend = api.dispatches[1];
    expect(resend.token.turnId, original.token.turnId);
    expect(resend.token.attemptId, original.token.attemptId);
    expect(resend.token.generation, 1);
    expect(resend.token.deliveryEpoch, original.token.deliveryEpoch + 1);
    expect(resend.isRetry, isFalse);
    expect(resend.request, original.request);
    api.emit(1, 'completed', reply: 'Accepted once');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(api.dispatches.length, 3);
    expect(api.dispatches.last.threadId, 'thread-core');
    api.emit(2, 'completed', reply: 'Continued');
    await tester.pumpAndSettle();
    expect(key.currentState!.debugChatState.turns.length, 2);
    expect(key.currentState!.debugChatState.turns.first.attempts.length, 1);
    expect(key.currentState!.debugChatState.turns.first.reply, 'Accepted once');
  });

  testWidgets(
      'lost retry acknowledgement retransmits the same retry attempt and generation',
      (tester) async {
    await mount(tester);
    await sendText(tester, 'Recover request');
    api.emit(0, 'failed_recoverably');
    await tester.pumpAndSettle();
    api.autoAccept = false;
    await tester.tap(find.byKey(const ValueKey<String>('pandora-chat-retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    final retry = api.dispatches[1];
    api.deliveries[1].addError(const PandoraIntelligenceException(
        'Retry acceptance was interrupted',
        outcomeUnknown: true));
    await tester.pumpAndSettle();
    expect(key.currentState!.debugChatState.turns.single.failure?.code,
        'CHAT_NOT_ADMITTED');
    api.autoAccept = true;
    await tester.tap(find.byKey(const ValueKey<String>('pandora-chat-retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    final resend = api.dispatches[2];
    expect(resend.token.attemptId, retry.token.attemptId);
    expect(resend.token.generation, 2);
    expect(resend.token.deliveryEpoch, retry.token.deliveryEpoch + 1);
    expect(resend.expectedGeneration, 1);
    expect(resend.isRetry, isTrue);
    expect(resend.request, retry.request);
    api.emit(2, 'completed', reply: 'Recovered once');
    await tester.pumpAndSettle();
    expect(key.currentState!.debugChatState.turns.single.attempts.length, 2);
    expect(
        key.currentState!.debugChatState.turns.single.reply, 'Recovered once');
  });

  testWidgets(
      'unadmitted cancellation waits for an atomic receipt and never sends again',
      (tester) async {
    api.autoAccept = false;
    api.cancellation = Completer<PandoraChatWireEvent>();
    await mount(tester);
    await sendText(tester, 'Cancel offline request');
    final original = api.dispatches.single;
    api.deliveries.single.addError(const PandoraIntelligenceException(
        'Connection interrupted',
        outcomeUnknown: true));
    await tester.pumpAndSettle();
    await tester.tap(find
        .bySemanticsIdentifier('pandora.chat.cancel.${original.token.turnId}'));
    await tester.pump();
    expect(key.currentState!.debugChatState.activeTurn?.phase,
        PandoraChatPhase.cancelling);
    expect(api.cancelRequests.single.attemptId, original.token.attemptId);
    expect(api.cancelRequests.single.generation, 1);
    api.cancellation!.complete(PandoraChatWireEvent.fromJson({
      'protocolVersion': 2,
      'organizationId': api.organizationId,
      'turnId': original.token.turnId,
      'attemptId': original.token.attemptId,
      'generation': 1,
      'currentGeneration': 1,
      'sequence': 1,
      'status': 'cancelled',
      'type': 'cancelled',
      'found': true,
      'admitted': false,
      'admissionCancelled': true,
      'retryable': false,
      'cancellationRequested': true,
    }));
    await tester.pumpAndSettle();
    expect(key.currentState!.debugChatState.turns.single.phase,
        PandoraChatPhase.cancelled);
    expect(key.currentState!.debugChatState.hasPendingWork, isFalse);
    expect(key.currentState!.debugChatState.threadId, isNull);
    expect(api.dispatches.length, 1);
    key.currentState!.newChat();
    await tester.pumpAndSettle();
    expect(key.currentState!.debugChatState.turns, isEmpty);
  });

  testWidgets(
      'structured team clarification preserves its route regardless of reply wording',
      (tester) async {
    await mount(tester, enterpriseContext: const {});
    await sendText(tester, 'Invite a member');
    api.emit(0, 'completed', reply: 'Who should be included?', extra: const {
      'conversationLane': 'team_admin',
      'needsClarification': true,
    });
    await tester.pumpAndSettle();
    expect(
        key.currentState!.debugChatState.turns.single.receipt
            ?.routing['conversationLane'],
        'team_admin');
    await sendText(tester, 'Call Mark');
    expect(api.dispatches.length, 2);
    expect(api.deviceAdmissions, 0);
    api.emit(1, 'completed',
        reply: 'Please give me the email address for Mark.');
    await tester.pumpAndSettle();
    expect(key.currentState!.debugChatState.turns.last.reply,
        'Please give me the email address for Mark.');
  });

  testWidgets(
      'Stop during device Activity admission prevents all native preparation and effects',
      (tester) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('pandora/device_agent'),
            (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('pandora/device_agent'), null));
    api.deviceAdmission = Completer<PandoraDeviceActivityExecution>();
    await mount(tester, enterpriseContext: const {});
    await sendText(tester, 'Call Mark');
    expect(api.deviceAdmissions, 1);
    await tester.tap(find.byKey(const ValueKey<String>('ask-pandora-stop')));
    await tester.pumpAndSettle();
    expect(key.currentState!.debugChatState.turns.single.phase,
        PandoraChatPhase.cancelled);
    api.deviceAdmission!.complete(const PandoraDeviceActivityExecution(
        jobId: 'late-device-job', events: Stream.empty()));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(api.dispatches, isEmpty);
    expect(api.deviceFacts.single.jobId, 'late-device-job');
    expect(api.deviceFacts.single.operationId,
        key.currentState!.debugChatState.turns.single.attempt!.token.attemptId);
    expect(api.deviceFacts.single.stage, 'cancelled');
    expect(key.currentState!.debugChatState.turns.single.phase,
        PandoraChatPhase.cancelled);
  });

  testWidgets(
      'Activity details and controls belong to the captured turn and stop accepting edits after visible content',
      (tester) async {
    await mount(tester);
    await sendText(tester, 'Inspect the project status');
    final original = api.dispatches.single;
    expect(api.activitySubscriptions, 0);
    await tester.tap(find.bySemanticsIdentifier(
        'pandora.chat.details.${original.token.turnId}'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(api.activitySubscriptions, 1);
    await tester.enterText(
        find.byKey(const ValueKey<String>('pandora-chat-control-input')),
        'Check the latest release only');
    await tester
        .tap(find.byKey(const ValueKey<String>('pandora-chat-add-constraint')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(api.controls.single.jobId, 'activity-${original.token.turnId}');
    expect(api.controls.single.type, PandoraActivityControlType.constraint);
    expect(api.controls.single.instruction, 'Check the latest release only');
    api.emit(0, 'streaming',
        sequence: 2, streamSequence: 1, delta: 'The current status');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey<String>('pandora-chat-control-input')),
        findsNothing);
    expect(find.text('Send a new message to continue or change direction.'),
        findsOneWidget);
    key.currentState!.presentationController.closeSurface();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(key.currentState!.debugChatState.turns.single.id,
        original.token.turnId);
    api.emit(0, 'completed',
        sequence: 3, reply: 'The current status is ready.');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(api.controls.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'late service catalog cannot stack a context sheet over a newer picker intent',
      (tester) async {
    api.registry = Completer<PandoraCapabilityRegistry>();
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey<String>('ask-pandora-plus')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey<String>('ask-pandora-menu-services')));
    await tester.pump();
    final presentation = key.currentState!.presentationController;
    await presentation.showPicker();
    await tester.pumpAndSettle();
    api.registry!.complete(PandoraCapabilityRegistry(
        contractVersion: 'fixture',
        observedAt: DateTime.utc(2026),
        projectRequired: false,
        providers: const []));
    await tester.pumpAndSettle();
    expect(presentation.value.surface, PandoraChatSurface.picker);
    expect(find.bySemanticsIdentifier('pandora.chat.model-picker'),
        findsOneWidget);
    expect(find.text('Services'), findsNothing);
    presentation.closeSurface();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'restored unadmitted retry without cached attachment bytes can cancel without resending work',
      (tester) async {
    final store = MemoryPandoraLocalStore();
    await mount(tester, store: store);
    await sendText(tester, 'Retry with attachment');
    api.emit(0, 'failed_recoverably');
    await tester.pumpAndSettle();
    api.autoAccept = false;
    await tester.tap(find.byKey(const ValueKey<String>('pandora-chat-retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    final retry = api.dispatches[1];
    api.deliveries[1].addError(const PandoraIntelligenceException(
        'Retry acceptance interrupted',
        outcomeUnknown: true));
    await tester.pumpAndSettle();
    final before = key.currentState!.debugChatState;
    expect(before.turns.single.failure?.code, 'CHAT_NOT_ADMITTED');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    final persistence =
        PandoraConversationStore(store, scopeId: before.scopeId);
    expect(
        await persistence.save(before.copyWith(
            revision: before.revision + 1,
            turns: [
              before.turns.single
                  .copyWith(request: const {}, requestAvailable: false)
            ])),
        isTrue);
    await persistence.flush();
    await mount(tester, store: store);
    expect(key.currentState!.debugChatState.turns.single.requestAvailable,
        isFalse);
    expect(key.currentState!.debugChatState.hasUnresolvedAdmission, isTrue);
    expect(
        find.byKey(const ValueKey<String>('pandora-chat-retry')), findsNothing);
    api.cancellation = Completer<PandoraChatWireEvent>();
    await tester.tap(find
        .bySemanticsIdentifier('pandora.chat.cancel.${retry.token.turnId}'));
    await tester.pump();
    expect(api.cancelRequests.single.attemptId, retry.token.attemptId);
    expect(api.cancelRequests.single.generation, 2);
    expect(api.dispatches.length, 2);
    api.cancellation!.complete(PandoraChatWireEvent.fromJson({
      'protocolVersion': 2,
      'organizationId': api.organizationId,
      'threadId': 'thread-core',
      'userMessageId': before.turns.single.userMessageId,
      'turnId': retry.token.turnId,
      'attemptId': retry.token.attemptId,
      'generation': 2,
      'currentGeneration': 2,
      'sequence': 1,
      'status': 'cancelled',
      'type': 'cancelled',
      'found': true,
      'admitted': false,
      'admissionCancelled': true,
      'retryable': false,
      'cancellationRequested': true,
    }));
    await tester.pumpAndSettle();
    expect(key.currentState!.debugChatState.turns.single.phase,
        PandoraChatPhase.cancelled);
    expect(key.currentState!.debugChatState.hasPendingWork, isFalse);
    api.autoAccept = true;
    await sendText(tester, 'Continue safely');
    expect(api.dispatches.length, 3);
    expect(api.dispatches.last.threadId, 'thread-core');
    api.emit(2, 'completed', reply: 'Continued on the same thread');
    await tester.pumpAndSettle();
  });

  testWidgets(
      'mixed imported history and v2 turns retain server order and append the next turn last',
      (tester) async {
    await mount(tester);
    PandoraChatWireEvent receipt(String turnId) =>
        PandoraChatWireEvent.fromJson({
          'protocolVersion': 2,
          'organizationId': api.organizationId,
          'threadId': 'mixed-thread',
          'turnId': turnId,
          'attemptId': '$turnId-attempt',
          'generation': 1,
          'sequence': 3,
          'status': 'completed',
          'type': 'completed',
          'reply': '$turnId reply',
          'activityJobId': '$turnId-job',
          'userMessageId': '$turnId-user',
          'assistantMessageId': '$turnId-assistant',
        });
    PandoraIntelligenceMessage cloud(String turnId, int serverSequence) =>
        PandoraIntelligenceMessage(
            id: '$turnId-user',
            threadId: 'mixed-thread',
            authorRole: 'user',
            content: turnId,
            createdAt: DateTime.utc(2026, 1, 1),
            turnId: turnId,
            sequence: serverSequence,
            turnReceipt: receipt(turnId));
    final loading = key.currentState!.loadThread('mixed-thread');
    await tester.pump();
    api.histories['mixed-thread']!.complete([
      cloud('cloud-a', 1),
      PandoraIntelligenceMessage(
          id: 'local-user',
          threadId: 'mixed-thread',
          authorRole: 'user',
          content: 'Local middle',
          createdAt: DateTime.utc(2026),
          clientOrigin: 'local_device',
          clientHistoryTurnId: 'local-turn'),
      PandoraIntelligenceMessage(
          id: 'local-reply',
          threadId: 'mixed-thread',
          authorRole: 'assistant',
          content: 'Local middle reply',
          createdAt: DateTime.utc(2026),
          clientOrigin: 'local_device',
          clientHistoryTurnId: 'local-turn'),
      cloud('cloud-c', 2),
    ]);
    await loading;
    await tester.pumpAndSettle();
    var viewport =
        tester.widget<PandoraChatViewport>(find.byType(PandoraChatViewport));
    expect(viewport.items.map((item) => item.id),
        ['cloud-a', 'history:local-user', 'history:local-reply', 'cloud-c']);
    expect(
        key.currentState!.debugChatState.turns
            .map((turn) => turn.serverSequence),
        [1, 2]);
    await sendText(tester, 'After restored history');
    viewport =
        tester.widget<PandoraChatViewport>(find.byType(PandoraChatViewport));
    expect(viewport.items.last.id, api.dispatches.single.token.turnId);
    expect(api.dispatches.single.threadId, 'mixed-thread');
    api.emit(0, 'completed', reply: 'Next on the same thread');
    await tester.pumpAndSettle();
  });
}
