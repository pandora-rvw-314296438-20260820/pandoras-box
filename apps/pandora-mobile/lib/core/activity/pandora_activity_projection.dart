enum PandoraActivityState {
  understanding,
  planning,
  acting,
  checking,
  needsYou,
  retrying,
  fallback,
  verifying,
  paused,
  resuming,
  result,
  failed,
  cancelled;

  static PandoraActivityState parse(String value) => switch (value) {
        'understanding' => understanding,
        'planning' => planning,
        'acting' => acting,
        'checking' => checking,
        'needs_you' => needsYou,
        'retrying' => retrying,
        'fallback' => fallback,
        'verifying' => verifying,
        'paused' => paused,
        'resuming' => resuming,
        'result' => result,
        'failed' => failed,
        'cancelled' => cancelled,
        _ => throw const FormatException('Unsupported Activity Theatre state.'),
      };

  String get wireName => switch (this) {
        needsYou => 'needs_you',
        _ => name,
      };

  bool get isTerminal => this == result || this == failed || this == cancelled;
}

class PandoraActivitySource {
  const PandoraActivitySource({
    required this.sourceType,
    required this.sourceId,
    required this.observedAt,
    this.sourceEventId,
  });

  final String sourceType;
  final String sourceId;
  final String? sourceEventId;
  final DateTime observedAt;
}

class PandoraActivityEvidenceRef {
  const PandoraActivityEvidenceRef({
    required this.type,
    required this.relation,
    required this.ref,
  });

  final String type;
  final String relation;
  final String ref;
}

class PandoraActivityBlocker {
  const PandoraActivityBlocker({
    required this.reasonCode,
    required this.reason,
    required this.requiredAction,
    required this.approvalRequired,
    this.policyRef,
  });

  final String reasonCode;
  final String reason;
  final String requiredAction;
  final bool approvalRequired;
  final String? policyRef;
}

class PandoraActivityOutcome {
  const PandoraActivityOutcome({
    required this.summary,
    required this.physicalDevice,
  });

  final String summary;
  final bool physicalDevice;
}

class PandoraActivityProjection {
  const PandoraActivityProjection({
    required this.eventId,
    required this.jobId,
    required this.sequence,
    required this.state,
    required this.message,
    required this.occurredAt,
    required this.admittedAt,
    required this.source,
    required this.evidenceRefs,
    this.domain,
    this.capability,
    this.executionId,
    this.blocker,
    this.outcome,
  });

  final String eventId;
  final String jobId;
  final int sequence;
  final PandoraActivityState state;
  final String message;
  final DateTime occurredAt;
  final DateTime admittedAt;
  final String? domain;
  final String? capability;
  final String? executionId;
  final PandoraActivitySource source;
  final List<PandoraActivityEvidenceRef> evidenceRefs;
  final PandoraActivityBlocker? blocker;
  final PandoraActivityOutcome? outcome;

  static const _topKeys = <String>{
    'projectionVersion',
    'eventId',
    'jobId',
    'sequence',
    'state',
    'message',
    'occurredAt',
    'admittedAt',
    'domain',
    'capability',
    'executionId',
    'source',
    'evidenceRefs',
    'blocker',
    'outcome',
  };
  static const _sourceKeys = <String>{
    'sourceType',
    'sourceId',
    'sourceEventId',
    'observedAt',
  };
  static const _evidenceKeys = <String>{'type', 'relation', 'ref'};
  static const _blockerKeys = <String>{
    'reasonCode',
    'reason',
    'requiredAction',
    'approvalRequired',
    'policyRef',
  };
  static const _outcomeKeys = <String>{'summary', 'physicalDevice'};
  static const _sourceTypes = <String>{
    'runtime',
    'device',
    'provider',
    'pandora',
    'model',
    'tool',
  };
  static const _evidenceTypes = <String>{
    'runtime_event',
    'provider_receipt',
    'device_event',
    'tool_receipt',
    'test_receipt',
    'artifact',
    'verification_receipt',
    'policy_decision',
    'user_control',
  };
  static const _needsYouReasonCodes = <String>{
    'authorization_required',
    'missing_consequential_user_choice',
    'account_connection_or_reauthentication_required',
    'protected_app_user_presence_required',
    'user_only_recovery_or_conflict_resolution',
    'external_blocker_only_user_can_resolve',
  };
  static const _relations = <String>{
    'source',
    'verification',
    'failure',
    'accepted_control',
    'authoritative_pause',
    'authoritative_cancellation',
    'prior_attempt',
    'capability',
    'policy',
    'readback',
  };

  factory PandoraActivityProjection.fromJson(Map<String, dynamic> json) {
    _rejectUnknown(json, _topKeys, 'projection');
    if (json['projectionVersion'] != 1) {
      throw const FormatException('Unsupported Activity projection version.');
    }
    final state = PandoraActivityState.parse(_requiredText(json, 'state', 40));
    final sourceJson = _requiredMap(json, 'source');
    _rejectUnknown(sourceJson, _sourceKeys, 'source');
    final sourceType = _requiredText(sourceJson, 'sourceType', 40);
    if (!_sourceTypes.contains(sourceType)) {
      throw const FormatException('Unsupported Activity source type.');
    }
    final evidenceJson = json['evidenceRefs'];
    if (evidenceJson is! List || evidenceJson.length > 20) {
      throw const FormatException('Invalid Activity evidence references.');
    }
    final evidence = evidenceJson.map((value) {
      if (value is! Map) {
        throw const FormatException('Invalid Activity evidence reference.');
      }
      final item = value.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      _rejectUnknown(item, _evidenceKeys, 'evidenceRef');
      final type = _requiredText(item, 'type', 80);
      final relation = _requiredText(item, 'relation', 80);
      if (!_evidenceTypes.contains(type) || !_relations.contains(relation)) {
        throw const FormatException(
          'Unsupported Activity evidence reference.',
        );
      }
      return PandoraActivityEvidenceRef(
        type: type,
        relation: relation,
        ref: _publicText(item, 'ref', 500),
      );
    }).toList(growable: false);
    final evidenceKeys = <String>{};
    for (final item in evidence) {
      final key = '${item.type}\u0000${item.relation}\u0000${item.ref}';
      if (!evidenceKeys.add(key)) {
        throw const FormatException('Duplicate Activity evidence reference.');
      }
    }
    final sourceEventId = _optionalOpaqueId(sourceJson, 'sourceEventId');
    if (sourceEventId == null && evidence.isEmpty) {
      throw const FormatException(
          'Activity provenance requires source evidence.');
    }
    final occurredAt = _timestamp(json, 'occurredAt');
    final admittedAt = _timestamp(json, 'admittedAt');
    if (admittedAt.isBefore(occurredAt)) {
      throw const FormatException(
          'Activity admission cannot predate occurrence.');
    }
    final blocker = _parseBlocker(json['blocker'], state);
    final outcome = _parseOutcome(json['outcome'], state);
    final sequence = json['sequence'];
    if (sequence is! int || sequence < 1 || sequence > 9007199254740991) {
      throw const FormatException('Invalid Activity sequence.');
    }
    _validateStateEvidence(state, evidence, outcome);
    return PandoraActivityProjection(
      eventId: _opaqueId(json, 'eventId'),
      jobId: _opaqueId(json, 'jobId'),
      sequence: sequence,
      state: state,
      message: _publicText(json, 'message', 1000),
      occurredAt: occurredAt,
      admittedAt: admittedAt,
      domain: _optionalPublicText(json, 'domain', 100),
      capability: _optionalPublicText(json, 'capability', 160),
      executionId: _optionalOpaqueId(json, 'executionId'),
      source: PandoraActivitySource(
        sourceType: sourceType,
        sourceId: _opaqueId(sourceJson, 'sourceId'),
        sourceEventId: sourceEventId,
        observedAt: _timestamp(sourceJson, 'observedAt'),
      ),
      evidenceRefs: evidence,
      blocker: blocker,
      outcome: outcome,
    );
  }

  static PandoraActivityBlocker? _parseBlocker(
    Object? value,
    PandoraActivityState state,
  ) {
    if (state != PandoraActivityState.needsYou) {
      if (value != null) {
        throw const FormatException('Blocker is only valid for Needs You.');
      }
      return null;
    }
    if (value is! Map) {
      throw const FormatException('Needs You requires a blocker.');
    }
    final json = value.map((key, value) => MapEntry(key.toString(), value));
    _rejectUnknown(json, _blockerKeys, 'blocker');
    final approvalRequired = json['approvalRequired'];
    if (approvalRequired is! bool) {
      throw const FormatException('Invalid Needs You approval boundary.');
    }
    final reasonCode = _requiredText(json, 'reasonCode', 100);
    if (!_needsYouReasonCodes.contains(reasonCode)) {
      throw const FormatException('Unsupported Needs You reason code.');
    }
    return PandoraActivityBlocker(
      reasonCode: reasonCode,
      reason: _publicText(json, 'reason', 500),
      requiredAction: _publicText(json, 'requiredAction', 500),
      approvalRequired: approvalRequired,
      policyRef: _optionalPublicText(json, 'policyRef', 300),
    );
  }

  static PandoraActivityOutcome? _parseOutcome(
    Object? value,
    PandoraActivityState state,
  ) {
    if (state != PandoraActivityState.result) {
      if (value != null) {
        throw const FormatException('Outcome is only valid for Result.');
      }
      return null;
    }
    if (value is! Map) {
      throw const FormatException('Result requires an outcome.');
    }
    final json = value.map((key, value) => MapEntry(key.toString(), value));
    _rejectUnknown(json, _outcomeKeys, 'outcome');
    final physicalDevice = json['physicalDevice'];
    if (physicalDevice is! bool) {
      throw const FormatException('Invalid Activity outcome.');
    }
    return PandoraActivityOutcome(
      summary: _publicText(json, 'summary', 1000),
      physicalDevice: physicalDevice,
    );
  }

  static void _validateStateEvidence(
    PandoraActivityState state,
    List<PandoraActivityEvidenceRef> evidence,
    PandoraActivityOutcome? outcome,
  ) {
    bool has(String relation, [String? type]) => evidence.any(
          (item) =>
              item.relation == relation && (type == null || item.type == type),
        );
    if (state == PandoraActivityState.result &&
        !has('verification', 'verification_receipt')) {
      throw const FormatException('Result requires verification evidence.');
    }
    if (outcome?.physicalDevice == true &&
        !has('verification', 'device_event')) {
      throw const FormatException(
        'Physical-device Result requires device verification evidence.',
      );
    }
    if (state == PandoraActivityState.failed && !has('failure')) {
      throw const FormatException('Failed Activity requires failure evidence.');
    }
    if (state == PandoraActivityState.retrying && !has('prior_attempt')) {
      throw const FormatException('Retrying requires prior-attempt evidence.');
    }
    if (state == PandoraActivityState.fallback &&
        !has('prior_attempt') &&
        !has('capability')) {
      throw const FormatException(
        'Fallback requires prior-attempt or capability evidence.',
      );
    }
    final acceptedControl = has('accepted_control', 'user_control');
    final authoritativePause = has('authoritative_pause', 'runtime_event') ||
        has('authoritative_pause', 'device_event');
    if (state == PandoraActivityState.paused &&
        !acceptedControl &&
        !authoritativePause) {
      throw const FormatException(
        'Paused Activity requires accepted or authoritative pause evidence.',
      );
    }
    if (state == PandoraActivityState.resuming && !acceptedControl) {
      throw const FormatException(
        'Resuming Activity requires accepted control evidence.',
      );
    }
    final authoritativeCancellation =
        has('authoritative_cancellation', 'runtime_event') ||
            has('authoritative_cancellation', 'device_event') ||
            has('authoritative_cancellation', 'provider_receipt');
    if (state == PandoraActivityState.cancelled &&
        !acceptedControl &&
        !authoritativeCancellation) {
      throw const FormatException(
        'Cancelled Activity requires accepted or authoritative cancellation evidence.',
      );
    }
  }

  static Map<String, dynamic> _requiredMap(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value is! Map) throw FormatException('Invalid Activity $key.');
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static String _requiredText(
    Map<String, dynamic> json,
    String key,
    int maxLength,
  ) {
    final value = json[key];
    if (value is! String) throw FormatException('Invalid Activity $key.');
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > maxLength) {
      throw FormatException('Invalid Activity $key.');
    }
    return normalized;
  }

  static final List<RegExp> _credentialPatterns = <RegExp>[
    RegExp(r'Authorization\s*:\s*(?:Bearer|Basic)\s+\S+', caseSensitive: false),
    RegExp(r'\b(?:gh[pousr]_|github_pat_)[A-Za-z0-9_]{20,}\b'),
    RegExp(r'\bsk-[A-Za-z0-9_-]{20,}\b'),
    RegExp(r'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'),
    RegExp(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    RegExp(r'\bBearer\s+[A-Za-z0-9._~+/-]{12,}\b', caseSensitive: false),
    RegExp(
        r'\beyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\b'),
    RegExp(r'(?:postgres(?:ql)?):\/\/[^\s:@]+:[^@\s]+@', caseSensitive: false),
  ];

  static String _publicText(
    Map<String, dynamic> json,
    String key,
    int maxLength,
  ) {
    final value = _requiredText(json, key, maxLength);
    if (_credentialPatterns.any((pattern) => pattern.hasMatch(value))) {
      throw FormatException('Activity $key contains credential-like material.');
    }
    return value;
  }

  static String? _optionalPublicText(
    Map<String, dynamic> json,
    String key,
    int maxLength,
  ) {
    if (json[key] == null) return null;
    return _publicText(json, key, maxLength);
  }

  static final RegExp _opaqueIdPattern =
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$');

  static String _opaqueId(Map<String, dynamic> json, String key) {
    final value = _publicText(json, key, 200);
    if (!_opaqueIdPattern.hasMatch(value)) {
      throw FormatException('Invalid Activity $key identifier.');
    }
    return value;
  }

  static String? _optionalOpaqueId(
    Map<String, dynamic> json,
    String key,
  ) {
    if (json[key] == null) return null;
    return _opaqueId(json, key);
  }

  static final RegExp _timestampPattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|[+-]\d{2}:\d{2})$',
    caseSensitive: false,
  );

  static bool _isLeapYear(int year) =>
      year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

  static DateTime _timestamp(Map<String, dynamic> json, String key) {
    final raw = _requiredText(json, key, 80);
    final match = _timestampPattern.firstMatch(raw);
    if (match == null) {
      throw FormatException(
          'Activity $key must be an offset-aware ISO-8601 timestamp.');
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);
    final days = <int>[
      31,
      _isLeapYear(year) ? 29 : 28,
      31,
      30,
      31,
      30,
      31,
      31,
      30,
      31,
      30,
      31,
    ];
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        day > days[month - 1] ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      throw FormatException('Invalid Activity $key.');
    }
    final zone = match.group(7)!;
    if (zone.toUpperCase() != 'Z') {
      final offsetHour = int.parse(zone.substring(1, 3));
      final offsetMinute = int.parse(zone.substring(4, 6));
      if (offsetHour > 23 || offsetMinute > 59) {
        throw FormatException('Invalid Activity $key timezone offset.');
      }
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) throw FormatException('Invalid Activity $key.');
    return parsed.toUtc();
  }

  static void _rejectUnknown(
    Map<String, dynamic> json,
    Set<String> allowed,
    String field,
  ) {
    for (final key in json.keys) {
      if (!allowed.contains(key)) {
        throw FormatException(
          '$field.$key is not part of the public Activity projection.',
        );
      }
    }
  }
}
