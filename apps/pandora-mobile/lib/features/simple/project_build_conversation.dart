import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/analytics/owner_analytics.dart';
import '../../core/data/project_experience_api.dart';
import '../../core/models/project_journey_models.dart';
import 'live_build_theatre/live_build_theatre.dart';
import 'live_build_theatre/project_build_stream_theatre_projection.dart';
import 'pandora_v2_ui.dart';
import 'professional_build_plan.dart';
import 'project_experience_v2.dart';
import 'project_build_snapshot_render_coalescer.dart';

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
    if (_stream != null) return;
    final rawStream = PandoraDependencies.of(context)
        .projectExperienceRepository
        ?.watchResilientBuildStream(
          projectId: widget.project.id,
          streamId: widget.buildStart.streamId,
        );
    _stream = rawStream == null
        ? null
        : coalesceProjectBuildSnapshotsForRendering(rawStream);
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
                    PandoraProfessionalBuildPlan(
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
                          return _LiveBuildProjection(
                            streamId: widget.buildStart.streamId,
                            snapshot: streamState,
                            disconnected: snapshot.hasError,
                            onOpenProject: _openProject,
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
  });

  final String streamId;
  final ProjectBuildStreamSnapshot snapshot;
  final bool disconnected;
  final VoidCallback onOpenProject;

  @override
  Widget build(BuildContext context) {
    if (snapshot.requiresReplay) {
      return const _ConversationBuildNotice(
        title: 'Refreshing live build evidence',
        message: 'Pandora is reconciling the authoritative build sequence.',
      );
    }

    if (snapshot.events.isEmpty) {
      if (snapshot.historyGapDueToRetention || snapshot.latestSequence > 0) {
        final stage = snapshot.buildStage?.replaceAll('_', ' ');
        return _ConversationBuildNotice(
          title: 'Build continued while you were away',
          message: stage == null || stage.isEmpty
              ? 'Expired source is not recreated. Current durable build state remains authoritative.'
              : 'Current durable stage: $stage. Expired source is not recreated.',
        );
      }
      return const _ConversationBuildNotice(
        title: 'Connecting to the live build',
        message: 'Source will appear only after real source bytes arrive.',
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
          LiveBuildTheatre(state: theatre),
          if (execution.activity.isNotEmpty) ...[
            const SizedBox(height: 12),
            _BuildExecutionActivity(lines: execution.activity),
          ],
          if (disconnected || snapshot.reconnecting) ...[
            const SizedBox(height: 10),
            const Text(
              'Reconnecting to the live build. The durable build continues independently and will reconcile from authoritative replay.',
              style: TextStyle(
                color: PandoraV2Colors.muted,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
          if (theatre.previewReady) ...[
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
            'Pandora rejected an invalid live-build projection. The durable build remains authoritative.',
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
