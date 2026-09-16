import 'dart:async';

import 'package:flutter/services.dart';

import 'pandora_communication_command.dart';
import 'pandora_communications.dart';
import 'pandora_contacts.dart';

typedef PandoraDirectCommunicationExecute
    = Future<PandoraDirectCommunicationResult> Function(
  PandoraDirectCommunicationRequest request,
);
typedef PandoraDirectCommunicationStatus
    = Future<PandoraDirectCommunicationResult?> Function(String operationId);
typedef PandoraCommunicationFallbackOpen
    = Future<PandoraCommunicationHandoffResult> Function(
  PandoraCommunicationRequest request,
);
typedef PandoraContactResolve = Future<PandoraContactResolutionResult> Function(
  String query,
);
typedef PandoraCommunicationActivityReporter = Future<void> Function(
  PandoraCommunicationActivityFact fact,
);

class PandoraCommunicationActivityFact {
  const PandoraCommunicationActivityFact({
    required this.capability,
    required this.stage,
    required this.observedAt,
  });

  final String capability;
  final String stage;
  final DateTime observedAt;
}

class PandoraCommunicationExecutionResult {
  const PandoraCommunicationExecutionResult({
    required this.reply,
    required this.terminalStage,
    required this.capability,
    required this.observedAt,
    this.needsUserAction = false,
    this.outcomeUnknown = false,
  });

  final String reply;
  final String terminalStage;
  final String capability;
  final DateTime observedAt;
  final bool needsUserAction;
  final bool outcomeUnknown;
}

class PandoraCommunicationActionExecutor {
  PandoraCommunicationActionExecutor({
    PandoraCommunicationsClient? communications,
    PandoraContactsClient? contacts,
    PandoraCommunicationActivityReporter? reporter,
    DateTime Function()? clock,
    Duration statusDelay = const Duration(milliseconds: 250),
    int maxStatusPolls = 8,
  })  : _communications = communications ?? PandoraCommunicationsClient(),
        _contacts = contacts ?? PandoraContactsClient(),
        _reporter = reporter,
        _clock = clock ?? DateTime.now,
        _statusDelay = statusDelay,
        _maxStatusPolls = maxStatusPolls;

  final PandoraCommunicationsClient _communications;
  final PandoraContactsClient _contacts;
  final PandoraCommunicationActivityReporter? _reporter;
  final DateTime Function() _clock;
  final Duration _statusDelay;
  final int _maxStatusPolls;

  Future<PandoraCommunicationExecutionResult> execute(
    PandoraDeviceCommunicationCommand command, {
    required String operationId,
  }) async {
    final capability = command.kind == PandoraCommunicationKind.sms
        ? 'communication.sms'
        : 'communication.call';
    final requestedRecipient = command.recipient.trim();
    if (requestedRecipient.isEmpty) {
      return _finish(
        capability,
        'failed',
        'The communication target is empty. Nothing was sent or called.',
      );
    }
    if (command.kind == PandoraCommunicationKind.sms &&
        !command.messageIsReady) {
      return _finish(
        capability,
        'needs_choice',
        'Tell me the message you want to send before I dispatch it.',
        needsUserAction: true,
      );
    }

    var recipient = requestedRecipient;
    var label = requestedRecipient;
    if (!command.recipientIsBounded) {
      final resolution = await _contacts.resolve(requestedRecipient);
      final unresolved = await _resolveContactFailure(
        capability,
        requestedRecipient,
        resolution,
      );
      if (unresolved != null) return unresolved;
      recipient = resolution.normalizedPhoneNumber!.trim();
      label = resolution.displayName?.trim().isNotEmpty == true
          ? resolution.displayName!.trim()
          : requestedRecipient;
    }

    await _report(capability, 'acting', _clock());
    final request = PandoraDirectCommunicationRequest(
      operationId: operationId,
      kind: command.kind,
      recipient: recipient,
      authorizedByCurrentIntent: true,
      message: command.message,
    );

    PandoraDirectCommunicationResult result;
    try {
      result = await _communications.executeDirect(request);
    } on TimeoutException {
      return _recoverAfterAmbiguousFailure(
        capability,
        operationId,
        command.kind,
        recipient,
        label,
      );
    } on PlatformException {
      return _recoverAfterAmbiguousFailure(
        capability,
        operationId,
        command.kind,
        recipient,
        label,
      );
    }
    result = await _settle(result, operationId);
    return _finishFromDirectResult(
      capability,
      result,
      recipient,
      label,
    );
  }

  Future<PandoraDirectCommunicationResult> _settle(
    PandoraDirectCommunicationResult initial,
    String operationId,
  ) async {
    var current = initial;
    for (var attempt = 0; attempt < _maxStatusPolls; attempt += 1) {
      if (current.terminal ||
          current.state == PandoraDirectCommunicationState.sent ||
          current.state == PandoraDirectCommunicationState.permissionRequired ||
          current.state == PandoraDirectCommunicationState.permanentlyDenied ||
          current.state == PandoraDirectCommunicationState.restricted ||
          current.state ==
              PandoraDirectCommunicationState.subscriptionRequired ||
          current.state == PandoraDirectCommunicationState.fallbackRequired) {
        return current;
      }
      await _report(
        current.kind == PandoraCommunicationKind.sms
            ? 'communication.sms'
            : 'communication.call',
        'verifying',
        _clock(),
      );
      await Future<void>.delayed(_statusDelay);
      try {
        final readback = await _communications.getDirectStatus(operationId);
        if (readback != null) current = readback;
      } on TimeoutException {
        return current;
      } on PlatformException {
        return current;
      }
    }
    return current;
  }

  Future<PandoraCommunicationExecutionResult?> _resolveContactFailure(
    String capability,
    String query,
    PandoraContactResolutionResult resolution,
  ) async {
    switch (resolution.status) {
      case PandoraContactResolutionStatus.resolved:
        return null;
      case PandoraContactResolutionStatus.permissionRequired:
        return _finish(
          capability,
          'needs_permission',
          'Grant Contacts permission to Pandora before I use the name $query. No communication was dispatched.',
          needsUserAction: true,
        );
      case PandoraContactResolutionStatus.ambiguous:
        final names = resolution.candidates
            .map((candidate) => candidate.displayName)
            .take(3)
            .join(', ');
        return await _finish(
          capability,
          'needs_choice',
          names.isEmpty
              ? 'More than one contact matches $query. Choose the exact contact before I continue.'
              : 'More than one contact matches $query: $names. Choose the exact contact before I continue.',
          needsUserAction: true,
        );
      case PandoraContactResolutionStatus.notFound:
      case PandoraContactResolutionStatus.unavailable:
        return _finish(
          capability,
          'failed',
          'I could not resolve $query to one verified Android contact. Nothing was dispatched.',
        );
    }
  }

  Future<PandoraCommunicationExecutionResult> _recoverAfterAmbiguousFailure(
    String capability,
    String operationId,
    PandoraCommunicationKind kind,
    String recipient,
    String label,
  ) async {
    await _report(capability, 'verifying', _clock());
    try {
      final status = await _communications.getDirectStatus(operationId);
      if (status != null) {
        return await _finishFromDirectResult(
          capability,
          status,
          recipient,
          label,
        );
      }
    } on TimeoutException {
      // The outcome remains unknown. Never retry the dispatch with a new id.
    } on PlatformException {
      // The outcome remains unknown. Never retry the dispatch with a new id.
    }
    return _finish(
      capability,
      'verifying',
      kind == PandoraCommunicationKind.sms
          ? 'Android did not return a conclusive SMS status. I will not send it again with a different operation ID.'
          : 'Android did not return a conclusive call status. I will not place it again with a different operation ID.',
      outcomeUnknown: true,
    );
  }

  Future<PandoraCommunicationExecutionResult> _finishFromDirectResult(
    String capability,
    PandoraDirectCommunicationResult result,
    String recipient,
    String label,
  ) async {
    switch (result.state) {
      case PandoraDirectCommunicationState.permissionRequired:
      case PandoraDirectCommunicationState.permanentlyDenied:
        return _finish(
          capability,
          'needs_permission',
          'Android permission ${result.requiredPermission ?? 'is required'} before Pandora can continue. Nothing was dispatched.',
          needsUserAction: true,
        );
      case PandoraDirectCommunicationState.restricted:
        return _finish(
          capability,
          'failed',
          'Android policy currently blocks this communication. Nothing was dispatched.',
        );
      case PandoraDirectCommunicationState.subscriptionRequired:
        return _finish(
          capability,
          'needs_choice',
          'Android cannot determine a safe SMS subscription. Choose the default SIM/account in Android, then retry. Nothing was sent.',
          needsUserAction: true,
        );
      case PandoraDirectCommunicationState.fallbackRequired:
        return _openTrustedFallback(
          capability,
          result.kind,
          recipient,
          label,
          'Android requires the trusted system communication UI for this action.',
        );
      case PandoraDirectCommunicationState.deliveryFailed:
      case PandoraDirectCommunicationState.failed:
        return _finish(
          capability,
          'failed',
          result.kind == PandoraCommunicationKind.sms
              ? 'Android reported that the SMS failed. I did not retry it.'
              : 'Android reported that the call launch failed. I did not retry it.',
        );
      case PandoraDirectCommunicationState.delivered:
        return _finish(
          capability,
          'result',
          'Android delivery callbacks verified the SMS was delivered to $label ($recipient).',
        );
      case PandoraDirectCommunicationState.sent:
        return _finish(
          capability,
          'result',
          'Android sent callbacks verified the SMS was sent to $label ($recipient). Delivery is not being claimed.',
        );
      case PandoraDirectCommunicationState.initiated:
        return _finish(
          capability,
          'result',
          'Android verified that the call launch was initiated for $label ($recipient). Connection is not being claimed.',
        );
      case PandoraDirectCommunicationState.dispatching:
      case PandoraDirectCommunicationState.submitted:
        return _finish(
          capability,
          'verifying',
          'Android accepted the communication but final native status is still pending. I will not dispatch it again with a different operation ID.',
          outcomeUnknown: true,
        );
    }
  }

  Future<PandoraCommunicationExecutionResult> _openTrustedFallback(
    String capability,
    PandoraCommunicationKind kind,
    String recipient,
    String label,
    String reason,
  ) async {
    final request = kind == PandoraCommunicationKind.call
        ? PandoraCommunicationRequest.call(recipient)
        : PandoraCommunicationRequest.sms(recipient, message: null);
    try {
      final handoff = await _communications.open(request);
      if (handoff.opened && handoff.userConfirmationRequired) {
        return await _finish(
          capability,
          'needs_choice',
          kind == PandoraCommunicationKind.call
              ? '$reason Phone UI opened for $label ($recipient); review it and confirm Call yourself.'
              : '$reason Messages opened for $label ($recipient); review it and confirm Send yourself.',
          needsUserAction: true,
        );
      }
    } on PlatformException {
      // Fall through to a truthful failed result below.
    } on FormatException {
      // Fall through to a truthful failed result below.
    }
    return _finish(
      capability,
      'failed',
      '$reason The trusted system communication UI could not be opened.',
    );
  }

  Future<PandoraCommunicationExecutionResult> _finish(
    String capability,
    String stage,
    String reply, {
    bool needsUserAction = false,
    bool outcomeUnknown = false,
  }) async {
    final observedAt = _clock();
    await _report(capability, stage, observedAt);
    return PandoraCommunicationExecutionResult(
      reply: reply,
      terminalStage: stage,
      capability: capability,
      observedAt: observedAt,
      needsUserAction: needsUserAction,
      outcomeUnknown: outcomeUnknown,
    );
  }

  Future<void> _report(
    String capability,
    String stage,
    DateTime observedAt,
  ) async {
    final reporter = _reporter;
    if (reporter == null) return;
    await reporter(
      PandoraCommunicationActivityFact(
        capability: capability,
        stage: stage,
        observedAt: observedAt,
      ),
    );
  }
}
