import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/models/pandora_models.dart';
import '../../core/models/project_journey_models.dart';
import '../../core/platform/pandora_native_io.dart';
import '../../core/widgets/pandora_mark.dart';
import '../approvals/approvals_screen.dart';
import '../settings/settings_screen.dart';
import 'pandora_simple_ui.dart';

void _openJourney(BuildContext context, Widget screen) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}

Future<void> _launchProjectUrl(BuildContext context, String? value) async {
  final text = value?.trim() ?? '';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.scheme != 'https') {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That project link is not available yet.'),
        ),
      );
    }
    return;
  }
  final opened = await PandoraNativeIo.openExternalUrl(uri.toString());
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pandora could not open that link.')),
    );
  }
}

class CreateProjectFlowScreen extends StatefulWidget {
  const CreateProjectFlowScreen({super.key});

  @override
  State<CreateProjectFlowScreen> createState() =>
      _CreateProjectFlowScreenState();
}

class _CreateProjectFlowScreenState extends State<CreateProjectFlowScreen> {
  final _name = TextEditingController();
  final _objective = TextEditingController();
  ProjectBuildKind _kind = ProjectBuildKind.helpMeDecide;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _objective.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    final objective = _objective.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Give this project a short name.');
      return;
    }
    if (objective.length < 10) {
      setState(
        () => _error = 'Tell Pandora a little more about the result you want.',
      );
      return;
    }
    final runtime = PandoraDependencies.of(context).projectRuntime;
    if (runtime == null) {
      setState(
        () =>
            _error = 'Project building is not available in this app build yet.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final project = await runtime.createProject(
        name: name,
        buildKind: _kind,
        objective: objective,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ProjectBuildTheatreScreen(project: project),
        ),
      );
    } on PandoraRepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Pandora could not create that project yet.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => PandoraSimplePage(
    header: PandoraOwnerHeader(
      title: 'New Project',
      subtitle: 'Tell Pandora what you want to create.',
      centerBrand: true,
      showBack: true,
      onBack: () => Navigator.of(context).maybePop(),
      onNotifications: () => _openJourney(context, const ApprovalsScreen()),
      onAvatar: () => _openJourney(context, const SettingsScreen()),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'What are we building?',
          style: TextStyle(
            color: PandoraSimpleColors.ink,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -.6,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose a starting point. Pandora can change the shape later as it learns more.',
          style: pandoraSimpleMutedText,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Project name',
            hintText: 'PLP Boracay',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _objective,
          minLines: 4,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What should this accomplish?',
            hintText: 'Build a premium resort website where guests can explore rooms, check availability and make reservations.',
          ),
        ),
        const SizedBox(height: 22),
        const PandoraSectionTitle(title: 'Starting shape'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final kind in ProjectBuildKind.values)
              ChoiceChip(
                label: Text(kind.label),
                selected: _kind == kind,
                onSelected: _submitting
                    ? null
                    : (_) => setState(() => _kind = kind),
                selectedColor: PandoraSimpleColors.blush,
                side: BorderSide(
                  color: _kind == kind
                      ? PandoraSimpleColors.red
                      : PandoraSimpleColors.line,
                ),
                labelStyle: TextStyle(
                  color: _kind == kind
                      ? PandoraSimpleColors.deepRed
                      : PandoraSimpleColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(_kind.description, style: pandoraSimpleMutedText),
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
        const SizedBox(height: 24),
        PandoraPrimaryButton(
          label: _submitting ? 'Creating project…' : 'Start building',
          icon: Icons.auto_awesome_rounded,
          loading: _submitting,
          onPressed: _submitting ? null : _create,
          expanded: true,
        ),
      ],
    ),
  );
}

class ProjectBuildTheatreScreen extends StatefulWidget {
  const ProjectBuildTheatreScreen({
    super.key,
    required this.project,
    this.popWhenDone = false,
  });

  final CustomerProject project;
  final bool popWhenDone;

  @override
  State<ProjectBuildTheatreScreen> createState() =>
      _ProjectBuildTheatreScreenState();
}

class _ProjectBuildTheatreScreenState extends State<ProjectBuildTheatreScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _orbit;
  Timer? _stageTimer;
  bool _started = false;
  int _stage = 0;
  ProjectPreviewResult? _result;
  String? _error;

  static const _steps = <String>[
    'Understanding your idea',
    'Designing the experience',
    'Building your project',
    'Connecting the runtime',
    'Checking the result',
    'Preparing your live preview',
  ];

  @override
  void initState() {
    super.initState();
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _stageTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (!mounted || _result != null || _error != null) return;
      if (_stage < _steps.length - 1) setState(() => _stage += 1);
    });
    unawaited(_buildPreview());
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    _orbit.dispose();
    super.dispose();
  }

  Future<void> _buildPreview() async {
    final runtime = PandoraDependencies.of(context).projectRuntime;
    if (runtime == null) {
      setState(
        () =>
            _error = 'Project building is not available in this app build yet.',
      );
      return;
    }
    try {
      final result = await runtime.createPreview(projectId: widget.project.id);
      if (!mounted) return;
      _stageTimer?.cancel();
      setState(() {
        _stage = _steps.length;
        _result = result;
      });
    } on PandoraRepositoryException catch (error) {
      if (!mounted) return;
      _stageTimer?.cancel();
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      _stageTimer?.cancel();
      setState(() => _error = 'Pandora could not finish this preview yet.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _result?.previewUrl != null;
    return PandoraSimplePage(
      header: PandoraOwnerHeader(
        title: ready ? 'Preview ready' : 'Pandora is building',
        subtitle: widget.project.name,
        centerBrand: true,
        showBack: true,
        onBack: () => Navigator.of(context).maybePop(),
        onNotifications: () => _openJourney(context, const ApprovalsScreen()),
        onAvatar: () => _openJourney(context, const SettingsScreen()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!ready && _error == null) ...[
            const Text(
              'Watch your project take shape',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: PandoraSimpleColors.ink,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -.6,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pandora is turning your intent into the first working experience.',
              textAlign: TextAlign.center,
              style: pandoraSimpleMutedText,
            ),
            const SizedBox(height: 28),
            _TheatreMark(controller: _orbit),
            const SizedBox(height: 26),
            PandoraSimpleCard(
              shadow: false,
              child: Column(
                children: [
                  for (var index = 0; index < _steps.length; index++)
                    _BuildStageRow(
                      label: _steps[index],
                      state: index < _stage
                          ? _StageState.complete
                          : index == _stage
                          ? _StageState.current
                          : _StageState.pending,
                      last: index == _steps.length - 1,
                    ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            PandoraSimpleCard(
              backgroundColor: const Color(0xFFFFF4F5),
              borderColor: const Color(0xFFF0C3CA),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PandoraIconBadge(icon: Icons.warning_amber_rounded),
                  const SizedBox(height: 12),
                  const Text(
                    'The preview needs another try',
                    style: TextStyle(
                      color: PandoraSimpleColors.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(_error!, style: pandoraSimpleMutedText),
                  const SizedBox(height: 16),
                  PandoraPrimaryButton(
                    label: 'Try again',
                    icon: Icons.refresh_rounded,
                    onPressed: () {
                      setState(() {
                        _error = null;
                        _stage = 0;
                      });
                      _stageTimer?.cancel();
                      _stageTimer = Timer.periodic(
                        const Duration(milliseconds: 1200),
                        (_) {
                          if (!mounted || _result != null || _error != null)
                            return;
                          if (_stage < _steps.length - 1) {
                            setState(() => _stage += 1);
                          }
                        },
                      );
                      unawaited(_buildPreview());
                    },
                  ),
                ],
              ),
            ),
          ],
          if (ready) ...[
            const PandoraStatusPill(
              label: 'Live preview',
              icon: Icons.visibility_outlined,
              foreground: PandoraSimpleColors.green,
              background: PandoraSimpleColors.greenWash,
            ),
            const SizedBox(height: 14),
            const Text(
              'Your first preview is ready',
              style: TextStyle(
                color: PandoraSimpleColors.ink,
                fontSize: 29,
                fontWeight: FontWeight.w700,
                letterSpacing: -.6,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This is a real preview deployment. Keep changing it until it feels right, then publish that exact version.',
              style: pandoraSimpleMutedText,
            ),
            const SizedBox(height: 20),
            PandoraSimpleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PandoraIconBadge(
                    icon: Icons.public_rounded,
                    foreground: PandoraSimpleColors.blue,
                    background: PandoraSimpleColors.blueWash,
                    size: 52,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _result!.previewUrl!,
                    style: const TextStyle(
                      color: PandoraSimpleColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  PandoraPrimaryButton(
                    label: 'Open Preview',
                    icon: Icons.open_in_new_rounded,
                    onPressed: () =>
                        _launchProjectUrl(context, _result!.previewUrl),
                    expanded: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            PandoraSecondaryButton(
              label: 'Open project workspace',
              icon: Icons.dashboard_customize_outlined,
              onPressed: () {
                if (widget.popWhenDone) {
                  Navigator.of(context).pop();
                  return;
                }
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => ProjectJourneyWorkspaceScreen(
                      projectIdentifier: widget.project.id,
                    ),
                  ),
                );
              },
              expanded: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _TheatreMark extends StatelessWidget {
  const _TheatreMark({required this.controller});
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    final frozen = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      height: 270,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (final size in <double>[250, 205, 162])
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: PandoraSimpleColors.red.withValues(alpha: .11),
                ),
              ),
            ),
          Container(
            width: 172,
            height: 172,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  PandoraSimpleColors.red.withValues(alpha: .2),
                  Colors.transparent,
                ],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x35D40A24),
                  blurRadius: 58,
                  spreadRadius: 8,
                ),
              ],
            ),
          ),
          const PandoraMark(size: 132, color: PandoraSimpleColors.red),
          for (final item in <(double, double, Color)>[
            (0, 108, PandoraSimpleColors.purple),
            (.34, 108, PandoraSimpleColors.green),
            (.67, 108, PandoraSimpleColors.red),
          ])
            AnimatedBuilder(
              animation: controller,
              builder: (context, child) => Transform.rotate(
                angle:
                    (frozen ? item.$1 : controller.value + item.$1) *
                    6.283185307179586,
                child: Transform.translate(
                  offset: Offset(item.$2, 0),
                  child: child,
                ),
              ),
              child: Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  color: item.$3,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [
                    BoxShadow(color: Color(0x26000000), blurRadius: 8),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _StageState { complete, current, pending }

class _BuildStageRow extends StatelessWidget {
  const _BuildStageRow({
    required this.label,
    required this.state,
    required this.last,
  });

  final String label;
  final _StageState state;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _StageState.complete => PandoraSimpleColors.green,
      _StageState.current => PandoraSimpleColors.red,
      _StageState.pending => const Color(0xFFC3C1BD),
    };
    final icon = switch (state) {
      _StageState.complete => Icons.check_rounded,
      _StageState.current => Icons.auto_awesome_rounded,
      _StageState.pending => Icons.circle_outlined,
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 16),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: color.withValues(alpha: .24),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 19),
              child: Text(
                label,
                style: TextStyle(
                  color: state == _StageState.pending
                      ? PandoraSimpleColors.muted
                      : PandoraSimpleColors.ink,
                  fontSize: 15.5,
                  fontWeight: state == _StageState.current
                      ? FontWeight.w700
                      : FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProjectJourneyWorkspaceScreen extends StatefulWidget {
  const ProjectJourneyWorkspaceScreen({
    super.key,
    required this.projectIdentifier,
    this.fallback,
  });

  final String projectIdentifier;
  final ProjectSummary? fallback;

  @override
  State<ProjectJourneyWorkspaceScreen> createState() =>
      _ProjectJourneyWorkspaceScreenState();
}

class _ProjectJourneyWorkspaceScreenState
    extends State<ProjectJourneyWorkspaceScreen> {
  ProjectRuntimeSnapshot? _snapshot;
  bool _loading = true;
  bool _publishing = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading && _snapshot == null) unawaited(_load());
  }

  Future<void> _load() async {
    final runtime = PandoraDependencies.of(context).projectRuntime;
    if (runtime == null) {
      setState(() {
        _loading = false;
        _error = 'Project runtime is not available in this build.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await runtime.runtime(widget.projectIdentifier);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
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
        _error = 'Pandora could not load this project workspace.';
      });
    }
  }

  Future<void> _buildAgain() async {
    final project = _snapshot?.project;
    if (project == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ProjectBuildTheatreScreen(project: project, popWhenDone: true),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _publish() async {
    final project = _snapshot?.project;
    if (project == null) return;
    final controller = TextEditingController(
      text: project.requestedDomain ?? '',
    );
    final domain = await showModalBottomSheet<String?>(
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
              'Publish this preview',
              style: TextStyle(
                color: PandoraSimpleColors.ink,
                fontSize: 23,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pandora will publish the exact preview version you reviewed. A custom domain is optional.',
              style: pandoraSimpleMutedText,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Custom domain (optional)',
                hintText: 'www.mybusiness.com',
              ),
            ),
            const SizedBox(height: 18),
            PandoraPrimaryButton(
              label: 'Publish',
              icon: Icons.rocket_launch_outlined,
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              expanded: true,
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (domain == null || !mounted) return;
    final runtime = PandoraDependencies.of(context).projectRuntime;
    if (runtime == null) return;
    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      await runtime.publish(
        projectId: project.id,
        versionId: _snapshot?.preview?.versionId,
        domain: domain.isEmpty ? null : domain,
      );
      if (mounted) await _load();
    } on PandoraRepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Pandora could not publish that project yet.');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = _snapshot?.project;
    final title = project?.name ?? widget.fallback?.name ?? 'Project';
    return PandoraSimplePage(
      onRefresh: _load,
      header: PandoraOwnerHeader(
        title: title,
        subtitle: project?.isLive == true
            ? 'Live project'
            : 'Project workspace',
        centerBrand: true,
        showBack: true,
        onBack: () => Navigator.of(context).maybePop(),
        onNotifications: () => _openJourney(context, const ApprovalsScreen()),
        onAvatar: () => _openJourney(context, const SettingsScreen()),
      ),
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 64),
              child: Center(
                child: CircularProgressIndicator(
                  color: PandoraSimpleColors.red,
                ),
              ),
            )
          : _snapshot == null
          ? PandoraSimpleCard(
              shadow: false,
              backgroundColor: const Color(0xFFFFF4F5),
              borderColor: const Color(0xFFF0C3CA),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _error ?? 'Project details are unavailable.',
                    style: const TextStyle(color: PandoraSimpleColors.deepRed),
                  ),
                  const SizedBox(height: 14),
                  PandoraSecondaryButton(
                    label: 'Try again',
                    icon: Icons.refresh_rounded,
                    onPressed: _load,
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    PandoraStatusPill(
                      label: project!.isLive
                          ? 'Live'
                          : project.hasPreview
                          ? 'Preview ready'
                          : 'Working',
                      icon: project.isLive
                          ? Icons.public_rounded
                          : project.hasPreview
                          ? Icons.visibility_outlined
                          : Icons.auto_awesome_rounded,
                      foreground: project.isLive
                          ? PandoraSimpleColors.green
                          : PandoraSimpleColors.blue,
                      background: project.isLive
                          ? PandoraSimpleColors.greenWash
                          : PandoraSimpleColors.blueWash,
                    ),
                    const Spacer(),
                    Text(
                      project.buildKind.label,
                      style: pandoraSimpleMutedText,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                PandoraSimpleCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'What this project should accomplish',
                        style: TextStyle(
                          color: PandoraSimpleColors.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(project.objective, style: pandoraSimpleMutedText),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_snapshot!.preview != null)
                  _ProjectLinkCard(
                    title: 'Current preview',
                    url: _snapshot!.preview!.url,
                    status: _snapshot!.preview!.status,
                    icon: Icons.visibility_outlined,
                    onOpen: () =>
                        _launchProjectUrl(context, _snapshot!.preview!.url),
                  ),
                if (_snapshot!.production != null) ...[
                  if (_snapshot!.preview != null) const SizedBox(height: 12),
                  _ProjectLinkCard(
                    title: 'Live version',
                    url: project.liveUrl ?? _snapshot!.production!.url,
                    status: _snapshot!.production!.status,
                    icon: Icons.public_rounded,
                    onOpen: () => _launchProjectUrl(
                      context,
                      project.liveUrl ?? _snapshot!.production!.url,
                    ),
                  ),
                ],
                if (_snapshot!.domain != null) ...[
                  const SizedBox(height: 12),
                  PandoraSimpleCard(
                    shadow: false,
                    child: Row(
                      children: [
                        PandoraIconBadge(
                          icon: Icons.language_rounded,
                          foreground: _snapshot!.domain!.verified
                              ? PandoraSimpleColors.green
                              : PandoraSimpleColors.amber,
                          background: _snapshot!.domain!.verified
                              ? PandoraSimpleColors.greenWash
                              : PandoraSimpleColors.amberWash,
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _snapshot!.domain!.domain,
                                style: const TextStyle(
                                  color: PandoraSimpleColors.ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _snapshot!.domain!.verified
                                    ? 'Domain connected'
                                    : 'Domain verification required',
                                style: pandoraSimpleMutedText,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  PandoraSimpleCard(
                    shadow: false,
                    backgroundColor: const Color(0xFFFFF4F5),
                    borderColor: const Color(0xFFF0C3CA),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: PandoraSimpleColors.deepRed,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                PandoraPrimaryButton(
                  label: project.hasPreview
                      ? 'Build a new preview'
                      : 'Build preview',
                  icon: Icons.auto_awesome_rounded,
                  onPressed: _publishing ? null : _buildAgain,
                  expanded: true,
                ),
                if (project.hasPreview) ...[
                  const SizedBox(height: 10),
                  PandoraSecondaryButton(
                    label: _publishing ? 'Publishing…' : 'Publish',
                    icon: Icons.rocket_launch_outlined,
                    onPressed: _publishing ? null : _publish,
                    expanded: true,
                  ),
                ],
              ],
            ),
    );
  }
}

class _ProjectLinkCard extends StatelessWidget {
  const _ProjectLinkCard({
    required this.title,
    required this.url,
    required this.status,
    required this.icon,
    required this.onOpen,
  });

  final String title;
  final String? url;
  final String status;
  final IconData icon;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => PandoraSimpleCard(
    child: Row(
      children: [
        PandoraIconBadge(
          icon: icon,
          foreground: PandoraSimpleColors.blue,
          background: PandoraSimpleColors.blueWash,
          size: 50,
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: PandoraSimpleColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                url ?? 'Deployment URL is still being prepared',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: pandoraSimpleMutedText,
              ),
              const SizedBox(height: 4),
              Text(
                status.replaceAll('_', ' '),
                style: const TextStyle(
                  color: PandoraSimpleColors.green,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Open',
          onPressed: url == null ? null : onOpen,
          icon: const Icon(Icons.open_in_new_rounded),
        ),
      ],
    ),
  );
}
