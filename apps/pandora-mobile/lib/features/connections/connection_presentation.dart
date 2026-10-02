enum ConnectionCardState {
  verified,
  partial,
  notConnected,
  error;

  String get label => switch (this) {
        verified => 'Verified',
        partial => 'Partial',
        notConnected => 'Not connected',
        error => 'Error',
      };

  bool get isConnected => this == verified || this == partial;
}

ConnectionCardState synthesizeConnectionCardState({
  required String state,
  required String rawStatus,
  required bool canUseNow,
  required bool accountVerified,
  required bool scopesVerified,
  required Iterable<bool> capabilityAvailability,
  String? failureCode,
  String? failureMessage,
}) {
  final normalized =
      '${state.trim().toLowerCase()} ${rawStatus.trim().toLowerCase()}';
  final hardFailure = <String>[
    failureCode ?? '',
    failureMessage ?? '',
    normalized,
  ].join(' ').toLowerCase();
  final hasHardFailure = RegExp(
    r'(^|[^a-z])(error|failed|failure|down|unhealthy|rejected)([^a-z]|$)',
  ).hasMatch(hardFailure);

  final capabilities = capabilityAvailability.toList(growable: false);
  final anyCapability = capabilities.any((value) => value);
  final allCapabilities =
      capabilities.isNotEmpty && capabilities.every((value) => value);
  final stateClaimsConnection = RegExp(
    r'(^|[^a-z])(connected|authorized|verified|healthy|ready|active)([^a-z]|$)',
  ).hasMatch(normalized);

  if (hasHardFailure) return ConnectionCardState.error;

  if (canUseNow &&
      (capabilities.isEmpty || allCapabilities) &&
      (accountVerified || scopesVerified || stateClaimsConnection)) {
    return ConnectionCardState.verified;
  }

  if (anyCapability || canUseNow || stateClaimsConnection) {
    return ConnectionCardState.partial;
  }

  return ConnectionCardState.notConnected;
}

String connectionVerificationLabel({
  required ConnectionCardState state,
  required DateTime? checkedAt,
  DateTime? now,
}) {
  if (checkedAt == null) return 'Never verified';
  final age = _relativeAge(checkedAt, now ?? DateTime.now());
  return switch (state) {
    ConnectionCardState.verified || ConnectionCardState.partial =>
      'Verified $age',
    ConnectionCardState.error || ConnectionCardState.notConnected =>
      'Last check failed $age',
  };
}

String connectionProviderDisplayName(String rawName) {
  final raw = rawName.trim();
  if (raw.isEmpty) return 'Provider';
  final normalized = raw.toLowerCase();
  const providers = <(String, String)>[
    ('github', 'GitHub'),
    ('supabase', 'Supabase'),
    ('vercel', 'Vercel'),
    ('posthog', 'PostHog'),
    ('meta', 'Meta'),
    ('google workspace', 'Google Workspace'),
    ('google_drive', 'Google Workspace'),
    ('openai', 'OpenAI'),
    ('gemini', 'Gemini'),
    ('kimi', 'Kimi'),
    ('namria', 'NAMRIA Geoportal'),
    ('phivolcs', 'PHIVOLCS Hazard GIS'),
    ('psa openstat', 'PSA OpenSTAT'),
    ('psa psgc', 'PSA PSGC'),
  ];
  for (final entry in providers) {
    if (normalized.contains(entry.$1)) return entry.$2;
  }
  final beforeDash = raw.split(RegExp(r'\s+[—:-]\s+')).first.trim();
  return beforeDash
      .replaceFirst(RegExp(r'\s+(?:account|business)(String provider, String? rawLabel) {
  final raw = rawLabel?.trim() ?? '';
  if (raw.isEmpty) return '';

  final cleaned = raw
      .replaceFirst(
        RegExp(
          '^' + RegExp.escape(provider.trim()) + r'\s+(?:Account|Business)\s*[—:-]\s*',
          caseSensitive: false,
        ),
        '',
      )
      .trim();

  final candidate = cleaned.isEmpty ? raw : cleaned;
  if (RegExp(r'^pandora-rvw-\d+-\d+$', caseSensitive: false)
      .hasMatch(candidate)) {
    return 'Pandora GitHub account';
  }
  if (_uuid.hasMatch(candidate)) return 'Connected account';
  if (candidate.length <= 52) return candidate;
  return '${candidate.substring(0, 34)}…${candidate.substring(candidate.length - 10)}';
}

bool connectionIdentityNeedsTooltip(String? rawLabel) {
  final raw = rawLabel?.trim() ?? '';
  if (raw.isEmpty) return false;
  return RegExp(r'pandora-rvw-\d+-\d+', caseSensitive: false).hasMatch(raw) ||
      _uuid.hasMatch(raw) ||
      raw.length > 52;
}

final RegExp _uuid = RegExp(
  r'\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b',
  caseSensitive: false,
);

String _relativeAge(DateTime value, DateTime now) {
  var difference = now.toLocal().difference(value.toLocal());
  if (difference.isNegative) difference = Duration.zero;
  if (difference.inMinutes < 1) return 'just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  return '${difference.inDays}d ago';
}
, caseSensitive: false), '')
      .trim();
}

String connectionDisplayIdentity(String provider, String? rawLabel) {
  final raw = rawLabel?.trim() ?? '';
  if (raw.isEmpty) return '';

  final cleaned = raw
      .replaceFirst(
        RegExp(
          '^' + RegExp.escape(provider.trim()) + r'\s+(?:Account|Business)\s*[—:-]\s*',
          caseSensitive: false,
        ),
        '',
      )
      .trim();

  final candidate = cleaned.isEmpty ? raw : cleaned;
  if (RegExp(r'^pandora-rvw-\d+-\d+$', caseSensitive: false)
      .hasMatch(candidate)) {
    return 'Pandora GitHub account';
  }
  if (_uuid.hasMatch(candidate)) return 'Connected account';
  if (candidate.length <= 52) return candidate;
  return '${candidate.substring(0, 34)}…${candidate.substring(candidate.length - 10)}';
}

bool connectionIdentityNeedsTooltip(String? rawLabel) {
  final raw = rawLabel?.trim() ?? '';
  if (raw.isEmpty) return false;
  return RegExp(r'pandora-rvw-\d+-\d+', caseSensitive: false).hasMatch(raw) ||
      _uuid.hasMatch(raw) ||
      raw.length > 52;
}

final RegExp _uuid = RegExp(
  r'\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b',
  caseSensitive: false,
);

String _relativeAge(DateTime value, DateTime now) {
  var difference = now.toLocal().difference(value.toLocal());
  if (difference.isNegative) difference = Duration.zero;
  if (difference.inMinutes < 1) return 'just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  return '${difference.inDays}d ago';
}
