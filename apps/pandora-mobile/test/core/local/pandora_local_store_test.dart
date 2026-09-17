import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/local/pandora_device_activity_local_sync.dart';
import 'package:pandora_mobile/core/local/pandora_local_data_policy.dart';
import 'package:pandora_mobile/core/local/pandora_local_store_stub.dart';
import 'package:pandora_mobile/core/local/pandora_local_sync_coordinator.dart';

class _FakeTransport implements PandoraLocalSyncTransport {
  _FakeTransport(this.results);

  final List<PandoraLocalSyncResult> results;
  final List<String> seen = <String>[];

  @override
  Future<PandoraLocalSyncResult> apply(operation) async {
    seen.add(operation.operationId);
    return results.removeAt(0);
  }
}

void main() {
  final now = DateTime.utc(2026, 9, 16, 12);

  test('local payload policy rejects credential-like fields recursively', () {
    expect(
      () => PandoraLocalDataPolicy.encodePayload(<String, Object?>{
        'safe': <String, Object?>{'apiToken': 'must-not-persist'},
      }),
      throwsFormatException,
    );
  });

  test('cache expires and is removed from local state', () async {
    final store = MemoryPandoraLocalStore(clock: () => now);
    await store.putCache(
      namespace: PandoraLocalNamespace.deviceState,
      key: 'permission-calendar',
      payload: <String, Object?>{'readGranted': true},
      expiresAt: now.add(const Duration(minutes: 5)),
    );
    expect(
      await store.getCache(
        PandoraLocalNamespace.deviceState,
        'permission-calendar',
      ),
      isNotNull,
    );
    await store.close();
  });

  test('idempotency key cannot be rebound to a different operation', () async {
    final store = MemoryPandoraLocalStore(clock: () => now);
    await store.enqueue(
      operationId: 'operation-0001',
      idempotencyKey: 'idem-0001',
      capability: 'activity.device.fact',
      payload: <String, Object?>{'value': 1},
      createdAt: now,
    );
    expect(
      () => store.enqueue(
        operationId: 'operation-0002',
        idempotencyKey: 'idem-0001',
        capability: 'activity.device.fact',
        payload: <String, Object?>{'value': 2},
        createdAt: now,
      ),
      throwsStateError,
    );
  });

  test('sync coordinator marks retry then applies on next drain', () async {
    final store = MemoryPandoraLocalStore(clock: () => now);
    await store.enqueue(
      operationId: 'operation-1001',
      idempotencyKey: 'idem-1001',
      capability: 'activity.device.fact',
      payload: <String, Object?>{'value': 1},
      createdAt: now,
    );
    final transport = _FakeTransport(<PandoraLocalSyncResult>[
      const PandoraLocalSyncResult(
        outcome: PandoraLocalSyncOutcome.retryableFailure,
        errorCode: 'offline',
      ),
      const PandoraLocalSyncResult(
        outcome: PandoraLocalSyncOutcome.applied,
      ),
    ]);
    var clock = now;
    final coordinator = PandoraLocalSyncCoordinator(
      store: store,
      transport: transport,
      clock: () => clock,
      baseBackoff: const Duration(seconds: 1),
    );
    final first = await coordinator.drain();
    expect(first.retried, 1);
    clock = now.add(const Duration(seconds: 2));
    final second = await coordinator.drain();
    expect(second.applied, 1);
    expect(transport.seen, <String>['operation-1001', 'operation-1001']);
  });

  test('offline device timeline is queued once with deterministic identity',
      () async {
    final store = MemoryPandoraLocalStore(clock: () => now);
    final events = <Map<String, Object?>>[
      <String, Object?>{
        'capability': 'calendar.events',
        'stage': 'acting',
        'observedAt': now.toIso8601String(),
      },
      <String, Object?>{
        'capability': 'calendar.events',
        'stage': 'result',
        'observedAt': now.add(const Duration(seconds: 1)).toIso8601String(),
      },
    ];
    await enqueuePandoraDeviceTimeline(
      store: store,
      requestId: 'pandora-calendar-12345678',
      threadId: 'thread-1',
      projectId: 'project-1',
      events: events,
    );
    await enqueuePandoraDeviceTimeline(
      store: store,
      requestId: 'pandora-calendar-12345678',
      threadId: 'thread-1',
      projectId: 'project-1',
      events: events,
    );
    final pending =
        await store.pendingOperations(now: now.add(const Duration(seconds: 1)));
    expect(pending, hasLength(1));
    expect(pending.single.capability, 'activity.device.timeline');
  });
}
