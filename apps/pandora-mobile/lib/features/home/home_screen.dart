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
import '../../core/widgets/status_badge.dart';
import '../approvals/approvals_screen.dart';
import '../command/command_screen.dart';
import '../projects/project_detail_screen.dart';
import '../projects/projects_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ScreenController<HomeSummary>? _controller;
  final _intent = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final repository = PandoraDependencies.of(context).repository;
    _controller = ScreenController<HomeSummary>(repository.home)..load();
  }

  @override
  void dispose() {
    _intent.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  void _askPandora() {
    final objective = _intent.text.trim();
    _open(CommandScreen(initialPrompt: objective.isEmpty ? null : objective));
  }

  @override
  Widget build(BuildContext context) => PandoraPage(
        title: 'Pandora',
        subtitle: 'Intent to trusted working result.',
        showProductMark: true,
        actions: [
          IconButton(
            tooltip: 'Open Settings',
            onPressed: () => _open(const SettingsScreen()),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
        onRefresh: () => _controller!.refresh(),
        child: AnimatedBuilder(
          animation: _controller!,
          builder: (context, _) {
            final controller = _controller!;
            if (controller.isLoading && controller.data == null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AskPandoraCard(controller: _intent, onSubmit: _askPandora),
                  const SizedBox(height: PandoraSpacing.md),
                  const ContentSkeleton(lines: 5),
                ],
              );
            }
            if (controller.error != null && controller.data == null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AskPandoraCard(controller: _intent, onSubmit: _askPandora),
                  const SizedBox(height: PandoraSpacing.md),
                  ErrorContent(
                    title: 'Owner briefing could not refresh',
                    message: _safeError(controller.error),
                    onRetry: controller.load,
                  ),
                ],
              );
            }
            final summary = controller.data;
            if (summary == null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AskPandoraCard(controller: _intent, onSubmit: _askPandora),
                  const SizedBox(height: PandoraSpacing.md),
                  EmptyContent(
                    title: 'No verified owner briefing yet',
                    message:
                        'Ask Pandora now, or check the portfolio when verified state returns.',
                    onAction: controller.load,
                    actionLabel: 'Check owner state',
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AskPandoraCard(controller: _intent, onSubmit: _askPandora),
                const SizedBox(height: PandoraSpacing.md),
                if (controller.error != null) ...[
                  DegradedContentNotice(
                    message:
                        'Showing the previous usable owner view. ${controller.error!.message}',
                    onRetry: controller.refresh,
                  ),
                  const SizedBox(height: PandoraSpacing.md),
                ],
                _HomeContent(
                  summary: summary,
                  refreshing: controller.isLoading,
                  onOpenApprovals: () => _open(const ApprovalsScreen()),
                  onOpenProjects: () => _open(const ProjectsScreen()),
                  onOpenProject: (project) =>
                      _open(ProjectDetailScreen(project: project)),
                  onAskRecommended: (objective) =>
                      _open(CommandScreen(initialPrompt: objective)),
                ),
              ],
            );
          },
        ),
      );
}

class _AskPandoraCard extends StatelessWidget {
  const _AskPandoraCard({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => PandoraSurface(
        title: 'Ask Pandora',
        subtitle: 'What should Pandora accomplish?',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => onSubmit(),
              decoration: const InputDecoration(
                hintText:
                    'Build a booking system, repair checkout, create an Android release…',
              ),
            ),
            const SizedBox(height: PandoraSpacing.sm),
            FilledButton.icon(
              onPressed: onSubmit,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('Describe the outcome'),
            ),
            const SizedBox(height: PandoraSpacing.xs),
            Text(
              'Build Credits: not estimated · Runtime Credits: not estimated until Pandora understands the plan.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.summary,
    required this.refreshing,
    required this.onOpenApprovals,
    required this.onOpenProjects,
    required this.onOpenProject,
    required this.onAskRecommended,
  });

  final HomeSummary summary;
  final bool refreshing;
  final VoidCallback onOpenApprovals;
  final VoidCallback onOpenProjects;
  final ValueChanged<ProjectSummary> onOpenProject;
  final ValueChanged<String> onAskRecommended;

  @override
  Widget build(BuildContext context) {
    final needsDecision = summary.countersVerified && summary.approvalCount > 0;
    final meaningfulPriority =
        isMeaningfulOwnerPriority(summary.priority) ? summary.priority : null;
    final projects = summary.topProjects
        .where(isOwnerVisibleProject)
        .toList(growable: true)
      ..sort(_compareProjectAttention);
    final working = _firstExecutingProject(projects);
    final recommendation = _recommendedNextAction(
      summary,
      projects,
      meaningfulPriority: meaningfulPriority,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OwnerBriefingHero(
          eyebrow: needsDecision ? 'Needs you' : 'Owner briefing',
          title: needsDecision
              ? meaningfulPriority?.action ??
                  '${summary.approvalCount} owner decision${summary.approvalCount == 1 ? '' : 's'} waiting'
              : !summary.countersVerified
                  ? 'Owner decision state is not verified'
                  : 'Nothing currently requires your decision',
          message: needsDecision
              ? meaningfulPriority?.reason ??
                  'Pandora has protected work that cannot continue without an owner decision.'
              : !summary.countersVerified
                  ? 'Pandora cannot verify whether an owner decision is waiting. The last usable screen remains visible without claiming zero or no action.'
                  : working == null
                      ? 'No verified execution is running. Pandora will not imply active work without evidence.'
                      : 'Pandora has verified work in motion and will surface only decisions that require you.',
          icon: needsDecision
              ? Icons.priority_high_rounded
              : Icons.auto_awesome_rounded,
          tone: needsDecision
              ? PandoraStatusTone.attention
              : PandoraStatusTone.informative,
          statusLabel: summary.healthLabel,
          actionLabel: needsDecision ? 'Review owner decisions' : null,
          onAction: needsDecision ? onOpenApprovals : null,
          footer: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (refreshing) ...[
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: PandoraSpacing.xs),
              ],
              FreshnessLabel(freshness: summary.freshness),
            ],
          ),
        ),
        const SizedBox(height: PandoraSpacing.md),
        OwnerMetricGrid(
          metrics: [
            OwnerMetric(
              label: 'Needs you',
              value:
                  summary.countersVerified ? '${summary.approvalCount}' : '—',
              icon: Icons.approval_outlined,
              tone: needsDecision
                  ? PandoraStatusTone.attention
                  : PandoraStatusTone.neutral,
              semanticLabel:
                  summary.countersVerified ? null : 'Needs you: not verified',
            ),
            OwnerMetric(
              label: 'Working now',
              value: working != null
                  ? '1+'
                  : summary.countersVerified
                      ? '0'
                      : '—',
              icon: Icons.play_circle_outline_rounded,
              tone: working == null
                  ? PandoraStatusTone.neutral
                  : PandoraStatusTone.informative,
              semanticLabel: working == null && !summary.countersVerified
                  ? 'Working now: not verified'
                  : null,
            ),
            OwnerMetric(
              label: 'Portfolio attention',
              value: summary.countersVerified
                  ? '${summary.needsAttentionCount}'
                  : '—',
              icon: Icons.warning_amber_rounded,
              tone: summary.countersVerified && summary.needsAttentionCount > 0
                  ? PandoraStatusTone.attention
                  : PandoraStatusTone.neutral,
              semanticLabel: summary.countersVerified
                  ? null
                  : 'Portfolio attention: not verified',
            ),
          ],
        ),
        const SizedBox(height: PandoraSpacing.xl),
        const OwnerSectionHeading(
          title: 'Working now',
          subtitle: 'Only execution supported by current project evidence.',
        ),
        const SizedBox(height: PandoraSpacing.sm),
        if (working == null)
          const OwnerSignal(
            label: 'Current execution',
            value: 'No verified work is running.',
            icon: Icons.pause_circle_outline_rounded,
          )
        else
          OwnerSignal(
            label: canonicalOwnerProjectLabel(working),
            value:
                '${working.nextAction ?? working.phase} · ${compactProofSummary(working)}',
            icon: Icons.play_circle_outline_rounded,
            tone: PandoraStatusTone.informative,
          ),
        const SizedBox(height: PandoraSpacing.xl),
        OwnerSectionHeading(
          title: 'Recommended next',
          subtitle:
              'One highest-value safe action. Scope and proof are confirmed before execution.',
          trailing: FilledButton.tonal(
            onPressed: () => onAskRecommended(recommendation),
            child: const Text('Prepare this action'),
          ),
        ),
        const SizedBox(height: PandoraSpacing.sm),
        OwnerSignal(
          label: 'Next action',
          value: recommendation,
          icon: Icons.arrow_forward_rounded,
          tone: needsDecision
              ? PandoraStatusTone.attention
              : PandoraStatusTone.informative,
        ),
        const SizedBox(height: PandoraSpacing.xs),
        const OwnerSignal(
          label: 'Cost and risk',
          value:
              'Build Credits and Runtime Credits are not estimated until the action is resolved. Protected or irreversible work still requires its proof gate.',
          icon: Icons.payments_outlined,
        ),
        const SizedBox(height: PandoraSpacing.xl),
        OwnerSectionHeading(
          title: 'Portfolio',
          subtitle: projects.isEmpty
              ? 'No owner-facing project summaries were returned.'
              : 'Internal recovery and ingestion lanes are hidden by default; provenance is preserved.',
          trailing: TextButton(
            onPressed: onOpenProjects,
            child: const Text('Search all'),
          ),
        ),
        const SizedBox(height: PandoraSpacing.sm),
        if (projects.isEmpty)
          const EmptyContent(
            title: 'No owner-facing projects',
            message:
                'Open Projects to inspect the latest verified portfolio state.',
          )
        else
          for (var index = 0; index < projects.length; index++) ...[
            _ProjectBrief(
              project: projects[index],
              onTap: () => onOpenProject(projects[index]),
            ),
            if (index != projects.length - 1)
              const SizedBox(height: PandoraSpacing.sm),
          ],
        const SizedBox(height: PandoraSpacing.xl),
        const OwnerSectionHeading(
          title: 'Recent results',
          subtitle:
              'Working outcomes and owner-relevant changes, with technical evidence available deeper in the app.',
        ),
        const SizedBox(height: PandoraSpacing.sm),
        PandoraSurface(
          child: summary.recentActivity.isEmpty
              ? const Text('No recent verified result was returned.')
              : Column(
                  children: [
                    for (var index = 0;
                        index < summary.recentActivity.length;
                        index++) ...[
                      _ActivityBrief(event: summary.recentActivity[index]),
                      if (index != summary.recentActivity.length - 1)
                        const Divider(),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _ProjectBrief extends StatelessWidget {
  const _ProjectBrief({required this.project, required this.onTap});

  final ProjectSummary project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ownerState = resolveOwnerProjectState(project);
    return Semantics(
      button: true,
      label: 'Open ${canonicalOwnerProjectLabel(project)}',
      child: InkWell(
        borderRadius: PandoraRadius.cardBorder,
        onTap: onTap,
        child: PandoraSurface(
          title: canonicalOwnerProjectLabel(project),
          subtitle: project.purpose,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: PandoraSpacing.xs,
                runSpacing: PandoraSpacing.xs,
                children: [
                  StatusBadge(
                    label: ownerState.label,
                    tone: statusToneFor(ownerState.label),
                    compact: true,
                  ),
                  StatusBadge(
                    label: compactProofSummary(project),
                    tone: project.evidenceState(
                              EvidenceStage.productionVerified,
                            ) ==
                            EvidenceClaimState.verified
                        ? PandoraStatusTone.verified
                        : PandoraStatusTone.neutral,
                    compact: true,
                  ),
                ],
              ),
              if (project.phase != 'Phase not verified') ...[
                const SizedBox(height: PandoraSpacing.sm),
                Text(
                  project.phase,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (project.blocker != null) ...[
                const SizedBox(height: PandoraSpacing.sm),
                OwnerSignal(
                  label: 'Blocked by',
                  value: project.blocker!,
                  icon: Icons.block_rounded,
                  tone: PandoraStatusTone.critical,
                ),
              ],
              if (project.nextAction != null) ...[
                const SizedBox(height: PandoraSpacing.xs),
                OwnerSignal(
                  label: 'Next',
                  value: project.nextAction!,
                  icon: Icons.arrow_forward_rounded,
                  tone: PandoraStatusTone.informative,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityBrief extends StatelessWidget {
  const _ActivityBrief({required this.event});

  final AuditEvent event;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: PandoraSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(providerIconFor(event.provider ?? event.type), size: 20),
            const SizedBox(width: PandoraSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.summary),
                  const SizedBox(height: PandoraSpacing.xxs),
                  Text(
                    [
                      event.project,
                      event.provider,
                      ownerRelativeTime(event.happenedAt),
                    ]
                        .whereType<String>()
                        .where((item) => item.isNotEmpty)
                        .join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (event.result != null) ...[
                    const SizedBox(height: PandoraSpacing.xs),
                    StatusBadge(
                      label: event.result!,
                      tone: statusToneFor(event.result!),
                      compact: true,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}

ProjectSummary? _firstExecutingProject(List<ProjectSummary> projects) {
  for (final project in projects) {
    if (!project.freshness.isFresh) continue;
    if (resolveOwnerProjectState(project) == OwnerProjectState.executing) {
      return project;
    }
  }
  return null;
}

String _recommendedNextAction(
  HomeSummary summary,
  List<ProjectSummary> projects, {
  ApprovalSummary? meaningfulPriority,
}) {
  if (meaningfulPriority != null) return meaningfulPriority.action;
  for (final project in projects) {
    final nextAction = project.nextAction?.trim();
    if (nextAction != null && nextAction.isNotEmpty) {
      return '${canonicalOwnerProjectLabel(project)}: $nextAction';
    }
  }
  return 'Review the owner portfolio and prepare the safest verified next action.';
}

int _compareProjectAttention(ProjectSummary left, ProjectSummary right) {
  int score(ProjectSummary project) =>
      switch (resolveOwnerProjectState(project)) {
        OwnerProjectState.ownerActionRequired => 0,
        OwnerProjectState.blocked => 1,
        OwnerProjectState.executing => 2,
        OwnerProjectState.monitoring => 3,
        OwnerProjectState.idle => 4,
        OwnerProjectState.archived => 5,
      };
  final scoreDifference = score(left).compareTo(score(right));
  if (scoreDifference != 0) return scoreDifference;
  if (left.freshness.state != right.freshness.state) {
    return left.freshness.isFresh ? 1 : -1;
  }
  return left.name.toLowerCase().compareTo(right.name.toLowerCase());
}

String _safeError(Object? error) {
  if (error is PandoraRepositoryException) return error.message;
  return 'Pandora could not verify this information. Try again.';
}
