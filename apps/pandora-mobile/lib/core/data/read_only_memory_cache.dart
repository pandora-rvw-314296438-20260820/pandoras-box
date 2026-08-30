import '../models/pandora_models.dart';
import 'pandora_repository.dart';

class ReadOnlyMemoryCache {
  ReadOnlyMemoryCache({
    int maxProjectSummaries = 250,
    int maxActivityItems = 50,
    int maxConnections = 100,
  }) : maxProjectSummaries = maxProjectSummaries.clamp(1, 1000).toInt(),
       maxActivityItems = maxActivityItems.clamp(1, 100).toInt(),
       maxConnections = maxConnections.clamp(1, 250).toInt();

  final int maxProjectSummaries;
  final int maxActivityItems;
  final int maxConnections;

  RepositorySnapshot<List<ProjectSummary>>? _projects;
  RepositorySnapshot<List<AuditEvent>>? _activity;
  RepositorySnapshot<List<ConnectionSummary>>? _connections;

  RepositorySnapshot<List<ProjectSummary>>? get projects => _projects;
  RepositorySnapshot<List<AuditEvent>>? get activity => _activity;
  RepositorySnapshot<List<ConnectionSummary>>? get connections => _connections;

  void putProjects(RepositorySnapshot<List<ProjectSummary>> snapshot) {
    _projects = _bounded(snapshot, maxProjectSummaries);
  }

  void putActivity(RepositorySnapshot<List<AuditEvent>> snapshot) {
    _activity = _bounded(snapshot, maxActivityItems);
  }

  void putConnections(RepositorySnapshot<List<ConnectionSummary>> snapshot) {
    _connections = _bounded(snapshot, maxConnections);
  }

  RepositorySnapshot<List<T>> _bounded<T>(
    RepositorySnapshot<List<T>> snapshot,
    int maximum,
  ) {
    final data = snapshot.data.length <= maximum
        ? List<T>.unmodifiable(snapshot.data)
        : List<T>.unmodifiable(snapshot.data.take(maximum));
    return RepositorySnapshot<List<T>>(
      data: data,
      source: snapshot.source,
      fetchedAt: snapshot.fetchedAt,
      verifiedAt: snapshot.verifiedAt,
      staleAfter: snapshot.staleAfter,
      requestId: snapshot.requestId,
      degradedReason: snapshot.degradedReason,
    );
  }

  void clear() {
    _projects = null;
    _activity = null;
    _connections = null;
  }
}
