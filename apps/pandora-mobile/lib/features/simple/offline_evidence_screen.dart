import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
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
        _error = 'No saved evidence is available on this device yet.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PandoraSimplePage(
        header: PandoraOwnerHeader(
          title: 'Saved evidence',
          subtitle:
              'Last-known proof you can review without changing anything.',
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
                          'No saved evidence available yet',
                          style: TextStyle(
                            color: PandoraSimpleColors.ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _error ??
                              'Open Pandora while connected first so a read-only copy of the latest evidence can be saved.',
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
                      ? 'This is the last saved evidence. It may be out of date and cannot approve or start a change.'
                      : 'This is the latest saved evidence. It is read-only and cannot approve or start a change.',
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
    required this.fetchedAt,
  });
  final int projects;
  final int connections;
  final int activity;
  final bool cached;
  final List<DateTime> fetchedAt;
}
