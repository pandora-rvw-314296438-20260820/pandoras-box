import 'pandora_activity_projection.dart';

class PandoraActivityTimelineException implements Exception {
  const PandoraActivityTimelineException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PandoraActivityTimelineReducer {
  final List<PandoraActivityProjection> _events = <PandoraActivityProjection>[];
  String? _jobId;
  bool _paused = false;

  String? get jobId => _jobId;
  List<PandoraActivityProjection> get events => List.unmodifiable(_events);
  bool get isTerminal => _events.isNotEmpty && _events.last.state.isTerminal;

  List<PandoraActivityProjection> merge(
    Iterable<PandoraActivityProjection> incoming,
  ) {
    for (final event in incoming) {
      _mergeOne(event);
    }
    return events;
  }

  void reset() {
    _events.clear();
    _jobId = null;
    _paused = false;
  }

  void _mergeOne(PandoraActivityProjection event) {
    final currentJob = _jobId;
    if (currentJob == null) {
      if (event.sequence != 1) {
        throw const PandoraActivityTimelineException(
          'Activity replay is incomplete from the initial cursor.',
        );
      }
      _jobId = event.jobId;
    } else if (event.jobId != currentJob) {
      throw const PandoraActivityTimelineException(
        'Activity replay changed job identity.',
      );
    }

    final duplicateIndex =
        _events.indexWhere((item) => item.eventId == event.eventId);
    if (duplicateIndex >= 0) {
      if (!_sameProjection(_events[duplicateIndex], event)) {
        throw const PandoraActivityTimelineException(
          'Activity event identity was reused with different content.',
        );
      }
      return;
    }

    if (_events.any((item) => item.sequence == event.sequence)) {
      throw const PandoraActivityTimelineException(
        'Activity sequence was reused by a different event.',
      );
    }

    if (_events.isNotEmpty) {
      final previous = _events.last;
      if (previous.state.isTerminal) {
        throw const PandoraActivityTimelineException(
          'Activity cannot continue after a terminal event.',
        );
      }
      if (event.sequence != previous.sequence + 1) {
        throw const PandoraActivityTimelineException(
          'Activity replay contains a sequence gap or reordering.',
        );
      }
      if (event.state == PandoraActivityState.resuming && !_paused) {
        throw const PandoraActivityTimelineException(
          'Resuming requires a prior admitted Paused state.',
        );
      }
    }

    if (event.state == PandoraActivityState.paused) _paused = true;
    if (event.state == PandoraActivityState.resuming) _paused = false;
    _events.add(event);
  }

  bool _sameProjection(
    PandoraActivityProjection left,
    PandoraActivityProjection right,
  ) =>
      left.eventId == right.eventId &&
      left.jobId == right.jobId &&
      left.sequence == right.sequence &&
      left.state == right.state &&
      left.message == right.message &&
      left.occurredAt == right.occurredAt &&
      left.admittedAt == right.admittedAt &&
      left.domain == right.domain &&
      left.capability == right.capability &&
      left.executionId == right.executionId &&
      left.source.sourceType == right.source.sourceType &&
      left.source.sourceId == right.source.sourceId &&
      left.source.sourceEventId == right.source.sourceEventId &&
      left.source.observedAt == right.source.observedAt &&
      _sameEvidence(left.evidenceRefs, right.evidenceRefs) &&
      _sameBlocker(left.blocker, right.blocker) &&
      _sameOutcome(left.outcome, right.outcome);

  bool _sameEvidence(
    List<PandoraActivityEvidenceRef> left,
    List<PandoraActivityEvidenceRef> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      final a = left[index];
      final b = right[index];
      if (a.type != b.type || a.relation != b.relation || a.ref != b.ref) {
        return false;
      }
    }
    return true;
  }

  bool _sameBlocker(
      PandoraActivityBlocker? left, PandoraActivityBlocker? right) {
    if (identical(left, right)) return true;
    if (left == null || right == null) return false;
    return left.reasonCode == right.reasonCode &&
        left.reason == right.reason &&
        left.requiredAction == right.requiredAction &&
        left.approvalRequired == right.approvalRequired &&
        left.policyRef == right.policyRef;
  }

  bool _sameOutcome(
      PandoraActivityOutcome? left, PandoraActivityOutcome? right) {
    if (identical(left, right)) return true;
    if (left == null || right == null) return false;
    return left.summary == right.summary &&
        left.physicalDevice == right.physicalDevice;
  }
}
