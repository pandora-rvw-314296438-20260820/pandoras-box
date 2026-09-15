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
  }) =>
      PandoraCommunicationRequest._(
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

enum PandoraDirectCommunicationState {
  permissionRequired,
  permanentlyDenied,
  restricted,
  subscriptionRequired,
  dispatching,
  submitted,
  sent,
  delivered,
  deliveryFailed,
  initiated,
  failed,
  fallbackRequired,
}

PandoraDirectCommunicationState _parseDirectState(Object? value) =>
    switch (value) {
      'permission_required' =>
        PandoraDirectCommunicationState.permissionRequired,
      'permanently_denied' => PandoraDirectCommunicationState.permanentlyDenied,
      'restricted' => PandoraDirectCommunicationState.restricted,
      'subscription_required' =>
        PandoraDirectCommunicationState.subscriptionRequired,
      'dispatching' => PandoraDirectCommunicationState.dispatching,
      'submitted' => PandoraDirectCommunicationState.submitted,
      'sent' => PandoraDirectCommunicationState.sent,
      'delivered' => PandoraDirectCommunicationState.delivered,
      'delivery_failed' => PandoraDirectCommunicationState.deliveryFailed,
      'initiated' => PandoraDirectCommunicationState.initiated,
      'failed' => PandoraDirectCommunicationState.failed,
      'fallback_required' => PandoraDirectCommunicationState.fallbackRequired,
      _ => throw FormatException('Unknown direct communication state: $value'),
    };

class PandoraDirectCommunicationRequest {
  const PandoraDirectCommunicationRequest({
    required this.operationId,
    required this.kind,
    required this.recipient,
    required this.authorizedByCurrentIntent,
    this.message,
    this.subscriptionId,
  });

  final String operationId;
  final PandoraCommunicationKind kind;
  final String recipient;
  final bool authorizedByCurrentIntent;
  final String? message;
  final int? subscriptionId;

  Map<String, Object?> toMap() {
    final normalizedId = operationId.trim();
    if (!RegExp(r'^[A-Za-z0-9._:-]{8,128}$').hasMatch(normalizedId)) {
      throw const FormatException(
          'Direct communication operation id is invalid.');
    }
    final normalizedRecipient = recipient.trim();
    if (!PandoraCommunicationRequest.isSupportedRecipient(
        normalizedRecipient)) {
      throw const FormatException('Direct communication recipient is invalid.');
    }
    if (!authorizedByCurrentIntent) {
      throw const FormatException(
        'Direct communication requires current explicit intent or scoped standing authority.',
      );
    }
    if (kind == PandoraCommunicationKind.sms) {
      if (message == null ||
          message!.trim().isEmpty ||
          message!.length > 2000) {
        throw const FormatException('Direct SMS body is invalid.');
      }
    } else if (message != null) {
      throw const FormatException('Direct calls cannot include an SMS body.');
    }
    if (subscriptionId != null && subscriptionId! < 0) {
      throw const FormatException(
          'Direct communication subscription id is invalid.');
    }
    return <String, Object?>{
      'operationId': normalizedId,
      'kind': switch (kind) {
        PandoraCommunicationKind.call => 'call',
        PandoraCommunicationKind.sms => 'sms',
      },
      'recipient': normalizedRecipient,
      'authorizedByCurrentIntent': true,
      if (message != null) 'message': message,
      if (subscriptionId != null) 'subscriptionId': subscriptionId,
    };
  }
}

class PandoraDirectCommunicationResult {
  const PandoraDirectCommunicationResult({
    required this.operationId,
    required this.kind,
    required this.state,
    required this.terminal,
    required this.acceptedByPlatform,
    required this.duplicatePrevented,
    this.requiredPermission,
    this.failure,
    required this.updatedAtEpochMs,
  });

  final String operationId;
  final PandoraCommunicationKind kind;
  final PandoraDirectCommunicationState state;
  final bool terminal;
  final bool acceptedByPlatform;
  final bool duplicatePrevented;
  final String? requiredPermission;
  final String? failure;
  final int updatedAtEpochMs;

  factory PandoraDirectCommunicationResult.fromMap(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Direct communication result must be a map.');
    }
    final map = <String, Object?>{};
    for (final entry in raw.entries) {
      if (entry.key is! String) {
        throw const FormatException(
          'Direct communication result has a non-string key.',
        );
      }
      map[entry.key as String] = entry.value;
    }
    final kind = switch (map['kind']) {
      'call' => PandoraCommunicationKind.call,
      'sms' => PandoraCommunicationKind.sms,
      _ => throw const FormatException('Unknown direct communication kind.'),
    };
    final state = _parseDirectState(map['state']);
    final terminal = map['terminal'];
    final accepted = map['acceptedByPlatform'];
    if (terminal is! bool || accepted is! bool) {
      throw const FormatException(
          'Direct communication truth flags are invalid.');
    }
    final terminalExpected = const <PandoraDirectCommunicationState>{
      PandoraDirectCommunicationState.delivered,
      PandoraDirectCommunicationState.deliveryFailed,
      PandoraDirectCommunicationState.initiated,
      PandoraDirectCommunicationState.failed,
      PandoraDirectCommunicationState.fallbackRequired,
    }.contains(state);
    if (terminal != terminalExpected) {
      throw const FormatException(
          'Direct communication terminal flag contradicts state.');
    }
    final acceptedRequired = const <PandoraDirectCommunicationState>{
      PandoraDirectCommunicationState.submitted,
      PandoraDirectCommunicationState.sent,
      PandoraDirectCommunicationState.delivered,
      PandoraDirectCommunicationState.deliveryFailed,
      PandoraDirectCommunicationState.initiated,
    }.contains(state);
    final acceptedForbidden = const <PandoraDirectCommunicationState>{
      PandoraDirectCommunicationState.permissionRequired,
      PandoraDirectCommunicationState.permanentlyDenied,
      PandoraDirectCommunicationState.restricted,
      PandoraDirectCommunicationState.subscriptionRequired,
      PandoraDirectCommunicationState.dispatching,
      PandoraDirectCommunicationState.fallbackRequired,
    }.contains(state);
    if ((acceptedRequired && !accepted) || (acceptedForbidden && accepted)) {
      throw const FormatException(
          'Direct communication platform-acceptance flag contradicts state.');
    }
    final operationId = map['operationId'];
    final updated = map['updatedAtEpochMs'];
    final duplicate = map['duplicatePrevented'] ?? false;
    if (operationId is! String ||
        operationId.isEmpty ||
        updated is! int ||
        duplicate is! bool) {
      throw const FormatException(
          'Direct communication identity/evidence is invalid.');
    }
    return PandoraDirectCommunicationResult(
      operationId: operationId,
      kind: kind,
      state: state,
      terminal: terminal,
      acceptedByPlatform: accepted,
      duplicatePrevented: duplicate,
      requiredPermission: map['requiredPermission'] as String?,
      failure: map['failure'] as String?,
      updatedAtEpochMs: updated,
    );
  }
}

extension PandoraDirectCommunicationsClient on PandoraCommunicationsClient {
  Future<PandoraDirectCommunicationResult> executeDirect(
    PandoraDirectCommunicationRequest request,
  ) async {
    final raw = await _channel.invokeMethod<Object?>(
      'executeDirectCommunication',
      request.toMap(),
    );
    return PandoraDirectCommunicationResult.fromMap(raw);
  }

  Future<PandoraDirectCommunicationResult?> getDirectStatus(
    String operationId,
  ) async {
    final raw = await _channel.invokeMethod<Object?>(
      'getDirectCommunicationStatus',
      <String, Object?>{'operationId': operationId.trim()},
    );
    return raw == null ? null : PandoraDirectCommunicationResult.fromMap(raw);
  }
}
