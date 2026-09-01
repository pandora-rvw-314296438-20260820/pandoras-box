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
import 'project_detail_screen.dart';

enum ProjectFilter {
  all('All'),
  needsMe('Needs me'),
  active('Active'),
  blocked('Blocked'),
  stale('Stale'),
  recentlyChanged('Recently changed'),
  productionVerified('Production verified');

  const ProjectFilter(this.label);
  final String label;
}

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  ScreenController<List<ProjectSummary>>? _controller;
  final _search = TextEditingController();
  ProjectFilter _filter = ProjectFilter.all;
  bool _showInternal = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final repository = PandoraDependencies.of(context).repository;
    _controller = ScreenController<List<ProjectSummary>>(
      () => repository.projects(allowCached: true),
    )..load();
  }

  @override
  void dispose() {
    _search.dispose();
    _controller?.dispose();
    super.dispose();
  }

  List<ProjectSummary> _visible(List<ProjectSummary> projects) {
    final query = _search.text.trim().toLowerCase();
    final visible = projects
        .where((project) {
          if (!_showInternal && !isOwnerVisibleProject(project)) return false;
          final ownerState = resolveOwnerProjectState(project);
          final matchesQuery =
              query.isEmpty ||
              '${project.name} ${project.purpose} ${project.phase} ${ownerState.label}'
                  .toLowerCase()
                  .contains(query);
          if (!matchesQuery) return false;
          return switch (_filter) {
            ProjectFilter.all => true,
            ProjectFilter.needsMe =>
              ownerState == OwnerProjectState.ownerActionRequired,
            ProjectFilter.active => ownerState == OwnerProjectState.executing,
            ProjectFilter.blocked => ownerState == OwnerProjectState.blocked,
            ProjectFilter.stale =>
              project.freshness.state != FreshnessState.fresh,
            ProjectFilter.recentlyChanged =>
              project.freshness.state == FreshnessState.fresh,
            ProjectFilter.productionVerified =>
              project.evidenceState(EvidenceStage.productionVerified) ==
                  EvidenceClaimState.verified,
          };
        })
        .toList(growable: true);
    visible.sort(_compareProjectAttention);
    return List<ProjectSummary>.unmodifiable(visible);
  }

  @override
  Widget build(BuildContext context) => PandoraPage(
    title: 'Projects',
    subtitle: 'Business systems first; technical workstreams on demand.',
    onRefresh: () => _controller!.refresh(),
    child: AnimatedBuilder(
      animation: _controller!,
      builder: (context, _) {
        final controller = _controller!;
        if (controller.isLoading && controller.data == null) {
          return const ContentSkeleton(lines: 6);
        }
        if (controller.error != null && controller.data == null) {
          return ErrorContent(
            title: 'Projects could not load',
            message: _safeError(controller.error),
            onRetry: controller.load,
          );
        }
        final allProjects = controller.data ?? const <ProjectSummary>[];
        final ownerProjects = allProjects
            .where(isOwnerVisibleProject)
            .toList(growable: false);
        final projects = _visible(allProjects);
        final blocked = ownerProjects
            .where(
              (project) =>
                  resolveOwnerProjectState(project) ==
                  OwnerProjectState.blocked,
            )
            .length;
        final working = ownerProjects
            .where(
              (project) =>
                  resolveOwnerProjectState(project) ==
                  OwnerProjectState.executing,
            )
            .length;
        final productionVerified = ownerProjects
            .where(
              (project) =>
                  project.evidenceState(EvidenceStage.productionVerified) ==
                  EvidenceClaimState.verified,
            )
            .length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (controller.degradedReason != null ||
                controller.error != null) ...[
              DegradedContentNotice(
                message: controller.degradedReason ?? controller.error!.message,
                onRetry: controller.refresh,
              ),
              const SizedBox(height: PandoraSpacing.md),
            ],
            OwnerMetricGrid(
              metrics: [
                OwnerMetric(
                  label: 'Owner projects',
                  value: '${ownerProjects.length}',
                  icon: Icons.workspaces_outline,
                  tone: PandoraStatusTone.informative,
                ),
                OwnerMetric(
                  label: 'Working now',
                  value: '$working',
                  icon: Icons.play_circle_outline_rounded,
                  tone: working > 0
                      ? PandoraStatusTone.informative
                      : PandoraStatusTone.neutral,
                ),
                OwnerMetric(
                  label: 'Blocked',
                  value: '$blocked',
                  icon: Icons.block_rounded,
                  tone: blocked > 0
                      ? PandoraStatusTone.critical
                      : PandoraStatusTone.neutral,
                ),
                OwnerMetric(
                  label: 'Production verified',
                  value: '$productionVerified',
                  icon: Icons.verified_outlined,
                  tone: PandoraStatusTone.verified,
                ),
              ],
            ),
            const SizedBox(height: PandoraSpacing.md),
            PandoraSurface(
              title: 'Search portfolio',
              subtitle: 'Internal recovery and ingestion records stay hidden in Simple view.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Search projects',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: PandoraSpacing.sm),
                  Wrap(
                    spacing: PandoraSpacing.xs,
                    runSpacing: PandoraSpacing.xs,
                    children: [
                      for (final filter in ProjectFilter.values)
                        FilterChip(
                          label: Text(filter.label),
                          selected: _filter == filter,
                          onSelected: (_) => setState(() => _filter = filter),
                        ),
                      FilterChip(
                        label: const Text('Professional: internal'),
                        selected: _showInternal,
                        onSelected: (value) =>
                            setState(() => _showInternal = value),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: PandoraSpacing.xl),
            OwnerSectionHeading(
              title: _showInternal ? 'All project records' : 'Portfolio',
              subtitle: projects.isEmpty
                  ? 'No projects match the current view.'
                  : '${projects.length} project${projects.length == 1 ? '' : 's'} · owner action, blockers, and active work first',
            ),
            const SizedBox(height: PandoraSpacing.sm),
            if (projects.isEmpty)
              EmptyContent(
                title: 'No matching projects',
                message: _search.text.isEmpty && _filter == ProjectFilter.all
                    ? 'No verified projects were returned for this view.'
                    : 'Try another search or filter.',
              )
            else
              for (var index = 0; index < projects.length; index++) ...[
                _ProjectCard(project: projects[index]),
                if (index != projects.length - 1)
                  const SizedBox(height: PandoraSpacing.sm),
              ],
          ],
        );
      },
    ),
  );
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});

  final ProjectSummary project;

  @override
  Widget build(BuildContext context) {
    final ownerState = resolveOwnerProjectState(project);
    return Semantics(
      button: true,
      label: 'Open ${canonicalOwnerProjectLabel(project)}',
      child: InkWell(
        borderRadius: PandoraRadius.cardBorder,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ProjectDetailScreen(project: project),
          ),
        ),
        child: PandoraSurface(
          title: canonicalOwnerProjectLabel(project),
          subtitle: project.purpose,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: PandoraSpacing.xs,
                runSpacing: PandoraSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusBadge(
                    label: ownerState.label,
                    tone: statusToneFor(ownerState.label),
                    compact: true,
                  ),
                  StatusBadge(
                    label: compactProofSummary(project),
                    tone:
                        project.evidenceState(
                              EvidenceStage.productionVerified,
                            ) ==
                            EvidenceClaimState.verified
                        ? PandoraStatusTone.verified
                        : PandoraStatusTone.neutral,
                    compact: true,
                  ),
                  FreshnessLabel(freshness: project.freshness),
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
  final difference = score(left).compareTo(score(right));
  if (difference != 0) return difference;
  if (left.freshness.state != right.freshness.state) {
    return left.freshness.isFresh ? 1 : -1;
  }
  return left.name.toLowerCase().compareTo(right.name.toLowerCase());
}

String _safeError(Object? error) {
  if (error is PandoraRepositoryException) return error.message;
  return 'Pandora could not verify the project list. Try again.';
}
