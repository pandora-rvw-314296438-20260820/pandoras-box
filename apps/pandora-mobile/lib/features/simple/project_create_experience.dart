import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/data/project_experience_api.dart';
import '../../core/models/project_journey_models.dart';
import '../../core/network/idempotency_key.dart';
import '../../core/platform/pandora_native_io.dart';
import 'pandora_v2_ui.dart';
import 'project_experience_v2.dart';

class CreateProjectExperienceScreen extends StatefulWidget {
  const CreateProjectExperienceScreen({super.key, this.initialIntent});

  final String? initialIntent;

  @override
  State<CreateProjectExperienceScreen> createState() =>
      _CreateProjectExperienceScreenState();
}

class _CreateProjectExperienceScreenState
    extends State<CreateProjectExperienceScreen> {
  late final TextEditingController _intent;
  final _keys = IdempotencyKeyFactory();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _intent = TextEditingController(text: widget.initialIntent?.trim() ?? '');
  }

  @override
  void dispose() {
    _intent.dispose();
    super.dispose();
  }

  String _inferName(String text) {
    final plain = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final forIndex = plain.toLowerCase().lastIndexOf(' for ');
    if (forIndex >= 0) {
      var candidate = plain.substring(forIndex + 5);
      candidate = candidate
          .split(
            RegExp(r'[,.;]|\bwhere\b|\bthat\b|\bwith\b', caseSensitive: false),
          )
          .first
          .trim();
      final words = candidate
          .split(' ')
          .where((word) => word.isNotEmpty)
          .take(5)
          .toList();
      if (words.isNotEmpty) return words.join(' ');
    }
    var candidate = plain.replaceFirst(
      RegExp(
        r'^(please\s+)?(build|create|make|design|develop)\s+(me\s+)?',
        caseSensitive: false,
      ),
      '',
    );
    candidate = candidate.split(RegExp(r'[,.;]')).first.trim();
    final words = candidate
        .split(' ')
        .where((word) => word.isNotEmpty)
        .take(5)
        .toList();
    return words.isEmpty ? 'New project' : words.join(' ');
  }

  Future<void> _submit(String text) async {
    final intent = text.trim();
    if (intent.length < 10 || _submitting) {
      if (intent.length < 10) {
        setState(
          () => _error = 'Tell Pandora a little more about what you want.',
        );
      }
      return;
    }
    final experience = PandoraDependencies.of(context)
        .projectExperienceRepository;
    if (experience == null) {
      setState(() => _error = 'Pandora cannot start a new project right now.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final project = await experience.createProject(
        name: _inferName(intent),
        buildKind: ProjectBuildKind.helpMeDecide,
        objective: intent,
        idempotencyKey: _keys.create('pandora-v2-project-create'),
      );
      final intentId = await experience.submitIntent(
        projectId: project.id,
        intentText: intent,
        intentKind: 'create',
        idempotencyKey: 'pandora-v2-initial-intent:${project.id}',
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ProjectUnderstandingScreen(
            project: project,
            sourceIntentId: intentId,
          ),
        ),
      );
    } on ProjectExperienceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on PandoraRepositoryException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Pandora could not start that project right now.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: PandoraV2Colors.canvas,
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PandoraV2ObjectHeader(
              title: 'Create',
              subtitle: 'Start with the outcome',
            ),
            const SizedBox(height: 44),
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
            const SizedBox(height: 14),
            const Text(
              'Describe the result in your own words. Pandora will choose the technical shape.',
              style: pandoraV2Muted,
            ),
            const SizedBox(height: 24),
            PandoraV2IntentSurface(
              controller: _intent,
              hintText: 'Describe anything…',
              autofocus: widget.initialIntent == null,
              enabled: !_submitting,
              onSubmit: _submit,
              onVoice: () async {
                final value = await PandoraNativeIo.dictate();
                if (value != null && mounted) _intent.text = value;
              },
              onAttachment: () async {
                final file = await PandoraNativeIo.pickTextAttachment();
                if (file != null && mounted) {
                  _intent.text = '${_intent.text.trim()}\n${file.promptBlock}'
                      .trim();
                }
              },
            ),
            if (_submitting) ...[
              const SizedBox(height: 18),
              const LinearProgressIndicator(
                minHeight: 2,
                color: PandoraV2Colors.ink,
                backgroundColor: PandoraV2Colors.soft,
              ),
              const SizedBox(height: 10),
              const Text(
                'Creating the project around your intent…',
                style: pandoraV2Muted,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 18),
              PandoraV2InlineMessage(
                title: 'Nothing has been published',
                message: _error!,
                actionLabel: 'Dismiss',
                onAction: () => setState(() => _error = null),
                danger: true,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class ProjectUnderstandingScreen extends StatefulWidget {
  const ProjectUnderstandingScreen({
    super.key,
    required this.project,
    required this.sourceIntentId,
  });

  final CustomerProject project;
  final String sourceIntentId;

  @override
  State<ProjectUnderstandingScreen> createState() =>
      _ProjectUnderstandingScreenState();
}

class _ProjectUnderstandingScreenState
    extends State<ProjectUnderstandingScreen> {
  OwnerProjectUnderstanding? _understanding;
  Timer? _timer;
  bool _building = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final api = PandoraDependencies.of(context).projectExperienceRepository;
    if (api == null) return;
    try {
      final value = await api.understanding(
        projectId: widget.project.id,
        expectedSourceIntentId: widget.sourceIntentId,
      );
      if (!mounted) return;
      setState(() {
        _understanding = value;
        _error = null;
      });
    } on ProjectExperienceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _build() async {
    if (_building) return;
    final api = PandoraDependencies.of(context).projectExperienceRepository;
    if (api == null) return;
    setState(() {
      _building = true;
      _error = null;
    });
    try {
      await api.requestBuild(
        projectId: widget.project.id,
        idempotencyKey: 'pandora-v2-build:${widget.project.id}',
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ProjectWorkspaceV2Screen(
            project: widget.project.copyWith(
              name: _understanding?.projectName ?? widget.project.name,
            ),
          ),
        ),
      );
    } on ProjectExperienceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _understanding;
    final ready = u?.isReady ?? false;
    final businessSummary = u?.businessSummary;
    final projectName = u?.projectName ?? 'Understanding your project…';
    final intentSummary = u?.intentSummary ?? businessSummary;
    final objectives = u?.objectives ?? const <String>[];
    final requirements = u?.requirements ?? const <String>[];
    final plan = <String>[
      if (objectives.isNotEmpty) objectives.first,
      ...requirements.take(4),
    ];
    return Scaffold(
      backgroundColor: PandoraV2Colors.canvas,
      body: SafeArea(
        child: PandoraV2Page(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PandoraV2ObjectHeader(title: projectName),
              const SizedBox(height: 30),
              if (!ready) ...[
                const Text(
                  'Turning your request into a clear build plan…',
                  style: TextStyle(color: PandoraV2Colors.muted, fontSize: 16),
                ),
                const SizedBox(height: 18),
                const PandoraV2Skeleton(height: 156),
              ] else ...[
                const Text(
                  'Here’s what Pandora will build.',
                  style: TextStyle(color: PandoraV2Colors.muted, fontSize: 16),
                ),
                const SizedBox(height: 10),
                if (intentSummary != null)
                  Text(
                    intentSummary,
                    style: const TextStyle(
                      color: PandoraV2Colors.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.45,
                      height: 1.14,
                    ),
                  ),
                const SizedBox(height: 24),
                if (plan.isNotEmpty)
                  PandoraV2InlineMessage(
                    title: 'Build plan',
                    message: plan.join('\n'),
                  ),
                const SizedBox(height: 28),
                PandoraV2PrimaryAction(
                  label: 'Build it',
                  loading: _building,
                  onPressed: _build,
                  icon: Icons.arrow_forward_rounded,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 18),
                PandoraV2InlineMessage(
                  title: 'Pandora is still holding your request',
                  message: _error!,
                  actionLabel: 'Try again',
                  onAction: _refresh,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
