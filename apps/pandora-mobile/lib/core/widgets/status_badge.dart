import 'package:flutter/material.dart';

import '../design/pandora_tokens.dart';

enum PandoraStatusTone { neutral, informative, verified, attention, critical }

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.tone,
    this.compact = false,
  });

  final String label;
  final PandoraStatusTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.pandoraPalette;
    final scheme = Theme.of(context).colorScheme;
    final (color, onColor, icon) = switch (tone) {
      PandoraStatusTone.informative => (
          palette.informative,
          palette.onInformative,
          Icons.info_outline_rounded,
        ),
      PandoraStatusTone.verified => (
          palette.verified,
          palette.onVerified,
          Icons.verified_outlined,
        ),
      PandoraStatusTone.attention => (
          palette.attention,
          palette.onAttention,
          Icons.priority_high_rounded,
        ),
      PandoraStatusTone.critical => (
          palette.critical,
          palette.onCritical,
          Icons.error_outline_rounded,
        ),
      PandoraStatusTone.neutral => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          Icons.remove_circle_outline_rounded,
        ),
    };
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(PandoraRadius.control),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? PandoraSpacing.xs : PandoraSpacing.sm,
            vertical: compact ? PandoraSpacing.xxs : PandoraSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 14 : 17, color: onColor),
              const SizedBox(width: PandoraSpacing.xs),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: onColor, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

PandoraStatusTone statusToneFor(String status) {
  final words = status
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((word) => word.isNotEmpty)
      .toSet();
  bool hasAny(Set<String> candidates) =>
      words.intersection(candidates).isNotEmpty;
  if (words.contains('not') ||
      words.contains('unverified') ||
      words.contains('inactive')) {
    return PandoraStatusTone.neutral;
  }
  if (hasAny({
    'blocked',
    'failed',
    'error',
    'critical',
    'high',
    'problem',
    'denied',
    'unhealthy',
    'unprotected',
  })) {
    return PandoraStatusTone.critical;
  }
  if (hasAny({
    'attention',
    'pending',
    'waiting',
    'stale',
    'warning',
    'expired',
    'medium',
    'degraded',
  })) {
    return PandoraStatusTone.attention;
  }
  if (hasAny({
    'verified',
    'healthy',
    'protected',
    'ready',
    'complete',
    'active',
  })) {
    return PandoraStatusTone.verified;
  }
  if (hasAny({'working', 'running', 'progress', 'connected'})) {
    return PandoraStatusTone.informative;
  }
  return PandoraStatusTone.neutral;
}
