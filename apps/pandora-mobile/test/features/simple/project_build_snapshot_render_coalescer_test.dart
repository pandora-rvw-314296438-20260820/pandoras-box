import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/project_experience_api.dart';
import 'package:pandora_mobile/features/simple/project_build_snapshot_render_coalescer.dart';

ProjectBuildStreamSnapshot snapshot(
  int sequence, {
  bool reconnecting = false,
  bool requiresReplay = false,
  bool historyGapDueToRetention = false,
  String? buildStatus,
  String? publicErrorCode,
}) =>
    ProjectBuildStreamSnapshot(
      events: const <ProjectBuildStreamEvent>[],
      latestSequence: sequence,
      historyGapDueToRetention: historyGapDueToRetention,
      requiresReplay: requiresReplay,
      reconnecting: reconnecting,
      streamStatus: 'building',
      buildStatus: buildStatus,
      buildStage: 'source_generation',
      buildJobId: 'job-1',
      projectVersionId: null,
      publicErrorCode: publicErrorCode,
      durableSummary: const <String, Object?>{},
    );

void main() {
  test('coalesces a high-rate burst to the latest exact snapshot', () async {
    final input = StreamController<ProjectBuildStreamSnapshot>(sync: true);
    final output = <ProjectBuildStreamSnapshot>[];
    final done = Completer<void>();
    final subscription = coalesceProjectBuildSnapshotsForRendering(
      input.stream,
      cadence: const Duration(milliseconds: 10),
    ).listen(output.add, onDone: done.complete);

    for (var sequence = 1; sequence <= 100; sequence += 1) {
      input.add(snapshot(sequence));
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(output, hasLength(1));
    expect(output.single.latestSequence, 100);

    await input.close();
    await done.future;
    await subscription.cancel();
  });

  test('control and terminal snapshots bypass render cadence', () async {
    final input = StreamController<ProjectBuildStreamSnapshot>(sync: true);
    final output = <ProjectBuildStreamSnapshot>[];
    final subscription = coalesceProjectBuildSnapshotsForRendering(
      input.stream,
      cadence: const Duration(seconds: 1),
    ).listen(output.add);

    input.add(snapshot(1));
    input.add(snapshot(2, reconnecting: true));
    input.add(snapshot(2, buildStatus: 'failed', publicErrorCode: 'FAILED'));

    expect(output.map((value) => value.latestSequence), <int>[2, 2]);
    expect(output.last.publicErrorCode, 'FAILED');

    await input.close();
    await subscription.cancel();
  });

  test('stream completion flushes the latest pending snapshot', () async {
    final input = StreamController<ProjectBuildStreamSnapshot>(sync: true);
    final output = <ProjectBuildStreamSnapshot>[];
    final done = Completer<void>();
    coalesceProjectBuildSnapshotsForRendering(
      input.stream,
      cadence: const Duration(seconds: 1),
    ).listen(output.add, onDone: done.complete);

    input.add(snapshot(7));
    input.add(snapshot(8));
    await input.close();
    await done.future;

    expect(output, hasLength(1));
    expect(output.single.latestSequence, 8);
  });
}
