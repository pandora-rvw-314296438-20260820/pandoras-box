import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../data/pandora_intelligence_api.dart';
import 'pandora_local_store_contract.dart';
import 'pandora_local_sync_coordinator.dart';

const _deviceFactCapability = 'activity.device.fact';
const _deviceTimelineCapability = 'activity.device.timeline';

String pandoraActivitySyncIdentity(String canonical) {
  final digest = sha256.convert(utf8.encode(canonical)).toString();
  return 'activity-sync:$digest';
}

Map<String, Object?> pandoraDeviceFactPayload({
  required String jobId,
  required String operationId,
  required String capability,
  required String stage,
  required DateTime observedAt,
}) =>
    <String, Object?>{
      'jobId': jobId,
      'operationId': operationId,
      'capability': capability,
      'stage': stage,
      'observedAt': observedAt.toUtc().toIso8601String(),
    };
Map<String, Object?> pandoraDeviceTimelinePayload({
  required String requestId,
  required List<Map<String, Object?>> events,
  String? threadId,
  String? projectId,
}) =>
    <String, Object?>{
      'requestId': requestId,
      if (threadId != null) 'threadId': threadId,
      if (projectId != null) 'projectId': projectId,
      'events': events,
    };

class PandoraDeviceActivityLocalSyncTransport
    implements PandoraLocalSyncTransport {
  const PandoraDeviceActivityLocalSyncTransport(this._intelligence);

  final PandoraIntelligenceApi _intelligence;

  @override
  Future<PandoraLocalSyncResult> apply(
    PandoraOfflineOperation operation,
  ) async {
    try {
      final decoded = jsonDecode(operation.payloadJson);
      if (decoded is! Map) return _terminal('payload_invalid');
      final payload = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      switch (operation.capability) {
        case _deviceFactCapability:
          return await _applyFact(payload);
        case _deviceTimelineCapability:
          return await _applyTimeline(payload);
        default:
          return _terminal('capability_unsupported');
      }
    } on FormatException {
      return _terminal('payload_invalid');
    } on PandoraIntelligenceException {
      return const PandoraLocalSyncResult(
        outcome: PandoraLocalSyncOutcome.retryableFailure,
        errorCode: 'activity_sync_unavailable',
      );
    } on Object {
      return const PandoraLocalSyncResult(
        outcome: PandoraLocalSyncOutcome.retryableFailure,
        errorCode: 'activity_sync_failed',
      );
    }
  }

  Future<PandoraLocalSyncResult> _applyFact(
    Map<String, Object?> payload,
  ) async {
    await _intelligence.recordDeviceActivity(
      jobId: _requiredText(payload, 'jobId'),
      operationId: _requiredText(payload, 'operationId'),
      capability: _requiredText(payload, 'capability'),
      stage: _requiredText(payload, 'stage'),
      observedAt: _requiredTime(payload, 'observedAt'),
    );
    return const PandoraLocalSyncResult(
      outcome: PandoraLocalSyncOutcome.applied,
    );
  }

  Future<PandoraLocalSyncResult> _applyTimeline(
    Map<String, Object?> payload,
  ) async {
    final requestId = _requiredText(payload, 'requestId');
    final threadId = _optionalText(payload['threadId']);
    final projectId = _optionalText(payload['projectId']);
    final rawEvents = payload['events'];
    if (rawEvents is! List || rawEvents.isEmpty || rawEvents.length > 16) {
      throw const FormatException('Invalid device activity timeline.');
    }
    final execution = await _intelligence.startDeviceActivity(
      requestId: requestId,
      threadId: threadId,
      projectId: projectId,
    );
    for (final rawEvent in rawEvents) {
      if (rawEvent is! Map) {
        throw const FormatException('Invalid device activity event.');
      }
      final event = rawEvent.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      await _intelligence.recordDeviceActivity(
        jobId: execution.jobId,
        operationId: requestId,
        capability: _requiredText(event, 'capability'),
        stage: _requiredText(event, 'stage'),
        observedAt: _requiredTime(event, 'observedAt'),
      );
    }
    return const PandoraLocalSyncResult(
      outcome: PandoraLocalSyncOutcome.applied,
    );
  }

  String _requiredText(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Missing $key.');
    }
    return value.trim();
  }

  DateTime _requiredTime(Map<String, Object?> payload, String key) {
    final raw = _requiredText(payload, key);
    final parsed = DateTime.tryParse(raw)?.toUtc();
    if (parsed == null) throw FormatException('Invalid $key.');
    return parsed;
  }

  String? _optionalText(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  PandoraLocalSyncResult _terminal(String code) => PandoraLocalSyncResult(
        outcome: PandoraLocalSyncOutcome.terminalFailure,
        errorCode: code,
      );
}

Future<void> enqueuePandoraDeviceFact({
  required PandoraLocalStore store,
  required String jobId,
  required String operationId,
  required String capability,
  required String stage,
  required DateTime observedAt,
}) async {
  final identity = pandoraActivitySyncIdentity(
    '$jobId|$operationId|$capability|$stage',
  );
  await store.enqueue(
    operationId: identity,
    idempotencyKey: identity,
    capability: _deviceFactCapability,
    payload: pandoraDeviceFactPayload(
      jobId: jobId,
      operationId: operationId,
      capability: capability,
      stage: stage,
      observedAt: observedAt,
    ),
    createdAt: observedAt,
  );
}

Future<void> enqueuePandoraDeviceTimeline({
  required PandoraLocalStore store,
  required String requestId,
  required List<Map<String, Object?>> events,
  String? threadId,
  String? projectId,
}) async {
  final identity = pandoraActivitySyncIdentity('timeline|$requestId');
  final firstObserved = events.isEmpty
      ? null
      : DateTime.tryParse(events.first['observedAt']?.toString() ?? '')
          ?.toUtc();
  await store.enqueue(
    operationId: identity,
    idempotencyKey: identity,
    capability: _deviceTimelineCapability,
    payload: pandoraDeviceTimelinePayload(
      requestId: requestId,
      events: events,
      threadId: threadId,
      projectId: projectId,
    ),
    createdAt: firstObserved ?? DateTime.now().toUtc(),
  );
}
