import 'dart:collection';

enum LiveBuildEventKind {
  buildAdmitted,
  streamStarted,
  fileStarted,
  codeChunk,
  fileCompleted,
  generationCompleted,
  buildJobCreated,
  jobState,
  buildStep,
  verification,
  previewReady,
  needsYou,
  buildCompleted,
  buildFailed,
  streamError,
  unknown,
}

enum LiveBuildRetentionClass { ephemeral, durableProjection, unknown }

/// Typed client projection of Pandora Live-Build Protocol V2.
///
/// The authoritative ordering key is [streamId] + [sequence]. Storage row IDs,
/// arrival order, timestamps and widget callback order are deliberately absent
/// from the ordering contract.
class LiveBuildEvent {
  LiveBuildEvent({
    required this.streamId,
    required this.sequence,
    required this.schemaVersion,
    required this.kind,
    required this.rawEventType,
    required Map<String, Object?> safePayload,
    required this.createdAt,
    this.retentionClass = LiveBuildRetentionClass.unknown,
    this.filePath,
    this.contentChunk,
    this.buildJobId,
    this.expiresAt,
  }) : safePayload = UnmodifiableMapView<String, Object?>(safePayload) {
    if (streamId.trim().isEmpty) {
      throw const FormatException('Live build stream identity is required.');
    }
    if (sequence < 1) {
      throw const FormatException('Live build sequence must be positive.');
    }
    if (schemaVersion != 2) {
      throw const FormatException('Unsupported live build protocol version.');
    }
    if (kind == LiveBuildEventKind.codeChunk) {
      if (filePath == null || filePath!.trim().isEmpty) {
        throw const FormatException('Live code chunk file path is required.');
      }
      if (contentChunk == null || contentChunk!.isEmpty) {
        throw const FormatException(
          'Live code chunk source bytes are required.',
        );
      }
    }
  }

  factory LiveBuildEvent.fromProtocolV2Json(Map<String, dynamic> json) {
    Object? read(String camel, String snake) => json[camel] ?? json[snake];

    final streamId = _requiredText(read('streamId', 'stream_id'));
    final sequence = _requiredInt(read('sequence', 'sequence'));
    final schemaVersion = _requiredInt(
      read('eventSchemaVersion', 'event_schema_version'),
    );
    final rawType = _requiredText(read('eventType', 'event_type'));
    final createdAt = _requiredDate(read('createdAt', 'created_at'));
    final rawPayload = read('safePayload', 'safe_payload');
    final payload = rawPayload is Map
        ? <String, Object?>{
            for (final entry in rawPayload.entries)
              entry.key.toString(): entry.value,
          }
        : <String, Object?>{};

    final event = LiveBuildEvent(
      streamId: streamId,
      sequence: sequence,
      schemaVersion: schemaVersion,
      kind: liveBuildEventKindFromWire(rawType),
      rawEventType: rawType,
      retentionClass: liveBuildRetentionClassFromWire(
        _optionalText(read('retentionClass', 'retention_class')),
      ),
      filePath: _optionalText(read('filePath', 'file_path')),
      contentChunk: read('contentChunk', 'content_chunk') is String
          ? read('contentChunk', 'content_chunk') as String
          : null,
      buildJobId: _optionalText(read('buildJobId', 'build_job_id')),
      safePayload: payload,
      createdAt: createdAt,
      expiresAt: _optionalDate(read('expiresAt', 'expires_at')),
    );

    return event;
  }

  final String streamId;
  final int sequence;
  final int schemaVersion;
  final LiveBuildEventKind kind;
  final String rawEventType;
  final LiveBuildRetentionClass retentionClass;
  final String? filePath;
  final String? contentChunk;
  final String? buildJobId;
  final Map<String, Object?> safePayload;
  final DateTime createdAt;
  final DateTime? expiresAt;

  String get dedupeKey => '$streamId:$sequence';

  bool get hasRealSourceBytes =>
      kind == LiveBuildEventKind.codeChunk &&
      contentChunk != null &&
      contentChunk!.isNotEmpty;
}

LiveBuildEventKind liveBuildEventKindFromWire(String value) {
  switch (value) {
    case 'build_admitted':
      return LiveBuildEventKind.buildAdmitted;
    case 'stream_started':
      return LiveBuildEventKind.streamStarted;
    case 'file_started':
      return LiveBuildEventKind.fileStarted;
    case 'code_chunk':
      return LiveBuildEventKind.codeChunk;
    case 'file_completed':
      return LiveBuildEventKind.fileCompleted;
    case 'generation_completed':
      return LiveBuildEventKind.generationCompleted;
    case 'build_job_created':
      return LiveBuildEventKind.buildJobCreated;
    case 'job_state':
      return LiveBuildEventKind.jobState;
    case 'build_step':
      return LiveBuildEventKind.buildStep;
    case 'verification':
      return LiveBuildEventKind.verification;
    case 'preview_ready':
      return LiveBuildEventKind.previewReady;
    case 'needs_you':
      return LiveBuildEventKind.needsYou;
    case 'build_completed':
      return LiveBuildEventKind.buildCompleted;
    case 'build_failed':
      return LiveBuildEventKind.buildFailed;
    case 'stream_error':
      return LiveBuildEventKind.streamError;
    default:
      return LiveBuildEventKind.unknown;
  }
}

LiveBuildRetentionClass liveBuildRetentionClassFromWire(String? value) {
  switch (value) {
    case 'ephemeral':
      return LiveBuildRetentionClass.ephemeral;
    case 'durable_projection':
      return LiveBuildRetentionClass.durableProjection;
    default:
      return LiveBuildRetentionClass.unknown;
  }
}

String _requiredText(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  throw const FormatException('Required live build event value is missing.');
}

String? _optionalText(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

int _requiredInt(Object? value) {
  if (value is int) return value;
  final parsed = int.tryParse(value?.toString() ?? '');
  if (parsed != null) return parsed;
  throw const FormatException('Required live build event number is missing.');
}

DateTime _requiredDate(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) {
    throw const FormatException('Live build event timestamp is invalid.');
  }
  return parsed.toUtc();
}

DateTime? _optionalDate(Object? value) {
  final raw = value?.toString();
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc();
}
