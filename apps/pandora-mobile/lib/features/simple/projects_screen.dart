import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/models/pandora_models.dart';
import 'pandora_v2_ui.dart';
import 'project_create_experience.dart';
import 'project_experience_v2.dart';

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
      final result = await PandoraDependencies.of(context).repository.projects(allowCached: true);
      if (!mounted) return;
      setState(() {
        _projects = result.data;
        _loading = false;
        _error = null;
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

  Future<void> _open(ProjectSummary project) async {
    if (_openingId != null) return;
    final runtime = PandoraDependencies.of(context).projectRuntime;
    if (runtime == null) return;
    setState(() => _openingId = project.id);
    try {
      final snapshot = await runtime.runtime(project.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ProjectWorkspaceV2Screen(project: snapshot.project)),
      );
      if (mounted) await _load();
    } catch (_) {
      if (mounted) setState(() => _error = 'Pandora could not open ${project.name} right now.');
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  String _state(ProjectSummary project) {
    if (project.blocker != null && project.blocker!.trim().isNotEmpty) return 'Needs you';
    final live = project.evidenceState(EvidenceStage.productionVerified) == EvidenceClaimState.verified && project.freshness.isFresh;
    if (live) return 'Live';
    if (project.pendingApprovalCount > 0) return 'Ready for review';
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
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Work',
                      style: TextStyle(color: PandoraV2Colors.ink, fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -1.1),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Create',
                    style: IconButton.styleFrom(backgroundColor: PandoraV2Colors.ink, foregroundColor: Colors.white),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const CreateProjectExperienceScreen()),
                      );
                      if (mounted) await _load();
                    },
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Everything Pandora is helping you make real.', style: pandoraV2Muted),
              const SizedBox(height: 30),
              if (_loading) ...[
                const PandoraV2Skeleton(),
                const SizedBox(height: 12),
                const PandoraV2Skeleton(),
              ] else if (_error != null && _projects.isEmpty)
                PandoraV2InlineMessage(title: 'Your work is still safe', message: _error!, actionLabel: 'Try again', onAction: _load)
              else if (_projects.isEmpty)
                PandoraV2InlineMessage(
                  title: 'Nothing here yet',
                  message: 'Start with the outcome you want. Pandora will choose the technical shape.',
                  actionLabel: 'Create',
                  onAction: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CreateProjectExperienceScreen())),
                )
              else
                for (final project in _projects)
                  PandoraV2ObjectWindow(
                    title: project.name,
                    subtitle: _state(project),
                    detail: project.purpose.trim().isEmpty ? null : project.purpose,
                    onTap: _openingId == project.id ? null : () => _open(project),
                    trailing: _openingId == project.id
                        ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: PandoraV2Colors.ink))
                        : null,
                  ),
              if (_error != null && _projects.isNotEmpty) ...[
                const SizedBox(height: 18),
                PandoraV2InlineMessage(title: 'Latest refresh did not complete', message: _error!, actionLabel: 'Try again', onAction: _load),
              ],
              const SizedBox(height: 60),
            ],
          ),
        ),
      );
}
