import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/models/pandora_models.dart';
import '../../core/widgets/pandora_navigation.dart';
import 'pandora_v2_ui.dart';
import 'project_create_experience.dart';
import 'project_experience_v2.dart';
import 'project_intent_presentation.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  bool _loading = true;
  String? _error;
  String? _openingId;
  List<ProjectSummary> _projects = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _projects.isEmpty) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final result = await PandoraDependencies.of(context)
          .repository
          .projects(allowCached: true);
      if (!mounted) return;
      setState(() {
        _projects = result.data;
        _loading = false;
        _error = result.isCached
            ? (result.degradedReason ??
                'Pandora is showing the last safe project list while it reconnects.')
            : null;
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
        _error = 'Pandora could not load your work right now.';
      });
    }
  }

  Future<void> _create() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CreateProjectExperienceScreen(),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _open(ProjectSummary project) async {
    if (_openingId != null) return;
    final runtime = PandoraDependencies.of(context).projectRuntime;
    if (runtime == null) return;
    setState(() => _openingId = project.id);
    try {
      final snapshot = await runtime.runtime(project.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProjectWorkspaceV2Screen(project: snapshot.project),
        ),
      );
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Pandora could not open ${project.name} right now.',
        );
      }
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  String _state(ProjectSummary project) {
    if (project.blocker != null && project.blocker!.trim().isNotEmpty) {
      return 'Needs You';
    }
    final live = project.evidenceState(EvidenceStage.productionVerified) ==
            EvidenceClaimState.verified &&
        project.freshness.isFresh;
    if (live) return 'Live';
    final status = project.status.toLowerCase();
    if (status.contains('fail') ||
        status.contains('error') ||
        status.contains('blocked') ||
        status.contains('problem')) {
      return 'Problem';
    }
    if (status.contains('needs_you') || status.contains('approval')) {
      return 'Needs You';
    }
    if (status.contains('ready') || status.contains('review')) {
      return 'Ready';
    }
    return 'Working';
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        color: PandoraV2Colors.ink,
        onRefresh: _load,
        child: PandoraV2Page(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PandoraPageHeader(
                title: 'Projects',
                actions: [
                  IconButton(
                    tooltip: 'Create project',
                    onPressed: _create,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Everything Pandora is helping you make real.',
                style: pandoraV2Muted,
              ),
              const SizedBox(height: 30),
              if (_loading) ...[
                const PandoraV2Skeleton(),
                const SizedBox(height: 12),
                const PandoraV2Skeleton(),
              ] else if (_error != null && _projects.isEmpty)
                PandoraV2InlineMessage(
                  title: 'Your work is still safe',
                  message: _error!,
                  actionLabel: 'Try again',
                  onAction: _load,
                )
              else if (_projects.isEmpty)
                PandoraV2InlineMessage(
                  title: 'Nothing here yet',
                  message:
                      'Start with the outcome you want. Pandora will choose the technical shape.',
                  actionLabel: 'Create',
                  onAction: _create,
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 1,
                  ),
                  itemCount: _projects.length,
                  itemBuilder: (context, index) {
                    final project = _projects[index];
                    return _ObsidianProjectCard(
                      project: project,
                      state: _state(project),
                      busy: _openingId == project.id,
                      onTap: _openingId == project.id
                          ? null
                          : () => _open(project),
                    );
                  },
                ),
              if (_error != null && _projects.isNotEmpty) ...[
                const SizedBox(height: 18),
                PandoraV2InlineMessage(
                  title: 'Latest refresh did not complete',
                  message: _error!,
                  actionLabel: 'Try again',
                  onAction: _load,
                ),
              ],
              const SizedBox(height: 60),
            ],
          ),
        ),
      );
}

class _ObsidianProjectCard extends StatelessWidget {
  const _ObsidianProjectCard({
    required this.project,
    required this.state,
    required this.busy,
    required this.onTap,
  });

  final ProjectSummary project;
  final String state;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final detail = projectPurposeForDisplay(project.purpose);
    return Material(
      color: const Color(0x66141414),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: PandoraV2Colors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF171717),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2A2A2A)),
                    ),
                    child: busy
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.language_rounded, size: 18),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.more_horiz_rounded,
                    size: 18,
                    color: PandoraV2Colors.muted,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PandoraV2Colors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                detail.isEmpty ? state : '$state • $detail',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PandoraV2Colors.muted,
                  fontSize: 11.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
