part of 'pandora_intelligence_api.dart';

/// A receipt from the scoped v2 endpoint. This is transport evidence; the chat
/// controller remains responsible for accepting it against its active token.
class PandoraChatWireEvent {
  PandoraChatWireEvent._(Map<String, dynamic> json)
      : data = Map<String, dynamic>.unmodifiable(json);

  final Map<String, dynamic> data;
  String get organizationId => data['organizationId'] as String;
  String? get threadId => data['threadId'] as String?;
  String get turnId => data['turnId'] as String;
  String get attemptId => data['attemptId'] as String;
  String? get activityJobId => _optionalText(data['activityJobId']);
  String? get userMessageId => _optionalText(data['userMessageId']);
  String? get assistantMessageId => _optionalText(data['assistantMessageId']);
  int get generation => (data['generation'] as num).toInt();
  int get sequence => (data['sequence'] as num).toInt();
  int? get streamSequence => (data['streamSequence'] as num?)?.toInt();
  String get type => _text(data['type'], fallback: status);
  String get status => data['status'] as String;
  String get textDelta =>
      data['textDelta'] is String ? data['textDelta'] as String : '';
  String get reply => _text(data['reply']);
  bool get replayed => data['replayed'] == true;
  bool get admissionCancelled => data['admissionCancelled'] == true;
  bool get recoverable =>
      data['recoverable'] != false &&
      data['retryable'] != false &&
      !const {'failed_permanently', 'failedPermanently', 'failed_permanent'}
          .contains(status);
  bool get outcomeUnknown =>
      data['outcomeUnknown'] == true ||
      const {'reconciling', 'reconciliation_required', 'outcome_unknown'}
          .contains(status);
  String? get errorCode => _optionalText(data['errorCode'] ?? data['code']);
  String get plainMessage => _text(
        data['plainMessage'],
        fallback: outcomeUnknown
            ? 'Checking the outcome of this message…'
            : recoverable
                ? 'This message could not be completed. You can retry it.'
                : 'This message could not be completed.',
      );
  bool get isTerminal => const {
        'completed',
        'cancelled',
        'canceled',
        'failed_recoverably',
        'failed_permanently',
        'failedRecoverably',
        'failedPermanently',
        'failed_recoverable',
        'failed_permanent',
        'superseded',
      }.contains(status);
  PandoraIntelligenceTurn? get turn =>
      status == 'completed' ? PandoraIntelligenceTurn.fromJson(data) : null;

  factory PandoraChatWireEvent.fromJson(Map<String, dynamic> json) {
    final initialCancellation = json['generation'] == 1 &&
        json['threadId'] == null &&
        json['userMessageId'] == null;
    final retryCancellation = json['generation'] is num &&
        (json['generation'] as num) > 1 &&
        json['threadId'] is String &&
        (json['threadId'] as String).isNotEmpty &&
        json['userMessageId'] is String &&
        (json['userMessageId'] as String).isNotEmpty;
    final admissionCancelled = json['admissionCancelled'] == true &&
        json['found'] == true &&
        json['admitted'] == false &&
        json['status'] == 'cancelled' &&
        (initialCancellation || retryCancellation) &&
        json['activityJobId'] == null &&
        json['assistantMessageId'] == null &&
        json['sequence'] == 1 &&
        json['retryable'] == false &&
        json['cancellationRequested'] == true &&
        json['textDelta'] == null &&
        json['reply'] == null &&
        json['type'] != 'delta';
    if (json['protocolVersion'] != 2 ||
        const [
          'organizationId',
          'turnId',
          'attemptId',
          'status'
        ].any((key) => json[key] is! String || (json[key] as String).isEmpty) ||
        (!admissionCancelled &&
            (json['threadId'] is! String ||
                (json['threadId'] as String).isEmpty)) ||
        (json['admissionCancelled'] == true && !admissionCancelled) ||
        (json['admitted'] == false && !admissionCancelled) ||
        json['generation'] is! num ||
        (json['generation'] as num) < 1 ||
        (json['generation'] as num) % 1 != 0 ||
        json['sequence'] is! num ||
        (json['sequence'] as num) < 0 ||
        (json['sequence'] as num) % 1 != 0 ||
        (json['streamSequence'] != null &&
            (json['streamSequence'] is! num ||
                (json['streamSequence'] as num) < 1 ||
                (json['streamSequence'] as num) % 1 != 0)) ||
        (json['type'] == 'delta' && json['streamSequence'] == null) ||
        (json['textDelta'] != null && json['textDelta'] is! String) ||
        (json['status'] == 'completed' &&
            (json['reply'] is! String ||
                (json['reply'] as String).trim().isEmpty))) {
      throw const FormatException('Invalid chat lifecycle receipt.');
    }
    final frozen = freezePandoraChatMap(json);
    return PandoraChatWireEvent._(Map<String, dynamic>.from(frozen));
  }

  void requireIdentity({
    required String organizationId,
    required String turnId,
    String? attemptId,
    int? generation,
    String? threadId,
  }) {
    if (this.organizationId != organizationId ||
        this.turnId != turnId ||
        (attemptId != null && this.attemptId != attemptId) ||
        (generation != null && this.generation != generation) ||
        (threadId != null && this.threadId != threadId)) {
      throw const FormatException('Chat receipt belongs to another execution.');
    }
  }
}

PandoraIntelligenceException _chatProtocolFailure(Map<String, dynamic> payload,
    {required int status}) {
  final denied = status == 401 || status == 403;
  final invalid = status == 400 || status == 422;
  final code = _text(
      payload['errorCode'] ?? payload['error'] ?? payload['code'],
      fallback: 'CHAT_REQUEST_UNCONFIRMED');
  return PandoraIntelligenceException(
    denied
        ? 'Please sign in again to continue this conversation.'
        : invalid
            ? 'Pandora could not accept this message. Check it and try again.'
            : 'Pandora could not confirm this message. Checking its outcome…',
    code: RegExp(r'^[A-Z][A-Z0-9_]{1,100}$').hasMatch(code)
        ? code
        : 'CHAT_REQUEST_UNCONFIRMED',
    recoverable: !denied && !invalid,
    // A transport/5xx response is not proof that provider work did not happen.
    outcomeUnknown: !denied && !invalid && payload['accepted'] != false,
  );
}
