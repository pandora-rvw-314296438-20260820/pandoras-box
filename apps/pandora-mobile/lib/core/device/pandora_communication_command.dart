import 'pandora_communications.dart';

class PandoraDeviceCommunicationCommand {
  const PandoraDeviceCommunicationCommand({
    required this.kind,
    required this.recipient,
    this.message,
  });

  final PandoraCommunicationKind kind;
  final String recipient;
  final String? message;

  bool get recipientIsBounded =>
      PandoraCommunicationRequest.isSupportedRecipient(recipient);

  bool get messageIsReady =>
      kind != PandoraCommunicationKind.sms ||
      (message != null && message!.trim().isNotEmpty);

  static PandoraDeviceCommunicationCommand? tryParse(String raw) {
    final input = raw.trim();
    if (input.isEmpty) return null;

    final call = RegExp(
      r'^(?:please\s+)?(?:call|dial)\s+(.+?)\s*$',
      caseSensitive: false,
    ).firstMatch(input);
    if (call != null) {
      final recipient = _cleanRecipientLabel(call.group(1) ?? '');
      if (recipient.isEmpty) return null;
      return PandoraDeviceCommunicationCommand(
        kind: PandoraCommunicationKind.call,
        recipient: recipient,
      );
    }

    final send = RegExp(
      r'^(?:please\s+)?send(?:\s+to)?\s+(.+?)\s*:\s*(.+?)\s*$',
      caseSensitive: false,
    ).firstMatch(input);
    if (send != null) {
      final recipient = _cleanRecipientLabel(send.group(1) ?? '');
      final body = (send.group(2) ?? '').trim();
      if (recipient.isEmpty || body.isEmpty) return null;
      return PandoraDeviceCommunicationCommand(
        kind: PandoraCommunicationKind.sms,
        recipient: recipient,
        message: body,
      );
    }

    final text = RegExp(
      r'^(?:please\s+)?(?:text|sms)\s+(.+?)\s*$',
      caseSensitive: false,
    ).firstMatch(input);
    final reply = RegExp(
      r'^(?:please\s+)?reply\s+to\s+(.+?)\s*$',
      caseSensitive: false,
    ).firstMatch(input);
    final smsMatch = text ?? reply;
    if (smsMatch == null) return null;

    var rest = (smsMatch.group(1) ?? '').trim();
    if (text != null) {
      rest = rest.replaceFirst(RegExp(r'^to\s+', caseSensitive: false), '');
    }
    if (rest.isEmpty) return null;

    final saying = RegExp(
      r'^(.+?)\s+saying\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(rest);
    if (saying != null) {
      final recipient = _cleanRecipientLabel(saying.group(1) ?? '');
      final body = (saying.group(2) ?? '').trim();
      if (recipient.isEmpty) return null;
      return PandoraDeviceCommunicationCommand(
        kind: PandoraCommunicationKind.sms,
        recipient: recipient,
        message: body.isEmpty ? null : body,
      );
    }

    final quoted = RegExp(r'^(.+?)\s+["“](.*)["”]\s*$').firstMatch(rest);
    if (quoted != null) {
      final recipient = _cleanRecipientLabel(quoted.group(1) ?? '');
      final body = (quoted.group(2) ?? '').trim();
      if (recipient.isEmpty) return null;
      return PandoraDeviceCommunicationCommand(
        kind: PandoraCommunicationKind.sms,
        recipient: recipient,
        message: body.isEmpty ? null : body,
      );
    }

    final numeric = RegExp(r'^([0-9+*#(). -]{3,64})\s+(.+)$').firstMatch(rest);
    if (numeric != null) {
      final recipient = (numeric.group(1) ?? '').trim();
      final body = (numeric.group(2) ?? '').trim();
      if (PandoraCommunicationRequest.isSupportedRecipient(recipient)) {
        return PandoraDeviceCommunicationCommand(
          kind: PandoraCommunicationKind.sms,
          recipient: recipient,
          message: body.isEmpty ? null : body,
        );
      }
    }

    return PandoraDeviceCommunicationCommand(
      kind: PandoraCommunicationKind.sms,
      recipient: _cleanRecipientLabel(rest),
    );
  }

  static String _cleanRecipientLabel(String value) {
    var result = value.trim();
    result = result.replaceFirst(
      RegExp(r'\s+now[.!?]*$', caseSensitive: false),
      '',
    );
    if ((result.startsWith('"') && result.endsWith('"')) ||
        (result.startsWith('“') && result.endsWith('”'))) {
      result = result.substring(1, result.length - 1).trim();
    }
    return result;
  }
}
