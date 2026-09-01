import 'package:flutter/material.dart';

import '../pandora_v2_ui.dart';
import 'live_build_reducer.dart';

class LiveBuildFileActivity extends StatefulWidget {
  const LiveBuildFileActivity({super.key, required this.state});

  final LiveBuildTheatreState state;

  @override
  State<LiveBuildFileActivity> createState() => _LiveBuildFileActivityState();
}

class _LiveBuildFileActivityState extends State<LiveBuildFileActivity> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant LiveBuildFileActivity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.state.generationComplete &&
        widget.state.generationComplete &&
        _expanded) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    if (state.files.isEmpty) return const SizedBox.shrink();

    if (state.generationComplete && !_expanded) {
      return Container(
        key: const Key('live-build-source-summary'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: PandoraV2Colors.soft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.check_rounded,
              size: 18,
              color: PandoraV2Colors.ink,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Source created',
                    style: TextStyle(
                      color: PandoraV2Colors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _metricSummary(state),
                    style: const TextStyle(
                      color: PandoraV2Colors.muted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _expanded = true),
              child: const Text('View files'),
            ),
          ],
        ),
      );
    }

    final visibleFiles = _expanded ? state.files : state.files.take(6).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PandoraV2Colors.surface,
        border: Border.all(color: PandoraV2Colors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  state.generationComplete
                      ? 'Files created'
                      : 'Files being created',
                  style: const TextStyle(
                    color: PandoraV2Colors.ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (state.generationComplete)
                TextButton(
                  onPressed: () => setState(() => _expanded = false),
                  child: const Text('Collapse'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final file in visibleFiles)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      file.completed ? '✓' : '+',
                      style: const TextStyle(
                        color: PandoraV2Colors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      file.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: file.path == state.activeFile
                            ? PandoraV2Colors.ink
                            : PandoraV2Colors.muted,
                        fontSize: 12.5,
                        fontWeight: file.path == state.activeFile
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (file.byteCount > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${file.lineCount} lines',
                      style: const TextStyle(
                        color: PandoraV2Colors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (!_expanded && state.files.length > visibleFiles.length)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                '+${state.files.length - visibleFiles.length} more',
                style: const TextStyle(
                  color: PandoraV2Colors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _metricSummary(LiveBuildTheatreState state) {
  final reportedFiles = state.reportedFileCount;
  final reportedLines = state.reportedSourceLineCount;
  final reportedBytes = state.reportedSourceByteCount;

  if (reportedFiles != null && reportedLines != null && reportedBytes != null) {
    return '$reportedFiles files · $reportedLines lines · ${_formatBytes(reportedBytes)} source';
  }

  if (state.locallyCompleteSourceMetrics) {
    return '${state.uniqueFileCount} files · ${state.sourceLineCount} lines · ${_formatBytes(state.sourceByteCount)} source';
  }

  if (reportedFiles != null) {
    return '$reportedFiles files';
  }

  if (state.historyGapDueToRetention) {
    return 'Build continued while you were away';
  }

  return 'Source summary ready';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
}
