import 'dart:async';

/// Shares one upstream subscription while listeners are attached, then opens a
/// fresh upstream stream when a later listener era starts.
///
/// This prevents Flutter lifecycle detach/reattach from re-listening to a
/// cancelled single-subscription stream. The upstream source remains the
/// authority for replay, ordering, errors, and completion.
Stream<T> restartableBroadcastStream<T>(
  Stream<T> Function() sourceFactory, {
  bool sync = true,
}) {
  // Intentionally kept open across zero-listener eras so a later Flutter
  // reattachment can start a fresh authoritative source.
  // ignore: close_sinks
  late StreamController<T> controller;
  StreamSubscription<T>? subscription;
  var generation = 0;

  void startSource() {
    if (controller.isClosed || subscription != null) return;
    final sourceGeneration = ++generation;

    try {
      var completedSynchronously = false;
      final next = sourceFactory().listen(
        (event) {
          if (sourceGeneration != generation ||
              controller.isClosed ||
              !controller.hasListener) {
            return;
          }
          controller.add(event);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (sourceGeneration != generation ||
              controller.isClosed ||
              !controller.hasListener) {
            return;
          }
          controller.addError(error, stackTrace);
        },
        onDone: () {
          completedSynchronously = true;
          if (sourceGeneration != generation || controller.isClosed) return;
          subscription = null;
        },
        cancelOnError: false,
      );

      if (completedSynchronously ||
          sourceGeneration != generation ||
          controller.isClosed ||
          !controller.hasListener) {
        unawaited(next.cancel());
      } else {
        subscription = next;
      }
    } catch (error, stackTrace) {
      subscription = null;
      scheduleMicrotask(() {
        if (sourceGeneration == generation &&
            !controller.isClosed &&
            controller.hasListener) {
          controller.addError(error, stackTrace);
        }
      });
    }
  }

  void stopSource() {
    generation += 1;
    final current = subscription;
    subscription = null;
    if (current != null) unawaited(current.cancel());
  }

  controller = StreamController<T>.broadcast(
    sync: sync,
    onListen: startSource,
    onCancel: stopSource,
  );
  return controller.stream;
}
