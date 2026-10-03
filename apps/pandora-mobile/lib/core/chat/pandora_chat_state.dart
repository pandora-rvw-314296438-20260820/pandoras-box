/// Immutable client projections of the existing server-owned chat execution.
///
/// These types contain no transport or provider authority. A local pending turn
/// is an acknowledged user intent; only an adapter's verified acceptance or
/// terminal event advances its server execution state.
library;

enum PandoraChatPhase {
  pending,
  accepted,
  processing,
  streaming,
  completed,
  cancelling,
  cancelled,
  failedRecoverably,
  failedPermanently,
  reconciling,
  superseded;

  bool get isTerminal => switch (this) {
        completed ||
        cancelled ||
        failedRecoverably ||
        failedPermanently ||
        superseded =>
          true,
        _ => false,
      };

  bool get isGenerating => switch (this) {
        pending || accepted || processing || streaming => true,
        _ => false,
      };
}

/// Recursively freezes JSON-shaped request data before any asynchronous work.
Map<String, Object?> freezePandoraChatMap(Map<String, Object?> value) =>
    Map<String, Object?>.unmodifiable(
      value.map((key, item) => MapEntry(key, _freeze(item))),
    );

Object? _freeze(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.unmodifiable(
      value.map((key, item) => MapEntry(key.toString(), _freeze(item))),
    );
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  throw ArgumentError('Chat request data must be JSON-shaped.');
}

class PandoraChatPreferences {
  const PandoraChatPreferences.auto({this.reasoningMode = 'auto'})
      : selection = 'auto',
        provider = null,
        model = null,
        fallbackMode = 'allow_fallback',
        label = 'Auto';

  const PandoraChatPreferences.manual({
    required String this.provider,
    required String this.model,
    required this.label,
    this.fallbackMode = 'strict',
    this.reasoningMode = 'auto',
  }) : selection = 'manual';

  final String selection;
  final String? provider;
  final String? model;
  final String fallbackMode;
  final String reasoningMode;
  final String label;

  bool get isAuto => selection == 'auto';

  bool get isValid =>
      const {'auto', 'fast', 'deep'}.contains(reasoningMode) &&
      (isAuto ||
          (selection == 'manual' &&
              (provider?.trim().isNotEmpty ?? false) &&
              (model?.trim().isNotEmpty ?? false) &&
              const {'strict', 'allow_fallback'}.contains(fallbackMode)));

  Map<String, Object?> get modelSelectionJson => <String, Object?>{
        'selection': selection,
        if (provider != null) 'provider': provider,
        if (model != null) 'model': model,
        'fallbackMode': fallbackMode,
      };

  PandoraChatPreferences copyWithReasoning(String reasoningMode) => isAuto
      ? PandoraChatPreferences.auto(reasoningMode: reasoningMode)
      : PandoraChatPreferences.manual(
          provider: provider!,
          model: model!,
          label: label,
          fallbackMode: fallbackMode,
          reasoningMode: reasoningMode,
        );

  Map<String, Object?> toJson() => <String, Object?>{
        ...modelSelectionJson,
        'reasoningMode': reasoningMode,
        'label': label,
      };

  factory PandoraChatPreferences.fromJson(Map<String, Object?> json) {
    final mode = json['reasoningMode']?.toString() ?? 'auto';
    final value = json['selection'] == 'manual'
        ? PandoraChatPreferences.manual(
            provider: json['provider']?.toString() ?? '',
            model: json['model']?.toString() ?? '',
            label: json['label']?.toString() ?? 'Manual',
            fallbackMode: json['fallbackMode']?.toString() ?? 'strict',
            reasoningMode: mode,
          )
        : PandoraChatPreferences.auto(reasoningMode: mode);
    if (!value.isValid) throw const FormatException('Invalid chat preference.');
    return value;
  }
}

class PandoraChatAttemptToken {
  const PandoraChatAttemptToken({
    required this.scopeId,
    required this.scopeEpoch,
    required this.conversationId,
    required this.turnId,
    required this.attemptId,
    required this.generation,
    this.deliveryEpoch = 0,
  });

  final String scopeId;
  final int scopeEpoch;
  final String conversationId;
  final String turnId;
  final String attemptId;
  final int generation;

  /// Client callback fence for retransmission of the same server attempt.
  /// Never sent as a new server attempt or execution generation.
  final int deliveryEpoch;

  @override
  bool operator ==(Object other) =>
      other is PandoraChatAttemptToken &&
      scopeId == other.scopeId &&
      scopeEpoch == other.scopeEpoch &&
      conversationId == other.conversationId &&
      turnId == other.turnId &&
      attemptId == other.attemptId &&
      generation == other.generation &&
      deliveryEpoch == other.deliveryEpoch;

  @override
  int get hashCode => Object.hash(
        scopeId,
        scopeEpoch,
        conversationId,
        turnId,
        attemptId,
        generation,
        deliveryEpoch,
      );
}

class PandoraChatDraftState {
  const PandoraChatDraftState({this.text = '', this.revision = 0});
  final String text;
  final int revision;
}

class PandoraChatDraftToken {
  const PandoraChatDraftToken({
    required this.scopeEpoch,
    required this.conversationId,
    required this.revision,
  });
  final int scopeEpoch;
  final String conversationId;
  final int revision;
}

class PandoraChatLoadToken {
  const PandoraChatLoadToken({
    required this.scopeId,
    required this.scopeEpoch,
    required this.conversationId,
    required this.threadId,
  });
  final String scopeId;
  final int scopeEpoch;
  final String conversationId;
  final String threadId;
}

class PandoraChatFailure {
  const PandoraChatFailure({
    required this.message,
    this.code,
    this.recoverable = true,
    this.outcomeUnknown = false,
  });

  final String message;
  final String? code;
  final bool recoverable;
  final bool outcomeUnknown;
}

/// Factual execution details; never changes the user's routing preference.
class PandoraChatExecutionReceipt {
  PandoraChatExecutionReceipt({
    this.provider,
    this.model,
    this.providerRequestId,
    this.assistantMessageId,
    Map<String, Object?> routing = const {},
    Map<String, Object?> usage = const {},
    Map<String, Object?>? inspection,
  })  : routing = freezePandoraChatMap(routing),
        usage = freezePandoraChatMap(usage),
        inspection =
            inspection == null ? null : freezePandoraChatMap(inspection);

  final String? provider;
  final String? model;
  final String? providerRequestId;
  final String? assistantMessageId;
  final Map<String, Object?> routing;
  final Map<String, Object?> usage;

  /// Bounded read-only navigation intent, requiring an explicit user gesture.
  final Map<String, Object?>? inspection;
}

const _unchanged = Object();

class PandoraChatDeliveryFailure {
  const PandoraChatDeliveryFailure({
    required this.deliveryEpoch,
    required this.observedAt,
    required this.failure,
  });

  final int deliveryEpoch;
  final DateTime observedAt;
  final PandoraChatFailure failure;
}

class PandoraChatAttempt {
  PandoraChatAttempt({
    required this.token,
    required this.phase,
    required this.startedAt,
    this.lastSequence = 0,
    this.lastStreamSequence = 0,
    this.activityJobId,
    this.finishedAt,
    this.failure,
    this.receipt,
    this.supersededByAttemptId,
    this.cancellationRequested = false,
    List<PandoraChatDeliveryFailure> deliveryFailures = const [],
  }) : deliveryFailures =
            List<PandoraChatDeliveryFailure>.unmodifiable(deliveryFailures);

  final PandoraChatAttemptToken token;
  final PandoraChatPhase phase;
  final DateTime startedAt;
  final int lastSequence;

  /// Chunk offset is independent of the durable execution lifecycle revision.
  final int lastStreamSequence;
  final String? activityJobId;
  final DateTime? finishedAt;
  final PandoraChatFailure? failure;
  final PandoraChatExecutionReceipt? receipt;
  final String? supersededByAttemptId;
  final bool cancellationRequested;
  final List<PandoraChatDeliveryFailure> deliveryFailures;

  PandoraChatAttempt copyWith({
    PandoraChatAttemptToken? token,
    PandoraChatPhase? phase,
    int? lastSequence,
    int? lastStreamSequence,
    String? activityJobId,
    DateTime? finishedAt,
    Object? failure = _unchanged,
    PandoraChatExecutionReceipt? receipt,
    String? supersededByAttemptId,
    bool? cancellationRequested,
    List<PandoraChatDeliveryFailure>? deliveryFailures,
  }) =>
      PandoraChatAttempt(
        token: token ?? this.token,
        phase: phase ?? this.phase,
        startedAt: startedAt,
        lastSequence: lastSequence ?? this.lastSequence,
        lastStreamSequence: lastStreamSequence ?? this.lastStreamSequence,
        activityJobId: activityJobId ?? this.activityJobId,
        finishedAt: finishedAt ?? this.finishedAt,
        failure: identical(failure, _unchanged)
            ? this.failure
            : failure as PandoraChatFailure?,
        receipt: receipt ?? this.receipt,
        supersededByAttemptId:
            supersededByAttemptId ?? this.supersededByAttemptId,
        cancellationRequested:
            cancellationRequested ?? this.cancellationRequested,
        deliveryFailures: deliveryFailures ?? this.deliveryFailures,
      );
}

class PandoraChatTurn {
  PandoraChatTurn({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.sequence,
    required this.phase,
    required this.preferences,
    required Map<String, Object?> request,
    this.requestAvailable = true,
    List<PandoraChatAttempt> attempts = const [],
    this.reply = '',
    this.userMessageId,
    this.assistantMessageId,
    this.serverSequence,
    this.failure,
    this.receipt,
  })  : request = freezePandoraChatMap(request),
        attempts = List<PandoraChatAttempt>.unmodifiable(attempts);

  final String id;
  final String text;
  final DateTime createdAt;
  final int sequence;
  final PandoraChatPhase phase;
  final PandoraChatPreferences preferences;

  /// Original admitted request. Retrying must reuse this exact payload.
  final Map<String, Object?> request;
  final bool requestAvailable;
  final List<PandoraChatAttempt> attempts;
  final String reply;
  final String? userMessageId;
  final String? assistantMessageId;
  final int? serverSequence;
  final PandoraChatFailure? failure;
  final PandoraChatExecutionReceipt? receipt;

  PandoraChatAttempt? get attempt => attempts.isEmpty ? null : attempts.last;
  String get userRowId => 'user:$id';
  String get assistantRowId => 'assistant:$id';
  bool get canRetry =>
      requestAvailable &&
      phase == PandoraChatPhase.failedRecoverably &&
      failure?.outcomeUnknown != true;

  PandoraChatTurn copyWith({
    PandoraChatPhase? phase,
    PandoraChatPreferences? preferences,
    Map<String, Object?>? request,
    bool? requestAvailable,
    List<PandoraChatAttempt>? attempts,
    String? reply,
    String? userMessageId,
    String? assistantMessageId,
    int? serverSequence,
    Object? failure = _unchanged,
    Object? receipt = _unchanged,
  }) =>
      PandoraChatTurn(
        id: id,
        text: text,
        createdAt: createdAt,
        sequence: sequence,
        phase: phase ?? this.phase,
        preferences: preferences ?? this.preferences,
        request: request ?? this.request,
        requestAvailable: requestAvailable ?? this.requestAvailable,
        attempts: attempts ?? this.attempts,
        reply: reply ?? this.reply,
        userMessageId: userMessageId ?? this.userMessageId,
        assistantMessageId: assistantMessageId ?? this.assistantMessageId,
        serverSequence: serverSequence ?? this.serverSequence,
        failure: identical(failure, _unchanged)
            ? this.failure
            : failure as PandoraChatFailure?,
        receipt: identical(receipt, _unchanged)
            ? this.receipt
            : receipt as PandoraChatExecutionReceipt?,
      );
}

/// Canonical history rows retain their identities, without inventing a pairing
/// or successful execution for legacy adjacent rows.
class PandoraChatHistoryMessage {
  PandoraChatHistoryMessage({
    required this.id,
    required this.threadId,
    required this.role,
    required this.text,
    required this.createdAt,
    this.turnId,
    this.attemptId,
    this.sequence,
    Map<String, Object?>? inspection,
  }) : inspection =
            inspection == null ? null : freezePandoraChatMap(inspection);
  final String id;
  final String threadId;
  final String role;
  final String text;
  final DateTime createdAt;
  final String? turnId;
  final String? attemptId;
  final int? sequence;
  final Map<String, Object?>? inspection;
  bool get isUser => role == 'user';

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'threadId': threadId,
        'role': role,
        'text': text,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (turnId != null) 'turnId': turnId,
        if (attemptId != null) 'attemptId': attemptId,
        if (sequence != null) 'sequence': sequence,
        if (inspection != null) 'inspection': inspection,
      };

  factory PandoraChatHistoryMessage.fromJson(Map<String, Object?> json) =>
      PandoraChatHistoryMessage(
        id: json['id'] as String,
        threadId: json['threadId'] as String,
        role: json['role'] as String,
        text: json['text'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        turnId: json['turnId'] as String?,
        attemptId: json['attemptId'] as String?,
        sequence: (json['sequence'] as num?)?.toInt(),
        inspection: json['inspection'] is Map
            ? Map<String, Object?>.from(json['inspection'] as Map)
            : null,
      );
}

class PandoraChatSessionState {
  PandoraChatSessionState({
    required this.scopeId,
    required this.scopeEpoch,
    required this.conversationId,
    this.threadId,
    this.revision = 0,
    this.draft = const PandoraChatDraftState(),
    this.preferences = const PandoraChatPreferences.auto(),
    List<PandoraChatTurn> turns = const [],
    List<PandoraChatHistoryMessage> history = const [],
    this.activeTurnId,
    this.queuedTurnId,
    this.loadingHistory = false,
  })  : turns = List<PandoraChatTurn>.unmodifiable(turns),
        history = List<PandoraChatHistoryMessage>.unmodifiable(history);

  final String scopeId;
  final int scopeEpoch;
  final String conversationId;
  final String? threadId;
  final int revision;
  final PandoraChatDraftState draft;
  final PandoraChatPreferences preferences;
  final List<PandoraChatTurn> turns;
  final List<PandoraChatHistoryMessage> history;
  final String? activeTurnId;
  final String? queuedTurnId;
  final bool loadingHistory;

  PandoraChatTurn? turn(String? id) {
    if (id == null) return null;
    for (final value in turns) {
      if (value.id == id) return value;
    }
    return null;
  }

  PandoraChatTurn? get activeTurn => turn(activeTurnId);
  PandoraChatTurn? get queuedTurn => turn(queuedTurnId);
  PandoraChatAttemptToken? get activeAttempt => activeTurn?.attempt?.token;
  bool get hasUnresolvedOutcome => turns.any(
        (turn) =>
            turn.phase == PandoraChatPhase.reconciling ||
            turn.phase == PandoraChatPhase.cancelling ||
            turn.failure?.outcomeUnknown == true,
      );
  bool get hasUnresolvedAdmission => turns.any((turn) =>
      turn.phase == PandoraChatPhase.failedRecoverably &&
      turn.failure?.code == 'CHAT_NOT_ADMITTED');
  bool get hasPendingWork =>
      activeTurnId != null ||
      queuedTurnId != null ||
      loadingHistory ||
      hasUnresolvedOutcome ||
      hasUnresolvedAdmission;

  PandoraChatSessionState copyWith({
    Object? threadId = _unchanged,
    int? revision,
    PandoraChatDraftState? draft,
    PandoraChatPreferences? preferences,
    List<PandoraChatTurn>? turns,
    List<PandoraChatHistoryMessage>? history,
    Object? activeTurnId = _unchanged,
    Object? queuedTurnId = _unchanged,
    bool? loadingHistory,
  }) =>
      PandoraChatSessionState(
        scopeId: scopeId,
        scopeEpoch: scopeEpoch,
        conversationId: conversationId,
        threadId: identical(threadId, _unchanged)
            ? this.threadId
            : threadId as String?,
        revision: revision ?? this.revision,
        draft: draft ?? this.draft,
        preferences: preferences ?? this.preferences,
        turns: turns ?? this.turns,
        history: history ?? this.history,
        activeTurnId: identical(activeTurnId, _unchanged)
            ? this.activeTurnId
            : activeTurnId as String?,
        queuedTurnId: identical(queuedTurnId, _unchanged)
            ? this.queuedTurnId
            : queuedTurnId as String?,
        loadingHistory: loadingHistory ?? this.loadingHistory,
      );
}

enum PandoraChatAdmissionKind { dispatched, queued, rejected }

class PandoraChatDispatch {
  const PandoraChatDispatch({
    required this.token,
    required this.turn,
    required this.threadId,
    this.isRetry = false,
    this.expectedGeneration,
  });
  final PandoraChatAttemptToken token;
  final PandoraChatTurn turn;
  final String? threadId;
  final bool isRetry;
  final int? expectedGeneration;
  Map<String, Object?> get request => turn.request;
  PandoraChatPreferences get preferences => turn.preferences;
  String get message => turn.text;
}

class PandoraChatAdmission {
  const PandoraChatAdmission._(
    this.kind,
    this.turnId,
    this.dispatch,
    this.reason,
  );
  const PandoraChatAdmission.rejected(String reason)
      : this._(PandoraChatAdmissionKind.rejected, null, null, reason);
  const PandoraChatAdmission.queued(String turnId)
      : this._(PandoraChatAdmissionKind.queued, turnId, null, null);
  PandoraChatAdmission.dispatched(PandoraChatDispatch dispatch)
      : this._(
          PandoraChatAdmissionKind.dispatched,
          dispatch.turn.id,
          dispatch,
          null,
        );

  final PandoraChatAdmissionKind kind;
  final String? turnId;
  final PandoraChatDispatch? dispatch;
  final String? reason;
  bool get admitted => kind != PandoraChatAdmissionKind.rejected;
}
