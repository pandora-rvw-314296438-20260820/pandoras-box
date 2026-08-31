import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/project_experience_api.dart';
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
  ProjectExperienceApi experience, {
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _buildRequested = widget.buildAlreadyRequested;
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

  Future<void> _refreshAndAdvance() async {
    if (_refreshing) return;
    final runtime = PandoraDependencies.of(context).projectRuntime;
    final experience = PandoraDependencies.of(context).projectExperience;
    if (runtime == null || experience == null) {
      setState(
        () => _error = 'Pandora cannot continue this project right now.',
      );
      return;
    }
    _refreshing = true;
    try {
      final snapshot = await runtime.runtime(widget.project.id);
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
          final result = await runtime.createPreview(
            projectId: widget.project.id,
            versionId: candidate.versionId,
            artifactDigest: candidate.artifactDigest,
            idempotencyKey:
                'pandora-v2-preview:${widget.project.id}:${candidate.versionId}',
          );
          if (mounted) {
            setState(() {
              _previewResult = result;
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
      if (mounted && !_ready) {
        _timer?.cancel();
        _timer = Timer(const Duration(seconds: 2), _refreshAndAdvance);
      }
    }
  }

  Future<void> _openExactPreview() async {
    if (_openingPreview) return;
    final candidate = _candidate;
    if (candidate == null) return;
    final experience = PandoraDependencies.of(context).projectExperience;
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
                          child: Padding(
                            padding: const EdgeInsets.all(26),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.project.name.toUpperCase(),
                                  style: const TextStyle(
                                    color: PandoraV2Colors.muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.8,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  _stageTitle,
                                  style: const TextStyle(
                                    color: PandoraV2Colors.ink,
                                    fontSize: 31,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -1.0,
                                    height: 1.05,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(_stageMessage, style: pandoraV2Muted),
                                const Spacer(),
                                if (!_ready)
                                  const LinearProgressIndicator(
                                    minHeight: 2,
                                    color: PandoraV2Colors.ink,
                                    backgroundColor: PandoraV2Colors.soft,
                                  ),
                              ],
                            ),
                          ),
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
                          });
                          unawaited(_refreshAndAdvance());
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_ready)
                      PandoraV2PrimaryAction(
                        label: 'Open project',
                        icon: Icons.arrow_forward_rounded,
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute<void>(
                              builder: (_) => ProjectWorkspaceV2Screen(
                                project: _snapshot?.project ?? widget.project,
                              ),
                            ),
                          );
                        },
                      ),
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
  List<Map<String, Object?>>? _previewFiles;
  String? _previewVersionId;
  String? _error;
  String? _intelligenceReply;
  String? _focusTarget;
  bool _started = false;
  bool _loading = true;
  bool _openingPreview = false;
  bool _changing = false;
  bool _publishing = false;
  bool _undoing = false;
  bool _recentlyUpdated = false;
  _ProjectChangePhase _phase = _ProjectChangePhase.idle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _change.dispose();
    super.dispose();
  }

  ProjectRuntimeCandidate? get _candidate => _snapshot?.candidate;

  bool get _canUndo {
    final candidate = _candidate;
    if (candidate == null || !candidate.canUndo) return false;
    return _snapshot?.production?.versionId != candidate.versionId;
  }

  bool get _canPublish {
    final snapshot = _snapshot;
    final candidate = snapshot?.candidate;
    return candidate != null &&
        snapshot?.verification?.versionId == candidate.versionId &&
        snapshot?.verification?.publishEligible == true &&
        snapshot?.production?.versionId != candidate.versionId;
  }

  bool get _currentVersionVerified {
    final snapshot = _snapshot;
    final candidate = snapshot?.candidate;
    final verification = snapshot?.verification;
    return candidate != null &&
        verification?.versionId == candidate.versionId &&
        verification?.publishEligible == true;
  }

  bool get _currentCandidateIsLive {
    final snapshot = _snapshot;
    final candidate = snapshot?.candidate;
    final production = snapshot?.production;
    return candidate != null &&
        production?.versionId == candidate.versionId &&
        snapshot?.project.isLive == true;
  }

  bool get _currentCandidateIsPublishing {
    final snapshot = _snapshot;
    final candidate = snapshot?.candidate;
    if (candidate == null || snapshot?.project.isLive == true) return false;
    return snapshot?.production?.versionId == candidate.versionId;
  }

  String get _statusLabel {
    switch (_phase) {
      case _ProjectChangePhase.designing:
        return 'Designing';
      case _ProjectChangePhase.building:
        return 'Building';
      case _ProjectChangePhase.checking:
        return 'Checking';
      case _ProjectChangePhase.idle:
        break;
    }
    if (_recentlyUpdated && _currentVersionVerified) return 'Updated';
    if (_currentCandidateIsLive) return 'Live';
    if (_currentCandidateIsPublishing) return 'Publishing · verifying';
    if (_currentVersionVerified) return 'Ready';
    if (_candidate != null) return 'Preview';
    return 'Working';
  }

  Color get _statusColor {
    final label = _statusLabel;
    if (label == 'Updated' || label == 'Live' || label == 'Ready') {
      return PandoraV2Colors.success;
    }
    return PandoraV2Colors.muted;
  }

  Future<List<Map<String, Object?>>?> _readExactPreview(
    ProjectRuntimeSnapshot snapshot,
  ) async {
    final candidate = snapshot.candidate;
    final experience = PandoraDependencies.of(context).projectExperience;
    if (candidate == null || experience == null) return null;
    try {
      return await _loadExactPreviewFiles(
        experience,
        projectId: widget.project.id,
        versionId: candidate.versionId,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _refresh() async {
    final runtime = PandoraDependencies.of(context).projectRuntime;
    if (runtime == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Pandora cannot open this project right now.';
      });
      return;
    }
    try {
      final snapshot = await runtime.runtime(widget.project.id);
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
    final experience = PandoraDependencies.of(context).projectExperience;
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

  List<String> get _focusTargets {
    final targets = <String>['Whole page'];
    final files = _previewFiles;
    if (files == null || files.isEmpty) return targets;
    var html = '';
    for (final file in files) {
      final path = (file['file'] as String? ?? '').toLowerCase();
      if (!path.endsWith('.html')) continue;
      final encoded = file['dataBase64'];
      if (encoded is! String || encoded.isEmpty) continue;
      try {
        html = utf8
            .decode(base64Decode(encoded), allowMalformed: false)
            .toLowerCase();
      } catch (_) {
        continue;
      }
      if (path == 'index.html' || path.endsWith('/index.html')) break;
    }
    if (html.contains('<header') || html.contains('<nav')) {
      targets.add('Header & navigation');
    }
    if (html.contains('<main')) targets.add('Main content');
    if (html.contains('<section')) targets.add('Section');
    if (html.contains('<footer')) targets.add('Footer');
    return targets;
  }

  String _focusBoundRequest(String request) {
    final focus = _focusTarget;
    if (focus == null || focus.isEmpty) return request;
    return 'Focus target: $focus\nRequested change: $request';
  }

  Future<void> _pickFocus() async {
    final targets = _focusTargets;
    final selected = _focusTarget ?? 'Whole page';
    final target = await showModalBottomSheet<String>(
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: Text(
                  'Focus your change',
                  style: TextStyle(
                    color: PandoraV2Colors.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.5,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  'Choose the part of this exact project you want Pandora to change.',
                  style: pandoraV2Muted,
                ),
              ),
              for (final option in targets)
                ListTile(
                  leading: Icon(
                    option == selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                  ),
                  title: Text(option),
                  onTap: () => Navigator.of(sheetContext).pop(option),
                ),
            ],
          ),
        ),
      ),
    );
    if (target == null || !mounted) return;
    setState(() {
      _focusTarget = target == 'Whole page' ? null : target;
    });
  }

  Future<void> _requestChange(String text) async {
    final request = text.trim();
    if (request.length < 4 || _changing) return;
    final dependencies = PandoraDependencies.of(context);
    final experience = dependencies.projectExperience;
    final intelligence = dependencies.intelligence;
    if (experience == null || intelligence == null) {
      setState(
        () => _error = 'Pandora cannot understand that request right now.',
      );
      return;
    }
    final baseVersion = _candidate?.versionId;
    setState(() {
      _changing = true;
      _phase = _ProjectChangePhase.designing;
      _recentlyUpdated = false;
      _error = null;
      _intelligenceReply = null;
    });
    try {
      final turn = await intelligence.chat(
        message: _focusBoundRequest(request),
        projectId: widget.project.id,
      );
      if (!mounted) return;

      if (turn.needsClarification) {
        _change.clear();
        setState(() {
          _changing = false;
          _phase = _ProjectChangePhase.idle;
          _intelligenceReply = turn.clarifyingQuestion ?? turn.reply;
        });
        return;
      }

      if (turn.intent == 'preview') {
        _change.clear();
        setState(() {
          _changing = false;
          _phase = _ProjectChangePhase.idle;
          _intelligenceReply = turn.reply;
        });
        await _openExactPreview();
        return;
      }
      if (turn.intent == 'publish') {
        _change.clear();
        setState(() {
          _changing = false;
          _phase = _ProjectChangePhase.idle;
          _intelligenceReply = turn.reply;
        });
        await _showPublish();
        return;
      }

      final handoff = turn.handoff;
      if (turn.intent != 'change_project' || handoff == null) {
        _change.clear();
        setState(() {
          _changing = false;
          _phase = _ProjectChangePhase.idle;
          _intelligenceReply = turn.reply;
        });
        return;
      }

      final actionRequest = handoff.request.trim();
      if (actionRequest.length < 4) {
        throw const ProjectExperienceException(
          'Pandora needs a clearer change before it can continue.',
        );
      }
      final intentId = await experience.submitIntent(
        projectId: widget.project.id,
        intentText: _focusBoundRequest(actionRequest),
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
      setState(() => _phase = _ProjectChangePhase.building);
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
        _phase = _ProjectChangePhase.idle;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _changing = false;
        _phase = _ProjectChangePhase.idle;
        _error = 'Pandora could not complete that request right now.';
      });
    }
  }

  Future<void> _watchExactChange(String? baseVersion) async {
    final runtime = PandoraDependencies.of(context).projectRuntime;
    if (runtime == null) {
      throw const ProjectExperienceException(
        'Pandora cannot check that change right now.',
      );
    }

    String? nextVersion;
    for (var attempt = 0; attempt < 90; attempt++) {
      if (!mounted) return;
      final snapshot = await runtime.runtime(widget.project.id);
      final candidate = snapshot.candidate;
      final isNewCandidate = candidate != null &&
          (baseVersion == null || candidate.versionId != baseVersion);

      if (isNewCandidate) {
        nextVersion ??= candidate.versionId;
        if (mounted && _phase != _ProjectChangePhase.checking) {
          setState(() => _phase = _ProjectChangePhase.checking);
        }

        List<Map<String, Object?>>? files;
        if (_previewVersionId != candidate.versionId) {
          files = await _readExactPreview(snapshot);
        }
        if (!mounted) return;
        setState(() {
          _snapshot = snapshot;
          if (files != null && files.isNotEmpty) {
            _previewFiles = files;
            _previewVersionId = candidate.versionId;
          }
        });

        final verification = snapshot.verification;
        final verified = verification?.versionId == candidate.versionId &&
            verification?.publishEligible == true;
        if (verified && _previewVersionId == candidate.versionId) {
          _change.clear();
          setState(() {
            _changing = false;
            _phase = _ProjectChangePhase.idle;
            _recentlyUpdated = true;
            _error = null;
          });
          return;
        }

        final runtimeStatus = snapshot.project.runtimeStatus.toLowerCase();
        if (runtimeStatus == 'failed' || runtimeStatus == 'blocked') {
          throw const ProjectExperienceException(
            'Pandora found something to resolve. Your previous project remains available.',
          );
        }
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    if (nextVersion == null) {
      throw const ProjectExperienceException(
        'Pandora is still building that change. Your current project remains available.',
      );
    }
    throw const ProjectExperienceException(
      'Pandora is still checking the new version. It has not been marked ready.',
    );
  }

  Future<void> _undoChange() async {
    final runtime = PandoraDependencies.of(context).projectRuntime;
    final candidate = _candidate;
    if (runtime == null || candidate == null || !_canUndo || _undoing) {
      return;
    }
    setState(() {
      _undoing = true;
      _error = null;
      _intelligenceReply = null;
    });
    try {
      final snapshot = await runtime.undo(
        projectId: widget.project.id,
        versionId: candidate.versionId,
        idempotencyKey:
            'pandora-v2-undo:${widget.project.id}:${candidate.versionId}',
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Undone.')),
      );
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
    final candidate = snapshot?.candidate;
    if (candidate == null || !_canPublish) {
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
                      content:
                          Text('Enter a domain name, not an email address.'),
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
      await _publish(domainController.text.trim());
    }
    domainController.dispose();
  }

  Future<void> _watchPublishCompletion() async {
    for (var attempt = 0; attempt < 45; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      await _refresh();
      if (!mounted) return;
      final snapshot = _snapshot;
      final candidate = snapshot?.candidate;
      final project = snapshot?.project;
      if (candidate != null &&
          snapshot?.production?.versionId == candidate.versionId &&
          snapshot?.project.isLive == true) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Live.')));
        return;
      }
      if (project?.runtimeStatus == 'failed') {
        setState(
          () => _error =
              'Pandora found something to resolve before this version can go live.',
        );
        return;
      }
    }
  }

  Future<void> _publish(String domain) async {
    final runtime = PandoraDependencies.of(context).projectRuntime;
    final candidate = _candidate;
    if (runtime == null || candidate == null || _publishing) return;
    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      await runtime.publish(
        projectId: widget.project.id,
        versionId: candidate.versionId,
        domain: domain.isEmpty ? null : domain,
        idempotencyKey:
            'pandora-v2-publish:${widget.project.id}:${candidate.versionId}:${domain.isEmpty ? 'default' : domain}',
      );
      if (!mounted) return;
      await _refresh();
      if (!mounted) return;
      if (_currentCandidateIsLive) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Live.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Publishing. Pandora is verifying this exact version.'),
          ),
        );
        unawaited(_watchPublishCompletion());
      }
    } catch (_) {
      if (!mounted) return;
      final protected = _snapshot?.production != null;
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
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: PandoraV2Colors.ink,
                                    strokeWidth: 2,
                                  ),
                                )
                              : hasExactPreview
                                  ? PandoraEmbeddedPreview(
                                      key: ValueKey<String>(versionId),
                                      files: files,
                                      versionId: versionId,
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
                        left: 10,
                        child: FilledButton.tonalIcon(
                          onPressed: _changing ? null : _pickFocus,
                          icon: const Icon(
                            Icons.center_focus_strong_rounded,
                            size: 18,
                          ),
                          label: Text(_focusTarget ?? 'Focus'),
                          style: FilledButton.styleFrom(
                            backgroundColor: PandoraV2Colors.surface,
                            foregroundColor: PandoraV2Colors.ink,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    if (hasExactPreview)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: _PreviewIconButton(
                          tooltip: 'Open full screen',
                          icon: Icons.open_in_full_rounded,
                          onPressed: _openingPreview ? null : _openExactPreview,
                        ),
                      ),
                    if (_phase != _ProjectChangePhase.idle)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: _ProjectProgressCapsule(phase: _phase),
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
                hintText: 'Describe your change or goal…',
                enabled: !_changing,
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
                style: TextButton.styleFrom(
                  foregroundColor: PandoraV2Colors.ink,
                ),
                child: Text(undoing ? 'Undoing…' : 'Undo'),
              ),
          ],
        ),
      );
}
