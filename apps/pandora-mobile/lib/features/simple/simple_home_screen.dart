import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/design/pandora_tokens.dart';
import '../../core/models/pandora_models.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import '../activity/activity_screen.dart';
import '../approvals/approvals_screen.dart';
import '../projects/project_detail_screen.dart';
import '../settings/settings_screen.dart';
import 'ask_pandora_screen.dart';
import 'systems_screen.dart';

void _openHome(BuildContext context, Widget screen) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}

class SimpleHomeScreen extends StatefulWidget {
  const SimpleHomeScreen({super.key});

  @override
  State<SimpleHomeScreen> createState() => _SimpleHomeScreenState();
}

class _SimpleHomeScreenState extends State<SimpleHomeScreen> {
  final TextEditingController _intent = TextEditingController();
  HomeSummary? _summary;
  bool _loading = true;
  String? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_load());
  }

  @override
  void dispose() {
    _intent.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = PandoraDependencies.of(context).repository;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final snapshot = await repository.home();
      if (!mounted) return;
      setState(() {
        _summary = snapshot.data;
        _loading = false;
      });
    } on PandoraRepositoryException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Pandora could not verify the current business state.';
      });
    }
  }

  void _ask() {
    final prompt = _intent.text.trim();
    _openHome(
      context,
      AskPandoraScreen(initialPrompt: prompt.isEmpty ? null : prompt),
    );
  }

  @override
  Widget build(BuildContext context) => PandoraPage(
        title: "Pandora's Box",
        showProductMark: true,
        onRefresh: _load,
        actions: [
          IconButton(
            tooltip: 'Open Settings',
            onPressed: () => _openHome(context, const SettingsScreen()),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Good morning. Here’s your business today.',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: PandoraSpacing.xs),
            Text(
              'Tell Pandora the result you want. Technical complexity stays behind the scenes.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: PandoraSpacing.xl),
            PandoraSurface(
              title: 'What do you want Pandora to do?',
              subtitle: 'Describe the business result in ordinary language.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _intent,
                    minLines: 2,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Build a booking system for my business…',
                      prefixIcon: Icon(Icons.auto_awesome_rounded),
                    ),
                  ),
                  const SizedBox(height: PandoraSpacing.sm),
                  FilledButton.icon(
                    onPressed: _ask,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Ask Pandora'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: PandoraSpacing.xl),
            if (_loading)
              const PandoraSurface(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: PandoraSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_error != null)
              PandoraSurface(
                title: 'Current state unavailable',
                subtitle: 'Pandora will not invent business status.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_error!),
                    const SizedBox(height: PandoraSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Check again'),
                    ),
                  ],
                ),
              )
            else
              _VerifiedHome(summary: _summary!),
          ],
        ),
      );
}

class _VerifiedHome extends StatelessWidget {
  const _VerifiedHome({required this.summary});

  final HomeSummary summary;

  @override
  Widget build(BuildContext context) {
    final recommendation = summary.priority?.reason ??
        (summary.topProjects.isNotEmpty
            ? summary.topProjects.first.nextAction
            : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PandoraSurface(
          title: 'Needs You',
          leading: const Icon(Icons.notifications_active_outlined),
          trailing: Container(
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: PandoraSpacing.xs),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              summary.countersVerified ? '${summary.approvalCount}' : '—',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                summary.priority?.action ??
                    (summary.countersVerified
                        ? summary.approvalCount == 0
                            ? 'Nothing needs your decision right now.'
                            : '${summary.approvalCount} decision${summary.approvalCount == 1 ? '' : 's'} waiting.'
                        : 'Decision state is not verified.'),
              ),
              if (summary.priority != null) ...[
                const SizedBox(height: PandoraSpacing.xs),
                Text(summary.priority!.reason),
              ],
              const SizedBox(height: PandoraSpacing.sm),
              OutlinedButton(
                onPressed: () => _openHome(context, const ApprovalsScreen()),
                child: const Text('Review Needs You'),
              ),
            ],
          ),
        ),
        const SizedBox(height: PandoraSpacing.md),
        PandoraSurface(
          title: 'Working',
          subtitle: 'Live work status from the governed runtime.',
          leading: const Icon(Icons.motion_photos_on_outlined),
          child: summary.topProjects.isEmpty
              ? const Text('No active work is currently verified.')
              : Column(
                  children: [
                    for (final project in summary.topProjects.take(3))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.circle_outlined, size: 18),
                        title: Text(project.name),
                        subtitle: Text(
                          [
                            project.status,
                            if (project.nextAction != null) project.nextAction!,
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(project.progressLabel),
                        onTap: () => _openHome(
                          context,
                          ProjectDetailScreen(project: project),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: PandoraSpacing.md),
        PandoraSurface(
          title: 'Business Pulse',
          subtitle: summary.countersVerified
              ? 'Verified operational signals.'
              : 'Operational counters have not been verified.',
          leading: const Icon(Icons.insights_outlined),
          child: Semantics(
            container: true,
            label: summary.countersVerified
                ? 'Active systems ${summary.activeProjectCount}. Needs attention ${summary.needsAttentionCount}. Decisions ${summary.approvalCount}.'
                : 'Active systems not verified. Needs attention not verified. Decisions not verified.',
            child: Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'Active systems',
                    value: summary.countersVerified
                        ? '${summary.activeProjectCount}'
                        : '—',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Needs attention',
                    value: summary.countersVerified
                        ? '${summary.needsAttentionCount}'
                        : '—',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Decisions',
                    value: summary.countersVerified
                        ? '${summary.approvalCount}'
                        : '—',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: PandoraSpacing.md),
        PandoraSurface(
          title: 'My Systems',
          subtitle: 'The systems Pandora is responsible for with you.',
          leading: const Icon(Icons.grid_view_rounded),
          trailing: TextButton(
            onPressed: () => _openHome(context, const SystemsScreen()),
            child: const Text('View all'),
          ),
          child: summary.topProjects.isEmpty
              ? const Text('No verified systems are available yet.')
              : Column(
                  children: [
                    for (final project in summary.topProjects.take(4))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          child: Icon(Icons.layers_outlined),
                        ),
                        title: Text(project.name),
                        subtitle: Text(
                          '${project.status} · ${project.progressLabel}',
                          maxLines: 2,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _openHome(
                          context,
                          ProjectDetailScreen(project: project),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: PandoraSpacing.md),
        PandoraSurface(
          title: 'Pandora Recommends',
          subtitle: 'The safest useful next move based on verified context.',
          leading: const Icon(Icons.lightbulb_outline_rounded),
          child: Text(
            recommendation ??
                'No recommendation is verified yet. Ask Pandora what should happen next.',
          ),
        ),
        const SizedBox(height: PandoraSpacing.md),
        PandoraSurface(
          title: 'Recent activity',
          leading: const Icon(Icons.history_rounded),
          trailing: TextButton(
            onPressed: () => _openHome(context, const ActivityScreen()),
            child: const Text('See all'),
          ),
          child: summary.recentActivity.isEmpty
              ? const Text('No recent verified activity.')
              : Column(
                  children: [
                    for (final event in summary.recentActivity.take(4))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.check_circle_outline_rounded),
                        title: Text(event.summary),
                        subtitle: Text(
                          [
                            if (event.project != null) event.project!,
                            if (event.result != null) event.result!,
                          ].join(' · '),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: PandoraSpacing.xs),
        child: Column(
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: PandoraSpacing.xxs),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
}
