import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/project_experience_api.dart';
import '../../core/models/project_journey_models.dart';
import 'pandora_v2_ui.dart';
import 'project_experience_v2.dart';

class ProjectBuildConversationScreen extends StatefulWidget {
  const ProjectBuildConversationScreen({
    super.key,
    required this.project,
    required this.originalIntent,
    required this.understanding,
    required this.buildStart,
  });

  final CustomerProject project;
  final String originalIntent;
  final OwnerProjectUnderstanding understanding;
  final ProjectBuildStart buildStart;

  @override
  State<ProjectBuildConversationScreen> createState() =>
      _ProjectBuildConversationScreenState();
}

class _ProjectBuildConversationScreenState
    extends State<ProjectBuildConversationScreen> {
  Stream<List<ProjectBuildStreamEvent>>? _stream;
  bool _intentExpanded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= PandoraDependencies.of(context)
        .projectExperienceRepository
        ?.watchBuildStream(
          projectId: widget.project.id,
          streamId: widget.buildStart.streamId,
        );
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
    final summary = widget.understanding.intentSummary ??
        widget.understanding.businessSummary ??
        'Pandora has a build plan for this project.';
    final plan = <String>[
      if (widget.understanding.objectives.isNotEmpty)
        widget.understanding.objectives.first,
      ...widget.understanding.requirements.take(4),
    ];

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
                    _ConversationLabel(label: 'You'),
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
                    _PandoraProposal(
                      name: widget.project.name,
                      summary: summary,
                      plan: plan,
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
                      StreamBuilder<List<ProjectBuildStreamEvent>>(
                        stream: stream,
                        initialData: const <ProjectBuildStreamEvent>[],
                        builder: (context, snapshot) {
                          final events = snapshot.data ??
                              const <ProjectBuildStreamEvent>[];
                          final view = _BuildConversationView.from(events);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _LiveBuildMessage(
                                view: view,
                                onOpenProject:
                                    view.previewReady ? _openProject : null,
                              ),
                              if (snapshot.hasError) ...[
                                const SizedBox(height: 10),
                                const Text(
                                  'Live code view disconnected. The durable build record will resync when the connection returns.',
                                  style: TextStyle(
                                    color: PandoraV2Colors.muted,
                                    fontSize: 12.5,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ],
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

class _PandoraProposal extends StatelessWidget {
  const _PandoraProposal({
    required this.name,
    required this.summary,
    required this.plan,
  });

  final String name;
  final String summary;
  final List<String> plan;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: PandoraV2Colors.surface,
          border: Border.all(color: PandoraV2Colors.line),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(
                color: PandoraV2Colors.ink,
                fontSize: 23,
                fontWeight: FontWeight.w700,
                letterSpacing: -.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(summary, style: pandoraV2Muted),
            if (plan.isNotEmpty) ...[
              const SizedBox(height: 16),
              for (final item in plan)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 7),
                        child: SizedBox(
                          width: 5,
                          height: 5,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: PandoraV2Colors.ink,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item,
                          style: const TextStyle(
                            color: PandoraV2Colors.ink,
                            fontSize: 15,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      );
}

class _LiveBuildMessage extends StatelessWidget {
  const _LiveBuildMessage({required this.view, required this.onOpenProject});

  final _BuildConversationView view;
  final VoidCallback? onOpenProject;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ConversationLabel(label: 'Pandora'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: PandoraV2Colors.surface,
            border: Border.all(color: PandoraV2Colors.line),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.code_rounded,
                    size: 20,
                    color: PandoraV2Colors.ink,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      view.previewReady
                          ? 'Build complete'
                          : view.failed
                              ? 'Build stopped'
                              : 'Pandora is coding',
                      style: const TextStyle(
                        color: PandoraV2Colors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (view.currentFile != null && view.visibleCode.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  view.currentFile!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PandoraV2Colors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(minHeight: 170),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PandoraV2Colors.ink,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    view.visibleCode,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      height: 1.36,
                    ),
                  ),
                ),
              ],
              if (view.activity.isNotEmpty) ...[
                const SizedBox(height: 14),
                for (final line in view.activity)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Text(
                      line,
                      style: const TextStyle(
                        color: PandoraV2Colors.muted,
                        fontSize: 13.5,
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
              if (onOpenProject != null) ...[
                const SizedBox(height: 12),
                PandoraV2PrimaryAction(
                  label: 'Open result',
                  onPressed: onOpenProject,
                  icon: Icons.arrow_forward_rounded,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _BuildConversationView {
  const _BuildConversationView({
    required this.currentFile,
    required this.visibleCode,
    required this.activity,
    required this.previewReady,
    required this.failed,
  });

  factory _BuildConversationView.from(List<ProjectBuildStreamEvent> events) {
    String? currentFile;
    var code = '';
    var completedFiles = 0;
    var previewReady = false;
    var failed = false;
    final activity = <String>[];

    void record(String value) {
      if (value.isEmpty) return;
      if (activity.isEmpty || activity.last != value) activity.add(value);
    }

    for (final event in events) {
      switch (event.eventType) {
        case 'stream_started':
          record('Source stream connected');
          break;
        case 'file_started':
          currentFile = event.filePath;
          code = '';
          if (currentFile != null) record('Writing $currentFile');
          break;
        case 'code_chunk':
          if (event.filePath == currentFile && event.contentChunk != null) {
            code += event.contentChunk!;
          }
          break;
        case 'file_completed':
          completedFiles += 1;
          if (event.filePath != null) record('✓ ${event.filePath} saved');
          break;
        case 'generation_completed':
          final count = event.safePayload['fileCount'] ?? completedFiles;
          record('✓ $count source files generated');
          break;
        case 'build_job_created':
          record('Source handed to the builder');
          break;
        case 'build_step':
          final kind = event.safePayload['stepKind']?.toString() ?? 'build';
          final status = event.safePayload['status']?.toString() ?? '';
          final key = event.safePayload['stepKey']?.toString() ?? kind;
          if (status == 'succeeded' || status == 'completed') {
            record('✓ ${_friendlyStep(key, kind)}');
          } else if (status == 'failed') {
            failed = true;
            record('Build step failed · ${_friendlyStep(key, kind)}');
          } else {
            record(_friendlyStep(key, kind));
          }
          break;
        case 'verification':
          record('Verifying the exact build');
          break;
        case 'preview_ready':
          previewReady = true;
          record('✓ Preview ready');
          break;
        case 'stream_error':
          failed = true;
          final codeValue = event.safePayload['code']?.toString();
          record(
            codeValue == null
                ? 'Live code stream stopped'
                : 'Live code stream stopped · $codeValue',
          );
          break;
        case 'job_state':
          final stage = event.safePayload['stage']?.toString();
          if (stage != null && stage.isNotEmpty) record(_friendlyStage(stage));
          break;
      }
    }

    final lines = code.split('\n');
    final visibleLines =
        lines.length > 36 ? lines.sublist(lines.length - 36) : lines;
    final recentActivity =
        activity.length > 7 ? activity.sublist(activity.length - 7) : activity;

    return _BuildConversationView(
      currentFile: currentFile,
      visibleCode: visibleLines.join('\n'),
      activity: List<String>.unmodifiable(recentActivity),
      previewReady: previewReady,
      failed: failed,
    );
  }

  final String? currentFile;
  final String visibleCode;
  final List<String> activity;
  final bool previewReady;
  final bool failed;

  static String _friendlyStep(String key, String kind) {
    final value = '$kind $key'.toLowerCase();
    if (value.contains('source')) return 'Source snapshot ready';
    if (value.contains('depend')) return 'Dependencies resolved';
    if (value.contains('test') || value.contains('verify')) {
      return 'Checks completed';
    }
    if (value.contains('build') || value.contains('package')) {
      return 'Application compiled';
    }
    return key.replaceAll('_', ' ');
  }

  static String _friendlyStage(String stage) {
    switch (stage.toLowerCase()) {
      case 'building':
        return 'Compiling application';
      case 'testing':
      case 'verifying':
        return 'Running checks';
      case 'repairing':
        return 'Repairing build issues';
      case 'previewing':
        return 'Preparing preview';
      case 'preview_ready':
        return '✓ Preview ready';
      default:
        return stage.replaceAll('_', ' ');
    }
  }
}
