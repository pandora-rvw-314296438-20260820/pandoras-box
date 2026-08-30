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
      candidate = candidate.split(RegExp(r'[,.;]|\bwhere\b|\bthat\b|\bwith\b', caseSensitive: false)).first.trim();
      final words = candidate.split(' ').where((word) => word.isNotEmpty).take(5).toList();
      if (words.isNotEmpty) return words.join(' ');
    }
    var candidate = plain.replaceFirst(
      RegExp(r'^(please\s+)?(build|create|make|design|develop)\s+(me\s+)?', caseSensitive: false),
      '',
    );
    candidate = candidate.split(RegExp(r'[,.;]')).first.trim();
    final words = candidate.split(' ').where((word) => word.isNotEmpty).take(5).toList();
    return words.isEmpty ? 'New project' : words.join(' ');
  }

  Future<void> _submit(String text) async {
    final intent = text.trim();
    if (intent.length < 10 || _submitting) {
      if (intent.length < 10) {
        setState(() => _error = 'Tell Pandora a little more about what you want.');
      }
      return;
    }
    final dependencies = PandoraDependencies.of(context);
    final runtime = dependencies.projectRuntime;
    final experience = dependencies.projectExperience;
    if (runtime == null || experience == null) {
      setState(() => _error = 'Pandora cannot start a new project right now.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final project = await runtime.createProject(
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
            intentText: intent,
            sourceIntentId: intentId,
          ),
        ),
      );
    } on ProjectExperienceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on PandoraRepositoryException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Pandora could not start that project right now.');
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
                PandoraV2ObjectHeader(title: 'Create', subtitle: 'Start with the outcome'),
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
                      _intent.text = '${_intent.text.trim()}\n${file.promptBlock}'.trim();
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
                  const Text('Creating the project around your intent…', style: pandoraV2Muted),
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
    required this.intentText,
    required this.sourceIntentId,
  });

  final CustomerProject project;
  final String intentText;
  final String sourceIntentId;

  @override
  State<ProjectUnderstandingScreen> createState() => _ProjectUnderstandingScreenState();
}

class _ProjectUnderstandingScreenState extends State<ProjectUnderstandingScreen> {
  Timer? _timer;
  OwnerProjectUnderstanding _understanding = const OwnerProjectUnderstanding.waiting();
  late String _sourceIntentId;
  late String _intentText;
  bool _started = false;
  bool _refreshing = false;
  bool _building = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sourceIntentId = widget.sourceIntentId;
    _intentText = widget.intentText;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    final experience = PandoraDependencies.of(context).projectExperience;
    if (experience == null) return;
    _refreshing = true;
    try {
      final value = await experience.understanding(
        projectId: widget.project.id,
        expectedSourceIntentId: _sourceIntentId,
      );
      if (!mounted) return;
      setState(() {
        _understanding = value;
        _error = value.state == OwnerProjectUnderstandingState.rejected
            ? 'Pandora needs a clearer request before it can build this safely.'
            : null;
      });
      if (!value.isReady && value.state != OwnerProjectUnderstandingState.rejected) {
        _timer?.cancel();
        _timer = Timer(const Duration(seconds: 2), _refresh);
      }
    } on ProjectExperienceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _changeRequest() async {
    final controller = TextEditingController(text: _intentText);
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PandoraV2Colors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Change your request', style: TextStyle(color: PandoraV2Colors.ink, fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 18),
            TextField(controller: controller, minLines: 4, maxLines: 9, autofocus: true),
            const SizedBox(height: 16),
            PandoraV2PrimaryAction(
              label: 'Update',
              onPressed: () => Navigator.of(sheetContext).pop(controller.text.trim()),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (value == null || value.length < 10 || !mounted) return;
    final experience = PandoraDependencies.of(context).projectExperience;
    if (experience == null) return;
    try {
      final intentId = await experience.submitIntent(
        projectId: widget.project.id,
        intentText: value,
        intentKind: 'create',
        idempotencyKey: 'pandora-v2-reframe:${widget.project.id}:${DateTime.now().microsecondsSinceEpoch}',
      );
      if (!mounted) return;
      setState(() {
        _sourceIntentId = intentId;
        _intentText = value;
        _understanding = const OwnerProjectUnderstanding.waiting();
        _error = null;
      });
      unawaited(_refresh());
    } on ProjectExperienceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _startBuild() async {
    if (_building || !_understanding.isReady) return;
    setState(() => _building = true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ProjectBuildExperienceV2Screen(project: widget.project),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _understanding.isReady;
    final summary = _understanding.businessSummary?.trim();
    final goal = _understanding.objectives.isNotEmpty
        ? _understanding.objectives.first
        : widget.project.objective;
    return Scaffold(
      backgroundColor: PandoraV2Colors.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PandoraV2ObjectHeader(title: widget.project.name, subtitle: ready ? 'Understood' : 'Understanding your idea'),
              const SizedBox(height: 34),
              if (!ready) ...[
                const Text(
                  'Pandora is turning your intent into a clear working plan.',
                  style: TextStyle(color: PandoraV2Colors.ink, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -.8, height: 1.08),
                ),
                const SizedBox(height: 18),
                Text(_intentText, style: pandoraV2Body),
                const Spacer(),
                if (_error == null)
                  const LinearProgressIndicator(minHeight: 2, color: PandoraV2Colors.ink, backgroundColor: PandoraV2Colors.soft),
              ] else ...[
                const Text(
                  'Here is what Pandora will make.',
                  style: TextStyle(color: PandoraV2Colors.ink, fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -.9, height: 1.06),
                ),
                if (summary != null && summary.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(summary, style: const TextStyle(color: PandoraV2Colors.ink, fontSize: 17, height: 1.42)),
                ],
                const SizedBox(height: 28),
                const Text('Goal', style: TextStyle(color: PandoraV2Colors.muted, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(goal, style: pandoraV2Body),
                if (_understanding.requirements.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  const Text('First version', style: TextStyle(color: PandoraV2Colors.muted, fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final item in _understanding.requirements.take(4))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Padding(padding: EdgeInsets.only(top: 7), child: SizedBox.square(dimension: 5, child: DecoratedBox(decoration: BoxDecoration(color: PandoraV2Colors.ink, shape: BoxShape.circle)))),
                        const SizedBox(width: 10),
                        Expanded(child: Text(item, style: pandoraV2Body)),
                      ]),
                    ),
                ],
                const Spacer(),
                TextButton(onPressed: _changeRequest, style: TextButton.styleFrom(foregroundColor: PandoraV2Colors.ink), child: const Text('Change request')),
                const SizedBox(height: 6),
                PandoraV2PrimaryAction(label: 'Create first version', loading: _building, onPressed: _startBuild),
              ],
              if (_error != null) ...[
                const SizedBox(height: 18),
                PandoraV2InlineMessage(title: 'Your project has not changed', message: _error!, actionLabel: 'Try again', onAction: _refresh, danger: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
