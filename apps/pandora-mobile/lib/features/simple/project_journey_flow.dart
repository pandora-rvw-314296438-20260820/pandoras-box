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
import 'owner_project_language.dart';
import 'pandora_simple_ui.dart';
import 'project_iteration_experience.dart';

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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _orbit;
  Timer? _refreshTimer;
  bool _started = false;
  bool _buildRequestStarted = false;
  bool _refreshing = false;
  String? _previewRequestedVersionId;
  ProjectRuntimeSnapshot? _snapshot;
  ProjectPreviewResult? _previewResult;
  String? _error;
  DateTime? _lastCheckedAt;

  static const _normalSteps = <PandoraOwnerBuildStage>[
    PandoraOwnerBuildStage.understanding,
    PandoraOwnerBuildStage.designing,
    PandoraOwnerBuildStage.building,
    PandoraOwnerBuildStage.connecting,
    PandoraOwnerBuildStage.preparingPreview,
    PandoraOwnerBuildStage.previewReady,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    unawaited(_resumeBuild(requestPreviewIfNeeded: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshDurableTruth());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _orbit.dispose();
    super.dispose();
  }

  Future<void> _resumeBuild({required bool requestPreviewIfNeeded}) async {
    _refreshTimer?.cancel();
    if (mounted) {
      setState(() => _error = null);
    }
    final snapshot = await _refreshDurableTruth(showBlockingError: true);
    if (!mounted || snapshot == null) return;

    if (requestPreviewIfNeeded && _shouldRequestPreview(snapshot)) {
      _requestStarted = true;
      unawaited(_requestPreview());
    }
    _scheduleRefresh();
  }

  Future<ProjectRuntimeSnapshot?> _refreshDurableTruth({
    bool showBlockingError = false,
  }) async {
    if (_refreshing) return _snapshot;
    final runtime = PandoraDependencies.of(context).projectRuntime;
    if (runtime == null) {
      if (mounted && (showBlockingError || _snapshot == null)) {
        setState(
          () => _error = 'Pandora cannot refresh this project right now.',
        );
      }
      return null;
    }

    _refreshing = true;
    try {
      final snapshot = await runtime.runtime(widget.project.id);
      if (!mounted) return snapshot;
      setState(() {
        _snapshot = snapshot;
        _lastCheckedAt = DateTime.now();
        _error = null;
      });
      return snapshot;
    } on PandoraRepositoryException {
      if (!mounted) return null;
      if (showBlockingError || _snapshot == null) {
        setState(
          () => _error = 'Pandora could not refresh this build right now.',
        );
      }
      return null;
    } catch (_) {
      if (!mounted) return null;
      if (showBlockingError || _snapshot == null) {
        setState(
          () => _error = 'Pandora could not refresh this build right now.',
        );
      }
      return null;
    } finally {
      _refreshing = false;
    }
  }

  bool _shouldRequestPreview(ProjectRuntimeSnapshot snapshot) {
    if (_requestStarted || pandoraHasLivePreview(snapshot)) return false;
    if (snapshot.preview != null || pandoraBuildAppearsInFlight(snapshot)) {
      return false;
    }
    final stage = snapshot.project.stage.toLowerCase();
    return stage == 'idea' || stage == 'draft' || stage == 'understanding';
  }

  Future<void> _requestPreview() async {
    final runtime = PandoraDependencies.of(context).projectRuntime;
    if (runtime == null) {
      if (mounted) {
        setState(() => _error = 'Pandora cannot build this preview right now.');
      }
      return;
    }

    try {
      final result = await runtime.createPreview(
        projectId: widget.project.id,
        idempotencyKey: _previewIdempotencyKey,
      );
      if (!mounted) return;
      setState(() {
        _previewResult = result;
        _lastCheckedAt = DateTime.now();
        _error = null;
      });
      await _refreshDurableTruth();
      _scheduleRefresh();
    } on PandoraRepositoryException {
      if (!mounted) return;
      _refreshTimer?.cancel();
      _requestStarted = false;
      setState(
        () => _error =
            'Pandora found something to fix before your preview is ready.',
      );
    } catch (_) {
      if (!mounted) return;
      _refreshTimer?.cancel();
      _requestStarted = false;
      setState(
        () => _error =
            'Pandora found something to fix before your preview is ready.',
      );
    }
  }

  String get _previewIdempotencyKey {
    final version = widget.project.updatedAt ?? widget.project.createdAt;
    final versionKey =
        version?.toUtc().toIso8601String() ?? widget.project.projectKey;
    return 'project-preview:${widget.project.id}:$versionKey';
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    if (_previewUrl != null) return;
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_refreshDurableTruth());
    });
  }

  String? get _previewUrl {
    final durableUrl = _snapshot?.preview?.url ?? _snapshot?.project.previewUrl;
    if (durableUrl != null && durableUrl.trim().isNotEmpty) return durableUrl;
    final resultUrl = _previewResult?.previewUrl;
    return resultUrl == null || resultUrl.trim().isEmpty ? null : resultUrl;
  }

  PandoraOwnerBuildStage get _currentStage {
    final snapshot = _snapshot;
    if (snapshot != null) return pandoraOwnerBuildStage(snapshot);
    if (_previewUrl != null) return PandoraOwnerBuildStage.previewReady;
    return PandoraOwnerBuildStage.understanding;
  }

  List<PandoraOwnerBuildStage> get _visibleSteps {
    return switch (_currentStage) {
      PandoraOwnerBuildStage.checking => <PandoraOwnerBuildStage>[
          ..._normalSteps.take(4),
          PandoraOwnerBuildStage.checking,
          PandoraOwnerBuildStage.preparingPreview,
          PandoraOwnerBuildStage.previewReady,
        ],
      PandoraOwnerBuildStage.fixing => <PandoraOwnerBuildStage>[
          ..._normalSteps.take(4),
          PandoraOwnerBuildStage.fixing,
          PandoraOwnerBuildStage.preparingPreview,
          PandoraOwnerBuildStage.previewReady,
        ],
      _ => _normalSteps,
    };
  }

  @override
  Widget build(BuildContext context) {
    final previewUrl = _previewUrl;
    final ready = previewUrl != null;
    final currentStage = _currentStage;
    final steps = _visibleSteps;
    final currentIndex = steps.indexOf(currentStage);
    final copy = pandoraOwnerBuildStageCopy(currentStage);

    return PandoraSimplePage(
      header: PandoraOwnerHeader(
        title: ready ? 'Live preview ready' : 'Pandora is building',
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
            Text(
              copy.detail,
              textAlign: TextAlign.center,
              style: pandoraSimpleMutedText,
            ),
            const SizedBox(height: 28),
            _TheatreMark(controller: _orbit),
            const SizedBox(height: 26),
            PandoraSimpleCard(
              shadow: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    copy.label,
                    style: const TextStyle(
                      color: PandoraSimpleColors.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (var index = 0; index < steps.length; index++)
                    _BuildStageRow(
                      label: pandoraOwnerBuildStageCopy(steps[index]).label,
                      state: currentIndex >= 0 && index < currentIndex
                          ? _StageState.complete
                          : index == currentIndex
                              ? _StageState.current
                              : _StageState.pending,
                      last: index == steps.length - 1,
                    ),
                ],
              ),
            ),
            if (_lastCheckedAt != null) ...[
              const SizedBox(height: 10),
              const Text(
                'Build state is synced from Pandora. It will reconnect after you return to the app.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: PandoraSimpleColors.muted,
                  fontSize: 12,
                ),
              ),
            ],
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
                    'Pandora found something to fix',
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
                      _requestStarted = false;
                      unawaited(_resumeBuild(requestPreviewIfNeeded: true));
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
              'Your preview is ready',
              style: TextStyle(
                color: PandoraSimpleColors.ink,
                fontSize: 29,
                fontWeight: FontWeight.w700,
                letterSpacing: -.6,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This version is available to preview. Pandora may still be checking it before publication is allowed.',
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
                    previewUrl,
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
                    onPressed: () => _launchProjectUrl(context, previewUrl),
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
                angle: (frozen ? item.$1 : controller.value + item.$1) *
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

  Future<void> _changeSomething() async {
    final project = _snapshot?.project;
    if (project == null) return;
    final buildUpdatedPreview = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ProjectIterationExperienceScreen(project: project),
      ),
    );
    if (!mounted) return;
    if (buildUpdatedPreview == true) {
      await _buildAgain();
      return;
    }
    await _load();
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
        subtitle:
            project?.isLive == true ? 'Live project' : 'Project workspace',
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
                        style:
                            const TextStyle(color: PandoraSimpleColors.deepRed),
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
                          Text(project.objective,
                              style: pandoraSimpleMutedText),
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
                      if (_snapshot!.preview != null)
                        const SizedBox(height: 12),
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
                    if (!project.hasPreview)
                      PandoraPrimaryButton(
                        label: 'Build preview',
                        icon: Icons.auto_awesome_rounded,
                        onPressed: _publishing ? null : _buildAgain,
                        expanded: true,
                      ),
                    if (project.hasPreview) ...[
                      PandoraPrimaryButton(
                        label: 'Change something',
                        icon: Icons.edit_outlined,
                        onPressed: _publishing ? null : _changeSomething,
                        expanded: true,
                      ),
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
