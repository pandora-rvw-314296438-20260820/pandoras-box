import 'dart:async';

import '../../core/data/project_experience_api.dart';

const Duration projectBuildRenderCadence = Duration(milliseconds: 16);

/// Coalesces only customer rendering cadence for cumulative build snapshots.
///
/// The resilient stream remains authoritative and unchanged. During a burst,
/// the latest exact snapshot wins for the next render tick. Replay, reconnect,
/// retention-gap and terminal/error snapshots bypass the cadence so trust and
/// intervention state are never delayed behind cosmetic rendering work.
Stream<ProjectBuildStreamSnapshot> coalesceProjectBuildSnapshotsForRendering(
  Stream<ProjectBuildStreamSnapshot> source, {
  Duration cadence = projectBuildRenderCadence,
}) {
  if (cadence <= Duration.zero) return source;

  late StreamController<ProjectBuildStreamSnapshot> controller;
  StreamSubscription<ProjectBuildStreamSnapshot>? subscription;
  Timer? timer;
  ProjectBuildStreamSnapshot? pending;
  var closed = false;

  bool requiresImmediateRender(ProjectBuildStreamSnapshot snapshot) {
    final status = snapshot.buildStatus?.trim().toLowerCase();
    return snapshot.requiresReplay ||
        snapshot.reconnecting ||
        snapshot.historyGapDueToRetention ||
        (snapshot.publicErrorCode?.trim().isNotEmpty ?? false) ||
        status == 'failed' ||
        status == 'completed' ||
        status == 'succeeded' ||
        status == 'cancelled' ||
        status == 'canceled';
  }

  void flush() {
    timer?.cancel();
    timer = null;
    if (closed) return;
    final next = pending;
    pending = null;
    if (next != null && !controller.isClosed) controller.add(next);
  }

  controller = StreamController<ProjectBuildStreamSnapshot>(
    sync: true,
    onListen: () {
      subscription = source.listen(
        (snapshot) {
          if (closed) return;
          pending = snapshot;
          if (requiresImmediateRender(snapshot)) {
            flush();
            return;
          }
          timer ??= Timer(cadence, flush);
        },
        onError: (Object error, StackTrace stackTrace) {
          flush();
          if (!closed && !controller.isClosed) {
            controller.addError(error, stackTrace);
          }
        },
        onDone: () {
          flush();
          closed = true;
          if (!controller.isClosed) controller.close();
        },
      );
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () async {
      closed = true;
      timer?.cancel();
      timer = null;
      pending = null;
      await subscription?.cancel();
    },
  );

  return controller.stream;
}
