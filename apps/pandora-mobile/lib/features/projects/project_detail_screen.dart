import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/owner_projection.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/design/pandora_tokens.dart';
import '../../core/models/pandora_models.dart';
import '../../core/state/screen_controller.dart';
import '../../core/widgets/content_state.dart';
import '../../core/widgets/freshness_label.dart';
import '../../core/widgets/owner_experience.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import '../../core/widgets/proof_ladder.dart';
import '../../core/widgets/status_badge.dart';

class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({super.key, required this.project});

  final ProjectSummary project;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  ScreenController<ProjectDetail>? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final repository = PandoraDependencies.of(context).repository;
    _controller = ScreenController<ProjectDetail>(
      () => repository.project(widget.project.id, allowCached: true),
    )..load();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PandoraPage(
      title: canonicalOwnerProjectLabel(widget.project),
      subtitle: widget.project.purpose,
      onRefresh: () => _controller!.refresh(),
      child: AnimatedBuilder(
        animation: _controller!,
        builder: (context, _) {
          final controller = _controller!;
          if (controller.isLoading && controller.data == null) {
            return _LoadingProjectSnapshot(project: widget.project);
          }
          if (controller.error != null && controller.data == null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProjectSnapshot(summary: widget.project),
                const SizedBox(height: PandoraSpacing.md),
                ErrorContent(
                  title: 'Latest project detail could not load',
                  message: _safeError(controller.error),
                  onRetry: controller.load,
                ),
              ],
            );
          }
          final detail = controller.data;
          if (detail == null) {
            return const EmptyContent(
              title: 'No verified detail',
              message: 'Pandora returned no project detail.',
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (controller.degradedReason != null ||
                  controller.error != null) ...[
                DegradedContentNotice(
                  message:
                      controller.degradedReason ?? controller.error!.message,
                  onRetry: controller.refresh,
                ),
                const SizedBox(height: PandoraSpacing.md),
              ],
              _DetailContent(detail: detail),
            ],
          );
        },
      ),
    ),
  );
}

class _LoadingProjectSnapshot extends StatelessWidget {
  const _LoadingProjectSnapshot({required this.project});

  final ProjectSummary project;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _ProjectSnapshot(summary: project),
      const SizedBox(height: PandoraSpacing.md),
      const OwnerSignal(
        label: 'Refreshing',
        value: 'The last usable summary stays visible while Pandora checks deeper evidence.',
        icon: Icons.sync_rounded,
        tone: PandoraStatusTone.informative,
      ),
      const SizedBox(height: PandoraSpacing.md),
      const ContentSkeleton(lines: 4),
    ],
  );
}

class _ProjectSnapshot extends StatelessWidget {
  const _ProjectSnapshot({required this.summary, this.tasks = const []});

  final ProjectSummary summary;
  final List<ProjectTask> tasks;

  @override
  Widget build(BuildContext context) {
    final state = resolveOwnerProjectState(summary, tasks: tasks);
    return OwnerBriefingHero(
      eyebrow: 'Current project truth',
      title: state.label,
      message:
          summary.nextAction ??
          (summary.phase == 'Phase not verified'
              ? 'No verified next autonomous action is recorded yet.'
              : summary.phase),
      icon: switch (state) {
        OwnerProjectState.ownerActionRequired => Icons.priority_high_rounded,
        OwnerProjectState.blocked => Icons.block_rounded,
        OwnerProjectState.executing => Icons.play_circle_outline_rounded,
        OwnerProjectState.monitoring => Icons.radar_rounded,
        OwnerProjectState.idle => Icons.pause_circle_outline_rounded,
        OwnerProjectState.archived => Icons.archive_outlined,
      },
      tone: switch (state) {
        OwnerProjectState.ownerActionRequired => PandoraStatusTone.attention,
        OwnerProjectState.blocked => PandoraStatusTone.critical,
        OwnerProjectState.executing => PandoraStatusTone.informative,
        OwnerProjectState.monitoring => PandoraStatusTone.informative,
        OwnerProjectState.idle => PandoraStatusTone.neutral,
        OwnerProjectState.archived => PandoraStatusTone.neutral,
      },
      statusLabel: compactProofSummary(summary),
      footer: FreshnessLabel(freshness: summary.freshness),
    );
  }
}

class _DetailContent extends StatelessWidget {
  const _DetailContent({required this.detail});

  final ProjectDetail detail;

  @override
  Widget build(BuildContext context) {
    final tasks = detail.tasks;
    final done = tasks
        .where((item) => item.state == ProjectTaskState.complete)
        .toList();
    final blocked = tasks
        .where((item) => item.state == ProjectTaskState.blocked)
        .toList();
    final inProgress = tasks
        .where(
          (item) =>
              item.state == ProjectTaskState.inProgress ||
              item.state == ProjectTaskState.ready ||
              item.state == ProjectTaskState.waitingReview ||
              item.state == ProjectTaskState.waitingApproval,
        )
        .toList();
    final notActive = tasks
        .where(
          (item) =>
              item.state == ProjectTaskState.notStarted ||
              item.state == ProjectTaskState.cancelled,
        )
        .toList();
    final unknown = tasks
        .where((item) => item.state == ProjectTaskState.unknown)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProjectSnapshot(summary: detail.summary, tasks: tasks),
        if (detail.summary.blocker != null) ...[
          const SizedBox(height: PandoraSpacing.sm),
          OwnerSignal(
            label: 'Blocked by',
            value: detail.summary.blocker!,
            icon: Icons.block_rounded,
            tone: PandoraStatusTone.critical,
          ),
        ],
        const SizedBox(height: PandoraSpacing.md),
        OwnerMetricGrid(
          title: 'Work state',
          metrics: [
            OwnerMetric(
              label: 'Done',
              value: '${done.length}',
              icon: Icons.check_circle_outline_rounded,
              tone: PandoraStatusTone.verified,
            ),
            OwnerMetric(
              label: 'Working',
              value: '${inProgress.length}',
              icon: Icons.autorenew_rounded,
              tone: inProgress.isEmpty
                  ? PandoraStatusTone.neutral
                  : PandoraStatusTone.informative,
            ),
            OwnerMetric(
              label: 'Blocked',
              value: '${blocked.length}',
              icon: Icons.block_rounded,
              tone: blocked.isEmpty
                  ? PandoraStatusTone.neutral
                  : PandoraStatusTone.critical,
            ),
          ],
        ),
        const SizedBox(height: PandoraSpacing.md),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            title: const Text('Verification'),
            subtitle: Text(compactProofSummary(detail.summary)),
            trailing: const Icon(Icons.expand_more_rounded),
            childrenPadding: const EdgeInsets.fromLTRB(
              PandoraSpacing.lg,
              0,
              PandoraSpacing.lg,
              PandoraSpacing.md,
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: FreshnessLabel(freshness: detail.summary.freshness),
              ),
              const SizedBox(height: PandoraSpacing.sm),
              ProofLadder(stages: detail.summary.evidenceStages),
            ],
          ),
        ),
        if (inProgress.isNotEmpty) ...[
          const SizedBox(height: PandoraSpacing.md),
          _TaskSection(title: 'Working', tasks: inProgress),
        ],
        if (blocked.isNotEmpty) ...[
          const SizedBox(height: PandoraSpacing.md),
          _TaskSection(title: 'Blocked', tasks: blocked),
        ],
        if (done.isNotEmpty) ...[
          const SizedBox(height: PandoraSpacing.md),
          _TaskSection(title: 'Done', tasks: done, initiallyExpanded: false),
        ],
        if (notActive.isNotEmpty) ...[
          const SizedBox(height: PandoraSpacing.md),
          _TaskSection(
            title: 'Not active',
            tasks: notActive,
            initiallyExpanded: false,
          ),
        ],
        if (unknown.isNotEmpty) ...[
          const SizedBox(height: PandoraSpacing.md),
          _TaskSection(
            title: 'Status not verified',
            tasks: unknown,
            initiallyExpanded: false,
          ),
        ],
        if (tasks.isEmpty) ...[
          const SizedBox(height: PandoraSpacing.md),
          const EmptyContent(
            title: 'No verified task breakdown',
            message:
                'Pandora will not infer active work from an empty task record.',
          ),
        ],
        const SizedBox(height: PandoraSpacing.md),
        PandoraSurface(
          title: 'Evidence',
          subtitle:
              '${detail.evidence.length} active evidence item${detail.evidence.length == 1 ? '' : 's'}',
          child: detail.evidence.isEmpty
              ? const Text('No active evidence was returned.')
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < detail.evidence.length;
                      index++
                    ) ...[
                      _EvidenceRow(item: detail.evidence[index]),
                      if (index != detail.evidence.length - 1) const Divider(),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _TaskSection extends StatelessWidget {
  const _TaskSection({
    required this.title,
    required this.tasks,
    this.initiallyExpanded = true,
  });

  final String title;
  final List<ProjectTask> tasks;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      title: Text(title),
      subtitle: Text('${tasks.length} task${tasks.length == 1 ? '' : 's'}'),
      childrenPadding: const EdgeInsets.fromLTRB(
        PandoraSpacing.lg,
        0,
        PandoraSpacing.lg,
        PandoraSpacing.md,
      ),
      children: [
        for (var index = 0; index < tasks.length; index++) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: PandoraSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tasks[index].title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: PandoraSpacing.xxs),
                Text(tasks[index].status),
                const SizedBox(height: PandoraSpacing.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusBadge(
                    label: tasks[index].risk.label,
                    tone: statusToneFor(tasks[index].risk.label),
                    compact: true,
                  ),
                ),
              ],
            ),
          ),
          if (index != tasks.length - 1) const Divider(),
        ],
      ],
    ),
  );
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({required this.item});

  final EvidenceItem item;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: PandoraSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(providerIconFor(item.provider), size: 20),
        const SizedBox(width: PandoraSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.type),
              const SizedBox(height: PandoraSpacing.xxs),
              Text(
                [
                  item.provider,
                  ownerRelativeTime(item.observedAt),
                ].where((value) => value.isNotEmpty).join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: PandoraSpacing.xs),
              StatusBadge(
                label: item.verdict ?? item.status,
                tone: statusToneFor(item.verdict ?? item.status),
                compact: true,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

String _safeError(Object? error) {
  if (error is PandoraRepositoryException) return error.message;
  return 'Pandora could not verify this project. Try again.';
}
