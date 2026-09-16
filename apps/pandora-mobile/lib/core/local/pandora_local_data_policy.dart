import 'dart:convert';

enum PandoraLocalNamespace {
  deviceState,
  recentConversation,
  permissionState,
  contactMetadata,
  offlineReminder,
  memoryContext,
}

class PandoraLocalDataPolicy {
  const PandoraLocalDataPolicy._();

  static const int maxPayloadBytes = 131072;
  static const Duration maxRetention = Duration(days: 30);
  static const Duration memoryRetention = Duration(days: 7);
  static const Duration contactRetention = Duration(hours: 24);

  static const Set<String> _forbiddenFragments = {
    'authorization',
    'credential',
    'password',
    'privatekey',
    'secret',
    'session',
    'token',
    'apikey',
    'cookie',
  };
  static String encodePayload(Object? payload) {
    _rejectForbiddenKeys(payload);
    final encoded = jsonEncode(payload);
    if (utf8.encode(encoded).length > maxPayloadBytes) {
      throw const FormatException('Pandora local payload exceeds 128 KiB.');
    }
    return encoded;
  }

  static Duration maxTtlFor(PandoraLocalNamespace namespace) {
    return switch (namespace) {
      PandoraLocalNamespace.memoryContext => memoryRetention,
      PandoraLocalNamespace.contactMetadata => contactRetention,
      _ => maxRetention,
    };
  }

  static void validateExpiry({
    required PandoraLocalNamespace namespace,
    required DateTime now,
    required DateTime expiresAt,
  }) {
    final ttl = expiresAt.toUtc().difference(now.toUtc());
    if (ttl <= Duration.zero || ttl > maxTtlFor(namespace)) {
      throw FormatException(
          'Invalid ${namespace.name} local retention window.');
    }
  }

  static void _rejectForbiddenKeys(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw const FormatException(
              'Pandora local payload keys must be strings.');
        }
        final normalized = (entry.key as String)
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (_forbiddenFragments.any(normalized.contains)) {
          throw FormatException(
            'Sensitive field ${entry.key} is not allowed in Pandora local state.',
          );
        }
        _rejectForbiddenKeys(entry.value);
      }
      return;
    }
    if (value is Iterable) {
      for (final item in value) {
        _rejectForbiddenKeys(item);
      }
      return;
    }
    if (value != null && value is! String && value is! num && value is! bool) {
      throw const FormatException(
          'Pandora local payload must be JSON-compatible.');
    }
  }
}
