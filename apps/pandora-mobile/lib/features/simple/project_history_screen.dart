
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/project_experience_api.dart';
import '../../core/models/project_conversation_history.dart';
import '../../core/models/project_journey_models.dart';
import 'live_build_theatre/live_build_theatre.dart';
import 'live_build_theatre/project_build_stream_theatre_projection.dart';
import 'pandora_v2_ui.dart';

class ProjectHistoryScreen extends StatefulWidget {
  const ProjectHistoryScreen({super.key, required this.project});

  final CustomerProject project;

  @override
  State<ProjectHistoryScreen> createState() => _ProjectHistoryScreenState();
}

class _ProjectHistoryScreenState extends State<ProjectHistoryScreen> {
  List<ProjectConversationHistoryItem>? _items;
  String? _error;
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_items == null && _loading) unawaited(_load());
  }

  Future<void> _load() async {
    final api = PandoraDependencies.of(context).projectExperience;
    if (api == null) {
      setState(() {
        _loading = false;
        _error = 'Pandora cannot open project history right now.';
      });
      return;
    }
    try {
      final items = await api.loadProjectConversation(
        projectId: widget.project.id,
        limit: 100,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } on ProjectExperienceException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _openBuildEvidence(ProjectConversationHistoryItem item) async {
    final buildJobId = item.buildJobId;
    final api = PandoraDependencies.of(context).projectExperience;
    if (buildJobId == null || api == null) return;
    try {
      final streamId = await api.findBuildStreamId(
        projectId: widget.project.id,
        buildJobId: buildJobId,
      );
      if (!mounted) return;
      if (streamId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Live build detail has expired. Durable history remains.'),
          ),
        );
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ProjectHistoryBuildEvidenceScreen(
            project: widget.project,
            streamId: streamId,
          ),
        ),
      );
    } on ProjectExperienceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: PandoraV2Colors.canvas,
      appBar: AppBar(
        backgroundColor: PandoraV2Colors.canvas,
        foregroundColor: PandoraV2Colors.ink,
        surfaceTintColor: Colors.transparent,
        title: const Text('History'),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text(
                widget.project.name,
                style: const TextStyle(
                  color: PandoraV2Colors.ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'What you asked, what Pandora changed, and what became real.',
                style: pandoraV2Muted,
              ),
              const SizedBox(height: 24),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_error != null)
                PandoraV2InlineMessage(
                  title: 'History unavailable',
                  message: _error!,
                  actionLabel: 'Try again',
                  onAction: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    unawaited(_load());
                  },
                )
              else if (items == null || items.isEmpty)
                const PandoraV2InlineMessage(
                  title: 'No history yet',
                  message: 'Your first project request will appear here.',
                )
              else
                for (final item in items) ...[
                  _HistoryItemCard(
                    item: item,
                    onOpenBuild: item.buildJobId == null
                        ? null
                        : () => _openBuildEvidence(item),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryItemCard extends StatefulWidget {
  const _HistoryItemCard({required this.item, this.onOpenBuild});

  final ProjectConversationHistoryItem item;
  final VoidCallback? onOpenBuild;

  @override
  State<_HistoryItemCard> createState() => _HistoryItemCardState();
}

class _HistoryItemCardState extends State<_HistoryItemCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final exactIntent = item.isUserIntent ? item.payloadText('intentText') : null;
    final detail = exactIntent ?? item.summary;
    final canExpand = item.expandable || detail.length > 260 || item.evidenceAvailable;
    final actor = item.actorType == 'customer' ? 'You' : 'Pandora';
    final status = item.status?.trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PandoraV2Colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PandoraV2Colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  actor,
                  style: const TextStyle(
                    color: PandoraV2Colors.muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _historyTime(item.occurredAt),
                style: const TextStyle(
                  color: PandoraV2Colors.muted,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            item.title,
            style: const TextStyle(
              color: PandoraV2Colors.ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            detail,
            maxLines: _expanded ? null : 5,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: const TextStyle(
              color: PandoraV2Colors.ink,
              fontSize: 14,
              height: 1.42,
            ),
          ),
          if (status != null && status.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              status,
              style: const TextStyle(
                color: PandoraV2Colors.muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (canExpand || widget.onOpenBuild != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (canExpand)
                  TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(_expanded ? 'Show less' : 'Show details'),
                  ),
                if (widget.onOpenBuild != null)
                  TextButton.icon(
                    onPressed: widget.onOpenBuild,
                    icon: const Icon(Icons.play_circle_outline_rounded),
                    label: const Text('Build activity'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class ProjectHistoryBuildEvidenceScreen extends StatefulWidget {
  const ProjectHistoryBuildEvidenceScreen({
    super.key,
    required this.project,
    required this.streamId,
  });

  final CustomerProject project;
  final String streamId;

  @override
  State<ProjectHistoryBuildEvidenceScreen> createState() =>
      _ProjectHistoryBuildEvidenceScreenState();
}

class _ProjectHistoryBuildEvidenceScreenState
    extends State<ProjectHistoryBuildEvidenceScreen> {
  Stream<ProjectBuildStreamSnapshot>? _stream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= PandoraDependencies.of(context)
        .projectExperienceRepository
        ?.watchResilientBuildStream(
          projectId: widget.project.id,
          streamId: widget.streamId,
        );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: PandoraV2Colors.canvas,
        appBar: AppBar(
          backgroundColor: PandoraV2Colors.canvas,
          foregroundColor: PandoraV2Colors.ink,
          surfaceTintColor: Colors.transparent,
          title: const Text('Build activity'),
        ),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _stream == null
                ? const PandoraV2InlineMessage(
                    title: 'Build activity unavailable',
                    message: 'Durable project history remains authoritative.',
                  )
                : StreamBuilder<ProjectBuildStreamSnapshot>(
                    stream: _stream,
                    initialData: const ProjectBuildStreamSnapshot.empty(),
                    builder: (context, snapshot) {
                      final value = snapshot.data ??
                          const ProjectBuildStreamSnapshot.empty();
                      if (value.requiresReplay) {
                        return const PandoraV2InlineMessage(
                          title: 'Refreshing build evidence',
                          message: 'Pandora is reconciling the durable stream.',
                        );
                      }
                      if (value.events.isEmpty) {
                        return const PandoraV2InlineMessage(
                          title: 'Detailed activity expired',
                          message:
                              'Pandora does not recreate expired events. The durable history item remains available.',
                        );
                      }
                      try {
                        final theatre =
                            ProjectBuildStreamTheatreProjection.fromSnapshot(
                          streamId: widget.streamId,
                          snapshot: value,
                        );
                        return SingleChildScrollView(
                          child: LiveBuildTheatre(state: theatre),
                        );
                      } on FormatException {
                        return const PandoraV2InlineMessage(
                          title: 'Build evidence rejected',
                          message:
                              'Pandora rejected mismatched build evidence instead of displaying it.',
                          danger: true,
                        );
                      }
                    },
                  ),
          ),
        ),
      );
}

String _historyTime(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
