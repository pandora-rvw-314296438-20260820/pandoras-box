import 'package:flutter/material.dart';

import '../design/pandora_tokens.dart';
import '../models/pandora_models.dart';

class FreshnessLabel extends StatelessWidget {
  const FreshnessLabel({super.key, required this.freshness, this.now});

  final FreshnessInfo freshness;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final verifiedAt = freshness.lastVerifiedAt;
    final relative = verifiedAt == null
        ? freshness.state.label
        : _displayLabel(freshness, verifiedAt, now ?? DateTime.now());
    final exact = verifiedAt?.toIso8601String();
    return Semantics(
      label: exact == null
          ? 'Data freshness: ${freshness.state.label}. No verified time recorded.'
          : 'Data freshness: ${freshness.state.label}. Last verified $exact.',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              freshness.state == FreshnessState.fresh
                  ? Icons.schedule_rounded
                  : Icons.history_toggle_off_rounded,
              size: 15,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: PandoraSpacing.xxs),
            Flexible(
              child: Text(
                relative,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _displayLabel(
  FreshnessInfo freshness,
  DateTime verifiedAt,
  DateTime now,
) {
  final relative = _relativeTime(verifiedAt, now);
  return switch (freshness.state) {
    FreshnessState.fresh => 'Verified $relative',
    FreshnessState.stale => 'Stale · $relative',
    FreshnessState.notChecked => 'Not checked · $relative',
  };
}

String _relativeTime(DateTime value, DateTime now) {
  final difference = now.difference(value);
  if (difference.isNegative || difference.inMinutes < 1) {
    return 'just now';
  }
  if (difference.inMinutes < 60) {
    return '${difference.inMinutes}m ago';
  }
  if (difference.inHours < 24) {
    return '${difference.inHours}h ago';
  }
  if (difference.inDays < 7) {
    return '${difference.inDays}d';
  }
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
