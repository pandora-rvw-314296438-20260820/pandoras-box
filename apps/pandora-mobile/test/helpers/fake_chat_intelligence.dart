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
