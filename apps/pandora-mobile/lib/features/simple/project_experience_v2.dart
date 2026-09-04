import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_intelligence_api.dart';
import '../../core/data/project_experience_api.dart';
import '../../core/data/project_experience_repository.dart';
import '../../core/models/project_candidate_safety.dart';
import '../../core/models/project_experience_projection.dart';
import '../../core/models/project_focus_token.dart';
import '../../core/models/project_journey_models.dart';
import '../../core/platform/pandora_native_io.dart';
import '../../core/platform/pandora_preview_host.dart';
import 'live_build_theatre/live_build_reducer.dart';
import 'live_build_theatre/live_build_theatre.dart';
import 'live_build_theatre/project_build_stream_theatre_projection.dart';
import 'pandora_v2_ui.dart';
import 'project_exact_source_diff.dart';
import 'project_history_screen.dart';
import 'project_source_files_screen.dart';
import 'project_workspace_v2_view.dart';

String? _safeHttps(String? value) {
  final text = value?.trim() ?? '';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  return uri.toString();
}

Future<List<Map<String, Object?>>> _loadExactPreviewFiles(
  ProjectExperienceRepository experience, {
  required String projectId,
  required String versionId,
}) async {
  return experience.loadExactPreviewFiles(
    projectId: projectId,
    versionId: versionId,
  );
}

String? _previewArtifactDigest(
  List<Map<String, Object?>>? files, {
  required String projectId,
  required String versionId,
}) {
  if (files == null || files.isEmpty) return null;
  String normalized(Object? value) =>
      (value as String? ?? '').trim().toLowerCase();
  final expectedProject = projectId.trim().toLowerCase();
  final expectedVersion = versionId.trim().toLowerCase();
  final digest = normalized(files.first['artifactDigest']);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) return null;
  for (final file in files) {
    if (normalized(file['artifactDigest']) != digest ||
        normalized(file['previewProjectId']) != expectedProject ||
        normalized(file['previewVersionId']) != expectedVersion) {
      return null;
    }
  }
  return digest;
}

class ProjectBuildExperienceV2Screen extends StatefulWidget {
  const ProjectBuildExperienceV2Screen({
    super.key,
    required this.project,
    this.baseVersionId,
    this.buildAlreadyRequested = false,
  });

  final CustomerProject project;
  final String? baseVersionId;
  final bool buildAlreadyRequested;

  @override
  State<ProjectBuildExperienceV2Screen> createState() =>
      _ProjectBuildExperienceV2ScreenState();
}

class _ProjectBuildExperienceV2ScreenState
    extends State<ProjectBuildExperienceV2Screen>
    with WidgetsBindingObserver {
  Timer? _timer;
  ProjectRuntimeSnapshot? _snapshot;
  ProjectPreviewResult? _previewResult;
  List<Map<String, Object?>>? _localPreviewFiles;
  String? _localPreviewVersionId;
  String? _error;
  bool _started = false;
  bool _buildRequested = false;
  bool _previewRequested = false;
  bool _refreshing = false;
  bool _openingPreview = false;
  bool _transitionedToWorkspace = false;
  DateTime? _flowStartedAt;
  DateTime? _flowBackgroundedAt;
  StreamSubscription<ProjectBuildStreamSnapshot>? _initialBuildSubscription;
  String? _initialBuildJobId;
  String? _initialBuildStreamId;
  LiveBuildTheatreState? _initialBuildActivity;
  bool _resolvingInitialBuild = false;

  static const _flowTimeout = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final backgroundedAt = _flowBackgroundedAt;
      if (backgroundedAt != null) {
        final startedAt = _flowStartedAt;
        if (startedAt != null) {
          _flowStartedAt = startedAt.add(
            DateTime.now().difference(backgroundedAt),
          );
        }
        _flowBackgroundedAt = null;
      }
      _timer?.cancel();
      unawaited(_refreshAndAdvance());
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _flowBackgroundedAt ??= DateTime.now();
      _timer?.cancel();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _buildRequested = widget.buildAlreadyRequested;
    _flowStartedAt = DateTime.now();
    unawaited(_refreshAndAdvance());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _initialBuildSubscription?.cancel();
    super.dispose();
  }

  bool _candidateIsCurrent(ProjectRuntimeCandidate? candidate) {
    if (candidate == null) return false;
    final base = widget.baseVersionId?.trim();
    return base == null || base.isEmpty || candidate.versionId != base;
  }

  ProjectRuntimeCandidate? get _candidate {
    final value = _snapshot?.candidate;
    return _candidateIsCurrent(value) ? value : null;
  }

  String? get _previewUrl {
    final candidate = _candidate;
    if (candidate == null) return null;
    final preview = _snapshot?.preview;
    if (preview != null && preview.versionId == candidate.versionId) {
      return _safeHttps(preview.url);
    }
    final result = _previewResult;
    if (result != null &&
        (result.versionId == null || result.versionId == candidate.versionId)) {
      return _safeHttps(result.previewUrl ?? result.deployment?.url);
    }
    return null;
  }

  bool get _ready {
    final candidate = _candidate;
    if (candidate == null) return false;
    return _previewUrl != null ||
        (_localPreviewVersionId == candidate.versionId &&
            _localPreviewFiles != null);
  }

  void _enterWorkspaceIfReady() {
    if (!_ready || _transitionedToWorkspace || !mounted) return;
    _transitionedToWorkspace = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ProjectWorkspaceV2Screen(
            project: _snapshot?.project ?? widget.project,
          ),
        ),
      );
    });
  }

  bool get _flowExpired {
    final startedAt = _flowStartedAt;
    return startedAt != null &&
        DateTime.now().difference(startedAt) >= _flowTimeout;
  }

  void _acceptInitialBuildSnapshot(
    String streamId,
    ProjectBuildStreamSnapshot snapshot,
  ) {
    if (!mounted ||
        _initialBuildStreamId != streamId ||
        snapshot.requiresReplay ||
        snapshot.events.isEmpty) {
      return;
    }
    try {
      final activity = ProjectBuildStreamTheatreProjection.fromSnapshot(
        streamId: streamId,
        snapshot: snapshot,
      );
      setState(() => _initialBuildActivity = activity);
    } on FormatException {
      // Reject mismatched stream evidence instead of fabricating activity.
    }
  }

  Future<void> _attachInitialBuildStream(
    ProjectExperienceRepository experience,
    String? rawStreamId, {
    String? buildJobId,
  }) async {
    final streamId = rawStreamId?.trim();
    if (streamId == null || streamId.isEmpty) return;
    if (_initialBuildStreamId == streamId &&
        _initialBuildSubscription != null) {
      return;
    }
    await _initialBuildSubscription?.cancel();
    _initialBuildSubscription = null;
    if (!mounted) return;
    setState(() {
      _initialBuildStreamId = streamId;
      _initialBuildJobId = buildJobId?.trim();
      _initialBuildActivity = null;
    });
    _initialBuildSubscription = experience
        .watchResilientBuildStream(
      projectId: widget.project.id,
      streamId: streamId,
    )
        .listen(
      (snapshot) => _acceptInitialBuildSnapshot(streamId, snapshot),
      onError: (_) {
        // Runtime polling remains the fail-closed fallback while the
        // resilient stream reconnects or becomes discoverable again.
      },
    );
  }

  Future<void> _syncInitialBuildActivity(
    ProjectExperienceRepository experience,
    String? rawBuildJobId,
  ) async {
    final buildJobId = rawBuildJobId?.trim();
    if (buildJobId == null || buildJobId.isEmpty) return;
    if (_initialBuildJobId == buildJobId &&
        (_initialBuildSubscription != null || _resolvingInitialBuild)) {
      return;
    }
    _resolvingInitialBuild = true;
    try {
      final streamId = await experience.findBuildStreamId(
        projectId: widget.project.id,
        buildJobId: buildJobId,
      );
      if (!mounted) return;
      await _attachInitialBuildStream(
        experience,
        streamId,
        buildJobId: buildJobId,
      );
    } catch (_) {
      // The 2-second authoritative runtime refresh retries discovery without
      // inventing progress or replacing the durable build state.
    } finally {
      _resolvingInitialBuild = false;
    }
  }

  Future<void> _refreshAndAdvance() async {
    if (_flowBackgroundedAt != null) return;
    if (_flowExpired) {
      _timer?.cancel();
      if (mounted) {
        setState(
          () => _error =
              'This is taking longer than expected. Your request is saved; try again to resume from the current project state.',
        );
      }
      return;
    }
    if (_refreshing) return;
    final experience =
        PandoraDependencies.of(context).projectExperienceRepository;
    if (experience == null) {
      setState(
        () => _error = 'Pandora cannot continue this project right now.',
      );
      return;
    }
    _refreshing = true;
    try {
      final snapshot = await experience.runtime(widget.project.id);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _error = null;
      });

      try {
        final projection = await experience.loadExperience(widget.project.id);
        if (mounted && _candidate == null) {
          await _syncInitialBuildActivity(
            experience,
            projection.activeBuildJobId,
          );
        }
      } catch (_) {
        // Build admission below can attach the exact stream directly.
      }

      final candidate = _candidate;
      if (candidate == null) {
        if (!_buildRequested) {
          _buildRequested = true;
          try {
            final start = await experience.requestBuild(
              projectId: widget.project.id,
              idempotencyKey: 'pandora-v2-build:${widget.project.id}',
            );
            if (mounted) {
              await _attachInitialBuildStream(
                experience,
                start.streamId,
                buildJobId: start.buildJobId,
              );
            }
          } on ProjectExperienceException catch (error) {
            _buildRequested = false;
            if (mounted) setState(() => _error = error.message);
          }
        }
      } else if (!_ready && !_previewRequested) {
        _previewRequested = true;
        try {
          final result = await experience.createPreview(
            projectId: widget.project.id,
            versionId: candidate.versionId,
            artifactDigest: candidate.artifactDigest,
            idempotencyKey:
                'pandora-v2-preview:${widget.project.id}:${candidate.versionId}',
          );
          List<Map<String, Object?>>? exactFiles;
          try {
            exactFiles = await _loadExactPreviewFiles(
              experience,
              projectId: widget.project.id,
              versionId: candidate.versionId,
            );
          } catch (_) {
            // The verified remote preview remains available if local hydration lags.
          }
          if (mounted) {
            setState(() {
              _previewResult = result;
              if (exactFiles != null && exactFiles.isNotEmpty) {
                _localPreviewFiles = exactFiles;
                _localPreviewVersionId = candidate.versionId;
              }
              _error = null;
            });
          }
        } catch (_) {
          try {
            final files = await _loadExactPreviewFiles(
              experience,
              projectId: widget.project.id,
              versionId: candidate.versionId,
            );
            if (mounted) {
              setState(() {
                _localPreviewFiles = files;
                _localPreviewVersionId = candidate.versionId;
                _error = null;
              });
            }
          } catch (_) {
            _previewRequested = false;
            if (mounted) {
              setState(
                () => _error =
                    'Pandora found something to resolve before your first version can open.',
              );
            }
          }
        }
      }
    } catch (_) {
      if (mounted && _snapshot == null) {
        setState(
          () => _error = 'Pandora could not refresh this project right now.',
        );
      }
    } finally {
      _refreshing = false;
      if (mounted && _ready) {
        _enterWorkspaceIfReady();
      }
      if (mounted &&
          !_ready &&
          !_flowExpired &&
          _flowBackgroundedAt == null) {
        _timer?.cancel();
        _timer = Timer(const Duration(seconds: 2), _refreshAndAdvance);
      }
    }
  }

  Future<void> _openExactPreview() async {
    if (_openingPreview) return;
    final candidate = _candidate;
    if (candidate == null) return;
    final experience =
        PandoraDependencies.of(context).projectExperienceRepository;
    if (experience == null) return;
    setState(() => _openingPreview = true);
    try {
      var files = _localPreviewVersionId == candidate.versionId
          ? _localPreviewFiles
          : null;
      files ??= await _loadExactPreviewFiles(
        experience,
        projectId: widget.project.id,
        versionId: candidate.versionId,
      );
      if (await PandoraNativeIo.openPreviewBundle(files)) return;
    } catch (_) {
      // Fall through to the verified remote preview when available.
    } finally {
      if (mounted) setState(() => _openingPreview = false);
    }
    final url = _previewUrl;
    if (url != null && await PandoraNativeIo.openExternalUrl(url)) return;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pandora could not open this version right now.'),
        ),
      );
    }
  }

  String get _stageTitle {
    final updating = widget.baseVersionId?.trim().isNotEmpty == true;
    if (_ready) return updating ? 'Updated' : 'Ready';
    if (_candidate != null) return 'Preparing your preview';
    if (_snapshot?.verification?.state == 'checking') return 'Checking';
    if (_buildRequested) return updating ? 'Building your change' : 'Building';
    return 'Preparing';
  }

  String get _stageMessage {
    if (_ready) return 'Your exact project is ready to experience.';
    if (_candidate != null) {
      return 'Preparing the exact version you just built.';
    }
    return 'Pandora is working while your project stays safe.';
  }

  Widget _buildStageSurface() {
    final activity = _initialBuildActivity;
    if (!_ready && activity != null && activity.latestSequence > 0) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(child: LiveBuildTheatre(state: activity)),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _stageTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: PandoraV2Colors.ink,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.7,
                  height: 1.08,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _stageMessage,
                textAlign: TextAlign.center,
                style: pandoraV2Muted,
              ),
              if (!_ready) ...[
                const SizedBox(height: 24),
                const SizedBox(
                  width: 144,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: PandoraV2Colors.ink,
                    backgroundColor: PandoraV2Colors.soft,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadySurface() {
    final candidate = _candidate;
    final files =
        candidate != null && _localPreviewVersionId == candidate.versionId
            ? _localPreviewFiles
            : null;
    if (candidate == null || files == null || files.isEmpty) {
      return _buildStageSurface();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(21),
      child: PandoraPreviewHost(
        files: files,
        versionId: candidate.versionId,
        fallback: _buildStageSurface(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: PandoraV2Colors.canvas,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: PandoraV2ObjectHeader(
                  title: widget.project.name,
                  subtitle: _ready ? 'Ready' : 'Working',
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: PandoraV2Colors.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: PandoraV2Colors.line),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _ready
                              ? _buildReadySurface()
                              : _buildStageSurface(),
                        ),
                        if (_ready)
                          Positioned(
                            right: 18,
                            top: 18,
                            child: IconButton.filled(
                              tooltip: 'Open exact preview',
                              onPressed:
                                  _openingPreview ? null : _openExactPreview,
                              style: IconButton.styleFrom(
                                backgroundColor: PandoraV2Colors.ink,
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.open_in_full_rounded),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: Column(
                  children: [
                    if (_error != null) ...[
                      PandoraV2InlineMessage(
                        title: 'This needs another try',
                        message: _error!,
                        actionLabel: 'Try again',
                        onAction: () {
                          setState(() {
                            _error = null;
                            _previewRequested = false;
                            _flowStartedAt = DateTime.now();
                            if (_candidate == null) _buildRequested = false;
                          });
                          unawaited(_refreshAndAdvance());
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class ProjectWorkspaceV2Screen extends StatefulWidget {
  const ProjectWorkspaceV2Screen({
    super.key,
    required this.project,
    this.initialChange,
  });

  final CustomerProject project;
  final String? initialChange;

  @override
  State<ProjectWorkspaceV2Screen> createState() =>
      _ProjectWorkspaceV2ScreenState();
}

class _ProjectWorkspaceV2ScreenState extends State<ProjectWorkspaceV2Screen>
    with WidgetsBindingObserver {
  final _change = TextEditingController();
  ProjectRuntimeSnapshot? _snapshot;
  ProjectExperienceProjection? _projection;
  StreamSubscription<ProjectExperienceProjection>? _projectionSubscription;
  Timer? _projectionRetryTimer;
  List<Map<String, Object?>>? _previewFiles;
  String? _previewVersionId;
  String? _error;
  String? _intelligenceReply;
  Map<String, Object?>? _publishReceipt;
  bool _started = false;
  bool _loading = true;
  bool _openingPreview = false;
  bool _changing = false;
  bool _publishing = false;
  bool _undoing = false;
  bool _recentlyUpdated = false;
  bool _initialChangeSubmitted = false;
  bool _initialChangeSubmitting = false;
  String? _initialChangeIdempotencyKey;
  ProjectExactSourceDiff? _lastChangeDiff;
  StreamSubscription<ProjectBuildStreamSnapshot>? _liveBuildSubscription;
  Timer? _liveBuildRetryTimer;
  String? _liveBuildJobId;
  String? _liveBuildStreamId;
  LiveBuildTheatreState? _liveBuildActivity;
  bool _resolvingLiveBuild = false;
  bool _selectionMode = false;
  PandoraPreviewSelection? _selectedPreviewTarget;
  ProjectFocusToken? _focusToken;
  Timer? _previewRetryTimer;
  String? _previewRetryVersionId;
  int _previewRetryCount = 0;

  static const _previewRetryLimit = 6;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeFromDurableState());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_startProjection());
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _previewRetryTimer?.cancel();
    _projectionRetryTimer?.cancel();
    _liveBuildRetryTimer?.cancel();
    _liveBuildSubscription?.cancel();
    _projectionSubscription?.cancel();
    _change.dispose();
    super.dispose();
  }

  Future<void> _resumeFromDurableState() async {
    _previewRetryTimer?.cancel();
    _projectionRetryTimer?.cancel();
    _liveBuildRetryTimer?.cancel();
    await _projectionSubscription?.cancel();
    _projectionSubscription = null;
    await _liveBuildSubscription?.cancel();
    _liveBuildSubscription = null;
    _resolvingLiveBuild = false;
    if (!mounted) return;
    await _startProjection();
    if (!mounted) return;
    await _refresh();
  }

  void _scheduleProjectionRetry() {
    if (_projectionRetryTimer?.isActive == true) return;
    _projectionRetryTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _projectionSubscription == null) {
        unawaited(_startProjection());
      }
    });
  }

  Future<void> _recoverProjectionAfterError() async {
    await _projectionSubscription?.cancel();
    _projectionSubscription = null;
    if (!mounted) return;
    _scheduleProjectionRetry();
  }

  Future<void> _recoverLiveBuildAfterError(String buildJobId) async {
    await _liveBuildSubscription?.cancel();
    _liveBuildSubscription = null;
    if (!mounted || _liveBuildJobId != buildJobId) return;
    _scheduleLiveBuildRetry(buildJobId);
  }

  Future<void> _startProjection() async {
    final repository =
        PandoraDependencies.of(context).projectExperienceRepository;
    if (repository == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Pandora cannot determine this project state right now.';
      });
      return;
    }

    try {
      final initial = await repository.loadExperience(widget.project.id);
      if (!mounted) return;
      _acceptProjection(initial);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error ??= 'Pandora cannot determine this project state right now.';
      });
    }

    if (!mounted || _projectionSubscription != null) return;
    _projectionSubscription =
        repository.watchExperience(widget.project.id).listen(
      _acceptProjection,
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _error ??= 'Pandora cannot refresh this project state right now.';
        });
        unawaited(_recoverProjectionAfterError());
      },
    );
  }

  void _acceptProjection(ProjectExperienceProjection next) {
    if (!mounted) return;
    final current = _projection;
    if (current != null && !next.isNewerThan(current)) return;
    final safety = ProjectCandidateSafety.fromProjection(
      next,
      visibleCurrentVersionId: _previewVersionId,
    );
    final shouldHydrate = safety.versionToHydrate != null;
    setState(() {
      _projection = next;
      _loading = false;
      if (safety.candidateFailed) {
        _error = safety.failureMessage(backendMessage: next.safeFailureMessage);
      } else if (next.hasSafeFailure && _error == null) {
        _error = next.safeFailureMessage ??
            'Pandora found something to resolve. Your current version is unchanged.';
      }
    });
    final initialChange = widget.initialChange?.trim();
    if (!_initialChangeSubmitted &&
        !_initialChangeSubmitting &&
        initialChange != null &&
        initialChange.length >= 4 &&
        next.canChange) {
      _initialChangeSubmitting = true;
      final routedAttempt = DateTime.now().microsecondsSinceEpoch;
      _initialChangeIdempotencyKey ??=
          'pandora-v2-routed-change:${widget.project.id}:$routedAttempt';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_requestInitialChange(initialChange));
      });
    }
    if (shouldHydrate) unawaited(_refresh());
    unawaited(_syncLiveBuildActivity(next.activeBuildJobId));
  }

  void _scheduleLiveBuildRetry(String buildJobId) {
    if (_liveBuildRetryTimer?.isActive == true) return;
    _liveBuildRetryTimer = Timer(const Duration(seconds: 2), () {
      if (mounted &&
          _liveBuildJobId == buildJobId &&
          _liveBuildSubscription == null) {
        unawaited(_syncLiveBuildActivity(buildJobId));
      }
    });
  }

  void _acceptLiveBuildSnapshot(
    String streamId,
    ProjectBuildStreamSnapshot snapshot,
  ) {
    if (!mounted ||
        _liveBuildStreamId != streamId ||
        snapshot.requiresReplay ||
        snapshot.events.isEmpty) {
      return;
    }
    try {
      final activity = ProjectBuildStreamTheatreProjection.fromSnapshot(
        streamId: streamId,
        snapshot: snapshot,
      );
      setState(() => _liveBuildActivity = activity);
    } on FormatException {
      // Reject mismatched stream evidence instead of fabricating activity.
    }
  }

  Future<void> _syncLiveBuildActivity(String? rawBuildJobId) async {
    final buildJobId = rawBuildJobId?.trim();
    if (buildJobId == null || buildJobId.isEmpty) {
      _liveBuildRetryTimer?.cancel();
      await _liveBuildSubscription?.cancel();
      _liveBuildSubscription = null;
      _resolvingLiveBuild = false;
      if (!mounted) return;
      if (_liveBuildJobId != null ||
          _liveBuildStreamId != null ||
          _liveBuildActivity != null) {
        setState(() {
          _liveBuildJobId = null;
          _liveBuildStreamId = null;
          _liveBuildActivity = null;
        });
      }
      return;
    }

    if (_liveBuildJobId != buildJobId) {
      _liveBuildRetryTimer?.cancel();
      await _liveBuildSubscription?.cancel();
      _liveBuildSubscription = null;
      if (!mounted) return;
      setState(() {
        _liveBuildJobId = buildJobId;
        _liveBuildStreamId = null;
        _liveBuildActivity = null;
      });
    }
    if (_liveBuildSubscription != null || _resolvingLiveBuild) return;

    final repository =
        PandoraDependencies.of(context).projectExperienceRepository;
    if (repository == null) return;

    _resolvingLiveBuild = true;
    try {
      final streamId = await repository.findBuildStreamId(
        projectId: widget.project.id,
        buildJobId: buildJobId,
      );
      if (!mounted || _liveBuildJobId != buildJobId) return;
      final normalizedStreamId = streamId?.trim();
      if (normalizedStreamId == null || normalizedStreamId.isEmpty) {
        _scheduleLiveBuildRetry(buildJobId);
        return;
      }
      setState(() => _liveBuildStreamId = normalizedStreamId);
      _liveBuildSubscription = repository
          .watchResilientBuildStream(
        projectId: widget.project.id,
        streamId: normalizedStreamId,
      )
          .listen(
        (snapshot) => _acceptLiveBuildSnapshot(normalizedStreamId, snapshot),
        onError: (_) {
          unawaited(_recoverLiveBuildAfterError(buildJobId));
        },
      );
    } on ProjectExperienceException {
      _scheduleLiveBuildRetry(buildJobId);
    } catch (_) {
      _scheduleLiveBuildRetry(buildJobId);
    } finally {
      _resolvingLiveBuild = false;
    }
  }

  String? get _liveActivityLabel {
    final activity = _liveBuildActivity;
    if (activity == null || activity.latestSequence <= 0) return null;
    return activity.statusLabel;
  }

  String? get _liveActivityDetail {
    final activity = _liveBuildActivity;
    if (activity == null || activity.uniqueFileCount <= 0) return null;
    return '${activity.completedFileCount} of ${activity.uniqueFileCount} files written';
  }

  Future<void> _openLiveBuildActivity() async {
    final streamId = _liveBuildStreamId;
    if (streamId == null || streamId.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProjectHistoryBuildEvidenceScreen(
          project: _snapshot?.project ?? widget.project,
          streamId: streamId,
        ),
      ),
    );
  }

  ProjectChangePhase? get _projectionProgressPhase {
    final projection = _projection;
    if (projection == null) {
      return _changing ? ProjectChangePhase.designing : null;
    }
    if (projection.isUpdating) {
      return projection.buildPhase?.toLowerCase() == 'checking'
          ? ProjectChangePhase.checking
          : ProjectChangePhase.building;
    }
    switch (projection.state) {
      case ProjectExperienceState.understand:
      case ProjectExperienceState.change:
        return ProjectChangePhase.designing;
      case ProjectExperienceState.build:
      case ProjectExperienceState.rebuild:
        return projection.buildPhase?.toLowerCase() == 'checking'
            ? ProjectChangePhase.checking
            : ProjectChangePhase.building;
      case ProjectExperienceState.review:
        return ProjectChangePhase.checking;
      default:
        return null;
    }
  }

  ProjectCandidateSafety? get _candidateSafety {
    final projection = _projection;
    if (projection == null) return null;
    return ProjectCandidateSafety.fromProjection(
      projection,
      visibleCurrentVersionId: _previewVersionId,
    );
  }

  ProjectVersionRoles? get _versionRoles => _candidateSafety?.roles;

  ProjectExactSourceDiff? _exactDiffForCandidate({
    required ProjectExperienceProjection projection,
    required String candidateVersionId,
    required List<Map<String, Object?>> candidateFiles,
  }) {
    final baselineVersionId = _previewVersionId;
    final baselineFiles = _previewFiles;
    if (baselineVersionId == null ||
        baselineFiles == null ||
        baselineFiles.isEmpty ||
        candidateVersionId == baselineVersionId) {
      return null;
    }
    if (!projection.currentVerified ||
        projection.currentVersionId != baselineVersionId ||
        projection.candidateVersionId != candidateVersionId ||
        projection.candidateVerificationState.trim().toLowerCase() !=
            'passed') {
      return null;
    }

    try {
      return ProjectExactSourceDiff.fromExactPreviewBundles(
        projectId: widget.project.id,
        baselineVersionId: baselineVersionId,
        baselineFiles: baselineFiles,
        candidateVersionId: candidateVersionId,
        candidateFiles: candidateFiles,
      );
    } on FormatException {
      return null;
    }
  }

  bool get _canUndo =>
      _projection?.canUndo == true && _projection?.candidateVersionId != null;

  bool get _canPublish =>
      _projection?.canPublish == true &&
      _candidateSafety?.candidateVerified == true &&
      _projection?.candidateVersionId != null;

  bool get _currentVersionVerified {
    final projection = _projection;
    final safety = _candidateSafety;
    final roles = _versionRoles;
    if (projection == null || safety == null || roles == null) return false;

    if (roles.candidateIsVisible) return safety.candidateVerified;
    return roles.visibleCurrentVersionId == projection.currentVersionId &&
        projection.currentVerified;
  }

  String get _statusLabel {
    if (_recentlyUpdated && _currentVersionVerified) return 'Updated';
    return _projection?.statusLabel ?? 'Working';
  }

  Color get _statusColor {
    final state = _projection?.state;
    if ((_recentlyUpdated && _currentVersionVerified) ||
        state == ProjectExperienceState.live ||
        state == ProjectExperienceState.review) {
      return PandoraV2Colors.success;
    }
    return PandoraV2Colors.muted;
  }

  Future<List<Map<String, Object?>>?> _readExactPreviewVersion(
    String versionId,
  ) async {
    final experience =
        PandoraDependencies.of(context).projectExperienceRepository;
    if (experience == null) return null;
    try {
      return await _loadExactPreviewFiles(
        experience,
        projectId: widget.project.id,
        versionId: versionId,
      ).timeout(const Duration(seconds: 12));
    } catch (_) {
      return null;
    }
  }

  Future<PandoraIntelligenceTurn?> _tryIntelligenceTurn(String request) async {
    final intelligence = PandoraDependencies.of(context).intelligence;
    if (intelligence == null) return null;
    try {
      return await intelligence
          .chat(message: request, projectId: widget.project.id)
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      // The owner already gave an explicit instruction inside a project.
      // Intelligence improves routing, but a transient intelligence outage
      // must not discard a durable change request.
      return null;
    }
  }

  void _schedulePreviewRetry(String versionId) {
    if (_previewVersionId == versionId) {
      _previewRetryTimer?.cancel();
      _previewRetryVersionId = null;
      _previewRetryCount = 0;
      return;
    }
    if (_previewRetryVersionId != versionId) {
      _previewRetryVersionId = versionId;
      _previewRetryCount = 0;
    }
    if (_previewRetryCount >= _previewRetryLimit ||
        _previewRetryTimer?.isActive == true) {
      return;
    }
    _previewRetryCount += 1;
    final delaySeconds = (_previewRetryCount * 2).clamp(2, 8).toInt();
    _previewRetryTimer = Timer(Duration(seconds: delaySeconds), () {
      if (mounted && _previewVersionId != versionId) {
        unawaited(_refresh());
      }
    });
  }

  Future<void> _refresh() async {
    final experience =
        PandoraDependencies.of(context).projectExperienceRepository;
    if (experience == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Pandora cannot open this project right now.';
      });
      return;
    }
    try {
      final snapshot = await experience.runtime(widget.project.id);
      final projection = await experience.loadExperience(widget.project.id);
      Map<String, Object?>? publishReceipt;
      try {
        publishReceipt = await experience.loadLatestPublishReceipt(
          projectId: widget.project.id,
        );
      } catch (_) {
        // Receipt history is supplemental to the authoritative project canvas.
      }
      if (!mounted) return;

      final safety = ProjectCandidateSafety.fromProjection(
        projection,
        visibleCurrentVersionId: _previewVersionId,
      );
      final targetVersionId = safety.versionToHydrate;
      List<Map<String, Object?>>? files;
      if (targetVersionId != null && targetVersionId != _previewVersionId) {
        files = await _readExactPreviewVersion(targetVersionId);
      }
      if (!mounted) return;

      final exactPreviewReady = files != null && files.isNotEmpty;
      final commitVisible = targetVersionId != null &&
          safety.canCommitVisibleVersion(
            versionId: targetVersionId,
            exactPreviewReady: exactPreviewReady,
          );
      final exactDiff = commitVisible &&
              targetVersionId == safety.roles.candidateVersionId &&
              files != null
          ? _exactDiffForCandidate(
              projection: projection,
              candidateVersionId: targetVersionId,
              candidateFiles: files,
            )
          : null;
      final currentProjection = _projection;
      final acceptProjection = currentProjection == null ||
          projection.isNewerThan(currentProjection);

      setState(() {
        _snapshot = snapshot;
        if (acceptProjection) _projection = projection;
        _publishReceipt = publishReceipt;
        _loading = false;

        if (commitVisible) {
          final versionChanged = _previewVersionId != targetVersionId;
          _previewFiles = files;
          _previewVersionId = targetVersionId;
          if (versionChanged) {
            if (targetVersionId == safety.roles.candidateVersionId) {
              _lastChangeDiff = exactDiff;
            }
            _selectionMode = false;
            _selectedPreviewTarget = null;
            _focusToken = null;
          }
          if (targetVersionId == safety.roles.candidateVersionId) {
            _recentlyUpdated = true;
          }
        }

        if (safety.candidateFailed) {
          _error = safety.failureMessage(
            backendMessage: projection.safeFailureMessage,
          );
        } else if (projection.hasSafeFailure) {
          _error = projection.safeFailureMessage ??
              'Pandora found something to resolve. Your current version is unchanged.';
        } else {
          _error = null;
        }
      });

      unawaited(_syncLiveBuildActivity(projection.activeBuildJobId));

      if (targetVersionId != null &&
          _previewVersionId != targetVersionId &&
          !safety.candidateFailed) {
        _schedulePreviewRetry(targetVersionId);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Pandora could not refresh this project right now.';
      });
    }
  }

  Future<void> _openExactPreview() async {
    if (_openingPreview) return;
    final experience =
        PandoraDependencies.of(context).projectExperienceRepository;
    if (experience == null) return;

    setState(() => _openingPreview = true);
    try {
      if (_previewVersionId == null || _previewFiles == null) {
        await _refresh();
      }
      if (!mounted) return;

      final versionId = _previewVersionId;
      if (versionId == null) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ProjectBuildExperienceV2Screen(project: widget.project),
          ),
        );
        return;
      }

      var files = _previewFiles;
      files ??= await _loadExactPreviewFiles(
        experience,
        projectId: widget.project.id,
        versionId: versionId,
      );
      if (!mounted) return;

      if (_previewVersionId != versionId) {
        return;
      }
      setState(() => _previewFiles = files);
      if (await PandoraNativeIo.openPreviewBundle(files)) return;
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Pandora could not open this exact version right now.',
        );
      }
    } finally {
      if (mounted) setState(() => _openingPreview = false);
    }
  }

  Future<void> _requestInitialChange(String request) async {
    if (_changing || _projection?.canChange != true) {
      if (mounted) setState(() => _initialChangeSubmitting = false);
      return;
    }
    await _requestChange(request, idempotencyKey: _initialChangeIdempotencyKey);
    if (!mounted) return;
    setState(() {
      _initialChangeSubmitting = false;
      if (_error == null && !_changing) _initialChangeSubmitted = true;
    });
  }

  Future<void> _requestChange(String text, {String? idempotencyKey}) async {
    final request = text.trim();
    if (request.length < 4 || _changing || _projection?.canChange != true) {
      return;
    }
    final experience =
        PandoraDependencies.of(context).projectExperienceRepository;
    if (experience == null) {
      setState(() => _error = 'Pandora cannot save that change right now.');
      return;
    }
    final baseVersion = _previewVersionId ?? _projection?.currentVersionId;
    setState(() {
      _changing = true;
      _recentlyUpdated = false;
      _lastChangeDiff = null;
      _error = null;
      _intelligenceReply = null;
    });
    try {
      var actionRequest = request;
      final turn = await _tryIntelligenceTurn(request);
      if (!mounted) return;

      if (turn != null) {
        if (turn.needsClarification) {
          _change.clear();
          setState(() {
            _changing = false;
            _intelligenceReply = turn.clarifyingQuestion ?? turn.reply;
          });
          return;
        }

        if (turn.intent == 'preview') {
          _change.clear();
          setState(() {
            _changing = false;
            _intelligenceReply = turn.reply;
          });
          await _openExactPreview();
          return;
        }
        if (turn.intent == 'publish') {
          _change.clear();
          setState(() {
            _changing = false;
            _intelligenceReply = turn.reply;
          });
          await _showPublish();
          return;
        }

        final handoff = turn.handoff;
        if (turn.intent == 'change_project' && handoff != null) {
          final routed = handoff.request.trim();
          if (routed.length >= 4) actionRequest = routed;
        } else if (turn.intent == 'chat') {
          _change.clear();
          setState(() {
            _changing = false;
            _intelligenceReply = turn.reply;
          });
          return;
        }
      }

      final selectedTarget = _selectedPreviewTarget;
      final focusToken = _focusToken;
      if (selectedTarget != null) {
        final visibleVersion = _previewVersionId;
        final artifactDigest = visibleVersion == null
            ? null
            : _previewArtifactDigest(
                _previewFiles,
                projectId: widget.project.id,
                versionId: visibleVersion,
              );
        if (focusToken == null ||
            visibleVersion == null ||
            artifactDigest == null ||
            !focusToken.matchesVisible(
              projectId: widget.project.id,
              versionId: visibleVersion,
              artifactDigest: artifactDigest,
            )) {
          setState(() {
            _selectionMode = false;
            _selectedPreviewTarget = null;
            _focusToken = null;
          });
          throw const ProjectExperienceException(
            'That selection belongs to an older preview. Select the object again before changing it.',
          );
        }
        actionRequest =
            '${focusToken.intentContext}\nOwner change: $actionRequest';
      }

      if (actionRequest.length < 4) {
        throw const ProjectExperienceException(
          'Pandora needs a clearer change before it can continue.',
        );
      }
      final changeAttempt = DateTime.now().microsecondsSinceEpoch;
      final changeIdempotencyKey = idempotencyKey ??
          'pandora-v2-change:${widget.project.id}:$changeAttempt';
      final intentId = await experience.submitChange(
        projectId: widget.project.id,
        changeText: actionRequest,
        idempotencyKey: changeIdempotencyKey,
      );

      OwnerProjectUnderstanding understanding =
          const OwnerProjectUnderstanding.waiting();
      for (var attempt = 0; attempt < 45; attempt++) {
        if (!mounted) return;
        understanding = await experience.understanding(
          projectId: widget.project.id,
          expectedSourceIntentId: intentId,
        );
        if (understanding.isReady) break;
        if (understanding.state == OwnerProjectUnderstandingState.rejected) {
          throw const ProjectExperienceException(
            'Pandora needs a different request before it can make that change.',
          );
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (!understanding.isReady) {
        throw const ProjectExperienceException(
          'Pandora is still preparing that change. Your current project is unchanged.',
        );
      }

      if (!mounted) return;
      await experience.requestBuild(
        projectId: widget.project.id,
        idempotencyKey:
            'pandora-v2-change-build:${widget.project.id}:$intentId',
      );
      if (!mounted) return;
      await _watchExactChange(baseVersion);
    } on ProjectExperienceException catch (error) {
      if (!mounted) return;
      setState(() {
        _changing = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _changing = false;
        _error = 'Pandora could not complete that request right now.';
      });
    }
  }

  Future<void> _watchExactChange(String? baseVersion) async {
    final repository =
        PandoraDependencies.of(context).projectExperienceRepository;
    final experience =
        PandoraDependencies.of(context).projectExperienceRepository;
    if (repository == null || experience == null) {
      throw const ProjectExperienceException(
        'Pandora cannot check that change right now.',
      );
    }

    bool resolved(ProjectExperienceProjection projection) {
      final safety = ProjectCandidateSafety.fromProjection(
        projection,
        visibleCurrentVersionId: _previewVersionId,
      );
      if (projection.hasSafeFailure || safety.candidateFailed) return true;

      final candidateVersion = projection.candidateVersionId;
      if (candidateVersion == null ||
          (baseVersion != null && candidateVersion == baseVersion)) {
        return false;
      }
      return safety.candidateVerified;
    }

    ProjectExperienceProjection? transition = _projection;
    if (transition == null || !resolved(transition)) {
      try {
        transition = await repository
            .watchExperience(widget.project.id)
            .firstWhere(resolved)
            .timeout(const Duration(minutes: 3));
      } on TimeoutException {
        throw const ProjectExperienceException(
          'Pandora is still building that change. Your current project remains available.',
        );
      } catch (_) {
        throw const ProjectExperienceException(
          'Pandora cannot check that change right now.',
        );
      }
    }

    if (!mounted) return;
    final transitionSafety = ProjectCandidateSafety.fromProjection(
      transition,
      visibleCurrentVersionId: _previewVersionId,
    );
    if (transition.hasSafeFailure || transitionSafety.candidateFailed) {
      throw ProjectExperienceException(
        transitionSafety.failureMessage(
          backendMessage: transition.safeFailureMessage,
        ),
      );
    }
    final versionId = transition.candidateVersionId;
    if (versionId == null || versionId.isEmpty) {
      throw const ProjectExperienceException(
        'Pandora is still preparing the new version.',
      );
    }

    List<Map<String, Object?>>? files;
    for (var attempt = 0; attempt < _previewRetryLimit; attempt++) {
      try {
        files = await _loadExactPreviewFiles(
          experience,
          projectId: widget.project.id,
          versionId: versionId,
        ).timeout(const Duration(seconds: 12));
      } catch (_) {
        files = null;
      }
      if (files != null && files.isNotEmpty) break;
      if (attempt + 1 < _previewRetryLimit) {
        final delaySeconds = ((attempt + 1) * 2).clamp(2, 8).toInt();
        await Future<void>.delayed(Duration(seconds: delaySeconds));
      }
    }

    if (!mounted) return;
    if (files == null || files.isEmpty) {
      throw const ProjectExperienceException(
        'Pandora verified the new version, but its exact preview is still preparing. Your current version is unchanged.',
      );
    }
    if (!transitionSafety.canCommitVisibleVersion(
      versionId: versionId,
      exactPreviewReady: true,
    )) {
      throw const ProjectExperienceException(
        'Pandora cannot safely show that candidate yet. Your current version is unchanged.',
      );
    }

    final exactDiff = _exactDiffForCandidate(
      projection: transition,
      candidateVersionId: versionId,
      candidateFiles: files,
    );

    _change.clear();
    setState(() {
      _previewFiles = files;
      _previewVersionId = versionId;
      _changing = false;
      _recentlyUpdated = true;
      _lastChangeDiff = exactDiff;
      _selectionMode = false;
      _selectedPreviewTarget = null;
      _focusToken = null;
      _error = null;
    });
  }

  Future<void> _undoChange() async {
    final experience =
        PandoraDependencies.of(context).projectExperienceRepository;
    final versionId = _projection?.candidateVersionId;
    if (experience == null || versionId == null || !_canUndo || _undoing) {
      return;
    }
    setState(() {
      _undoing = true;
      _error = null;
      _intelligenceReply = null;
    });
    try {
      final snapshot = await experience.undo(
        projectId: widget.project.id,
        versionId: versionId,
        idempotencyKey: 'pandora-v2-undo:${widget.project.id}:$versionId',
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _recentlyUpdated = false;
        _lastChangeDiff = null;
      });
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Undone.')));
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'Pandora could not undo that change. Your current live result was not altered.',
      );
    } finally {
      if (mounted) setState(() => _undoing = false);
    }
  }

  Future<void> _renameProject() async {
    final currentName = _snapshot?.project.name ?? widget.project.name;
    final controller = TextEditingController(text: currentName);
    final nextName = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PandoraV2Colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          22,
          24,
          22 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Rename project',
              style: TextStyle(
                color: PandoraV2Colors.ink,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Project name'),
              onSubmitted: (value) =>
                  Navigator.of(sheetContext).pop(value.trim()),
            ),
            const SizedBox(height: 12),
            PandoraV2PrimaryAction(
              label: 'Save name',
              onPressed: () =>
                  Navigator.of(sheetContext).pop(controller.text.trim()),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (!mounted || nextName == null || nextName == currentName) return;
    final api = PandoraDependencies.of(context).projectExperienceRepository;
    if (api == null) return;
    try {
      await api.renameProject(projectId: widget.project.id, name: nextName);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Project renamed.')));
    } on ProjectExperienceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  String? get _sourceVersionId {
    final preview = _previewVersionId?.trim();
    if (preview != null && preview.isNotEmpty) return preview;
    final production = _projection?.productionVersionId?.trim();
    if (production != null && production.isNotEmpty) return production;
    final candidate = _projection?.candidateVersionId?.trim();
    return candidate == null || candidate.isEmpty ? null : candidate;
  }

  Future<void> _showProjectActions() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: PandoraV2Colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: PandoraV2Colors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Rename project'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_renameProject());
                },
              ),
              ListTile(
                leading: const Icon(Icons.open_in_full_rounded),
                title: const Text('Open full screen'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_openExactPreview());
                },
              ),
              ListTile(
                leading: const Icon(Icons.history_rounded),
                title: const Text('History'),
                subtitle: const Text('Requests, builds, previews and releases'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => ProjectHistoryScreen(
                        project: _snapshot?.project ?? widget.project,
                      ),
                    ),
                  );
                },
              ),
              if (_sourceVersionId != null)
                ListTile(
                  leading: const Icon(Icons.folder_open_rounded),
                  title: const Text('Files'),
                  subtitle: const Text('Available with source access'),
                  onTap: () {
                    final versionId = _sourceVersionId;
                    Navigator.of(sheetContext).pop();
                    if (versionId == null) return;
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => ProjectSourceFilesScreen(
                          project: _snapshot?.project ?? widget.project,
                          versionId: versionId,
                        ),
                      ),
                    );
                  },
                ),
              if (_canPublish)
                ListTile(
                  leading: const Icon(Icons.public_rounded),
                  title: const Text('Publish'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_showPublish());
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPublish() async {
    final snapshot = _snapshot;
    final candidateVersionId = _projection?.candidateVersionId;
    if (candidateVersionId == null || !_canPublish) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pandora is still checking this version.'),
        ),
      );
      return;
    }
    final domainController = TextEditingController(
      text: snapshot?.domain?.domain ?? snapshot?.project.requestedDomain ?? '',
    );
    final approved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PandoraV2Colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Make this public?',
              style: TextStyle(
                color: PandoraV2Colors.ink,
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -.7,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              snapshot?.production == null
                  ? 'Pandora will publish the exact version you just reviewed.'
                  : 'Your current live version stays in history while this reviewed version becomes public.',
              style: pandoraV2Muted,
            ),
            const SizedBox(height: 22),
            TextField(
              controller: domainController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Domain (optional)',
                hintText: 'yourdomain.com',
              ),
            ),
            const SizedBox(height: 22),
            PandoraV2PrimaryAction(
              label: 'Publish',
              onPressed: () {
                final domain = domainController.text.trim();
                if (domain.contains('@')) {
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Enter a domain name, not an email address.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.of(sheetContext).pop(true);
              },
            ),
          ],
        ),
      ),
    );
    if (approved == true && mounted) {
      await _publish(domainController.text.trim(), candidateVersionId);
    }
    domainController.dispose();
  }

  Future<void> _refreshPublishReceipt() async {
    final experience =
        PandoraDependencies.of(context).projectExperienceRepository;
    if (experience == null) return;
    try {
      final receipt = await experience.loadLatestPublishReceipt(
        projectId: widget.project.id,
      );
      if (!mounted) return;
      setState(() => _publishReceipt = receipt);
    } catch (_) {
      // Receipt history is supplemental to the authoritative lifecycle projection.
    }
  }

  Future<void> _watchPublishCompletion(String versionId) async {
    final repository =
        PandoraDependencies.of(context).projectExperienceRepository;
    if (repository == null) {
      throw const ProjectExperienceException(
        'Pandora cannot confirm this publish right now.',
      );
    }

    bool resolved(ProjectExperienceProjection projection) =>
        projection.hasSafeFailure ||
        (projection.state == ProjectExperienceState.live &&
            projection.productionVersionId == versionId);

    ProjectExperienceProjection? transition = _projection;
    if (transition == null || !resolved(transition)) {
      try {
        transition = await repository
            .watchExperience(widget.project.id)
            .firstWhere(resolved)
            .timeout(const Duration(minutes: 2));
      } on TimeoutException {
        throw const ProjectExperienceException(
          'Publishing is still in progress. Pandora has not marked this version live yet.',
        );
      } catch (_) {
        throw const ProjectExperienceException(
          'Pandora cannot confirm this publish right now.',
        );
      }
    }

    if (!mounted) return;
    if (transition.hasSafeFailure) {
      throw ProjectExperienceException(
        transition.safeFailureMessage ??
            'Pandora found something to resolve before this version can go live.',
      );
    }
    await _refreshPublishReceipt();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Live.')));
  }

  Future<void> _publish(String domain, String versionId) async {
    final experience =
        PandoraDependencies.of(context).projectExperienceRepository;
    if (experience == null || versionId.isEmpty || _publishing) return;
    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      await experience.publish(
        projectId: widget.project.id,
        versionId: versionId,
        domain: domain.isEmpty ? null : domain,
        idempotencyKey:
            'pandora-v2-publish:${widget.project.id}:$versionId:${domain.isEmpty ? 'default' : domain}',
      );
      if (!mounted) return;
      final projection = _projection;
      if (projection?.state == ProjectExperienceState.live &&
          projection?.productionVersionId == versionId) {
        await _refreshPublishReceipt();
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Live.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Publishing. Pandora is verifying this exact version.',
            ),
          ),
        );
        await _watchPublishCompletion(versionId);
      }
    } on ProjectExperienceException catch (error) {
      if (!mounted) return;
      final protected = _projection?.productionVersionId != null;
      setState(
        () => _error = protected
            ? '${error.message} Your current live version was not replaced.'
            : error.message,
      );
    } catch (_) {
      if (!mounted) return;
      final protected = _projection?.productionVersionId != null;
      setState(
        () => _error = protected
            ? 'Publishing did not complete. Your current live version was not replaced.'
            : 'Publishing did not complete. Nothing was made public.',
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _dictateChange() async {
    final value = await PandoraNativeIo.dictate();
    if (value == null || !mounted) return;
    _change.text = value;
    _change.selection = TextSelection.collapsed(offset: value.length);
  }

  void _acceptPreviewSelection(PandoraPreviewSelection selection) {
    if (!mounted) return;
    final versionId = _previewVersionId;
    final artifactDigest = versionId == null
        ? null
        : _previewArtifactDigest(
            _previewFiles,
            projectId: widget.project.id,
            versionId: versionId,
          );
    if (versionId == null || artifactDigest == null) {
      setState(() {
        _selectionMode = false;
        _selectedPreviewTarget = null;
        _focusToken = null;
        _error =
            'Pandora cannot bind that selection to the exact preview. Select it again after the preview refreshes.';
      });
      return;
    }
    try {
      final bounds = selection.bounds;
      final token = ProjectFocusToken.create(
        projectId: widget.project.id,
        versionId: versionId,
        artifactDigest: artifactDigest,
        componentId: selection.componentId,
        semanticId: selection.semanticId,
        selector: selection.selector,
        role: selection.role,
        accessibleName: selection.accessibleName,
        route: selection.route,
        sourceFile: selection.sourceFile,
        sourceLine: selection.sourceLine,
        bounds: bounds == null
            ? null
            : ProjectFocusBounds(
                x: bounds.x,
                y: bounds.y,
                width: bounds.width,
                height: bounds.height,
              ),
      );
      setState(() {
        _selectionMode = false;
        _selectedPreviewTarget = selection;
        _focusToken = token;
        _error = null;
      });
    } on FormatException {
      setState(() {
        _selectionMode = false;
        _selectedPreviewTarget = null;
        _focusToken = null;
        _error =
            'Pandora could not identify that object safely. Select it again.';
      });
    }
  }

  void _togglePreviewSelection() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (_selectionMode) {
        _selectedPreviewTarget = null;
        _focusToken = null;
      }
    });
  }

  void _clearPreviewSelection() {
    setState(() {
      _selectionMode = false;
      _selectedPreviewTarget = null;
      _focusToken = null;
    });
  }

  void _dismissIntelligenceReply() {
    setState(() => _intelligenceReply = null);
  }

  void _dismissError() {
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final name = _snapshot?.project.name ?? widget.project.name;
    return ProjectWorkspaceV2View(
      title: name,
      status: _statusLabel,
      statusColor: _statusColor,
      canUndo: _canUndo,
      undoing: _undoing,
      onBack: () => Navigator.of(context).maybePop(),
      onUndo: _undoChange,
      onMore: _showProjectActions,
      loading: _loading,
      previewFiles: _previewFiles,
      previewVersionId: _previewVersionId,
      selectionMode: _selectionMode,
      selectedPreviewTarget: _selectedPreviewTarget,
      canFocus: _projection?.canFocus == true,
      changing: _changing,
      openingPreview: _openingPreview,
      onSelection: _acceptPreviewSelection,
      onToggleSelection: _togglePreviewSelection,
      onOpenPreview: _openExactPreview,
      progressPhase: _projectionProgressPhase,
      liveActivityLabel: _liveActivityLabel,
      liveActivityDetail: _liveActivityDetail,
      onOpenLiveActivity:
          _liveBuildStreamId == null ? null : _openLiveBuildActivity,
      recentlyUpdated: _recentlyUpdated,
      currentVersionVerified: _currentVersionVerified,
      changeDiff: _lastChangeDiff,
      intelligenceReply: _intelligenceReply,
      publishReceipt: _publishReceipt,
      error: _error,
      onClearSelection: _clearPreviewSelection,
      onDismissIntelligence: _dismissIntelligenceReply,
      onDismissError: _dismissError,
      changeController: _change,
      changeEnabled: !_changing && _projection?.canChange == true,
      onSubmit: _requestChange,
      onVoice: _dictateChange,
    );
  }
}
