import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/simple/live_build_theatre/live_build_event.dart';
import 'package:pandora_mobile/features/simple/live_build_theatre/live_build_reducer.dart';
import 'package:pandora_mobile/features/simple/pandora_simple_status.dart';

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
    createdAt: DateTime.utc(2026, 9, 10, 8, 0, sequence),
  );
}

void main() {
  const reducer = LiveBuildTheatreReducer();

  test('Simple status vocabulary is closed', () {
    expect(PandoraSimpleStatus.all, {
      'Working',
      'Ready',
      'Live',
      'Needs You',
      'Problem',
    });
    expect(PandoraSimpleStatus.fromWire('BUILDING'), 'Working');
    expect(PandoraSimpleStatus.fromWire('CHECKING'), 'Working');
    expect(PandoraSimpleStatus.fromWire('PREPARING'), 'Working');
    expect(PandoraSimpleStatus.fromWire('READY'), 'Ready');
    expect(PandoraSimpleStatus.fromWire('LIVE'), 'Live');
    expect(PandoraSimpleStatus.fromWire('NEEDS_YOU'), 'Needs You');
    expect(PandoraSimpleStatus.fromWire('BLOCKED'), 'Problem');
    expect(PandoraSimpleStatus.fromWire('FAILED'), 'Problem');
  });

  test('blocked and trusted_primitive failures never project Building', () {
    for (final stage in const [
      'blocked',
      'trusted_primitive_failed',
      'budget_exhausted',
      'pre_execution_failed',
      'pricing_unavailable',
    ]) {
      final state = reducer.reduce(<LiveBuildEvent>[
        _event(1, LiveBuildEventKind.buildAdmitted),
        _event(2, LiveBuildEventKind.buildJobCreated),
        _event(
          3,
          LiveBuildEventKind.jobState,
          payload: <String, Object?>{'status': 'running', 'stage': stage},
        ),
      ]);
      expect(state.stage, LiveBuildStage.problem, reason: stage);
      expect(state.statusLabel, 'Problem');
      expect(state.statusLabel, isNot('Building the application'));
    }
  });

  test('needs_you job stage is Needs You, not Building', () {
    final state = reducer.reduce(<LiveBuildEvent>[
      _event(1, LiveBuildEventKind.buildAdmitted),
      _event(
        2,
        LiveBuildEventKind.jobState,
        payload: const <String, Object?>{
          'status': 'running',
          'stage': 'needs_you',
        },
      ),
    ]);
    expect(state.stage, LiveBuildStage.needsYou);
    expect(state.statusLabel, 'Needs You');
  });

  test('blocked job status fails closed to Problem', () {
    final state = reducer.reduce(<LiveBuildEvent>[
      _event(1, LiveBuildEventKind.buildAdmitted),
      _event(
        2,
        LiveBuildEventKind.jobState,
        payload: const <String, Object?>{
          'status': 'blocked',
          'stage': 'building',
        },
      ),
    ]);
    expect(state.stage, LiveBuildStage.problem);
    expect(state.failed, isTrue);
  });
}
