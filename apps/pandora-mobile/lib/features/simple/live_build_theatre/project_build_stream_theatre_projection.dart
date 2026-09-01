import '../../../core/data/project_experience_api.dart';
import 'live_build_event.dart';
import 'live_build_reducer.dart';

/// Bridges the authoritative resilient project stream into Chat D's visible
/// theatre without inventing ordering, source bytes, metrics or lifecycle state.
class ProjectBuildStreamTheatreProjection {
  const ProjectBuildStreamTheatreProjection._();

  static LiveBuildTheatreState fromSnapshot({
    required String streamId,
    required ProjectBuildStreamSnapshot snapshot,
    LiveBuildTheatreReducer reducer = const LiveBuildTheatreReducer(),
  }) {
    final expectedStreamId = streamId.trim();
    if (expectedStreamId.isEmpty) {
      throw const FormatException('Live build stream identity is required.');
    }

    final events = <LiveBuildEvent>[
      for (final event in snapshot.events)
        LiveBuildEvent(
          streamId: expectedStreamId,
          sequence: event.sequence,
          schemaVersion: event.eventSchemaVersion,
          kind: liveBuildEventKindFromWire(event.eventType),
          rawEventType: event.eventType,
          retentionClass: liveBuildRetentionClassFromWire(event.retentionClass),
          filePath: event.filePath,
          contentChunk: event.contentChunk,
          buildJobId: event.buildJobId,
          safePayload: event.safePayload,
          createdAt: event.createdAt,
          expiresAt: event.expiresAt,
        ),
    ];

    return reducer.reduce(
      events,
      historyGapDueToRetention: snapshot.historyGapDueToRetention,
      sourceHistoryComplete: _hasCompleteSourcePrefix(snapshot),
    );
  }

  static bool _hasCompleteSourcePrefix(ProjectBuildStreamSnapshot snapshot) {
    if (snapshot.historyGapDueToRetention || snapshot.events.isEmpty) {
      return false;
    }

    final bySequence = <int, ProjectBuildStreamEvent>{
      for (final event in snapshot.events) event.sequence: event,
    };
    final generationSequences =
        bySequence.values
            .where((event) => event.eventType == 'generation_completed')
            .map((event) => event.sequence)
            .toList()
          ..sort();
    if (generationSequences.isEmpty) return false;

    final generationSequence = generationSequences.first;
    if (!bySequence.containsKey(1)) return false;
    for (var sequence = 1; sequence <= generationSequence; sequence += 1) {
      if (!bySequence.containsKey(sequence)) return false;
    }
    return true;
  }
}
