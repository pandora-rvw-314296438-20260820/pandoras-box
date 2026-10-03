part of '../ask_pandora_screen.dart';

extension _PandoraHistoryProjection on AskPandoraScreenState {
  bool _replaceVerifiedHistory(
      PandoraChatLoadToken load,
      List<PandoraIntelligenceMessage> messages,
      PandoraConversationSnapshot? cached) {
    if (!_chat.matchesLoad(load)) return false;
    final legacy = <PandoraChatHistoryMessage>[];
    // The server response is already ordered across imported/local and v2 rows.
    // Capture that shared presentation order; server turn revisions stay separate.
    final order = <String, int>{
      for (final entry in messages.indexed) entry.$2.id: entry.$1 + 1
    };
    final byTurn = <String, List<PandoraIntelligenceMessage>>{};
    for (final message in messages) {
      if (message.threadId != load.threadId) return false;
      final turnId = message.turnId;
      if (turnId == null || message.turnReceipt == null) {
        legacy.add(PandoraChatHistoryMessage(
            id: message.id,
            threadId: message.threadId,
            role: message.authorRole,
            text: message.content,
            createdAt: message.createdAt,
            sequence: order[message.id],
            inspection: message.inspectHandoff?.inspectionJson));
      } else {
        byTurn.putIfAbsent(turnId, () => []).add(message);
      }
    }
    final turns = <PandoraChatTurn>[];
    for (final entry in byTurn.entries) {
      final userRows = entry.value.where((m) => m.isUser).toList();
      // Never fabricate a user/assistant pair when the bounded server view
      // lacks its user row. Keep its canonical message identity instead.
      if (userRows.length != 1) {
        for (final row in entry.value) {
          legacy.add(PandoraChatHistoryMessage(
              id: row.id,
              threadId: row.threadId,
              role: row.authorRole,
              text: row.content,
              createdAt: row.createdAt,
              turnId: row.turnId,
              attemptId: row.attemptId,
              sequence: order[row.id],
              inspection: row.inspectHandoff?.inspectionJson));
        }
        continue;
      }
      final user = userRows.single;
      final receipt = user.turnReceipt!;
      receipt.requireIdentity(
          organizationId: _dependencies.intelligence!.organizationId,
          threadId: load.threadId,
          turnId: entry.key);
      final prior = cached?.state.turn(entry.key);
      final usablePrior = prior?.text == user.content ? prior : null;
      final currentPrior =
          usablePrior?.attempt?.token.generation == receipt.generation
              ? usablePrior?.attempt
              : null;
      var phase = _phaseFromReceipt(receipt);
      final cancelledDisplay = currentPrior?.cancellationRequested == true;
      if (phase == PandoraChatPhase.completed && cancelledDisplay) {
        phase = PandoraChatPhase.cancelled;
      }
      final token = PandoraChatAttemptToken(
          scopeId: load.scopeId,
          scopeEpoch: load.scopeEpoch,
          conversationId: load.conversationId,
          turnId: receipt.turnId,
          attemptId: receipt.attemptId,
          generation: receipt.generation);
      final failure = phase == PandoraChatPhase.failedRecoverably ||
              phase == PandoraChatPhase.failedPermanently ||
              phase == PandoraChatPhase.reconciling
          ? PandoraChatFailure(
              message: receipt.plainMessage,
              code: receipt.errorCode,
              recoverable: receipt.recoverable,
              outcomeUnknown: phase == PandoraChatPhase.reconciling)
          : null;
      final execution = _wireReceipt(receipt);
      final attempt = PandoraChatAttempt(
          token: token,
          phase: phase,
          startedAt: currentPrior?.startedAt ?? user.createdAt,
          finishedAt: currentPrior?.finishedAt,
          lastSequence: receipt.sequence,
          lastStreamSequence: currentPrior?.lastStreamSequence ?? 0,
          activityJobId: receipt.activityJobId,
          failure: failure,
          receipt: execution,
          cancellationRequested: cancelledDisplay);
      turns.add(PandoraChatTurn(
          id: receipt.turnId,
          text: user.content,
          createdAt: user.createdAt,
          sequence: order[user.id]!,
          phase: phase,
          preferences:
              usablePrior?.preferences ?? const PandoraChatPreferences.auto(),
          request: usablePrior?.request ?? const {},
          requestAvailable: usablePrior?.requestAvailable ?? false,
          attempts: [attempt],
          reply: receipt.status == 'completed' ? receipt.reply : '',
          userMessageId: user.id,
          assistantMessageId: receipt.assistantMessageId,
          serverSequence: user.sequence,
          failure: failure,
          receipt: execution));
    }
    turns.sort((a, b) => a.sequence.compareTo(b.sequence));
    return _chat.replaceHistory(load, legacy,
        reconstructedTurns: turns,
        preferences:
            cached?.state.preferences ?? const PandoraChatPreferences.auto());
  }

  PandoraChatPhase _phaseFromReceipt(PandoraChatWireEvent event) =>
      switch (event.status) {
        'completed' => PandoraChatPhase.completed,
        'cancelled' || 'canceled' => PandoraChatPhase.cancelled,
        'superseded' => PandoraChatPhase.superseded,
        'failed_recoverably' ||
        'failedRecoverably' ||
        'failed_recoverable' =>
          PandoraChatPhase.failedRecoverably,
        'failed_permanently' ||
        'failedPermanently' ||
        'failed_permanent' =>
          PandoraChatPhase.failedPermanently,
        _ => PandoraChatPhase.reconciling,
      };
}
