import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/models/pandora_models.dart';
import '../../core/platform/pandora_native_io.dart';
import '../settings/settings_screen.dart';
import 'pandora_v2_ui.dart';
import 'project_create_experience.dart';
import 'project_experience_v2.dart';

class SimpleHomeScreen extends StatefulWidget {
  const SimpleHomeScreen({
    super.key,
    this.onAskPandora,
    this.onOpenSystems,
    this.onOpenNeedsYou,
    this.onOpenMore,
  });
  final ValueChanged<String>? onAskPandora;
  final VoidCallback? onOpenSystems;
  final VoidCallback? onOpenNeedsYou;
  final VoidCallback? onOpenMore;
  @override
  State<SimpleHomeScreen> createState() => _SimpleHomeScreenState();
}

class _SimpleHomeScreenState extends State<SimpleHomeScreen> {
  final _intent = TextEditingController();
  HomeSummary? _summary;
  bool _loading = true;
  bool _started = false;
  String? _error;
  String? _openingId;

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
    try {
      final value = await PandoraDependencies.of(context).repository.home();
      if (!mounted) return;
      setState(() {
        _summary = value.data;
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
        _error = 'Pandora could not refresh your work right now.';
      });
    }
  }

  Future<void> _create(String value) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CreateProjectExperienceScreen(initialIntent: value),
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

  String _state(ProjectSummary p) {
    if (p.blocker != null && p.blocker!.trim().isNotEmpty) {
      return 'Needs you';
    }
    final live = p.evidenceState(EvidenceStage.productionVerified) ==
            EvidenceClaimState.verified &&
        p.freshness.isFresh;
    if (live) return 'Live';
    final status = p.status.toLowerCase();
    if (status.contains('ready') ||
        status.contains('review') ||
        status.contains('approval')) {
      return 'Ready';
    }
    if (status.contains('build') ||
        status.contains('progress') ||
        status.contains('working') ||
        status.contains('active')) {
      return 'Building';
    }
    return 'Working';
  }

  String? _displayPurpose(ProjectSummary project) {
    final value = project.purpose.trim();
    if (value.isEmpty) return null;
    final cleaned = value.replaceFirst(RegExp(r'^\s*[>\-–—]\s*'), '').trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return RefreshIndicator(
      color: PandoraV2Colors.ink,
      onRefresh: _load,
      child: PandoraV2Page(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PandoraV2BrandHeader(
              onAvatar: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              ),
            ),
            const SizedBox(height: 30),
            Text(
              _greeting,
              style: const TextStyle(
                color: PandoraV2Colors.muted,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'What do you want\nto make happen?',
              style: TextStyle(
                color: PandoraV2Colors.ink,
                fontSize: 36,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.35,
                height: 1.02,
              ),
            ),
            const SizedBox(height: 24),
            PandoraV2IntentSurface(
              controller: _intent,
              hintText: 'Tell Pandora what you want…',
              onSubmit: _create,
              onVoice: () async {
                final value = await PandoraNativeIo.dictate();
                if (value != null && mounted) {
                  _intent.text = value;
                }
              },
              onAttachment: () async {
                final file = await PandoraNativeIo.pickTextAttachment();
                if (file != null && mounted) {
                  _intent.text =
                      '${_intent.text.trim()}\n${file.promptBlock}'.trim();
                }
              },
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                const Text(
                  'Your projects',
                  style: TextStyle(
                    color: PandoraV2Colors.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if ((summary?.topProjects.length ?? 0) >= 3 &&
                    widget.onOpenSystems != null)
                  TextButton(
                    onPressed: widget.onOpenSystems,
                    style: TextButton.styleFrom(
                      foregroundColor: PandoraV2Colors.ink,
                    ),
                    child: const Text('All projects'),
                  ),
              ],
            ),
            if (_loading) ...[
              const SizedBox(height: 12),
              const PandoraV2Skeleton(),
              const SizedBox(height: 12),
              const PandoraV2Skeleton(),
            ] else if (summary == null)
              PandoraV2InlineMessage(
                title: 'Your work is still safe',
                message: _error ?? 'Pandora could not load it yet.',
                actionLabel: 'Try again',
                onAction: _load,
              )
            else if (summary.topProjects.isEmpty)
              PandoraV2InlineMessage(
                title: 'Nothing here yet',
                message:
                    'Describe what you want above and Pandora will create the first working version.',
              )
            else
              for (final project in summary.topProjects) ...[
                PandoraV2ProjectCard(
                  title: project.name,
                  status: _state(project),
                  detail: _displayPurpose(project),
                  signature: project.id.hashCode,
                  loading: _openingId == project.id,
                  onTap: _openingId == project.id ? null : () => _open(project),
                ),
                const SizedBox(height: 12),
              ],
            if (_error != null && summary != null) ...[
              const SizedBox(height: 16),
              PandoraV2InlineMessage(
                title: 'Latest refresh did not complete',
                message: _error!,
                actionLabel: 'Try again',
                onAction: _load,
              ),
            ],
            if (summary != null &&
                summary.countersVerified &&
                summary.approvalCount > 0) ...[
              const SizedBox(height: 30),
              const Text(
                'Needs you',
                style: TextStyle(
                  color: PandoraV2Colors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              PandoraV2InlineMessage(
                title: summary.approvalCount == 1
                    ? 'One decision is waiting for you'
                    : '${summary.approvalCount} decisions are waiting for you',
                message:
                    'Pandora has paused only the work that requires your judgment.',
                actionLabel: 'Review',
                onAction: widget.onOpenNeedsYou,
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
