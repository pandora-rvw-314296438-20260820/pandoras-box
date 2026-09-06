import 'dart:async';

import '../../core/data/project_experience_api.dart';

const Duration projectBuildRenderCadence = Duration(milliseconds: 16);

/// Coalesces only customer rendering cadence for cumulative build snapshots.
///
/// [sourceFactory] must create a fresh resilient source for each listener era.
/// This keeps the render stream safe when Flutter detaches and later reattaches
/// a StreamBuilder: the previous single-subscription source is cancelled, and a
/// new authoritative resilient stream is opened instead of listening twice to
/// the same Dart stream.
///
/// During a burst, the latest exact snapshot wins for the next render tick.
/// Replay, reconnect, retention-gap and terminal/error snapshots bypass the
/// cadence so trust and intervention state are never delayed behind cosmetic
/// rendering work.
Stream<ProjectBuildStreamSnapshot> coalesceProjectBuildSnapshotsForRendering(
  Stream<ProjectBuildStreamSnapshot> Function() sourceFactory, {
  Duration cadence = projectBuildRenderCadence,
}) {
  // This controller intentionally survives listener gaps; onCancel tears down
  // the upstream source and onListen creates a fresh listener era.
  // ignore: close_sinks
  late StreamController<ProjectBuildStreamSnapshot> controller;
  // stopSource cancels the active subscription whenever the last UI listener
  // detaches; the analyzer cannot prove that callback-owned lifecycle.
  // ignore: cancel_subscriptions
  StreamSubscription<ProjectBuildStreamSnapshot>? subscription;
  Timer? timer;
  ProjectBuildStreamSnapshot? pending;
  var sourceGeneration = 0;

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
    final next = pending;
    pending = null;
    if (next != null && !controller.isClosed && controller.hasListener) {
      controller.add(next);
    }
  }

  void schedule(ProjectBuildStreamSnapshot snapshot) {
    pending = snapshot;
    if (requiresImmediateRender(snapshot) || cadence <= Duration.zero) {
      flush();
      return;
    }
    timer ??= Timer(cadence, flush);
  }

  void startSource() {
    if (controller.isClosed || subscription != null) return;
    final generation = ++sourceGeneration;
    try {
      final source = sourceFactory();
      subscription = source.listen(
        (snapshot) {
          if (generation != sourceGeneration || controller.isClosed) return;
          schedule(snapshot);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (generation != sourceGeneration || controller.isClosed) return;
          flush();
          if (controller.hasListener) {
            controller.addError(error, stackTrace);
          }
        },
        onDone: () {
          if (generation != sourceGeneration || controller.isClosed) return;
          flush();
          subscription = null;
          if (controller.hasListener) {
            // A resilient source should reconnect internally. If it completes,
            // reopen from durable replay while this surface remains mounted.
            startSource();
          }
        },
        cancelOnError: false,
      );
    } catch (error, stackTrace) {
      subscription = null;
      scheduleMicrotask(() {
        if (generation == sourceGeneration &&
            !controller.isClosed &&
            controller.hasListener) {
          controller.addError(error, stackTrace);
        }
      });
    }
  }

  void stopSource() {
    sourceGeneration += 1;
    timer?.cancel();
    timer = null;
    pending = null;
    final current = subscription;
    subscription = null;
    if (current != null) unawaited(current.cancel());
  }

  controller = StreamController<ProjectBuildStreamSnapshot>.broadcast(
    sync: true,
    onListen: startSource,
    onCancel: stopSource,
  );

  return controller.stream;
}
