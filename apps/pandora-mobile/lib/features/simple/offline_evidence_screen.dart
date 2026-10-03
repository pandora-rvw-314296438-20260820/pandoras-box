import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/network/pandora_api_error.dart';
import '../../core/security/pandora_auth.dart';
import 'pandora_simple_ui.dart';

class OfflineEvidenceScreen extends StatefulWidget {
  const OfflineEvidenceScreen({super.key});
  @override
  State<OfflineEvidenceScreen> createState() => _OfflineEvidenceScreenState();
}

class _OfflineEvidenceScreenState extends State<OfflineEvidenceScreen> {
  static const _readTimeout = Duration(seconds: 6);

  PandoraRepository? _repository;
  PandoraAuth? _auth;
  StreamSubscription<PandoraSession?>? _authChanges;
  String? _userId;
  int _generation = 0;
  bool _loading = true;
  String? _error;
  _EvidencePacket? _packet;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = PandoraDependencies.of(context);
    final userId = dependencies.auth.currentSession?.userId;
    if (identical(_repository, dependencies.repository) &&
        identical(_auth, dependencies.auth) &&
        _userId == userId) {
      return;
    }
    _authChanges?.cancel();
    _repository = dependencies.repository;
    _auth = dependencies.auth;
    _userId = userId;
    _packet = null;
    _authChanges = _auth!.changes.listen((session) {
      if (!mounted || session?.userId == _userId) return;
      _generation++;
      setState(() {
        _userId = session?.userId;
        _repository = null;
        _packet = null;
        _loading = false;
        _error = 'Your account changed. Reopen Saved evidence.';
      });
    });
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _authChanges?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = _repository;
    if (repo == null) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });

    final reads = <_EvidenceRead?>[null, null, null];
    var completed = 0;
    var failed = 0;

    Future<_EvidenceOutcome> read(
      int index,
      Future<RepositorySnapshot<List<Object?>>> future,
    ) async {
      try {
        final snapshot = await future.timeout(_readTimeout);
        return _EvidenceOutcome.success(
            index, _EvidenceRead.fromSnapshot(snapshot));
      } catch (error) {
        return _EvidenceOutcome.failure(index, error);
      }
    }

    final outcomes = Stream<_EvidenceOutcome>.fromFutures([
      read(
        0,
        repo.projects(allowCached: true)
            .then<RepositorySnapshot<List<Object?>>>((snapshot) =>
                RepositorySnapshot<List<Object?>>(
                  data: snapshot.data,
                  source: snapshot.source,
                  fetchedAt: snapshot.fetchedAt,
                  degradedReason: snapshot.degradedReason,
                )),
      ),
      read(
        1,
        repo.connections(allowCached: true)
            .then<RepositorySnapshot<List<Object?>>>((snapshot) =>
                RepositorySnapshot<List<Object?>>(
                  data: snapshot.data,
                  source: snapshot.source,
                  fetchedAt: snapshot.fetchedAt,
                  degradedReason: snapshot.degradedReason,
                )),
      ),
      read(
        2,
        repo.activity(allowCached: true)
            .then<RepositorySnapshot<List<Object?>>>((snapshot) =>
                RepositorySnapshot<List<Object?>>(
                  data: snapshot.data,
                  source: snapshot.source,
                  fetchedAt: snapshot.fetchedAt,
                  degradedReason: snapshot.degradedReason,
                )),
      ),
    ]);

    await for (final outcome in outcomes) {
      if (!mounted || generation != _generation) return;
      completed++;

      final terminal = _terminalEvidenceError(outcome.error);
      if (terminal != null) {
        setState(() {
          _packet = null;
          _loading = false;
          _error = terminal;
        });
        return;
      }

      if (outcome.read != null) {
        reads[outcome.index] = outcome.read;
      } else {
        failed++;
      }

      final available = reads.whereType<_EvidenceRead>().toList(growable: false);
      if (available.isNotEmpty) {
        setState(() {
          _packet = _EvidencePacket(
            projects: reads[0]?.count,
            connections: reads[1]?.count,
            activity: reads[2]?.count,
            cached: available.any((read) => read.cached),
            oldestObservation: available
                .map((read) => read.fetchedAt)
                .reduce((left, right) => left.isBefore(right) ? left : right),
            incomplete: failed > 0 || completed < reads.length,
          );
          _loading = completed < reads.length;
          _error = failed > 0
              ? 'Some evidence could not be refreshed. Available observations are shown below.'
              : null;
        });
      } else if (completed == reads.length) {
        setState(() {
          _packet = null;
          _loading = false;
          _error =
              'Evidence could not be refreshed. Check your connection and try again.';
        });
      }
    }

    if (!mounted || generation != _generation) return;
    setState(() {
      _loading = false;
      if (_packet != null && failed > 0) {
        _packet = _packet!.copyWith(incomplete: true);
        _error =
            'Some evidence could not be refreshed. Available observations are shown below.';
      }
    });
  }

  String? _terminalEvidenceError(Object? error) => switch (error) {
        PandoraApiError(kind: PandoraApiErrorKind.sessionExpired) =>
          'Sign in again to view evidence.',
        PandoraApiError(kind: PandoraApiErrorKind.forbidden) =>
          'Access to this evidence is no longer available.',
        StaleAuthenticatedIdentityException() =>
          'Your account changed. Reopen Saved evidence.',
        _ => null,
      };
  @override
  Widget build(BuildContext context) => PandoraSimplePage(
        header: PandoraOwnerHeader(
          title: 'Saved evidence',
          subtitle: 'Read-only observations from this session.',
          showBack: true,
          onBack: () => Navigator.of(context).maybePop(),
        ),
        onRefresh: _load,
        child: _loading && _packet == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Loading evidence…'),
                    ],
                  ),
                ),
              )
            : _packet == null
                ? PandoraSimpleCard(
                    backgroundColor: PandoraSimpleColors.amberWash,
                    shadow: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Evidence unavailable',
                          style: TextStyle(
                            color: PandoraSimpleColors.ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _error ??
                              'Connect to Pandora to load evidence for this session.',
                        ),
                        const SizedBox(height: 16),
                        PandoraPrimaryButton(
                          label: 'Check again',
                          icon: Icons.refresh_rounded,
                          onPressed: _repository == null ? null : _load,
                          expanded: true,
                        ),
                      ],
                    ),
                  )
                : _content(_packet!),
      );

  Widget _content(_EvidencePacket p) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text('Refreshing remaining evidence…'),
            const SizedBox(height: 12),
          ],
          if (_error != null) ...[
            PandoraSimpleCard(
              backgroundColor: PandoraSimpleColors.amberWash,
              shadow: false,
              child: Text(
                _error!,
                style: const TextStyle(
                  color: PandoraSimpleColors.ink,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          PandoraSimpleCard(
            backgroundColor: PandoraSimpleColors.blueWash,
            shadow: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Saved evidence',
                  style: TextStyle(
                    color: PandoraSimpleColors.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  p.incomplete
                      ? 'Showing the observations that are available. Missing sections are not treated as verified.'
                      : p.cached
                          ? 'Showing earlier observations held in this session. They may be out of date.'
                          : 'Read-only observations from the latest successful refresh.',
                  style: const TextStyle(
                    color: PandoraSimpleColors.muted,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Oldest observation: ${_observationTime(p.oldestObservation)}',
                  style: const TextStyle(color: PandoraSimpleColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PandoraSimpleCard(
            shadow: false,
            child: Column(
              children: [
                _row('Systems', p.projects),
                const Divider(color: PandoraSimpleColors.line),
                _row('Connections', p.connections),
                const Divider(color: PandoraSimpleColors.line),
                _row('Activity records', p.activity),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PandoraSimpleCard(
            backgroundColor: PandoraSimpleColors.amberWash,
            shadow: false,
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_clock_outlined,
                    color: PandoraSimpleColors.amber),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Saved evidence is for reference only. Refresh the current system status before approving, releasing, or changing anything.',
                    style:
                        TextStyle(color: PandoraSimpleColors.ink, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _row(String label, int? count) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: PandoraSimpleColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              count == null ? 'Unavailable' : '$count',
              style: TextStyle(
                color: count == null
                    ? PandoraSimpleColors.muted
                    : PandoraSimpleColors.ink,
                fontSize: count == null ? 13 : 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
}

class _EvidencePacket {
  const _EvidencePacket({
    required this.projects,
    required this.connections,
    required this.activity,
    required this.cached,
    required this.oldestObservation,
    required this.incomplete,
  });
  final int? projects;
  final int? connections;
  final int? activity;
  final bool cached;
  final DateTime oldestObservation;
  final bool incomplete;

  _EvidencePacket copyWith({bool? incomplete}) => _EvidencePacket(
        projects: projects,
        connections: connections,
        activity: activity,
        cached: cached,
        oldestObservation: oldestObservation,
        incomplete: incomplete ?? this.incomplete,
      );
}

class _EvidenceRead {
  const _EvidenceRead(this.count, this.cached, this.fetchedAt);

  static _EvidenceRead fromSnapshot(
          RepositorySnapshot<List<Object?>> snapshot) =>
      _EvidenceRead(
          snapshot.data.length, snapshot.isCached, snapshot.fetchedAt);

  final int count;
  final bool cached;
  final DateTime fetchedAt;
}

class _EvidenceOutcome {
  const _EvidenceOutcome._(this.index, this.read, this.error);

  const _EvidenceOutcome.success(int index, _EvidenceRead read)
      : this._(index, read, null);

  const _EvidenceOutcome.failure(int index, Object error)
      : this._(index, null, error);

  final int index;
  final _EvidenceRead? read;
  final Object? error;
}
String _observationTime(DateTime value) {
  final utc = value.toUtc();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
      '${two(utc.hour)}:${two(utc.minute)} UTC';
}
