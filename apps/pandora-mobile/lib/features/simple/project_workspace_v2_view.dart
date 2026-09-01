import 'package:flutter/material.dart';

import '../../core/platform/pandora_preview_host.dart';
import 'pandora_v2_ui.dart';
import 'project_exact_source_diff.dart';

enum ProjectChangePhase { idle, designing, building, checking }

class ProjectWorkspaceV2View extends StatelessWidget {
  const ProjectWorkspaceV2View({
    super.key,
    required this.title,
    required this.status,
    required this.statusColor,
    required this.canUndo,
    required this.undoing,
    required this.onBack,
    required this.onUndo,
    required this.onMore,
    required this.loading,
    required this.previewFiles,
    required this.previewVersionId,
    required this.selectionMode,
    required this.selectedPreviewTarget,
    required this.canFocus,
    required this.changing,
    required this.openingPreview,
    required this.onSelection,
    required this.onToggleSelection,
    required this.onOpenPreview,
    required this.progressPhase,
    required this.recentlyUpdated,
    required this.currentVersionVerified,
    required this.changeDiff,
    required this.intelligenceReply,
    required this.error,
    required this.onClearSelection,
    required this.onDismissIntelligence,
    required this.onDismissError,
    required this.changeController,
    required this.changeEnabled,
    required this.onSubmit,
    required this.onVoice,
  });

  final String title;
  final String status;
  final Color statusColor;
  final bool canUndo;
  final bool undoing;
  final VoidCallback onBack;
  final VoidCallback onUndo;
  final VoidCallback onMore;
  final bool loading;
  final List<Map<String, Object?>>? previewFiles;
  final String? previewVersionId;
  final bool selectionMode;
  final PandoraPreviewSelection? selectedPreviewTarget;
  final bool canFocus;
  final bool changing;
  final bool openingPreview;
  final ValueChanged<PandoraPreviewSelection> onSelection;
  final VoidCallback onToggleSelection;
  final VoidCallback onOpenPreview;
  final ProjectChangePhase? progressPhase;
  final bool recentlyUpdated;
  final bool currentVersionVerified;
  final ProjectExactSourceDiff? changeDiff;
  final String? intelligenceReply;
  final String? error;
  final VoidCallback onClearSelection;
  final VoidCallback onDismissIntelligence;
  final VoidCallback onDismissError;
  final TextEditingController changeController;
  final bool changeEnabled;
  final ValueChanged<String> onSubmit;
  final Future<void> Function() onVoice;

  @override
  Widget build(BuildContext context) {
    final files = previewFiles;
    final versionId = previewVersionId;
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
              title: title,
              status: status,
              statusColor: statusColor,
              canUndo: canUndo,
              undoing: undoing,
              onBack: onBack,
              onUndo: onUndo,
              onMore: onMore,
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
                          child: loading
                              ? _ExactPreviewLoadingSurface(projectName: title)
                              : hasExactPreview
                                  ? PandoraPreviewHost(
                                      key: ValueKey<String>(versionId),
                                      files: files,
                                      versionId: versionId,
                                      selectionEnabled: selectionMode,
                                      selectedSelector:
                                          selectedPreviewTarget?.selector,
                                      onSelection: onSelection,
                                      fallback: _ExactPreviewFallback(
                                        projectName: title,
                                        onOpen: onOpenPreview,
                                      ),
                                    )
                                  : _ExactPreviewFallback(
                                      projectName: title,
                                      onOpen: onOpenPreview,
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
                              tooltip: selectionMode
                                  ? 'Cancel selection'
                                  : 'Select something to change',
                              icon: selectionMode
                                  ? Icons.close_rounded
                                  : Icons.touch_app_outlined,
                              onPressed: changing || !canFocus
                                  ? null
                                  : onToggleSelection,
                            ),
                            const SizedBox(width: 6),
                            _PreviewIconButton(
                              tooltip: 'Open full screen',
                              icon: Icons.open_in_full_rounded,
                              onPressed: openingPreview ? null : onOpenPreview,
                            ),
                          ],
                        ),
                      ),
                    if (progressPhase != null)
                      Positioned(
                        left: 12,
                        right: 12,
                        top: 58,
                        child: _ProjectProgressCapsule(phase: progressPhase!),
                      )
                    else if (recentlyUpdated && currentVersionVerified)
                      Positioned(
                        left: 12,
                        right: 12,
                        top: 58,
                        child: _VerifiedChangeCapsule(
                          diff: changeDiff,
                          canUndo: canUndo,
                          undoing: undoing,
                          onUndo: onUndo,
                        ),
                      ),
                    Positioned.fill(
                      child: DraggableScrollableSheet(
                        initialChildSize: .18,
                        minChildSize: .18,
                        maxChildSize: .64,
                        snap: true,
                        snapSizes: const [.38],
                        builder: (context, scrollController) =>
                            _PandoraComposerSheet(
                          scrollController: scrollController,
                          selectionMode: selectionMode,
                          selectedPreviewTarget: selectedPreviewTarget,
                          intelligenceReply: intelligenceReply,
                          error: error,
                          onClearSelection: onClearSelection,
                          onDismissIntelligence: onDismissIntelligence,
                          onDismissError: onDismissError,
                          changeController: changeController,
                          changeEnabled: changeEnabled,
                          onSubmit: onSubmit,
                          onVoice: onVoice,
                        ),
                      ),
                    ),
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

class _PandoraComposerSheet extends StatelessWidget {
  const _PandoraComposerSheet({
    required this.scrollController,
    required this.selectionMode,
    required this.selectedPreviewTarget,
    required this.intelligenceReply,
    required this.error,
    required this.onClearSelection,
    required this.onDismissIntelligence,
    required this.onDismissError,
    required this.changeController,
    required this.changeEnabled,
    required this.onSubmit,
    required this.onVoice,
  });

  final ScrollController scrollController;
  final bool selectionMode;
  final PandoraPreviewSelection? selectedPreviewTarget;
  final String? intelligenceReply;
  final String? error;
  final VoidCallback onClearSelection;
  final VoidCallback onDismissIntelligence;
  final VoidCallback onDismissError;
  final TextEditingController changeController;
  final bool changeEnabled;
  final ValueChanged<String> onSubmit;
  final Future<void> Function() onVoice;

  @override
  Widget build(BuildContext context) => Material(
        elevation: 12,
        shadowColor: Colors.black12,
        color: PandoraV2Colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: PandoraV2Colors.line),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: ListView(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(
            12,
            8,
            12,
            10 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            Center(
              child: Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: PandoraV2Colors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 8),
            PandoraV2IntentSurface(
              controller: changeController,
              hintText: selectedPreviewTarget == null
                  ? 'Tell Pandora what to change…'
                  : 'Change ${selectedPreviewTarget!.label}…',
              enabled: changeEnabled,
              onSubmit: onSubmit,
              onVoice: onVoice,
            ),
            if (selectionMode || selectedPreviewTarget != null) ...[
              const SizedBox(height: 8),
              _SelectionContextCapsule(
                selecting: selectionMode,
                selection: selectedPreviewTarget,
                onClear: onClearSelection,
              ),
            ],
            if (intelligenceReply != null) ...[
              const SizedBox(height: 8),
              PandoraV2InlineMessage(
                title: 'Pandora',
                message: intelligenceReply!,
                actionLabel: 'Dismiss',
                onAction: onDismissIntelligence,
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              PandoraV2InlineMessage(
                title: 'Project unchanged',
                message: error!,
                actionLabel: 'Dismiss',
                onAction: onDismissError,
                danger: true,
              ),
            ],
            const SizedBox(height: 4),
          ],
        ),
      );
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

  final ProjectChangePhase phase;

  int get _activeIndex => switch (phase) {
        ProjectChangePhase.designing => 0,
        ProjectChangePhase.building => 1,
        ProjectChangePhase.checking => 2,
        ProjectChangePhase.idle => 2,
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
    required this.diff,
    required this.canUndo,
    required this.undoing,
    required this.onUndo,
  });

  final ProjectExactSourceDiff? diff;
  final bool canUndo;
  final bool undoing;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Verified change',
                        style: TextStyle(
                          color: PandoraV2Colors.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (diff != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          diff!.compactSummary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: PandoraV2Colors.muted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (diff != null || canUndo) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (diff != null)
                    TextButton(
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        backgroundColor: PandoraV2Colors.surface,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(24)),
                        ),
                        builder: (_) => _ExactSourceDiffSheet(diff: diff!),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: PandoraV2Colors.ink,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('View changes'),
                    ),
                  if (canUndo)
                    TextButton(
                      onPressed: undoing ? null : onUndo,
                      style: TextButton.styleFrom(
                        foregroundColor: PandoraV2Colors.ink,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(undoing ? 'Undoing…' : 'Undo'),
                    ),
                ],
              ),
            ],
          ],
        ),
      );
}

class _ExactSourceDiffSheet extends StatelessWidget {
  const _ExactSourceDiffSheet({required this.diff});

  final ProjectExactSourceDiff diff;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .58,
          minChildSize: .34,
          maxChildSize: .88,
          builder: (context, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: PandoraV2Colors.line,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'What changed',
                style: TextStyle(
                  color: PandoraV2Colors.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(diff.compactSummary, style: pandoraV2Muted),
              const SizedBox(height: 18),
              if (diff.files.isEmpty)
                const Text(
                  'No material file changes detected.',
                  style: pandoraV2Muted,
                )
              else
                for (final file in diff.files) ...[
                  _ExactSourceDiffRow(file: file),
                  const Divider(height: 1, color: PandoraV2Colors.line),
                ],
            ],
          ),
        ),
      );
}

class _ExactSourceDiffRow extends StatelessWidget {
  const _ExactSourceDiffRow({required this.file});

  final ProjectExactSourceDiffFile file;

  IconData get _icon => switch (file.status) {
        ProjectExactSourceDiffStatus.added => Icons.add_circle_outline_rounded,
        ProjectExactSourceDiffStatus.modified => Icons.edit_outlined,
        ProjectExactSourceDiffStatus.removed => Icons.remove_circle_outline,
      };

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon, size: 18, color: PandoraV2Colors.ink),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.path,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PandoraV2Colors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    file.detailLabel,
                    style: const TextStyle(
                      color: PandoraV2Colors.muted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
