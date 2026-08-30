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
import 'project_conversation_screen.dart';
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
          builder: (_) => ProjectConversationScreen(
            project: project!,
            initialIntentText: intent,
            initialSourceIntentId: intentId,
            onBuildConfirmed: (conversationContext) {
              Navigator.of(conversationContext).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => ProjectBuildTheatreScreen(project: project!),
                ),
              );
            },
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
