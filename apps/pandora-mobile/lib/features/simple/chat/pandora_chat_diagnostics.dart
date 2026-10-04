part of '../ask_pandora_screen.dart';

/// Bounded, body-free instrumentation. These observations are intentionally
/// separate from both conversational content and transient generation labels.
class _ChatTimingObservation {
  _ChatTimingObservation() : clock = Stopwatch()..start();
  final Stopwatch clock;
  final Set<String> recorded = {};
}

extension _PandoraChatDiagnostics on AskPandoraScreenState {
  void _observeSpan(PandoraChatAttemptToken token, String stage,
      {bool failed = false}) {
    if (!_sameAttempt(token)) return;
    final timing = _timings[token.turnId];
    if (timing == null ||
        !timing.recorded
            .add('${token.attemptId}:${token.deliveryEpoch}:$stage')) {
      return;
    }
    _dependencies.diagnostics.record(DiagnosticEvent(
      occurredAt: DateTime.now().toUtc(),
      operation: 'chat.$stage',
      method: 'observation',
      routeTemplate: '/intelligence/chat',
      outcome: failed ? DiagnosticOutcome.failed : DiagnosticOutcome.succeeded,
      duration: timing.clock.elapsed,
      requestId: token.attemptId,
    ));
  }

  void _observeContent(PandoraChatAttemptToken token) {
    final timing = _timings[token.turnId];
    if (timing == null ||
        timing.recorded.contains(
            '${token.attemptId}:${token.deliveryEpoch}:first_content')) {
      return;
    }
    _observeSpan(token, 'first_content');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final turn = _chat.state.turn(token.turnId);
      if (_sameAttempt(token) &&
          turn?.phase != PandoraChatPhase.cancelled &&
          turn?.reply.isNotEmpty == true) {
        _observeSpan(token, 'first_rendered_frame');
      }
    });
  }
}
