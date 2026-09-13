import 'package:flutter/services.dart';

enum PandoraCommunicationKind { call, sms }

class PandoraCommunicationRequest {
  const PandoraCommunicationRequest._({
    required this.kind,
    required this.recipient,
    this.message,
  });

  factory PandoraCommunicationRequest.call(String recipient) =>
      PandoraCommunicationRequest._(
        kind: PandoraCommunicationKind.call,
        recipient: recipient,
      );

  factory PandoraCommunicationRequest.sms(
    String recipient, {
    String? message,
  }) => PandoraCommunicationRequest._(
    kind: PandoraCommunicationKind.sms,
    recipient: recipient,
    message: message,
  );

  final PandoraCommunicationKind kind;
  final String recipient;
  final String? message;

  static final RegExp _recipientPattern = RegExp(r'^[0-9+*#(). -]{1,64}$');

  static bool isSupportedRecipient(String recipient) {
    final normalized = recipient.trim();
    return _recipientPattern.hasMatch(normalized) &&
        RegExp(r'\d').allMatches(normalized).length >= 3;
  }

  Map<String, Object?> toMap() {
    final normalizedRecipient = recipient.trim();
    if (!isSupportedRecipient(normalizedRecipient)) {
      throw const FormatException(
        'Communication recipient must be a bounded phone-number target.',
      );
    }
    if (kind == PandoraCommunicationKind.call && message != null) {
      throw const FormatException('Call handoffs cannot include an SMS body.');
    }
    if (message != null && message!.length > 2000) {
      throw const FormatException(
        'SMS body exceeds the bounded handoff limit.',
      );
    }

    return <String, Object?>{
      'kind': switch (kind) {
        PandoraCommunicationKind.call => 'call',
        PandoraCommunicationKind.sms => 'sms',
      },
      'recipient': normalizedRecipient,
      if (kind == PandoraCommunicationKind.sms && message != null)
        'message': message,
    };
  }
}

class PandoraCommunicationHandoffResult {
  const PandoraCommunicationHandoffResult({
    required this.kind,
    required this.status,
    required this.handoff,
    required this.userConfirmationRequired,
  });

  final PandoraCommunicationKind kind;
  final String status;
  final String handoff;
  final bool userConfirmationRequired;

  bool get opened => status == 'opened';

  factory PandoraCommunicationHandoffResult.fromMap(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'Communication handoff result must be a map.',
      );
    }
    final map = <String, Object?>{};
    for (final entry in raw.entries) {
      if (entry.key is! String) {
        throw const FormatException(
          'Communication handoff result contains a non-string key.',
        );
      }
      map[entry.key as String] = entry.value;
    }

    final kind = switch (map['kind']) {
      'call' => PandoraCommunicationKind.call,
      'sms' => PandoraCommunicationKind.sms,
      _ => throw const FormatException('Unknown communication handoff kind.'),
    };
    final status = map['status'];
    if (status != 'opened' && status != 'unavailable') {
      throw const FormatException('Unknown communication handoff status.');
    }
    final handoff = map['handoff'];
    final expectedHandoff = switch (kind) {
      PandoraCommunicationKind.call => 'system_dialer',
      PandoraCommunicationKind.sms => 'system_sms_composer',
    };
    if (handoff != expectedHandoff) {
      throw const FormatException('Unexpected communication handoff surface.');
    }
    if (map['userConfirmationRequired'] != true) {
      throw const FormatException(
        'Communication handoff must preserve explicit user confirmation.',
      );
    }

    return PandoraCommunicationHandoffResult(
      kind: kind,
      status: status as String,
      handoff: handoff as String,
      userConfirmationRequired: true,
    );
  }
}

class PandoraCommunicationsClient {
  PandoraCommunicationsClient({
    MethodChannel channel = const MethodChannel('pandora/device_agent'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<PandoraCommunicationHandoffResult> open(
    PandoraCommunicationRequest request,
  ) async {
    final raw = await _channel.invokeMethod<Object?>(
      'openCommunicationComposer',
      request.toMap(),
    );
    return PandoraCommunicationHandoffResult.fromMap(raw);
  }
}
