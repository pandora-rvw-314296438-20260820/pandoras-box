import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/project_experience_api.dart';
import '../../core/models/project_journey_models.dart';
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
    if (_ready) return 'Your first version is ready';
    if (_candidate != null) return 'Preparing the exact preview';
    if (_snapshot?.verification?.state == 'checking') {
      return 'Checking your project';
    }
    if (_buildRequested) return 'Building the first version';
    return 'Structuring your project';
  }

  String get _stageMessage {
    if (_ready) {
      return 'Open it, experience it, then tell Pandora what should change.';
    }
    if (_candidate != null) {
      return 'Pandora is turning the verified build into something you can experience.';
    }
    return 'Your project stays here while Pandora handles the technical work underneath.';
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
  String? _error;
  bool _started = false;
  bool _loading = true;
  bool _openingPreview = false;
  bool _changing = false;
  bool _publishing = false;

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

  Future<void> _refresh() async {
    final runtime = PandoraDependencies.of(context).projectRuntime;
    if (runtime == null) {
      setState(() {
        _loading = false;
        _error = 'Pandora cannot open this project right now.';
      });
      return;
    }
    try {
      final snapshot = await runtime.runtime(widget.project.id);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Pandora could not refresh this project right now.';
      });
    }
  }

  ProjectRuntimeCandidate? get _candidate => _snapshot?.candidate;

  String? get _remotePreview {
    final candidate = _candidate;
    if (candidate == null) return _safeHttps(_snapshot?.project.previewUrl);
    final preview = _snapshot?.preview;
    if (preview != null && preview.versionId == candidate.versionId) {
      return _safeHttps(preview.url);
    }
    return _safeHttps(_snapshot?.project.previewUrl);
  }

  String get _subtitle {
    final snapshot = _snapshot;
    final candidate = _candidate;
    final production = snapshot?.production;
    if (candidate != null && production?.versionId == candidate.versionId) {
      if (snapshot?.project.isLive == true) {
        final live = _safeHttps(snapshot?.project.liveUrl ?? production?.url);
        return live == null ? 'Live' : 'Live · ${Uri.parse(live).host}';
      }
      return 'Publishing · verifying';
    }
    if (snapshot?.verification?.publishEligible == true) {
      return 'Ready to publish';
    }
    if (candidate != null) return 'Preview ready';
    if (snapshot?.project.isLive == true) {
      final live = _safeHttps(snapshot?.project.liveUrl);
      return live == null ? 'Live' : 'Live · ${Uri.parse(live).host}';
    }
    return 'Working';
  }

  Future<void> _openPreview() async {
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
      final files = await _loadExactPreviewFiles(
        experience,
        projectId: widget.project.id,
        versionId: candidate.versionId,
      );
      if (await PandoraNativeIo.openPreviewBundle(files)) return;
    } catch (_) {
      // Fall back to a verified https preview below.
    } finally {
      if (mounted) setState(() => _openingPreview = false);
    }
    final url = _remotePreview;
    if (url != null && await PandoraNativeIo.openExternalUrl(url)) return;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That project preview is not available yet.'),
        ),
      );
    }
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
      _error = null;
      _intelligenceReply = null;
    });
    try {
      final turn = await intelligence.chat(
        message: request,
        projectId: widget.project.id,
      );
      if (!mounted) return;

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
        await _openPreview();
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
      if (turn.intent != 'change_project' || handoff == null) {
        _change.clear();
        setState(() {
          _changing = false;
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
          'Pandora is still preparing that change. It will continue in the background.',
        );
      }

      // The durable source-convergence worker will also pick up this exact active
      // ProjectSpec if the app closes before this immediate request completes.
      await experience.requestBuild(
        projectId: widget.project.id,
        idempotencyKey:
            'pandora-v2-change-build:${widget.project.id}:$intentId',
      );
      if (!mounted) return;
      _change.clear();
      setState(() {
        _changing = false;
        _intelligenceReply = null;
      });
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ProjectBuildExperienceV2Screen(
            project: _snapshot?.project ?? widget.project,
            baseVersionId: baseVersion,
            buildAlreadyRequested: true,
          ),
        ),
      );
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
        _error =
            'Pandora could not understand or start that request right now.';
      });
    }
  }

  Future<void> _showPublish() async {
    final snapshot = _snapshot;
    final candidate = snapshot?.candidate;
    if (candidate == null ||
        snapshot?.verification?.publishEligible != true ||
        snapshot?.production?.versionId == candidate.versionId) {
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
                hintText: 'plpboracay.com',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'If you enter an address, use a domain name rather than an email address.',
              style: pandoraV2Muted,
            ),
            const SizedBox(height: 22),
            PandoraV2PrimaryAction(
              label: 'Publish',
              onPressed: () {
                final domain = domainController.text.trim();
                if (domain.contains('@')) {
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        'That looks like an email address. Try ${domain.split('@').first}.com instead.',
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
    if (approved != true || !mounted) return;
    await _publish(domainController.text.trim());
    domainController.dispose();
  }

  Future<void> _watchPublishCompletion() async {
    for (var attempt = 0; attempt < 45; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      await _refresh();
      if (!mounted) return;
      final project = _snapshot?.project;
      if (project?.isLive == true) {
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
      if (_snapshot?.project.isLive == true) {
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
    final objective =
        (_snapshot?.project.objective ?? widget.project.objective).trim();
    return Scaffold(
      backgroundColor: PandoraV2Colors.canvas,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: PandoraV2ObjectHeader(
                title: _snapshot?.project.name ?? widget.project.name,
                subtitle: _subtitle,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Material(
                  color: PandoraV2Colors.surface,
                  borderRadius: BorderRadius.circular(22),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _loading || _openingPreview ? null : _openPreview,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        border: Border.all(color: PandoraV2Colors.line),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: _loading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: PandoraV2Colors.ink,
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'CURRENT OBJECT',
                                      style: TextStyle(
                                        color: PandoraV2Colors.muted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (_candidate != null)
                                      const Icon(
                                        Icons.open_in_full_rounded,
                                        size: 20,
                                        color: PandoraV2Colors.ink,
                                      ),
                                  ],
                                ),
                                const Spacer(),
                                Text(
                                  _snapshot?.project.name ??
                                      widget.project.name,
                                  style: const TextStyle(
                                    color: PandoraV2Colors.ink,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -1.1,
                                    height: 1.04,
                                  ),
                                ),
                                if (objective.isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  Text(
                                    objective,
                                    maxLines: 5,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: PandoraV2Colors.muted,
                                      fontSize: 16,
                                      height: 1.42,
                                    ),
                                  ),
                                ],
                                const Spacer(),
                                Text(
                                  _candidate == null
                                      ? 'Tap to build the first version'
                                      : 'Tap anywhere to experience the exact project',
                                  style: const TextStyle(
                                    color: PandoraV2Colors.ink,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
            if (_intelligenceReply != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: PandoraV2InlineMessage(
                  title: 'Pandora',
                  message: _intelligenceReply!,
                  actionLabel: 'Dismiss',
                  onAction: () => setState(() => _intelligenceReply = null),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
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
                20,
                6,
                20,
                14 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                children: [
                  if (_snapshot?.verification?.publishEligible == true &&
                      _candidate != null &&
                      _snapshot?.production?.versionId !=
                          _candidate?.versionId) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _subtitle,
                            style: const TextStyle(
                              color: PandoraV2Colors.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _publishing ? null : _showPublish,
                          style: TextButton.styleFrom(
                            foregroundColor: PandoraV2Colors.ink,
                          ),
                          child: Text(_publishing ? 'Publishing…' : 'Publish'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  PandoraV2IntentSurface(
                    controller: _change,
                    hintText: 'Tell Pandora what should change…',
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
                  if (_changing) ...[
                    const SizedBox(height: 8),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Preparing your change…',
                        style: pandoraV2Muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
