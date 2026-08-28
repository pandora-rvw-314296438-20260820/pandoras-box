import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/models/pandora_models.dart';
import '../approvals/approvals_screen.dart';
import '../settings/settings_screen.dart';
import 'pandora_simple_ui.dart';
import 'project_create_experience.dart';
import 'project_journey_flow.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  bool _loading = true;
  String? _error;
  List<ProjectSummary> _projects = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _projects.isEmpty) unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await PandoraDependencies.of(context)
          .repository
          .projects(allowCached: true);
      if (!mounted) return;
      setState(() {
        _projects = result.data;
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
        _error = 'Pandora could not load your projects.';
      });
    }
  }

  Future<void> _createProject() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CreateProjectExperienceScreen()),
    );
    if (mounted) await _load();
  }

  Future<void> _openProject(ProjectSummary project) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProjectJourneyWorkspaceScreen(
          projectIdentifier: project.id,
          fallback: project,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => PandoraSimplePage(
        header: PandoraOwnerHeader(
          title: 'Projects',
          subtitle: 'Everything you have asked Pandora to build.',
          onNotifications: () => Navigator.of(
            context,
          ).push(
              MaterialPageRoute<void>(builder: (_) => const ApprovalsScreen())),
          onAvatar: () => Navigator.of(
            context,
          ).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
        ),
        onRefresh: _load,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PandoraSimpleCard(
              backgroundColor: const Color(0xFFFFFAFA),
              borderColor: const Color(0xFFF0D1D6),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const copy = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PandoraIconBadge(icon: Icons.add_rounded, size: 50),
                      SizedBox(height: 14),
                      Text(
                        'Start something new',
                        style: TextStyle(
                          color: PandoraSimpleColors.ink,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.25,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Create a project, describe the result you want, then watch Pandora build the first live preview.',
                        style: TextStyle(
                          color: PandoraSimpleColors.muted,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                    ],
                  );
                  final button = PandoraPrimaryButton(
                    label: 'New Project',
                    icon: Icons.add_rounded,
                    onPressed: _createProject,
                    expanded: constraints.maxWidth < 540,
                  );
                  if (constraints.maxWidth < 540) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [copy, const SizedBox(height: 18), button],
                    );
                  }
                  return Row(
                    children: [
                      const Expanded(child: copy),
                      const SizedBox(width: 24),
                      button,
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 26),
            PandoraSectionTitle(
              title: 'Your projects',
              meta: _loading ? null : '${_projects.length}',
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 44),
                child: Center(
                  child:
                      CircularProgressIndicator(color: PandoraSimpleColors.red),
                ),
              )
            else if (_error != null)
              PandoraSimpleCard(
                shadow: false,
                backgroundColor: const Color(0xFFFFF4F5),
                borderColor: const Color(0xFFF0C3CA),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: PandoraSimpleColors.deepRed,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    PandoraSecondaryButton(
                      label: 'Try again',
                      icon: Icons.refresh_rounded,
                      onPressed: _load,
                    ),
                  ],
                ),
              )
            else if (_projects.isEmpty)
              PandoraSimpleCard(
                shadow: false,
                child: Column(
                  children: [
                    const PandoraIconBadge(
                      icon: Icons.folder_open_rounded,
                      foreground: PandoraSimpleColors.blue,
                      background: PandoraSimpleColors.blueWash,
                      size: 54,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'No projects yet',
                      style: TextStyle(
                        color: PandoraSimpleColors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Your first project can start with a website, app, automation, backend, or simply an idea.',
                      textAlign: TextAlign.center,
                      style: pandoraSimpleMutedText,
                    ),
                    const SizedBox(height: 16),
                    PandoraPrimaryButton(
                      label: 'Create your first project',
                      icon: Icons.add_rounded,
                      onPressed: _createProject,
                    ),
                  ],
                ),
              )
            else ...[
              for (final project in _projects) ...[
                _ProjectCard(
                    project: project, onTap: () => _openProject(project)),
                const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      );
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onTap});
  final ProjectSummary project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final productionVerified =
        project.evidenceState(EvidenceStage.productionVerified) ==
                EvidenceClaimState.verified &&
            project.freshness.isFresh;
    final blocked =
        project.blocker != null && project.blocker!.trim().isNotEmpty;
    final label = productionVerified
        ? 'Live'
        : blocked
            ? 'Needs you'
            : 'Working';
    final foreground = productionVerified
        ? PandoraSimpleColors.green
        : blocked
            ? PandoraSimpleColors.amber
            : PandoraSimpleColors.blue;
    final background = productionVerified
        ? PandoraSimpleColors.greenWash
        : blocked
            ? PandoraSimpleColors.amberWash
            : PandoraSimpleColors.blueWash;
    final icon = productionVerified
        ? Icons.public_rounded
        : blocked
            ? Icons.priority_high_rounded
            : Icons.auto_awesome_rounded;

    return PandoraSimpleCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PandoraIconBadge(
            icon: Icons.folder_rounded,
            foreground: foreground,
            background: background,
            size: 52,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        project.name,
                        style: const TextStyle(
                          color: PandoraSimpleColors.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PandoraStatusPill(
                      label: label,
                      icon: icon,
                      foreground: foreground,
                      background: background,
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  project.purpose,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: pandoraSimpleMutedText,
                ),
                const SizedBox(height: 11),
                Row(
                  children: [
                    const Text(
                      'Next',
                      style: TextStyle(
                        color: PandoraSimpleColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        blocked
                            ? 'Review what needs your decision'
                            : (project.nextAction ?? 'Open project'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PandoraSimpleColors.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: PandoraSimpleColors.muted,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
