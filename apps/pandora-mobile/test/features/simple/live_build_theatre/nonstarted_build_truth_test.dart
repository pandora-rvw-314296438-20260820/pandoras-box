import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/simple/live_build_theatre/live_build_event.dart';
import 'package:pandora_mobile/features/simple/live_build_theatre/live_build_reducer.dart';

LiveBuildEvent _event(
  int sequence,
  LiveBuildEventKind kind, {
  Map<String, Object?> payload = const <String, Object?>{},
}) {
  return LiveBuildEvent(
    streamId: 'stream-1',
    sequence: sequence,
    schemaVersion: 2,
    kind: kind,
    rawEventType: kind.name,
    safePayload: payload,
    createdAt: DateTime.utc(2026, 9, 6, 6, 0, sequence),
  );
}

void main() {
  const reducer = LiveBuildTheatreReducer();

  test('admitted build identity does not imply active build execution', () {
    final state = reducer.reduce(<LiveBuildEvent>[
      _event(1, LiveBuildEventKind.buildAdmitted),
      _event(2, LiveBuildEventKind.buildJobCreated),
    ]);

    expect(state.stage, LiveBuildStage.starting);
    expect(state.statusLabel, isNot('Building the application'));
  });

  test('queued and claimed pre-execution states cannot project Building', () {
    final claimed = reducer.reduce(<LiveBuildEvent>[
      _event(1, LiveBuildEventKind.buildAdmitted),
      _event(2, LiveBuildEventKind.buildJobCreated),
      _event(
        3,
        LiveBuildEventKind.jobState,
        payload: const <String, Object?>{
          'status': 'claimed',
          'stage': 'building',
        },
      ),
    ]);
    expect(claimed.stage, LiveBuildStage.starting);

    final requeued = reducer.reduce(<LiveBuildEvent>[
      _event(1, LiveBuildEventKind.buildAdmitted),
      _event(2, LiveBuildEventKind.buildJobCreated),
      _event(
        3,
        LiveBuildEventKind.jobState,
        payload: const <String, Object?>{
          'status': 'claimed',
          'stage': 'building',
        },
      ),
      _event(
        4,
        LiveBuildEventKind.jobState,
        payload: const <String, Object?>{
          'status': 'queued',
          'stage': 'received',
        },
      ),
    ]);
    expect(requeued.stage, LiveBuildStage.starting);
    expect(requeued.statusLabel, isNot('Building the application'));
  });

  test('running execution may project the real build stage', () {
    final state = reducer.reduce(<LiveBuildEvent>[
      _event(1, LiveBuildEventKind.buildAdmitted),
      _event(2, LiveBuildEventKind.buildJobCreated),
      _event(
        3,
        LiveBuildEventKind.jobState,
        payload: const <String, Object?>{
          'status': 'running',
          'stage': 'building',
        },
      ),
    ]);

    expect(state.stage, LiveBuildStage.building);
    expect(state.statusLabel, 'Building the application');
  });
}
