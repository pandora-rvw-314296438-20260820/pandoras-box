import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/data/project_experience_api.dart';
import '../../core/models/project_journey_models.dart';
import '../../core/network/idempotency_key.dart';
import '../approvals/approvals_screen.dart';
import '../settings/settings_screen.dart';
import 'pandora_simple_ui.dart';
import 'project_journey_flow.dart';

void _openOwnerSurface(BuildContext context, Widget screen) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}

class CreateProjectExperienceScreen extends StatefulWidget {
  const CreateProjectExperienceScreen({super.key});

  @override
  State<CreateProjectExperienceScreen> createState() =>
      _CreateProjectExperienceScreenState();
}

class _CreateProjectExperienceScreenState
    extends State<CreateProjectExperienceScreen> {
  final _name = TextEditingController();
  final _intent = TextEditingController();
  final _keys = IdempotencyKeyFactory();
  ProjectBuildKind _kind = ProjectBuildKind.helpMeDecide;
  CustomerProject? _createdProject;
  String? _initialIntentId;
  String? _createIdempotencyKey;
  String? _intentIdempotencyKey;
  String? _error;
  var _step = 0;
  var _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _intent.dispose();
    super.dispose();
  }

  void _back() {
    if (_submitting) return;
    if (_step == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _error = null;
      _step -= 1;
    });
  }

  void _continueFromName() {
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Give this project a short name.');
      return;
    }
    setState(() {
      _error = null;
      _step = 1;
    });
  }

  void _continueFromKind() {
    setState(() {
      _error = null;
      _step = 2;
    });
  }

  Future<void> _createAndUnderstand() async {
    final name = _name.text.trim();
    final intent = _intent.text.trim();
    if (intent.length < 10) {
      setState(
        () => _error = 'Tell Pandora a little more about what you want.',
      );
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
      var project = _createdProject;
      if (project == null) {
        _createIdempotencyKey ??= _keys.create('customer-project-create');
        project = await runtime.createProject(
          name: name,
          buildKind: _kind,
          objective: intent,
          idempotencyKey: _createIdempotencyKey,
        );
        _createdProject = project;
      }

      _intentIdempotencyKey ??= 'project-initial-intent:${project.id}';
      final intentId =
          _initialIntentId ??
          await experience.submitIntent(
            projectId: project.id,
            intentText: intent,
            intentKind: 'create',
            idempotencyKey: _intentIdempotencyKey,
          );
      _initialIntentId = intentId;
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ProjectUnderstandingScreen(
            project: project!,
            intentText: intent,
            sourceIntentId: intentId,
          ),
        ),
      );
    } on ProjectExperienceException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } on PandoraRepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'Pandora could not start that project right now.',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_step) {
      0 => 'Name your project',
      1 => 'What do you want to build?',
      _ => 'Describe what you want',
    };
    final subtitle = switch (_step) {
      0 => 'Start with a name you will recognize.',
      1 => 'Choose the closest starting point. Pandora handles the technology.',
      _ => 'Tell Pandora the result you want in your own words.',
    };

    return PandoraSimplePage(
      header: PandoraOwnerHeader(
        title: 'New Project',
        subtitle: 'Step ${_step + 1} of 3',
        centerBrand: true,
        showBack: true,
        onBack: _back,
        onNotifications: () =>
            _openOwnerSurface(context, const ApprovalsScreen()),
        onAvatar: () => _openOwnerSurface(context, const SettingsScreen()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: PandoraSimpleColors.ink,
              fontSize: 29,
              fontWeight: FontWeight.w700,
              letterSpacing: -.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: pandoraSimpleMutedText),
          const SizedBox(height: 24),
          if (_step == 0) _nameStep(),
          if (_step == 1) _kindStep(),
          if (_step == 2) _intentStep(),
          if (_error != null) ...[
            const SizedBox(height: 16),
            PandoraSimpleCard(
              shadow: false,
              backgroundColor: const Color(0xFFFFF4F5),
              borderColor: const Color(0xFFF0C3CA),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: PandoraSimpleColors.deepRed,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _nameStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _name,
        autofocus: true,
        textInputAction: TextInputAction.done,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (_) => _continueFromName(),
        decoration: const InputDecoration(
          labelText: 'Project name',
          hintText: 'BOK Direct Ordering',
        ),
      ),
      const SizedBox(height: 22),
      PandoraPrimaryButton(
        label: 'Continue',
        icon: Icons.arrow_forward_rounded,
        onPressed: _continueFromName,
        expanded: true,
      ),
    ],
  );

  Widget _kindStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final kind in ProjectBuildKind.values) ...[
        PandoraSimpleCard(
          shadow: false,
          onTap: _submitting
              ? null
              : () => setState(() {
                  _kind = kind;
                  _error = null;
                }),
          borderColor: _kind == kind
              ? PandoraSimpleColors.red
              : PandoraSimpleColors.line,
          backgroundColor: _kind == kind
              ? PandoraSimpleColors.blush
              : PandoraSimpleColors.surface,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kind.label,
                      style: const TextStyle(
                        color: PandoraSimpleColors.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(kind.description, style: pandoraSimpleMutedText),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                _kind == kind
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: _kind == kind
                    ? PandoraSimpleColors.red
                    : PandoraSimpleColors.muted,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 12),
      PandoraPrimaryButton(
        label: 'Continue',
        icon: Icons.arrow_forward_rounded,
        onPressed: _continueFromKind,
        expanded: true,
      ),
    ],
  );

  Widget _intentStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const PandoraSimpleCard(
        shadow: false,
        backgroundColor: Color(0xFFFFFAFA),
        borderColor: Color(0xFFF0D1D6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PandoraIconBadge(icon: Icons.auto_awesome_rounded, size: 46),
            SizedBox(width: 13),
            Expanded(
              child: Text(
                'What do you want Pandora to build?',
                style: TextStyle(
                  color: PandoraSimpleColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _intent,
        minLines: 5,
        maxLines: 12,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Build a premium resort booking website where guests can explore rooms, check availability and book directly.',
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        'Describe the business result and the experience you want. Pandora will work out the technical details.',
        style: pandoraSimpleMutedText,
      ),
      const SizedBox(height: 22),
      PandoraPrimaryButton(
        label: _submitting ? 'Creating project…' : 'Continue',
        icon: Icons.arrow_forward_rounded,
        loading: _submitting,
        onPressed: _submitting ? null : _createAndUnderstand,
        expanded: true,
      ),
    ],
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
  State<ProjectUnderstandingScreen> createState() =>
      _ProjectUnderstandingScreenState();
}

class _ProjectUnderstandingScreenState extends State<ProjectUnderstandingScreen>
    with WidgetsBindingObserver {
  final _keys = IdempotencyKeyFactory();
  Timer? _refreshTimer;
  OwnerProjectUnderstanding _understanding =
      const OwnerProjectUnderstanding.waiting();
  late String _intentText;
  late String _sourceIntentId;
  String? _pendingChangeKey;
  String? _pendingChangeText;
  String? _error;
  var _started = false;
  var _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _intentText = widget.intentText;
    _sourceIntentId = widget.sourceIntentId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_refresh());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_refresh()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing || _understanding.isReady) return;
    final experience = PandoraDependencies.of(context).projectExperience;
    if (experience == null) {
      if (mounted) {
        setState(
          () => _error = 'Pandora cannot refresh this project right now.',
        );
      }
      return;
    }
    _refreshing = true;
    try {
      final result = await experience.understanding(
        projectId: widget.project.id,
        expectedSourceIntentId: _sourceIntentId,
      );
      if (!mounted) return;
      setState(() {
        _understanding = result;
        _error = null;
      });
      if (result.isReady) _refreshTimer?.cancel();
    } on ProjectExperienceException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _changeSomething() async {
    final controller = TextEditingController(text: _intentText);
    final nextText = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: PandoraSimpleColors.surface,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          6,
          22,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Change what Pandora understood',
              style: TextStyle(
                color: PandoraSimpleColors.ink,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Describe the result again in your own words.',
              style: pandoraSimpleMutedText,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              minLines: 4,
              maxLines: 10,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 18),
            PandoraPrimaryButton(
              label: 'Update request',
              icon: Icons.check_rounded,
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              expanded: true,
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (nextText == null || nextText.length < 10 || !mounted) return;

    final experience = PandoraDependencies.of(context).projectExperience;
    if (experience == null) return;
    if (_pendingChangeText != nextText) {
      _pendingChangeText = nextText;
      _pendingChangeKey = _keys.create('project-change-intent');
    }
    setState(() => _error = null);
    try {
      final intentId = await experience.submitIntent(
        projectId: widget.project.id,
        intentText: nextText,
        intentKind: 'change',
        idempotencyKey: _pendingChangeKey,
      );
      if (!mounted) return;
      setState(() {
        _intentText = nextText;
        _sourceIntentId = intentId;
        _understanding = const OwnerProjectUnderstanding.waiting();
        _pendingChangeKey = null;
        _pendingChangeText = null;
      });
      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => unawaited(_refresh()),
      );
      unawaited(_refresh());
    } on ProjectExperienceException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    }
  }

  void _buildIt() {
    if (!_understanding.isReady) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ProjectBuildTheatreScreen(project: widget.project),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _understanding.isReady;
    final rejected =
        _understanding.state == OwnerProjectUnderstandingState.rejected;
    return PandoraSimplePage(
      header: PandoraOwnerHeader(
        title: ready ? 'Pandora understands' : 'Understanding your project',
        subtitle: widget.project.name,
        centerBrand: true,
        showBack: true,
        onBack: () => Navigator.of(context).maybePop(),
        onNotifications: () =>
            _openOwnerSurface(context, const ApprovalsScreen()),
        onAvatar: () => _openOwnerSurface(context, const SettingsScreen()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!ready) ...[
            const Center(
              child: PandoraIconBadge(
                icon: Icons.auto_awesome_rounded,
                size: 66,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              rejected
                  ? 'Pandora needs a clearer direction'
                  : 'Pandora is understanding your project',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: PandoraSimpleColors.ink,
                fontSize: 27,
                fontWeight: FontWeight.w700,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              rejected
                  ? 'Change the request and Pandora will prepare a new understanding.'
                  : 'Pandora is turning your request into a clear project plan. You can leave and come back without losing it.',
              textAlign: TextAlign.center,
              style: pandoraSimpleMutedText,
            ),
            const SizedBox(height: 22),
            PandoraSimpleCard(
              shadow: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'You asked Pandora to',
                    style: TextStyle(
                      color: PandoraSimpleColors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _intentText,
                    style: const TextStyle(
                      color: PandoraSimpleColors.ink,
                      fontSize: 16,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: PandoraSimpleColors.deepRed),
              ),
            ],
            const SizedBox(height: 20),
            PandoraPrimaryButton(
              label: _refreshing ? 'Checking…' : 'Check again',
              icon: Icons.refresh_rounded,
              loading: _refreshing,
              onPressed: _refreshing ? null : _refresh,
              expanded: true,
            ),
            const SizedBox(height: 10),
            PandoraSecondaryButton(
              label: 'Change something',
              icon: Icons.edit_outlined,
              onPressed: _changeSomething,
              expanded: true,
            ),
          ],
          if (ready) ...[
            const PandoraStatusPill(
              label: 'Ready to build',
              icon: Icons.check_rounded,
              foreground: PandoraSimpleColors.green,
              background: PandoraSimpleColors.greenWash,
            ),
            const SizedBox(height: 16),
            const Text(
              'Here’s what I understood',
              style: TextStyle(
                color: PandoraSimpleColors.ink,
                fontSize: 29,
                fontWeight: FontWeight.w700,
                letterSpacing: -.6,
              ),
            ),
            const SizedBox(height: 18),
            PandoraSimpleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _understanding.projectType ??
                        widget.project.buildKind.label,
                    style: const TextStyle(
                      color: PandoraSimpleColors.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (_understanding.businessSummary != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _understanding.businessSummary!,
                      style: pandoraSimpleMutedText,
                    ),
                  ],
                  if (_understanding.targetUsers != null) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'For',
                      style: TextStyle(
                        color: PandoraSimpleColors.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _understanding.targetUsers!,
                      style: const TextStyle(
                        color: PandoraSimpleColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_understanding.requirements.isNotEmpty) ...[
              const SizedBox(height: 20),
              const PandoraSectionTitle(title: 'This project will include'),
              PandoraSimpleCard(
                shadow: false,
                child: Column(
                  children: [
                    for (final item in _understanding.requirements.take(6))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.check_rounded,
                              size: 19,
                              color: PandoraSimpleColors.green,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                item,
                                style: const TextStyle(
                                  color: PandoraSimpleColors.ink,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (_understanding.objectives.isNotEmpty) ...[
              const SizedBox(height: 20),
              const PandoraSectionTitle(title: 'Goal'),
              PandoraSimpleCard(
                shadow: false,
                child: Text(
                  _understanding.objectives.first,
                  style: const TextStyle(
                    color: PandoraSimpleColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            PandoraPrimaryButton(
              label: 'Build it',
              icon: Icons.auto_awesome_rounded,
              onPressed: _buildIt,
              expanded: true,
            ),
            const SizedBox(height: 10),
            PandoraSecondaryButton(
              label: 'Change something',
              icon: Icons.edit_outlined,
              onPressed: _changeSomething,
              expanded: true,
            ),
          ],
        ],
      ),
    );
  }
}
