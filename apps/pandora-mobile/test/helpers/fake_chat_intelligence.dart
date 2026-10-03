import 'package:pandora_mobile/core/chat/pandora_chat_state.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/platform/pandora_native_io.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Exercises the scoped chat path without calling a provider or Supabase.
class FakeChatIntelligence extends PandoraIntelligenceApi {
  FakeChatIntelligence(
      {this.onReply,
      this.startFailure,
      this.events = const Stream<Map<String, dynamic>>.empty()})
      : super(
          client: SupabaseClient(
            'https://example.supabase.co',
            'fixture-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
          organizationId: 'fixture-owner-organization',
        );

  final Future<PandoraIntelligenceTurn> Function(String message)? onReply;
  final PandoraIntelligenceException? startFailure;
  final Stream<Map<String, dynamic>> events;
  String? lastMessage;
  Map<String, Object?>? lastEnterpriseContext;
  String? lastThreadId;
  final List<PandoraChatDispatch> dispatches = <PandoraChatDispatch>[];
  final Map<String, PandoraChatWireEvent> _receipts = {};

  @override
  Stream<PandoraChatWireEvent> executeChatTurn(
    PandoraChatDispatch dispatch,
  ) async* {
    dispatches.add(dispatch);
    lastMessage = dispatch.message;
    lastThreadId = dispatch.threadId;
    final enterprise = dispatch.request['enterpriseContext'];
    lastEnterpriseContext =
        enterprise is Map ? Map<String, Object?>.from(enterprise) : null;
    if (startFailure != null) throw startFailure!;
    final identity = <String, dynamic>{
      'protocolVersion': 2,
      'organizationId': organizationId,
      'threadId': dispatch.threadId ?? 'fixture-chat-thread',
      'turnId': dispatch.token.turnId,
      'attemptId': dispatch.token.attemptId,
      'activityJobId': 'fixture-chat-execution',
      'userMessageId': 'user-${dispatch.token.turnId}',
      'generation': dispatch.token.generation,
    };
    final accepted = PandoraChatWireEvent.fromJson({
      ...identity,
      'type': 'accepted',
      'status': 'accepted',
      'sequence': 1,
    });
    _receipts[dispatch.token.turnId] = accepted;
    yield accepted;
    final turn = await Future<PandoraIntelligenceTurn>.sync(() =>
        onReply?.call(dispatch.message) ??
        const PandoraIntelligenceTurn(
          threadId: 'fixture-chat-thread',
          reply: 'Conversation started.',
          intent: 'conversation',
          confidence: 1,
          needsClarification: false,
        ));
    final completed = PandoraChatWireEvent.fromJson({
      ...identity,
      'threadId': turn.threadId,
      'type': 'completed',
      'status': 'completed',
      'sequence': 2,
      'reply': turn.reply,
      'intent': turn.intent,
      'confidence': turn.confidence,
      'needsClarification': turn.needsClarification,
      'conversationLane': turn.conversationLane,
      'assistantMessageId': 'assistant-${dispatch.token.attemptId}',
      if (turn.handoff != null)
        'handoff': <String, dynamic>{
          'required': true,
          'request': turn.handoff!.request,
          'projectId': turn.handoff!.projectId,
          'source': turn.handoff!.source,
          'kind': turn.handoff!.kind,
          'section': turn.handoff!.section,
          'action': turn.handoff!.action,
          'organizationId': turn.handoff!.organizationId,
        },
    });
    _receipts[dispatch.token.turnId] = completed;
    yield completed;
  }

  @override
  Stream<Map<String, dynamic>> watchChatActivity(String activityJobId) =>
      events;

  @override
  Future<PandoraChatWireEvent?> readChatTurn({required String turnId}) async =>
      _receipts[turnId];

  @override
  Future<PandoraChatWireEvent> cancelChatTurn({
    required String turnId,
    required int generation,
    String? attemptId,
    bool acknowledgeUnknown = false,
  }) async {
    final prior = _receipts[turnId]!;
    if (prior.isTerminal) return prior;
    if (acknowledgeUnknown) {
      if (prior.status != 'outcome_unknown') {
        throw const PandoraIntelligenceException(
            'This execution is still running.',
            code: 'CHAT_OUTCOME_NOT_UNKNOWN',
            recoverable: false);
      }
      final acknowledged = PandoraChatWireEvent.fromJson({
        ...prior.data,
        'sequence': prior.sequence + 1,
        'outcomeUnknownAcknowledged': true,
        'retryable': false,
        'cancellationRequested': true,
      });
      _receipts[turnId] = acknowledged;
      return acknowledged;
    }
    final cancelled = PandoraChatWireEvent.fromJson({
      ...prior.data,
      'status': 'cancelled',
      'type': 'cancelled',
      'sequence': prior.sequence + 1,
      'retryable': false,
    });
    _receipts[turnId] = cancelled;
    return cancelled;
  }

  @override
  Future<List<PandoraIntelligenceThread>> recentThreads(
          {int limit = 30}) async =>
      const <PandoraIntelligenceThread>[];

  @override
  Future<PandoraIntelligenceTurn?> recoverCompletedChatTurn(
          String jobId) async =>
      null;

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
  }) async {
    lastMessage = message;
    lastEnterpriseContext = enterpriseContext;
    if (startFailure != null) throw startFailure!;
    return PandoraIntelligenceExecution(
      jobId: 'fixture-chat-execution',
      events: events,
      turn: Future<PandoraIntelligenceTurn>.sync(() =>
          onReply?.call(message) ??
          const PandoraIntelligenceTurn(
            threadId: 'fixture-chat-thread',
            reply: 'Conversation started.',
            intent: 'conversation',
            confidence: 1,
            needsClarification: false,
          )),
    );
  }
}
