import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import 'pandora_simple_ui.dart';

class OfflineEvidenceScreen extends StatefulWidget {
  const OfflineEvidenceScreen({super.key});
  @override
  State<OfflineEvidenceScreen> createState() => _OfflineEvidenceScreenState();
}

class _OfflineEvidenceScreenState extends State<OfflineEvidenceScreen> {
  bool _started = false;
  bool _loading = true;
  String? _error;
  _EvidencePacket? _packet;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = PandoraDependencies.of(context).repository;
      final projects = await repo.projects(allowCached: true);
      final connections = await repo.connections(allowCached: true);
      final activity = await repo.activity(allowCached: true);
      if (!mounted) return;
      setState(() {
        _packet = _EvidencePacket(
          projects: projects.data.length,
          connections: connections.data.length,
          activity: activity.data.length,
          cached:
              projects.isCached || connections.isCached || activity.isCached,
          fetchedAt: [
            projects.fetchedAt,
            connections.fetchedAt,
            activity.fetchedAt,
          ]..sort(),
        );
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No bounded evidence packet is available on this device yet.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PandoraSimplePage(
        header: PandoraOwnerHeader(
          title: 'Offline evidence',
          subtitle:
              'Read-only proof you can inspect without authorizing a change.',
          showBack: true,
          onBack: () => Navigator.of(context).maybePop(),
        ),
        onRefresh: _load,
        child: _loading && _packet == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
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
                          'No offline evidence available yet',
                          style: TextStyle(
                            color: PandoraSimpleColors.ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _error ??
                              'Open Pandora while connected first so bounded read-only evidence can be retained.',
                        ),
                        const SizedBox(height: 16),
                        PandoraPrimaryButton(
                          label: 'Check again',
                          icon: Icons.refresh_rounded,
                          onPressed: _load,
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
          PandoraSimpleCard(
            backgroundColor: PandoraSimpleColors.blueWash,
            shadow: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Read-only evidence packet',
                  style: TextStyle(
                    color: PandoraSimpleColors.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  p.cached
                      ? 'Last-known cached evidence. It may be stale and cannot authorize execution.'
                      : 'Latest available evidence is shown. It remains read-only and does not authorize execution.',
                  style: const TextStyle(
                    color: PandoraSimpleColors.muted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PandoraSimpleCard(
            shadow: false,
            child: Column(
              children: [
                _row('Projects', p.projects),
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
                    'Offline evidence is informational only. Refresh live provider state before approving, releasing, or changing a system.',
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
    required this.fetchedAt,
  });
  final int projects;
  final int connections;
  final int activity;
  final bool cached;
  final List<DateTime> fetchedAt;
}
