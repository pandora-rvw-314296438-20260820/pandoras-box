import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/owner_projection.dart';
import '../../core/models/pandora_models.dart';
import 'ask_pandora_screen.dart';
import 'pandora_simple_ui.dart';

class SimpleBriefingScreen extends StatefulWidget {
  const SimpleBriefingScreen({super.key});
  @override
  State<SimpleBriefingScreen> createState() => _SimpleBriefingScreenState();
}

class _SimpleBriefingScreenState extends State<SimpleBriefingScreen> {
  bool _loading = true;
  String? _error;
  _BriefingSnapshot? _snapshot;
  bool _started = false;

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
      final approvals = await repo.approvals();
      final activity = await repo.activity(allowCached: true);
      final ownerProjects =
          projects.data.where(isOwnerVisibleProject).toList(growable: false);
      final uniqueConnections = deduplicateConnections(connections.data);
      final now = DateTime.now();
      final snapshot = _BriefingSnapshot(
        needsMe: ownerProjects
            .where(
              (p) =>
                  resolveOwnerProjectState(p) ==
                  OwnerProjectState.ownerActionRequired,
            )
            .length,
        active: ownerProjects
            .where(
              (p) => resolveOwnerProjectState(p) == OwnerProjectState.executing,
            )
            .length,
        blocked: ownerProjects
            .where(
              (p) => resolveOwnerProjectState(p) == OwnerProjectState.blocked,
            )
            .length,
        connectionAttention: uniqueConnections
            .where((c) => connectionAttentionRank(c) >= 3)
            .length,
        approvals: approvals.data.where((a) => a.canDecideAt(now)).length,
        recent: activity.data.take(3).toList(growable: false),
        cached: projects.isCached || connections.isCached || activity.isCached,
        degraded: [
          projects.degradedReason,
          connections.degradedReason,
          activity.degradedReason,
        ].whereType<String>().toList(growable: false),
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Pandora could not prepare a verified briefing. Check again when your connections are available.';
      });
    }
  }

  void _askNext() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const AskPandoraScreen(
            initialPrompt:
                'Review my current systems, approvals, blockers, connection health, and recent activity. Tell me the single highest-value next action and why.',
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => PandoraSimplePage(
        header: PandoraOwnerHeader(
          title: 'Daily briefing',
          subtitle: 'What needs your attention and what should happen next.',
          showBack: true,
          onBack: () => Navigator.of(context).maybePop(),
        ),
        onRefresh: _load,
        child: _loading && _snapshot == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            : _snapshot == null
                ? PandoraSimpleCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Briefing unavailable',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(_error ?? 'No verified briefing is available.'),
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
                : _content(_snapshot!),
      );

  Widget _content(_BriefingSnapshot s) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PandoraSimpleCard(
            backgroundColor: s.blocked > 0
                ? PandoraSimpleColors.blush
                : PandoraSimpleColors.greenWash,
            shadow: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.blocked > 0
                      ? 'Your systems need attention'
                      : 'Your systems are moving',
                  style: const TextStyle(
                    color: PandoraSimpleColors.ink,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  s.cached
                      ? 'This briefing includes saved information that may be out of date. Refresh before making an important decision.'
                      : 'Built from the latest verified information available to you.',
                  style: const TextStyle(
                    color: PandoraSimpleColors.muted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metric('Needs you', s.needsMe, Icons.person_outline_rounded),
              _metric('Working', s.active, Icons.play_circle_outline_rounded),
              _metric('Blocked', s.blocked, Icons.block_rounded),
              _metric('Approvals', s.approvals, Icons.approval_outlined),
              _metric(
                  'Connections', s.connectionAttention, Icons.cable_outlined),
            ],
          ),
          if (s.degraded.isNotEmpty) ...[
            const SizedBox(height: 16),
            PandoraSimpleCard(
              backgroundColor: PandoraSimpleColors.amberWash,
              shadow: false,
              child: Text(
                'Some current checks are unavailable. Pandora is showing the latest saved information where it can.',
                style: const TextStyle(
                  color: PandoraSimpleColors.ink,
                  height: 1.35,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const PandoraSectionTitle(
            title: 'Recent verified activity',
            meta: 'Latest 3',
          ),
          const SizedBox(height: 10),
          if (s.recent.isEmpty)
            const PandoraSimpleCard(
              shadow: false,
              child: Text('No recent verified activity was returned.'),
            )
          else
            for (final event in s.recent) ...[
              PandoraSimpleCard(
                shadow: false,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PandoraIconBadge(
                      icon: Icons.history_rounded,
                      foreground: PandoraSimpleColors.blue,
                      background: PandoraSimpleColors.blueWash,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        event.summary,
                        style: const TextStyle(
                          color: PandoraSimpleColors.ink,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 14),
          PandoraPrimaryButton(
            label: 'Ask Pandora what to do next',
            icon: Icons.auto_awesome_rounded,
            onPressed: _askNext,
            expanded: true,
          ),
        ],
      );

  Widget _metric(String label, int value, IconData icon) => SizedBox(
        width: 150,
        child: PandoraSimpleCard(
          shadow: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: PandoraSimpleColors.red),
              const SizedBox(height: 10),
              Text(
                '$value',
                style: const TextStyle(
                  color: PandoraSimpleColors.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: PandoraSimpleColors.muted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
}

class _BriefingSnapshot {
  const _BriefingSnapshot({
    required this.needsMe,
    required this.active,
    required this.blocked,
    required this.connectionAttention,
    required this.approvals,
    required this.recent,
    required this.cached,
    required this.degraded,
  });
  final int needsMe;
  final int active;
  final int blocked;
  final int connectionAttention;
  final int approvals;
  final List<AuditEvent> recent;
  final bool cached;
  final List<String> degraded;
}
