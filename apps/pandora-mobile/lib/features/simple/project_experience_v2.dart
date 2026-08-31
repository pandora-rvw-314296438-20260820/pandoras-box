import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_intelligence_api.dart';
import '../../core/data/project_experience_api.dart';
import '../../core/data/project_experience_repository.dart';
import '../../core/models/project_experience_projection.dart';
import '../../core/models/project_journey_models.dart';
import '../../core/platform/pandora_embedded_preview.dart';
import '../../core/platform/pandora_native_io.dart';
import 'pandora_v2_ui.dart';

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
    extends State<ProjectBuildExperienceV2Screen> {
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

  static const _flowTimeout = Duration(minutes: 2);

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
    _timer?.cancel();
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

  Future<void> _refreshAndAdvance() async {
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

      final candidate = _candidate;
      if (candidate == null) {
        if (!_buildRequested) {
          _buildRequested = true;
          try {
            await experience.requestBuild(
              projectId: widget.project.id,
              idempotencyKey: 'pandora-v2-build:${widget.project.id}',
            );
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
      if (mounted && !_ready && !_flowExpired) {
        _timer?.cancel();
        _timer = Timer(const Duration(seconds: 2), _refreshAndAdvance);
      }
    }
  }

  Future<void> _openExactPreview() async {
    if (_openingPreview) return;
    final candidate = _candidate;
    if (candidate == null) return;
    final experience = PandoraDependencies.of(context).projectExperienceRepository;
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

  Widget _buildStageSurface() => Center(
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
      child: PandoraEmbeddedPreview(
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

enum _ProjectChangePhase { idle, designing, building, checking }

class ProjectWorkspaceV2Screen extends StatefulWidget {
  const ProjectWorkspaceV2Screen({super.key, required this.project});

  final CustomerProject project;

  @override
  State<ProjectWorkspaceV2Screen> createState() =>
      _ProjectWorkspaceV2ScreenState();
}

class _ProjectWorkspaceV2ScreenState extends State<ProjectWorkspaceV2Screen> {
  final _change = TextEditingController();
  ProjectRuntimeSnapshot? _snapshot;
  ProjectExperienceProjection? _projection;
  StreamSubscription<ProjectExperienceProjection>? _projectionSubscription;
  List<Map<String, Object?>>? _previewFiles;
  String? _previewVersionId;
  String? _error;
  String? _intelligenceReply;
  bool _started = false;
  bool _loading = true;
  bool _openingPreview = false;
  bool _changing = false;
  bool _publishing = false;
  bool _undoing = false;
  bool _recentlyUpdated = false;
  bool _selectionMode = false;
  PandoraPreviewSelection? _selectedPreviewTarget;
  Timer? _previewRetryTimer;
  String? _previewRetryVersionId;
  int _previewRetryCount = 0;

  static const _previewRetryLimit = 6;

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
    _previewRetryTimer?.cancel();
    _projectionSubscription?.cancel();
    _change.dispose();
    super.dispose();
  }

  ProjectRuntimeCandidate? get _candidate => _snapshot?.candidate;

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
    _projectionSubscription = repository.watchExperience(widget.project.id).listen(
      _acceptProjection,
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _error ??= 'Pandora cannot refresh this project state right now.';
        });
      },
    );
  }

  void _acceptProjection(ProjectExperienceProjection next) {
    if (!mounted) return;
    final current = _projection;
    if (current != null && !next.isNewerThan(current)) return;
    final targetVersion = next.candidateVersionId ?? next.currentVersionId;
    final shouldHydrate =
        targetVersion != null && targetVersion != _previewVersionId;
    setState(() {
      _projection = next;
      _loading = false;
      if (next.hasSafeFailure && _error == null) {
        _error = next.safeFailureMessage ??
            'Pandora found something to resolve. Your current project remains available.';
      }
    });
    if (shouldHydrate) unawaited(_refresh());
  }

  _ProjectChangePhase? get _projectionProgressPhase {
    final projection = _projection;
    if (projection == null) {
      return _changing ? _ProjectChangePhase.designing : null;
    }
    if (projection.isUpdating) {
      return projection.buildPhase?.toLowerCase() == 'checking'
          ? _ProjectChangePhase.checking
          : _ProjectChangePhase.building;
    }
    switch (projection.state) {
      case ProjectExperienceState.understand:
      case ProjectExperienceState.change:
        return _ProjectChangePhase.designing;
      case ProjectExperienceState.build:
      case ProjectExperienceState.rebuild:
        return projection.buildPhase?.toLowerCase() == 'checking'
            ? _ProjectChangePhase.checking
            : _ProjectChangePhase.building;
      case ProjectExperienceState.review:
        return _ProjectChangePhase.checking;
      default:
        return null;
    }
  }

  bool get _canUndo =>
      _projection?.canUndo == true && _projection?.candidateVersionId != null;

  bool get _canPublish =>
      _projection?.canPublish == true &&
      _projection?.candidateVersionId != null;

  bool get _currentVersionVerified =>
      _projection?.currentVerified == true || _projection?.canPublish == true;

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

  Future<List<Map<String, Object?>>?> _readExactPreview(
    ProjectRuntimeSnapshot snapshot,
  ) async {
    final candidate = snapshot.candidate;
    final experience = PandoraDependencies.of(context).projectExperienceRepository;
    if (candidate == null || experience == null) return null;
    try {
      return await _loadExactPreviewFiles(
        experience,
        projectId: widget.project.id,
        versionId: candidate.versionId,
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
    if (runtime == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Pandora cannot open this project right now.';
      });
      return;
    }
    try {
      final snapshot = await experience.runtime(widget.project.id);
      if (!mounted) return;
      List<Map<String, Object?>>? files;
      final candidate = snapshot.candidate;
      if (candidate != null && _previewVersionId != candidate.versionId) {
        files = await _readExactPreview(snapshot);
      }
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
        _error = null;
        if (files != null && files.isNotEmpty && candidate != null) {
          _previewFiles = files;
          _previewVersionId = candidate.versionId;
        }
      });
      if (candidate != null) {
        _schedulePreviewRetry(candidate.versionId);
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
    final candidate = _candidate;
    if (candidate == null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ProjectBuildExperienceV2Screen(project: widget.project),
        ),
      );
      return;
    }
    final experience = PandoraDependencies.of(context).projectExperienceRepository;
    if (experience == null) return;
    setState(() => _openingPreview = true);
    try {
      var files =
          _previewVersionId == candidate.versionId ? _previewFiles : null;
      files ??= await _loadExactPreviewFiles(
        experience,
        projectId: widget.project.id,
        versionId: candidate.versionId,
      );
      if (!mounted) return;
      setState(() {
        _previewFiles = files;
        _previewVersionId = candidate.versionId;
      });
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

  Future<void> _requestChange(String text) async {
    final request = text.trim();
    if (request.length < 4 || _changing || _projection?.canChange != true) {
      return;
    }
    final experience = PandoraDependencies.of(context).projectExperienceRepository;
    if (experience == null) {
      setState(() => _error = 'Pandora cannot save that change right now.');
      return;
    }
    final baseVersion = _projection?.candidateVersionId ??
        _projection?.currentVersionId ??
        _candidate?.versionId;
    setState(() {
      _changing = true;
      _recentlyUpdated = false;
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
      if (selectedTarget != null) {
        actionRequest =
            '${selectedTarget.intentContext}\nOwner change: $actionRequest';
      }

      if (actionRequest.length < 4) {
        throw const ProjectExperienceException(
          'Pandora needs a clearer change before it can continue.',
        );
      }
      final intentId = await experience.submitIntent(
        projectId: widget.project.id,
        intentText: actionRequest,
        intentKind: 'change',
        idempotencyKey:
            'pandora-v2-change:${widget.project.id}:${DateTime.now().microsecondsSinceEpoch}',
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
    final experience = PandoraDependencies.of(context).projectExperienceRepository;
    if (repository == null || experience == null) {
      throw const ProjectExperienceException(
        'Pandora cannot check that change right now.',
      );
    }

    bool resolved(ProjectExperienceProjection projection) {
      if (projection.hasSafeFailure) return true;
      final candidateVersion = projection.candidateVersionId;
      if (candidateVersion == null ||
          (baseVersion != null && candidateVersion == baseVersion)) {
        return false;
      }
      return projection.canPublish ||
          projection.candidateVerificationState.toUpperCase() == 'PASS' ||
          projection.state == ProjectExperienceState.review;
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
    if (transition.hasSafeFailure) {
      throw ProjectExperienceException(
        transition.safeFailureMessage ??
            'Pandora found something to resolve. Your previous project remains available.',
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
        'Pandora verified the new version, but its exact preview is still preparing.',
      );
    }

    _change.clear();
    setState(() {
      _previewFiles = files;
      _previewVersionId = versionId;
      _changing = false;
      _recentlyUpdated = true;
      _selectionMode = false;
      _selectedPreviewTarget = null;
      _error = null;
    });
  }

  Future<void> _undoChange() async {
    final experience =
        PandoraDependencies.of(context).projectExperienceRepository;
    final versionId = _projection?.candidateVersionId;
    if (runtime == null || versionId == null || !_canUndo || _undoing) {
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
      final files = await _readExactPreview(snapshot);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _recentlyUpdated = false;
        if (files != null && files.isNotEmpty && snapshot.candidate != null) {
          _previewFiles = files;
          _previewVersionId = snapshot.candidate!.versionId;
        }
      });
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
                leading: const Icon(Icons.open_in_full_rounded),
                title: const Text('Open full screen'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_openExactPreview());
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
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Live.')));
  }

  Future<void> _publish(String domain, String versionId) async {
    final experience =
        PandoraDependencies.of(context).projectExperienceRepository;
    if (runtime == null || versionId.isEmpty || _publishing) return;
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

  @override
  Widget build(BuildContext context) {
    final name = _snapshot?.project.name ?? widget.project.name;
    final files = _previewFiles;
    final versionId = _previewVersionId;
    final hasExactPreview = files != null &&
        files.isNotEmpty &&
        versionId != null &&
        versionId.isNotEmpty;
    final progressPhase = _projectionProgressPhase;

    return Scaffold(
      backgroundColor: PandoraV2Colors.canvas,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _LiveProjectHeader(
              title: name,
              status: _statusLabel,
              statusColor: _statusColor,
              canUndo: _canUndo,
              undoing: _undoing,
              onBack: () => Navigator.of(context).maybePop(),
              onUndo: _undoChange,
              onMore: _showProjectActions,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: PandoraV2Colors.surface,
                            border: Border.all(color: PandoraV2Colors.line),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: _loading
                              ? _ExactPreviewLoadingSurface(projectName: name)
                              : hasExactPreview
                                  ? PandoraEmbeddedPreview(
                                      key: ValueKey<String>(versionId),
                                      files: files,
                                      versionId: versionId,
                                      selectionEnabled: _selectionMode,
                                      selectedSelector:
                                          _selectedPreviewTarget?.selector,
                                      onSelection: (selection) {
                                        if (!mounted) return;
                                        setState(() {
                                          _selectionMode = false;
                                          _selectedPreviewTarget = selection;
                                        });
                                      },
                                      fallback: _ExactPreviewFallback(
                                        projectName: name,
                                        onOpen: _openExactPreview,
                                      ),
                                    )
                                  : _ExactPreviewFallback(
                                      projectName: name,
                                      onOpen: _openExactPreview,
                                    ),
                        ),
                      ),
                    ),
                    if (hasExactPreview)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _PreviewIconButton(
                              tooltip: _selectionMode
                                  ? 'Cancel selection'
                                  : 'Select something to change',
                              icon: _selectionMode
                                  ? Icons.close_rounded
                                  : Icons.touch_app_outlined,
                              onPressed:
                                  _changing || _projection?.canFocus != true
                                      ? null
                                      : () => setState(() {
                                            _selectionMode = !_selectionMode;
                                            if (_selectionMode) {
                                              _selectedPreviewTarget = null;
                                            }
                                          }),
                            ),
                            const SizedBox(width: 6),
                            _PreviewIconButton(
                              tooltip: 'Open full screen',
                              icon: Icons.open_in_full_rounded,
                              onPressed:
                                  _openingPreview ? null : _openExactPreview,
                            ),
                          ],
                        ),
                      ),
                    if (progressPhase != null)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: _ProjectProgressCapsule(phase: progressPhase),
                      )
                    else if (_recentlyUpdated && _currentVersionVerified)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: _VerifiedChangeCapsule(
                          canUndo: _canUndo,
                          undoing: _undoing,
                          onUndo: _undoChange,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_selectionMode || _selectedPreviewTarget != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: _SelectionContextCapsule(
                  selecting: _selectionMode,
                  selection: _selectedPreviewTarget,
                  onClear: () => setState(() {
                    _selectionMode = false;
                    _selectedPreviewTarget = null;
                  }),
                ),
              ),
            if (_intelligenceReply != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: PandoraV2InlineMessage(
                  title: 'Pandora',
                  message: _intelligenceReply!,
                  actionLabel: 'Dismiss',
                  onAction: () => setState(() => _intelligenceReply = null),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: PandoraV2InlineMessage(
                  title: 'Project unchanged',
                  message: _error!,
                  actionLabel: 'Dismiss',
                  onAction: () => setState(() => _error = null),
                  danger: true,
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                4,
                12,
                10 + MediaQuery.paddingOf(context).bottom,
              ),
              child: PandoraV2IntentSurface(
                controller: _change,
                hintText: _selectedPreviewTarget == null
                    ? 'Tell Pandora what to change…'
                    : 'Change ${_selectedPreviewTarget!.label}…',
                enabled: !_changing && _projection?.canChange == true,
                onSubmit: _requestChange,
                onVoice: () async {
                  final value = await PandoraNativeIo.dictate();
                  if (value != null && mounted) {
                    _change.text = value;
                    _change.selection = TextSelection.collapsed(
                      offset: value.length,
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionContextCapsule extends StatelessWidget {
  const _SelectionContextCapsule({
    required this.selecting,
    required this.selection,
    required this.onClear,
  });

  final bool selecting;
  final PandoraPreviewSelection? selection;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final label = selecting
        ? 'Tap something in the project'
        : 'Selected · ${selection?.label ?? 'element'}';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: PandoraV2Colors.soft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PandoraV2Colors.line),
      ),
      child: Row(
        children: [
          Icon(
            selecting ? Icons.touch_app_outlined : Icons.adjust_rounded,
            size: 18,
            color: PandoraV2Colors.ink,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: PandoraV2Colors.ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              foregroundColor: PandoraV2Colors.muted,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 9),
            ),
            child: Text(selecting ? 'Cancel' : 'Clear'),
          ),
        ],
      ),
    );
  }
}

class _LiveProjectHeader extends StatelessWidget {
  const _LiveProjectHeader({
    required this.title,
    required this.status,
    required this.statusColor,
    required this.canUndo,
    required this.undoing,
    required this.onBack,
    required this.onUndo,
    required this.onMore,
  });

  final String title;
  final String status;
  final Color statusColor;
  final bool canUndo;
  final bool undoing;
  final VoidCallback onBack;
  final VoidCallback onUndo;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 58,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                color: PandoraV2Colors.ink,
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PandoraV2Colors.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PandoraV2Colors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (canUndo)
                TextButton(
                  onPressed: undoing ? null : onUndo,
                  style: TextButton.styleFrom(
                    foregroundColor: PandoraV2Colors.ink,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: Text(undoing ? 'Undoing…' : 'Undo'),
                ),
              IconButton(
                tooltip: 'More',
                onPressed: onMore,
                icon: const Icon(Icons.more_horiz_rounded),
                color: PandoraV2Colors.ink,
              ),
            ],
          ),
        ),
      );
}

class _ExactPreviewLoadingSurface extends StatelessWidget {
  const _ExactPreviewLoadingSurface({required this.projectName});

  final String projectName;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: PandoraV2Colors.soft,
                    shape: BoxShape.circle,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: PandoraV2Colors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    projectName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PandoraV2Colors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Container(
              height: 18,
              width: double.infinity,
              decoration: BoxDecoration(
                color: PandoraV2Colors.soft,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 10),
            FractionallySizedBox(
              widthFactor: .72,
              child: Container(
                height: 14,
                decoration: BoxDecoration(
                  color: PandoraV2Colors.soft,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              height: 132,
              width: double.infinity,
              decoration: BoxDecoration(
                color: PandoraV2Colors.soft,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const Spacer(),
          ],
        ),
      );
}

class _ExactPreviewFallback extends StatelessWidget {
  const _ExactPreviewFallback({
    required this.projectName,
    required this.onOpen,
  });

  final String projectName;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Material(
        color: PandoraV2Colors.surface,
        child: InkWell(
          onTap: onOpen,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: const BoxDecoration(
                      color: PandoraV2Colors.soft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.language_rounded,
                      color: PandoraV2Colors.ink,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    projectName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: PandoraV2Colors.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Open the exact project preview',
                    textAlign: TextAlign.center,
                    style: pandoraV2Muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _PreviewIconButton extends StatelessWidget {
  const _PreviewIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Material(
        color: PandoraV2Colors.surface.withValues(alpha: .94),
        elevation: 2,
        shadowColor: Colors.black12,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, size: 19),
          color: PandoraV2Colors.ink,
        ),
      );
}

class _ProjectProgressCapsule extends StatelessWidget {
  const _ProjectProgressCapsule({required this.phase});

  final _ProjectChangePhase phase;

  int get _activeIndex => switch (phase) {
        _ProjectChangePhase.designing => 0,
        _ProjectChangePhase.building => 1,
        _ProjectChangePhase.checking => 2,
        _ProjectChangePhase.idle => 2,
      };

  @override
  Widget build(BuildContext context) {
    const labels = ['Designing', 'Building', 'Checking'];
    final active = _activeIndex;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: PandoraV2Colors.surface.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PandoraV2Colors.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            if (index > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 7),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 14,
                  color: PandoraV2Colors.muted,
                ),
              ),
            if (index == active)
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: 6),
                decoration: const BoxDecoration(
                  color: PandoraV2Colors.ink,
                  shape: BoxShape.circle,
                ),
              ),
            Text(
              labels[index],
              style: TextStyle(
                color: index <= active
                    ? PandoraV2Colors.ink
                    : PandoraV2Colors.muted,
                fontSize: 12,
                fontWeight: index == active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VerifiedChangeCapsule extends StatelessWidget {
  const _VerifiedChangeCapsule({
    required this.canUndo,
    required this.undoing,
    required this.onUndo,
  });

  final bool canUndo;
  final bool undoing;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: PandoraV2Colors.surface.withValues(alpha: .96),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: PandoraV2Colors.line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Color(0xFFE9F5EF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 16,
                color: PandoraV2Colors.success,
              ),
            ),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                'Verified change',
                style: TextStyle(
                  color: PandoraV2Colors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (canUndo)
              TextButton(
                onPressed: undoing ? null : onUndo,
                style:
                    TextButton.styleFrom(foregroundColor: PandoraV2Colors.ink),
                child: Text(undoing ? 'Undoing…' : 'Undo'),
              ),
          ],
        ),
      );
}
