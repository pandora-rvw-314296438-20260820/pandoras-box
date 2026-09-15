import 'package:flutter/material.dart';

import '../design/pandora_tokens.dart';
import '../widgets/pandora_surface.dart';
import '../widgets/status_badge.dart';
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

    if (compact) {
      return Semantics(
        container: true,
        label: 'Activity Theatre. Done. ${events.length} events.',
        child: Card(
          child: ExpansionTile(
            title: const Text('Activity · Done'),
            childrenPadding: const EdgeInsets.fromLTRB(
              PandoraSpacing.md,
              0,
              PandoraSpacing.md,
              PandoraSpacing.md,
            ),
            children: [content],
          ),
        ),
      );
    }

    return PandoraSurface(
      title: 'Activity',
      trailing: StatusBadge(
        label: activityStateLabel(latest.state),
        tone: activityStateTone(latest.state),
        compact: true,
      ),
      child: content,
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
          StatusBadge(
            label: label,
            tone: activityStateTone(event.state),
            compact: true,
          ),
          const SizedBox(width: PandoraSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.message),
                if (requiredAction != null) ...[
                  const SizedBox(height: PandoraSpacing.xxs),
                  Text(
                    'Required action: $requiredAction',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
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

PandoraStatusTone activityStateTone(PandoraActivityState state) =>
    switch (state) {
      PandoraActivityState.result => PandoraStatusTone.verified,
      PandoraActivityState.failed => PandoraStatusTone.critical,
      PandoraActivityState.needsYou ||
      PandoraActivityState.retrying ||
      PandoraActivityState.fallback ||
      PandoraActivityState.paused =>
        PandoraStatusTone.attention,
      PandoraActivityState.cancelled => PandoraStatusTone.neutral,
      PandoraActivityState.understanding ||
      PandoraActivityState.planning ||
      PandoraActivityState.acting ||
      PandoraActivityState.checking ||
      PandoraActivityState.verifying ||
      PandoraActivityState.resuming =>
        PandoraStatusTone.informative,
    };
