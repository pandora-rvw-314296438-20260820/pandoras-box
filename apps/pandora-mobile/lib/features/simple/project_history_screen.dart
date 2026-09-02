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
            content: Text(
              'Live build detail has expired. Durable history remains.',
            ),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _showEvidenceDetails(ProjectConversationHistoryItem item) async {
    final ids = <MapEntry<String, String>>[];
    void add(String label, String? value) {
      final normalized = value?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        ids.add(MapEntry<String, String>(label, normalized));
      }
    }

    add('Request', item.sourceIntentId);
    add('Plan', item.projectSpecId);
    add('Build authorization', item.buildAuthorizationId);
    add('Build', item.buildJobId);
    add('Version', item.projectVersionId);
    add('Verification', item.verificationRunId);
    add('Deployment', item.deploymentId);
    add('Evidence record', item.sourceId);
    add('History record', item.id);

    final proofLabels = <String>[
      if (item.sourceIntentId != null) 'Request linked',
      if (item.projectSpecId != null) 'Plan linked',
      if (item.buildJobId != null) 'Build linked',
      if (item.projectVersionId != null) 'Exact version linked',
      if (item.verificationRunId != null) 'Verification linked',
      if (item.deploymentId != null) 'Deployment linked',
    ];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PandoraV2Colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: FractionallySizedBox(
          heightFactor: .72,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Evidence',
                      style: TextStyle(
                        color: PandoraV2Colors.ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                item.title,
                style: const TextStyle(
                  color: PandoraV2Colors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                ids.isEmpty
                    ? 'Pandora retained this durable history record.'
                    : 'Pandora retained the exact records behind this result so it can be independently traced.',
                style: pandoraV2Muted,
              ),
              if (proofLabels.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final label in proofLabels)
                      Chip(
                        avatar: const Icon(Icons.verified_outlined, size: 16),
                        label: Text(label),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_rounded),
                title: const Text('Recorded'),
                subtitle: Text(_historyTime(item.occurredAt)),
              ),
              if (item.status != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.fact_check_outlined),
                  title: const Text('Status'),
                  subtitle: Text(item.status!),
                ),
              if (ids.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: const Text('Technical IDs'),
                  subtitle: const Text(
                    'Exact lineage for advanced verification',
                  ),
                  children: [
                    for (final entry in ids)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(entry.key),
                        subtitle: SelectableText(entry.value),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    String? latestProposalId;
    DateTime? latestProposalAt;
    if (items != null) {
      for (final item in items) {
        final currentLatest = latestProposalAt;
        if (item.isProposal &&
            (currentLatest == null || item.occurredAt.isAfter(currentLatest))) {
          latestProposalId = item.id;
          latestProposalAt = item.occurredAt;
        }
      }
    }
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
                    projectName: widget.project.name,
                    collapseProposal:
                        item.isProposal && item.id != latestProposalId,
                    onOpenBuild: item.buildJobId == null
                        ? null
                        : () => _openBuildEvidence(item),
                    onOpenEvidence: item.evidenceAvailable
                        ? () => _showEvidenceDetails(item)
                        : null,
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton.icon(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Return to live'),
          ),
        ),
      ),
    );
  }
}

class _HistoryItemCard extends StatefulWidget {
  const _HistoryItemCard({
    required this.item,
    required this.projectName,
    required this.collapseProposal,
    this.onOpenBuild,
    this.onOpenEvidence,
  });

  final ProjectConversationHistoryItem item;
  final String projectName;
  final bool collapseProposal;
  final VoidCallback? onOpenBuild;
  final VoidCallback? onOpenEvidence;

  @override
  State<_HistoryItemCard> createState() => _HistoryItemCardState();
}

class _HistoryItemCardState extends State<_HistoryItemCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.item.isProposal && !widget.collapseProposal;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final exactIntent =
        item.isUserIntent ? item.payloadText('intentText') : null;
    final status = item.status?.trim();
    final proposalSummary = item.payloadText('businessSummary') ?? item.summary;
    final proposalTarget = item.payloadText('targetUserSummary');
    final completedBuild = item.isBuild &&
        status != null &&
        status != 'Working' &&
        status != 'Needs You';
    late final String compactDetail;
    if (item.isProposal) {
      compactDetail = proposalSummary;
    } else if (completedBuild) {
      compactDetail = _completedBuildSummary(item);
    } else {
      compactDetail = exactIntent ?? item.summary;
    }
    final expandedDetail = item.isProposal && proposalTarget != null
        ? '$proposalSummary\n\nFor: $proposalTarget'
        : compactDetail;
    final detail = _expanded ? expandedDetail : compactDetail;
    final canExpand = item.isProposal ||
        item.expandable ||
        expandedDetail.length > 260 ||
        item.evidenceAvailable;
    final actor = item.actorType == 'customer' ? 'You' : 'Pandora';
    final cardTitle = item.isProposal ? widget.projectName : item.title;
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
            cardTitle,
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
          if (canExpand ||
              widget.onOpenBuild != null ||
              widget.onOpenEvidence != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (canExpand)
                  TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(
                      item.isProposal
                          ? (_expanded ? 'Hide plan' : 'View plan')
                          : (_expanded ? 'Show less' : 'Show details'),
                    ),
                  ),
                if (widget.onOpenEvidence != null)
                  TextButton.icon(
                    onPressed: widget.onOpenEvidence,
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Evidence'),
                  ),
                if (widget.onOpenBuild != null)
                  TextButton.icon(
                    onPressed: widget.onOpenBuild,
                    icon: const Icon(Icons.play_circle_outline_rounded),
                    label: Text(
                      item.isBuild ? 'View build evidence' : 'Build activity',
                    ),
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

String _completedBuildSummary(ProjectConversationHistoryItem item) {
  final parts = <String>[];
  final buildNumber = item.payloadInt('buildNumber');
  final durationMs = item.payloadInt('durationMs');
  final fileCount = item.payloadInt('fileCount');
  final lineCount = item.payloadInt('lineCount');
  final checksTotal = item.payloadInt('checksTotal');
  final checksPassed = item.payloadInt('checksPassed');
  final checksFailed = item.payloadInt('checksFailed');
  final checksBlocked = item.payloadInt('checksBlocked');

  if (buildNumber != null) parts.add('Build #$buildNumber');
  if (durationMs != null) parts.add(_historyDuration(durationMs));
  if (fileCount != null) parts.add('$fileCount files');
  if (lineCount != null) parts.add('$lineCount lines');
  if (checksTotal != null && checksTotal > 0) {
    final passed = checksPassed ?? 0;
    final failed = checksFailed ?? 0;
    final blocked = checksBlocked ?? 0;
    if (failed > 0 || blocked > 0) {
      parts.add(
        '$passed/$checksTotal checks · $failed failed · $blocked blocked',
      );
    } else {
      parts.add('$passed/$checksTotal checks');
    }
  }
  final status = item.status?.trim();
  if (status != null && status.isNotEmpty) parts.add(status);
  return parts.isEmpty ? item.summary : parts.join(' · ');
}

String _historyDuration(int durationMs) {
  final seconds = (durationMs / 1000).round();
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return remainder == 0 ? '${minutes}m' : '${minutes}m ${remainder}s';
}

String _historyTime(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
