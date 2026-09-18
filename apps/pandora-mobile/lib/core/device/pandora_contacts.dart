import 'package:flutter/services.dart';

import 'pandora_communications.dart';

enum PandoraContactResolutionStatus {
  resolved,
  ambiguous,
  notFound,
  permissionRequired,
  unavailable,
}

class PandoraContactCandidate {
  const PandoraContactCandidate({
    required this.contactId,
    required this.displayName,
    required this.phoneNumber,
    required this.normalizedPhoneNumber,
  });

  final String contactId;
  final String displayName;
  final String phoneNumber;
  final String normalizedPhoneNumber;

  factory PandoraContactCandidate.fromMap(Object? raw) {
    final map = _stringMap(raw, 'contact candidate');
    final phoneNumber = _requiredString(map, 'phoneNumber');
    final normalized = _requiredString(map, 'normalizedPhoneNumber');
    if (!PandoraCommunicationRequest.isSupportedRecipient(phoneNumber) ||
        !PandoraCommunicationRequest.isSupportedRecipient(normalized)) {
      throw const FormatException(
          'Contact candidate has an invalid phone number.');
    }
    return PandoraContactCandidate(
      contactId: _requiredString(map, 'contactId'),
      displayName: _requiredString(map, 'displayName'),
      phoneNumber: phoneNumber,
      normalizedPhoneNumber: normalized,
    );
  }
}

class PandoraContactResolutionResult {
  const PandoraContactResolutionResult({
    required this.status,
    required this.source,
    required this.requiredPermission,
    required this.candidates,
    this.resolution,
    this.reason,
    this.contactId,
    this.displayName,
    this.phoneNumber,
    this.normalizedPhoneNumber,
  });

  final PandoraContactResolutionStatus status;
  final String source;
  final String requiredPermission;
  final List<PandoraContactCandidate> candidates;
  final String? resolution;
  final String? reason;
  final String? contactId;
  final String? displayName;
  final String? phoneNumber;
  final String? normalizedPhoneNumber;
  bool get isResolved => status == PandoraContactResolutionStatus.resolved;

  factory PandoraContactResolutionResult.fromMap(Object? raw) {
    final map = _stringMap(raw, 'contact resolution');
    final source = _requiredString(map, 'source');
    if (source != 'android_contacts') {
      throw const FormatException(
          'Contact resolution source is not Android Contacts.');
    }
    final status = switch (_requiredString(map, 'status')) {
      'resolved' => PandoraContactResolutionStatus.resolved,
      'ambiguous' => PandoraContactResolutionStatus.ambiguous,
      'not_found' => PandoraContactResolutionStatus.notFound,
      'permission_required' =>
        PandoraContactResolutionStatus.permissionRequired,
      'unavailable' => PandoraContactResolutionStatus.unavailable,
      final value =>
        throw FormatException('Unknown contact resolution status: $value'),
    };
    final requiredPermission = _requiredString(map, 'requiredPermission');
    if (requiredPermission != 'android.permission.READ_CONTACTS') {
      throw const FormatException(
          'Contact resolution requires an unexpected permission.');
    }
    final rawCandidates = map['candidates'];
    if (rawCandidates is! List) {
      throw const FormatException(
          'Contact resolution candidates must be a list.');
    }
    if (rawCandidates.length > 5) {
      throw const FormatException(
          'Contact resolution returned too many candidates.');
    }
    final candidates = rawCandidates
        .map(PandoraContactCandidate.fromMap)
        .toList(growable: false);
    final phoneNumber = _optionalString(map['phoneNumber']);
    final normalized = _optionalString(map['normalizedPhoneNumber']);
    if (status == PandoraContactResolutionStatus.resolved) {
      if (phoneNumber == null ||
          normalized == null ||
          !PandoraCommunicationRequest.isSupportedRecipient(phoneNumber) ||
          !PandoraCommunicationRequest.isSupportedRecipient(normalized) ||
          candidates.isNotEmpty) {
        throw const FormatException(
            'Resolved contact evidence is contradictory.');
      }
    } else if (phoneNumber != null || normalized != null) {
      throw const FormatException(
          'Unresolved contact must not expose a selected number.');
    }
    if (status == PandoraContactResolutionStatus.ambiguous &&
        candidates.isEmpty) {
      throw const FormatException(
          'Ambiguous contact resolution requires candidates.');
    }
    if (status != PandoraContactResolutionStatus.ambiguous &&
        candidates.isNotEmpty) {
      throw const FormatException(
          'Only ambiguous contact resolution may expose candidates.');
    }

    return PandoraContactResolutionResult(
      status: status,
      source: source,
      requiredPermission: requiredPermission,
      candidates: List.unmodifiable(candidates),
      resolution: _optionalString(map['resolution']),
      reason: _optionalString(map['reason']),
      contactId: _optionalString(map['contactId']),
      displayName: _optionalString(map['displayName']),
      phoneNumber: phoneNumber,
      normalizedPhoneNumber: normalized,
    );
  }
}

class PandoraContactsClient {
  PandoraContactsClient({
    MethodChannel channel = const MethodChannel('pandora/device_agent'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<PandoraContactResolutionResult> resolve(String query) async {
    final normalized = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty || normalized.length > 120) {
      throw const FormatException('Contact name is invalid.');
    }
    final raw = await _channel.invokeMethod<Object?>(
      'resolvePhoneContact',
      <String, Object?>{'query': normalized},
    );
    return PandoraContactResolutionResult.fromMap(raw);
  }
}

Map<String, Object?> _stringMap(Object? raw, String label) {
  if (raw is! Map) throw FormatException('$label must be a map.');
  final result = <String, Object?>{};
  for (final entry in raw.entries) {
    if (entry.key is! String) {
      throw FormatException('$label contains a non-string key.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _requiredString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value.trim();
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const FormatException('Optional contact value must be a string.');
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}
