import 'package:flutter/material.dart';

import '../design/pandora_tokens.dart';
import '../widgets/pandora_mark.dart';
import 'pandora_activity_projection.dart';

class PandoraActivityTimelineView extends StatelessWidget {
  const PandoraActivityTimelineView({
    super.key,
    required this.events,
    this.compactVerifiedResult = true,
  });

  final List<PandoraActivityProjection> events;
  final bool compactVerifiedResult;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    final latest = events.last;
    final compact =
        compactVerifiedResult && latest.state == PandoraActivityState.result;
    final content = _ActivityEventList(events: events);
    final foreground = Theme.of(context).colorScheme.onSurface;

    if (compact) {
      return Semantics(
        container: true,
        label: 'Activity Theatre. Done. ${events.length} events.',
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: PandoraSpacing.xs),
            backgroundColor: Colors.transparent,
            collapsedBackgroundColor: Colors.transparent,
            shape: const Border(),
            collapsedShape: const Border(),
            leading: PandoraMark(size: 24, color: foreground),
            title: Text(
              'Activity · Done',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            children: [content],
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: PandoraMark(size: 24, color: foreground),
        ),
        const SizedBox(width: 11),
        Expanded(child: content),
      ],
    );
  }
}

class _ActivityEventList extends StatelessWidget {
  const _ActivityEventList({required this.events});

  final List<PandoraActivityProjection> events;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < events.length; index++) ...[
          if (index > 0) const SizedBox(height: PandoraSpacing.sm),
          _ActivityEventRow(event: events[index]),
        ],
      ],
    );
  }
}

class _ActivityEventRow extends StatelessWidget {
  const _ActivityEventRow({required this.event});

  final PandoraActivityProjection event;

  @override
  Widget build(BuildContext context) {
    final label = activityStateLabel(event.state);
    final requiredAction = event.blocker?.requiredAction;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final statusColor = _activityStateColor(context, event.state);
    final semanticText = requiredAction == null
        ? '$label. ${event.message}'
        : '$label. ${event.message}. Required action: $requiredAction';

    return Semantics(
      container: true,
      label: semanticText,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(
              _activityStateIcon(event.state),
              size: 13,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: PandoraSpacing.xxs),
                Text(
                  event.message,
                  style: TextStyle(color: muted, fontSize: 14, height: 1.4),
                ),
                if (requiredAction != null) ...[
                  const SizedBox(height: PandoraSpacing.xxs),
                  Text(
                    'Required action: $requiredAction',
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Color _activityStateColor(BuildContext context, PandoraActivityState state) {
  final palette = context.pandoraPalette;
  final muted = Theme.of(context).colorScheme.onSurfaceVariant;
  return switch (state) {
    PandoraActivityState.result => palette.verified,
    PandoraActivityState.failed => palette.critical,
    PandoraActivityState.needsYou ||
    PandoraActivityState.retrying ||
    PandoraActivityState.fallback ||
    PandoraActivityState.paused =>
      palette.attention,
    _ => muted,
  };
}

IconData _activityStateIcon(PandoraActivityState state) => switch (state) {
      PandoraActivityState.result => Icons.check_rounded,
      PandoraActivityState.failed => Icons.error_outline_rounded,
      PandoraActivityState.cancelled => Icons.stop_rounded,
      PandoraActivityState.needsYou => Icons.priority_high_rounded,
      _ => Icons.circle,
    };

String activityStateLabel(PandoraActivityState state) => switch (state) {
      PandoraActivityState.understanding => 'Understanding',
      PandoraActivityState.planning => 'Planning',
      PandoraActivityState.acting => 'Working',
      PandoraActivityState.checking => 'Checking',
      PandoraActivityState.needsYou => 'Needs You',
      PandoraActivityState.retrying => 'Retrying',
      PandoraActivityState.fallback => 'Switching approach',
      PandoraActivityState.verifying => 'Verifying',
      PandoraActivityState.paused => 'Paused',
      PandoraActivityState.resuming => 'Resuming',
      PandoraActivityState.result => 'Done',
      PandoraActivityState.failed => 'Problem',
      PandoraActivityState.cancelled => 'Cancelled',
    };
