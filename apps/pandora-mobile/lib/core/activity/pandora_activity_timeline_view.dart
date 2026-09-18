import 'package:flutter/material.dart';

import '../design/pandora_tokens.dart';
import '../widgets/pandora_mark.dart';
import 'pandora_activity_presentation_policy.dart';
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
    final presentationText = pandoraActivityPresentationText(latest);
    final requiredAction = latest.blocker?.requiredAction;
    final terminal = latest.state == PandoraActivityState.result ||
        latest.state == PandoraActivityState.failed ||
        latest.state == PandoraActivityState.cancelled;
    final palette = context.pandoraPalette;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final statusColor = switch (latest.state) {
      PandoraActivityState.result => palette.verified,
      PandoraActivityState.failed => palette.critical,
      PandoraActivityState.needsYou ||
      PandoraActivityState.retrying ||
      PandoraActivityState.fallback ||
      PandoraActivityState.paused =>
        palette.attention,
      _ => muted,
    };
    final semanticText = requiredAction == null
        ? 'Activity Theatre. ${activityStateLabel(latest.state)}. $presentationText'
        : 'Activity Theatre. ${activityStateLabel(latest.state)}. '
            '$presentationText. Required action: $requiredAction';

    final announceTransition = latest.state == PandoraActivityState.needsYou ||
        latest.state == PandoraActivityState.failed ||
        latest.state == PandoraActivityState.result;

    return Semantics(
      container: true,
      liveRegion: announceTransition,
      label: semanticText,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: PandoraMark(size: 24, color: Colors.white),
          ),
          const SizedBox(width: 11),
          SizedBox.square(
            dimension: 16,
            child: terminal
                ? Icon(
                    latest.state == PandoraActivityState.result
                        ? Icons.check_rounded
                        : latest.state == PandoraActivityState.cancelled
                            ? Icons.stop_rounded
                            : Icons.error_outline_rounded,
                    size: 16,
                    color: statusColor,
                  )
                : CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: statusColor,
                  ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  presentationText,
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
