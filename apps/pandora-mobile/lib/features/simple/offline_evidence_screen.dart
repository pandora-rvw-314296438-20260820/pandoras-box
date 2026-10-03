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
    try {
      // Independent read-only snapshots share one UI generation. The repository
      // remains responsible for whether an authorized cached read is allowed.
      final reads = await Future.wait<_EvidenceRead>([
        repo.projects(allowCached: true).then(_EvidenceRead.fromSnapshot),
        repo.connections(allowCached: true).then(_EvidenceRead.fromSnapshot),
        repo.activity(allowCached: true).then(_EvidenceRead.fromSnapshot),
      ], eagerError: true);
      if (!mounted || generation != _generation) return;
      setState(() {
        _packet = _EvidencePacket(
          projects: reads[0].count,
          connections: reads[1].count,
          activity: reads[2].count,
          cached: reads.any((read) => read.cached),
          oldestObservation: reads
              .map((read) => read.fetchedAt)
              .reduce((left, right) => left.isBefore(right) ? left : right),
        );
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        // Never retain a packet after a failed read, including denied access.
        // Legitimate offline snapshots are supplied by the repository itself.
        _packet = null;
        _error = switch (error) {
          PandoraApiError(kind: PandoraApiErrorKind.sessionExpired) =>
            'Sign in again to view evidence.',
          PandoraApiError(kind: PandoraApiErrorKind.forbidden) =>
            'Access to this evidence is no longer available.',
          StaleAuthenticatedIdentityException() =>
            'Your account changed. Reopen Saved evidence.',
          _ =>
            'Evidence could not be refreshed. Check your connection and try again.',
        };
      });
    }
  }

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
            const Text('Refreshing evidence…'),
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
                  p.cached
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

  Widget _row(String label, int count) => Padding(
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
              '$count',
              style: const TextStyle(
                color: PandoraSimpleColors.ink,
                fontSize: 18,
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
  });
  final int projects;
  final int connections;
  final int activity;
  final bool cached;
  final DateTime oldestObservation;
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

String _observationTime(DateTime value) {
  final utc = value.toUtc();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
      '${two(utc.hour)}:${two(utc.minute)} UTC';
}
