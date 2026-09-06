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
    final subscription = coalesceProjectBuildSnapshotsForRendering(
      () => input.stream,
      cadence: const Duration(milliseconds: 10),
    ).listen(output.add);

    for (var sequence = 1; sequence <= 100; sequence += 1) {
      input.add(snapshot(sequence));
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(output, hasLength(1));
    expect(output.single.latestSequence, 100);

    await subscription.cancel();
    await input.close();
  });

  test('control and terminal snapshots bypass render cadence', () async {
    final input = StreamController<ProjectBuildStreamSnapshot>(sync: true);
    final output = <ProjectBuildStreamSnapshot>[];
    final subscription = coalesceProjectBuildSnapshotsForRendering(
      () => input.stream,
      cadence: const Duration(seconds: 1),
    ).listen(output.add);

    input.add(snapshot(1));
    input.add(snapshot(2, reconnecting: true));
    input.add(snapshot(2, buildStatus: 'failed', publicErrorCode: 'FAILED'));

    expect(output.map((value) => value.latestSequence), <int>[2, 2]);
    expect(output.last.publicErrorCode, 'FAILED');

    await subscription.cancel();
    await input.close();
  });

  test('stream completion flushes and reopens a resilient source', () async {
    final sources = <StreamController<ProjectBuildStreamSnapshot>>[];

    Stream<ProjectBuildStreamSnapshot> sourceFactory() {
      final source = StreamController<ProjectBuildStreamSnapshot>(sync: true);
      sources.add(source);
      return source.stream;
    }

    final output = <ProjectBuildStreamSnapshot>[];
    final subscription = coalesceProjectBuildSnapshotsForRendering(
      sourceFactory,
      cadence: const Duration(seconds: 1),
    ).listen(output.add);

    sources.single.add(snapshot(7));
    sources.single.add(snapshot(8));
    await sources.single.close();
    await Future<void>.delayed(Duration.zero);

    expect(output, hasLength(1));
    expect(output.single.latestSequence, 8);
    expect(sources, hasLength(2));

    sources.last.add(snapshot(9, reconnecting: true));
    expect(output.last.latestSequence, 9);

    await subscription.cancel();
    await sources.last.close();
  });

  test(
    'supports concurrent listeners with one authoritative source subscription',
    () async {
      var sourceListenCount = 0;
      final input = StreamController<ProjectBuildStreamSnapshot>(
        sync: true,
        onListen: () => sourceListenCount += 1,
      );
      final shared = coalesceProjectBuildSnapshotsForRendering(
        () => input.stream,
        cadence: const Duration(milliseconds: 1),
      );
      final first = <ProjectBuildStreamSnapshot>[];
      final second = <ProjectBuildStreamSnapshot>[];
      final firstSubscription = shared.listen(first.add);
      final secondSubscription = shared.listen(second.add);

      input.add(snapshot(11, reconnecting: true));

      expect(sourceListenCount, 1);
      expect(first.single.latestSequence, 11);
      expect(second.single.latestSequence, 11);

      await firstSubscription.cancel();
      await secondSubscription.cancel();
      await input.close();
    },
  );

  test(
    'listener replacement opens a fresh source instead of re-listening to a cancelled single-subscription stream',
    () async {
      var sourceFactoryCalls = 0;
      final sources = <StreamController<ProjectBuildStreamSnapshot>>[];

      Stream<ProjectBuildStreamSnapshot> sourceFactory() {
        sourceFactoryCalls += 1;
        final source = StreamController<ProjectBuildStreamSnapshot>(sync: true);
        sources.add(source);
        return source.stream;
      }

      final shared = coalesceProjectBuildSnapshotsForRendering(
        sourceFactory,
        cadence: const Duration(milliseconds: 1),
      );

      final firstOutput = <ProjectBuildStreamSnapshot>[];
      final first = shared.listen(firstOutput.add);
      sources.single.add(snapshot(21, reconnecting: true));
      expect(firstOutput.single.latestSequence, 21);

      await first.cancel();
      expect(sourceFactoryCalls, 1);

      final secondOutput = <ProjectBuildStreamSnapshot>[];
      final second = shared.listen(secondOutput.add);
      expect(sourceFactoryCalls, 2);
      expect(sources, hasLength(2));

      sources.last.add(snapshot(22, reconnecting: true));
      expect(secondOutput.single.latestSequence, 22);

      await second.cancel();
      await Future.wait(sources.map((source) => source.close()));
    },
  );
}
