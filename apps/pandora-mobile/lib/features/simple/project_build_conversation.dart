import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/analytics/owner_analytics.dart';
import '../../core/data/project_experience_api.dart';
import '../../core/models/project_experience_projection.dart';
import '../../core/models/project_journey_models.dart';
import 'live_build_theatre/live_build_theatre.dart';
import 'live_build_theatre/project_build_stream_theatre_projection.dart';
import 'pandora_v2_ui.dart';
import 'professional_build_plan.dart';
import 'project_build_snapshot_render_coalescer.dart';
import 'project_experience_v2.dart';

class ProjectBuildConversationScreen extends StatefulWidget {
  const ProjectBuildConversationScreen({
    super.key,
    required this.project,
    required this.originalIntent,
    required this.understanding,
    required this.buildStart,
    this.buildClickedAt,
  });

  final CustomerProject project;
  final String originalIntent;
  final OwnerProjectUnderstanding understanding;
  final ProjectBuildStart buildStart;
  final DateTime? buildClickedAt;

  @override
  State<ProjectBuildConversationScreen> createState() =>
      _ProjectBuildConversationScreenState();
}

class _ProjectBuildConversationScreenState
    extends State<ProjectBuildConversationScreen> {
  Stream<ProjectBuildStreamSnapshot>? _stream;
  Stream<ProjectExperienceProjection>? _experienceStream;
  bool _autoOpenedResult = false;
  bool _intentExpanded = false;
  bool _wasReconnecting = false;
  final Set<String> _capturedAnalytics = <String>{};

  Duration? _elapsed(DateTime? occurredAt) {
    final start = widget.buildClickedAt;
    if (start == null || occurredAt == null || occurredAt.isBefore(start)) {
      return null;
    }
    return occurredAt.difference(start);
  }

  void _captureMilestones(ProjectBuildStreamSnapshot snapshot) {
    final events = List<ProjectBuildStreamEvent>.of(snapshot.events)
      ..sort((left, right) => left.sequence.compareTo(right.sequence));

    void captureOnce(
      String key,
      OwnerAnalyticsEvent kind, {
      ProjectBuildStreamEvent? event,
      int? count,
      String? status,
      String? resultClass,
      String? errorCode,
    }) {
      if (!_capturedAnalytics.add(key)) return;
      unawaited(
        OwnerAnalytics.shared.capture(
          kind,
          projectKey: widget.project.projectKey,
          projectId: widget.project.id,
          buildJobId: event?.buildJobId ??
              snapshot.buildJobId ??
              widget.buildStart.buildJobId,
          streamId: widget.buildStart.streamId,
          projectVersionId: snapshot.projectVersionId,
          sequence: event?.sequence,
          count: count,
          status: status,
          resultClass: resultClass,
          errorCode: errorCode,
          duration: _elapsed(event?.createdAt),
        ),
      );
    }

    if (events.isNotEmpty) {
      captureOnce(
        'first_stream_event',
        OwnerAnalyticsEvent.firstStreamEvent,
        event: events.first,
      );
    }

    for (final event in events) {
      switch (event.eventType) {
        case 'code_chunk':
          if ((event.contentChunk ?? '').isNotEmpty) {
            captureOnce(
              'first_code',
              OwnerAnalyticsEvent.firstCode,
              event: event,
            );
          }
          break;
        case 'file_completed':
          captureOnce(
            'file_complete:${event.sequence}',
            OwnerAnalyticsEvent.fileComplete,
            event: event,
          );
          break;
        case 'generation_completed':
          captureOnce(
            'source_complete',
            OwnerAnalyticsEvent.sourceComplete,
            event: event,
          );
          break;
        case 'preview_ready':
          captureOnce(
            'preview_ready',
            OwnerAnalyticsEvent.previewReady,
            event: event,
          );
          break;
        case 'repair_started':
          captureOnce(
            'repair_started:${event.sequence}',
            OwnerAnalyticsEvent.repairStarted,
            event: event,
          );
          break;
        case 'repair_completed':
          captureOnce(
            'repair_completed:${event.sequence}',
            OwnerAnalyticsEvent.repairCompleted,
            event: event,
          );
          break;
      }
    }

    if (snapshot.historyGapDueToRetention) {
      captureOnce('history_gap', OwnerAnalyticsEvent.historyGap);
    }
    if (snapshot.reconnecting && !_wasReconnecting) {
      captureOnce(
        'stream_reconnected:${snapshot.latestSequence}',
        OwnerAnalyticsEvent.streamReconnected,
        count: snapshot.latestSequence,
        status: 'reconnecting',
      );
    }
    final terminalError = snapshot.publicErrorCode?.trim().toUpperCase();
    if (terminalError == 'BUILD_DEADLINE_EXCEEDED' ||
        terminalError == 'BUILD_LEASE_RETRY_EXHAUSTED') {
      captureOnce(
        'build_stalled:$terminalError',
        OwnerAnalyticsEvent.buildStalled,
        status: snapshot.buildStatus ?? 'failed',
        resultClass: 'runtime_stalled',
        errorCode: terminalError,
      );
      captureOnce(
        'funnel_drop_off:$terminalError',
        OwnerAnalyticsEvent.funnelDropOff,
        status: snapshot.buildStatus ?? 'failed',
        resultClass: 'build_stalled',
        errorCode: terminalError,
      );
    }
    if (terminalError == 'VERIFICATION_FAILED') {
      captureOnce(
        'verification_failed:$terminalError',
        OwnerAnalyticsEvent.verificationFailed,
        status: snapshot.buildStatus ?? 'failed',
        resultClass: 'verification_failed',
        errorCode: terminalError,
      );
      captureOnce(
        'funnel_drop_off:$terminalError',
        OwnerAnalyticsEvent.funnelDropOff,
        status: snapshot.buildStatus ?? 'failed',
        resultClass: 'verification_failed',
        errorCode: terminalError,
      );
    }
    _wasReconnecting = snapshot.reconnecting;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stream != null && _experienceStream != null) return;
    final repository =
        PandoraDependencies.of(context).projectExperienceRepository;
    if (repository == null) return;
    _stream ??= coalesceProjectBuildSnapshotsForRendering(
      () => repository.watchResilientBuildStream(
        projectId: widget.project.id,
        streamId: widget.buildStart.streamId,
      ),
    );
    _experienceStream ??= repository.watchExperience(widget.project.id);
  }

  void _maybeAutoOpenResult(ProjectExperienceProjection projection) {
    if (_autoOpenedResult || !mounted) return;
    final resultReady = projection.state == ProjectExperienceState.review &&
        (projection.currentVersionId != null ||
            projection.candidateVersionId != null);
    if (!resultReady) return;
    _autoOpenedResult = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openProject();
    });
  }

  void _openProject() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ProjectWorkspaceV2Screen(project: widget.project),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stream = _stream;
    final experienceStream = _experienceStream;

    return Scaffold(
      backgroundColor: PandoraV2Colors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PandoraV2Page(
                scrollable: false,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    PandoraV2ObjectHeader(title: widget.project.name),
                    const SizedBox(height: 28),
                    const _ConversationLabel(label: 'You'),
                    const SizedBox(height: 8),
                    _CollapsibleIntent(
                      text: widget.originalIntent,
                      expanded: _intentExpanded,
                      onToggle: () =>
                          setState(() => _intentExpanded = !_intentExpanded),
                    ),
                    const SizedBox(height: 24),
                    const _ConversationLabel(label: 'Pandora'),
                    const SizedBox(height: 8),
                    PandoraSimpleBuildPlan(
                      understanding: widget.understanding,
                      showDeliveryPromise: false,
                    ),
                    const SizedBox(height: 20),
                    if (stream == null)
                      const PandoraV2InlineMessage(
                        title: 'Live build stream unavailable',
                        message:
                            'The build did not expose a readable live stream.',
                        danger: true,
                      )
                    else
                      StreamBuilder<ProjectBuildStreamSnapshot>(
                        stream: stream,
                        initialData: const ProjectBuildStreamSnapshot.empty(),
                        builder: (context, snapshot) {
                          final streamState = snapshot.data ??
                              const ProjectBuildStreamSnapshot.empty();
                          _captureMilestones(streamState);
                          if (experienceStream == null) {
                            return _LiveBuildProjection(
                              streamId: widget.buildStart.streamId,
                              snapshot: streamState,
                              disconnected: snapshot.hasError,
                              onOpenProject: _openProject,
                            );
                          }
                          return StreamBuilder<ProjectExperienceProjection>(
                            stream: experienceStream,
                            builder: (context, experienceSnapshot) {
                              final experience = experienceSnapshot.data;
                              if (experience != null) {
                                _maybeAutoOpenResult(experience);
                              }
                              return _LiveBuildProjection(
                                streamId: widget.buildStart.streamId,
                                snapshot: streamState,
                                disconnected: snapshot.hasError,
                                onOpenProject: _openProject,
                                experience: experience,
                              );
                            },
                          );
                        },
                      ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveBuildProjection extends StatelessWidget {
  const _LiveBuildProjection({
    required this.streamId,
    required this.snapshot,
    required this.disconnected,
    required this.onOpenProject,
    this.experience,
  });

  final String streamId;
  final ProjectBuildStreamSnapshot snapshot;
  final bool disconnected;
  final VoidCallback onOpenProject;
  final ProjectExperienceProjection? experience;

  @override
  Widget build(BuildContext context) {
    if (snapshot.requiresReplay) {
      return _ConversationBuildNotice(
        title: experience?.statusLabel ?? 'Working',
        message: experience?.publicMessage ??
            'Pandora is reconnecting to the same build.',
      );
    }

    if (snapshot.events.isEmpty) {
      if (snapshot.historyGapDueToRetention) {
        return _ConversationBuildNotice(
          title: experience?.statusLabel ?? 'Build status',
          message: experience?.publicMessage ??
              'Some earlier live build activity is no longer available. Pandora is showing the saved build state.',
        );
      }
      if (snapshot.latestSequence > 0) {
        return _ConversationBuildNotice(
          title: experience?.statusLabel ?? 'Build status',
          message: experience?.publicMessage ??
              'Pandora is showing the saved state for this build.',
        );
      }
      return _ConversationBuildNotice(
        title: experience?.statusLabel ?? 'Working',
        message: experience?.publicMessage ??
            'Pandora is preparing the working result.',
      );
    }

    try {
      final theatre = ProjectBuildStreamTheatreProjection.fromSnapshot(
        streamId: streamId,
        snapshot: snapshot,
      );
      final execution = _BuildExecutionView.from(snapshot.events);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ConversationLabel(label: 'Pandora'),
          const SizedBox(height: 8),
          LiveBuildTheatre(
            state: theatre,
            ownerStatusLabel: experience?.statusLabel,
            ownerMessage: experience?.publicMessage,
          ),
          if (execution.activity.isNotEmpty) ...[
            const SizedBox(height: 12),
            _BuildExecutionActivity(lines: execution.activity),
          ],
          if (disconnected || snapshot.reconnecting) ...[
            const SizedBox(height: 10),
            const Text(
              'Reconnecting to the same build. Your project continues from its saved state.',
              style: TextStyle(
                color: PandoraV2Colors.muted,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
          if (experience?.needsYou == true) ...[
            const SizedBox(height: 12),
            PandoraV2InlineMessage(
              title: 'Needs You',
              message: experience?.publicMessage ??
                  'Pandora is waiting for a consequential decision before continuing.',
            ),
          ],
          if (experience?.hasSafeFailure == true) ...[
            const SizedBox(height: 12),
            PandoraV2InlineMessage(
              title: 'Problem',
              message: experience?.safeFailureMessage ??
                  experience?.publicMessage ??
                  'Pandora stopped safely because the current build could not be verified.',
              danger: true,
            ),
          ],
          if (experience?.retryAvailable == true) ...[
            const SizedBox(height: 10),
            const Text(
              'Retry is available from the project controls. Pandora will not retry automatically.',
              style: TextStyle(
                color: PandoraV2Colors.muted,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
          if (experience?.canRollback == true) ...[
            const SizedBox(height: 10),
            const Text(
              'Rollback is available from the project controls and remains approval-gated.',
              style: TextStyle(
                color: PandoraV2Colors.muted,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
          if ((experience?.state == ProjectExperienceState.review) ||
              theatre.previewReady) ...[
            const SizedBox(height: 12),
            PandoraV2PrimaryAction(
              label: 'Open result',
              onPressed: onOpenProject,
              icon: Icons.arrow_forward_rounded,
            ),
          ],
        ],
      );
    } on FormatException {
      return const PandoraV2InlineMessage(
        title: 'Live build evidence unavailable',
        message:
            'Pandora could not display the latest build activity. Your saved project state is unchanged.',
        danger: true,
      );
    }
  }
}

class _BuildExecutionView {
  const _BuildExecutionView({required this.activity});

  factory _BuildExecutionView.from(List<ProjectBuildStreamEvent> input) {
    final events = List<ProjectBuildStreamEvent>.of(input)
      ..sort((left, right) => left.sequence.compareTo(right.sequence));
    final activity = <String>[];

    void record(String? value) {
      if (value == null || value.trim().isEmpty) return;
      final normalized = value.trim();
      if (activity.isEmpty || activity.last != normalized) {
        activity.add(normalized);
      }
    }

    for (final event in events) {
      final payload = event.safePayload;
      switch (event.eventType) {
        case 'command_started':
          final command = _text(payload['display_command']);
          final commandClass = _text(payload['command_class']);
          record(
            command ??
                (commandClass == null
                    ? 'Build command started'
                    : '${_sentenceCase(commandClass)} command started'),
          );
          break;
        case 'stdout_chunk':
          final text = _text(payload['text']);
          if (text != null) record(text);
          break;
        case 'stderr_chunk':
          final text = _text(payload['text']);
          if (text != null) record('Error output · $text');
          break;
        case 'command_completed':
          final status = _text(payload['status']) ?? 'completed';
          final exitCode = _integer(payload['exit_code']);
          record(
            exitCode == null
                ? 'Command $status'
                : 'Command $status · exit $exitCode',
          );
          break;
        case 'compile_started':
          final tool = _text(payload['tool']);
          record(tool == null ? 'Compile started' : 'Compile started · $tool');
          break;
        case 'compile_diagnostic':
          final severity = _text(payload['severity']) ?? 'diagnostic';
          final code = _text(payload['error_code']);
          final message = _text(payload['message']) ?? 'Compiler diagnostic';
          final line = _integer(payload['line']);
          final column = _integer(payload['column']);
          var location = '';
          if (event.filePath != null) {
            location = event.filePath!;
            if (line != null) {
              location += ':$line';
              if (column != null) location += ':$column';
            }
            location += ' · ';
          }
          final codeText = code == null ? '' : '$code · ';
          record('$location$severity · $codeText$message');
          break;
        case 'compile_completed':
          final status = _text(payload['status']) ?? 'completed';
          final errors = _integer(payload['error_count']) ?? 0;
          final warnings = _integer(payload['warning_count']) ?? 0;
          record('Compile $status · $errors errors · $warnings warnings');
          break;
        case 'test_started':
          final suites = _integer(payload['suite_count']);
          record(
            suites == null
                ? 'Checks started'
                : 'Checks started · $suites suites',
          );
          break;
        case 'test_result':
          final suite = _text(payload['suite']) ?? 'check';
          final status = _text(payload['status']) ?? 'unknown';
          record('$suite · $status');
          break;
        case 'test_completed':
          final executed = _integer(payload['executed']) ?? 0;
          final passed = _integer(payload['passed']) ?? 0;
          final failed = _integer(payload['failed']) ?? 0;
          final skipped = _integer(payload['skipped']) ?? 0;
          record(
            'Checks complete · $executed executed · $passed passed · $failed failed · $skipped skipped',
          );
          break;
        case 'repair_started':
          final attempt = _integer(payload['repair_attempt']);
          final files = _integer(payload['changed_file_count']);
          record(
            'Repair started${attempt == null ? '' : ' · attempt $attempt'}'
            '${files == null ? '' : ' · $files files'}',
          );
          break;
        case 'repair_completed':
          final status = _text(payload['status']) ?? 'completed';
          final files = _integer(payload['changed_file_count']);
          record(
            'Repair $status${files == null ? '' : ' · $files files'}',
          );
          break;
        case 'provider_fallback_started':
          final from = _text(payload['from_provider']);
          final to = _text(payload['to_provider']);
          record(
            from == null || to == null
                ? 'Provider fallback started'
                : 'Provider fallback · $from → $to',
          );
          break;
        case 'provider_fallback_completed':
          final provider = _text(payload['provider']);
          record(
            provider == null
                ? 'Provider fallback completed'
                : 'Provider fallback completed · $provider',
          );
          break;
        case 'rollback_started':
          record('Rollback started');
          break;
        case 'rollback_completed':
          record('Rollback completed');
          break;
        case 'verification':
          record('Verifying the exact build');
          break;
      }
    }

    final recent = activity.length > 12
        ? activity.sublist(activity.length - 12)
        : activity;
    return _BuildExecutionView(activity: List<String>.unmodifiable(recent));
  }

  final List<String> activity;
}

class _BuildExecutionActivity extends StatelessWidget {
  const _BuildExecutionActivity({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('live-build-execution-activity'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: PandoraV2Colors.soft,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Build activity',
              style: TextStyle(
                color: PandoraV2Colors.ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(
                  line,
                  style: const TextStyle(
                    color: PandoraV2Colors.muted,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ),
          ],
        ),
      );
}

class _ConversationBuildNotice extends StatelessWidget {
  const _ConversationBuildNotice({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ConversationLabel(label: 'Pandora'),
          const SizedBox(height: 8),
          PandoraV2InlineMessage(title: title, message: message),
        ],
      );
}

class _ConversationLabel extends StatelessWidget {
  const _ConversationLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: const TextStyle(
          color: PandoraV2Colors.muted,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: .2,
        ),
      );
}

class _CollapsibleIntent extends StatelessWidget {
  const _CollapsibleIntent({
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final isLong = text.length > 240 || text.split('\n').length > 4;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: PandoraV2Colors.soft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            maxLines: expanded || !isLong ? null : 4,
            overflow: expanded || !isLong
                ? TextOverflow.visible
                : TextOverflow.ellipsis,
            style: const TextStyle(
              color: PandoraV2Colors.ink,
              fontSize: 16,
              height: 1.42,
            ),
          ),
          if (isLong) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onToggle,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
                foregroundColor: PandoraV2Colors.ink,
              ),
              icon: Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
              ),
              label: Text(expanded ? 'Collapse request' : 'Show full request'),
            ),
          ],
        ],
      ),
    );
  }
}

String? _text(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

int? _integer(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

String _sentenceCase(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1).replaceAll('_', ' ')}';
}
