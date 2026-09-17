import 'dart:async';

import 'package:flutter/foundation.dart';

import 'pandora_activity_projection.dart';
import 'pandora_activity_timeline.dart';

class PandoraActivityTimelineController extends ChangeNotifier {
  final PandoraActivityTimelineReducer _reducer =
      PandoraActivityTimelineReducer();

  // bind/clear/dispose and terminal/fail-closed paths all cancel this
  // subscription; the analyzer cannot prove the callback-owned lifecycle.
  // ignore: cancel_subscriptions
  StreamSubscription<Map<String, dynamic>>? _subscription;
  String? _boundJobId;
  String? _publicError;
  int _generation = 0;
  bool _disposed = false;

  List<PandoraActivityProjection> get events => _reducer.events;
  String? get jobId => _boundJobId;
  String? get publicError => _publicError;
  bool get hasError => _publicError != null;
  bool get isTerminal => _reducer.isTerminal;

  Future<void> bind({
    required String jobId,
    required Stream<Map<String, dynamic>> stream,
  }) async {
    _ensureActive();
    final normalizedJobId = jobId.trim();
    if (normalizedJobId.isEmpty) {
      throw ArgumentError.value(jobId, 'jobId', 'must not be empty');
    }

    final generation = ++_generation;
    final previous = _subscription;
    _subscription = null;
    if (previous != null) unawaited(previous.cancel());
    if (_disposed || generation != _generation) return;

    _reducer.reset();
    _boundJobId = normalizedJobId;
    _publicError = null;
    notifyListeners();

    _subscription = stream.listen(
      (raw) => _admit(raw, generation),
      onError: (_) => _failClosed(generation),
      onDone: () => _handleDone(generation),
      cancelOnError: false,
    );
  }

  Future<void> clear() async {
    _ensureActive();
    ++_generation;
    final previous = _subscription;
    _subscription = null;
    if (previous != null) unawaited(previous.cancel());
    _reducer.reset();
    _boundJobId = null;
    _publicError = null;
    notifyListeners();
  }

  void _admit(Map<String, dynamic> raw, int generation) {
    if (_disposed || generation != _generation || hasError) return;
    try {
      final projection = PandoraActivityProjection.fromJson(raw);
      if (projection.jobId != _boundJobId) {
        throw const PandoraActivityTimelineException(
          'Activity stream changed job identity.',
        );
      }
      final before = _reducer.events.length;
      _reducer.merge(<PandoraActivityProjection>[projection]);
      if (_reducer.events.length != before) notifyListeners();
      if (_reducer.isTerminal) {
        final current = _subscription;
        _subscription = null;
        if (current != null) unawaited(current.cancel());
      }
    } catch (_) {
      _failClosed(generation);
    }
  }

  void _handleDone(int generation) {
    if (_disposed || generation != _generation || hasError) return;
    _subscription = null;
    if (!_reducer.isTerminal) _failClosed(generation);
  }

  void _failClosed(int generation) {
    if (_disposed || generation != _generation || hasError) return;
    _publicError = 'Pandora could not verify live Activity history.';
    final current = _subscription;
    _subscription = null;
    if (current != null) unawaited(current.cancel());
    notifyListeners();
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('PandoraActivityTimelineController is disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    final current = _subscription;
    _subscription = null;
    if (current != null) unawaited(current.cancel());
    super.dispose();
  }
}
