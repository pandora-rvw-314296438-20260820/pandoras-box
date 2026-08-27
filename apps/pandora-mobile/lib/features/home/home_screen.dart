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
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
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
        // Greeting & Profile
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: PandoraSpacing.md),
          child: Row(
            children: [
              Text(
                'Good morning, Mark',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const Spacer(),
              const CircleAvatar(backgroundImage: NetworkImage('https://github.com/mbanatao.png')),
            ],
          ),
        ),
        const SizedBox(height: PandoraSpacing.sm),
        
        // Needs You Section
        if (needsDecision) ...[
          _NeedsYouCard(summary: summary, onAction: onOpenApprovals),
          const SizedBox(height: PandoraSpacing.md),
        ],

        // Pandora is Working
        _WorkingCard(summary: summary),
        const SizedBox(height: PandoraSpacing.md),
        
        // Business Pulse
        _BusinessPulseGrid(summary: summary),
        const SizedBox(height: PandoraSpacing.md),
        
        // Pandora Recommends
        _RecommendsCard(summary: summary, onAskRecommended: onAskRecommended),
        const SizedBox(height: PandoraSpacing.md),

        // My Systems
        OwnerSectionHeading(
          title: 'My Systems',
          subtitle: 'Systems currently managed by Pandora',
          trailing: TextButton(onPressed: onOpenProjects, child: const Text('See all')),
        ),
        const SizedBox(height: PandoraSpacing.sm),
        _SystemsGrid(projects: projects, onOpenProject: onOpenProject),

        // Recent Activity
        const SizedBox(height: PandoraSpacing.xl),
        const OwnerSectionHeading(
          title: 'Recent activity',
          subtitle: 'Latest verified events.',
        ),
        const SizedBox(height: PandoraSpacing.sm),
        PandoraSurface(
          child: summary.recentActivity.isEmpty
              ? const Text('No recent verified result.')
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

// ... New helper components _NeedsYouCard, _WorkingCard, _BusinessPulseGrid, _RecommendsCard, _SystemsGrid go here ...

class _NeedsYouCard extends StatelessWidget {
  const _NeedsYouCard({required this.summary, required this.onAction});
  final HomeSummary summary;
  final VoidCallback onAction;
  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
        child: Padding(
          padding: const EdgeInsets.all(PandoraSpacing.md),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: PandoraSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Needs You', style: Theme.of(context).textTheme.titleSmall),
                    Text('${summary.approvalCount} decisions waiting',
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              FilledButton(onPressed: onAction, child: const Text('Review')),
            ],
          ),
        ),
      );
}

class _WorkingCard extends StatelessWidget {
  const _WorkingCard({required this.summary});
  final HomeSummary summary;
  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
        child: Padding(
          padding: const EdgeInsets.all(PandoraSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.live_tv_rounded, size: 16, color: Colors.green),
                  const SizedBox(width: PandoraSpacing.xs),
                  Text('Pandora is working', style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  Text('View all', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
                ],
              ),
              const SizedBox(height: PandoraSpacing.sm),
              Text('Monitoring booking system — Healthy', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      );
}

class _BusinessPulseGrid extends StatelessWidget {
  const _BusinessPulseGrid({required this.summary});
  final HomeSummary summary;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Business Pulse', style: Theme.of(context).textTheme.titleMedium),
              Text('View dashboard', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
            ],
          ),
          const SizedBox(height: PandoraSpacing.sm),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: PandoraSpacing.sm,
            crossAxisSpacing: PandoraSpacing.sm,
            childAspectRatio: 2,
            children: [
              _MetricCard(label: 'Customers', value: '${summary.customerInquiryCount}', icon: Icons.person_outline),
              _MetricCard(label: 'Bookings', value: '${summary.bookingCount}', icon: Icons.calendar_today_outlined),
              _MetricCard(label: 'Revenue', value: '₱${summary.revenue}', icon: Icons.attach_money),
              _MetricCard(label: 'Operations', value: '96%', icon: Icons.settings_outlined),
            ],
          ),
        ],
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
        child: Padding(
          padding: const EdgeInsets.all(PandoraSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 4), Text(label, style: Theme.of(context).textTheme.bodySmall)]),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      );

class _RecommendsCard extends StatelessWidget {
  const _RecommendsCard({required this.summary, required this.onAskRecommended});
  final HomeSummary summary;
  final ValueChanged<String> onAskRecommended;
  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(PandoraSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: PandoraSpacing.xs),
                  Text('Pandora Recommends', style: Theme.of(context).textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: PandoraSpacing.sm),
              Text('7 inquiries went unanswered after 6 PM this week.', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: PandoraSpacing.sm),
              FilledButton(
                onPressed: () => onAskRecommended('Automate after-hours responses'),
                child: const Text('Automate this'),
              ),
            ],
          ),
        ),
      );
}

class _SystemsGrid extends StatelessWidget {
  const _SystemsGrid({required this.projects, required this.onOpenProject});
  final List<ProjectSummary> projects;
  final ValueChanged<ProjectSummary> onOpenProject;
  @override
  Widget build(BuildContext context) => GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: PandoraSpacing.sm,
        crossAxisSpacing: PandoraSpacing.sm,
        childAspectRatio: 1.5,
        children: [
          for (var p in projects)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
              child: InkWell(
                onTap: () => onOpenProject(p),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(PandoraSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.workspaces_rounded),
                      const SizedBox(height: 8),
                      Text(p.name, style: Theme.of(context).textTheme.titleSmall),
                    ],
                  ),
                ),
              ),
            )
        ],
      );
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
