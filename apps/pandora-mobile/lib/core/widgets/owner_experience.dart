import 'package:flutter/material.dart';

import '../design/pandora_tokens.dart';
import 'status_badge.dart';

class OwnerBriefingHero extends StatelessWidget {
  const OwnerBriefingHero({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.message,
    required this.icon,
    this.tone = PandoraStatusTone.informative,
    this.statusLabel,
    this.actionLabel,
    this.onAction,
    this.footer,
  });

  final String eyebrow;
  final String title;
  final String message;
  final IconData icon;
  final PandoraStatusTone tone;
  final String? statusLabel;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final palette = context.pandoraPalette;
    final scheme = Theme.of(context).colorScheme;
    final (accent, onAccent) = switch (tone) {
      PandoraStatusTone.verified => (palette.verified, palette.onVerified),
      PandoraStatusTone.attention => (palette.attention, palette.onAttention),
      PandoraStatusTone.critical => (palette.critical, palette.onCritical),
      PandoraStatusTone.informative => (
          palette.informative,
          palette.onInformative,
        ),
      PandoraStatusTone.neutral => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
    };
    return Semantics(
      container: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(PandoraSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: PandoraRadius.controlBorder,
                    ),
                    child: Icon(icon, color: onAccent),
                  ),
                  const SizedBox(width: PandoraSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          eyebrow.toUpperCase(),
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.9,
                                  ),
                        ),
                        const SizedBox(height: PandoraSpacing.xxs),
                        Text(
                          title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: PandoraSpacing.md),
              Text(message, style: Theme.of(context).textTheme.bodyLarge),
              if (statusLabel != null || footer != null) ...[
                const SizedBox(height: PandoraSpacing.md),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: PandoraSpacing.sm,
                  runSpacing: PandoraSpacing.sm,
                  children: [
                    if (statusLabel != null)
                      StatusBadge(
                        label: statusLabel!,
                        tone: tone,
                        compact: true,
                      ),
                    if (footer != null) footer!,
                  ],
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: PandoraSpacing.md),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: onAction,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(actionLabel!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class OwnerMetric {
  const OwnerMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.tone = PandoraStatusTone.neutral,
    this.semanticLabel,
  });

  final String label;
  final String value;
  final IconData icon;
  final PandoraStatusTone tone;
  final String? semanticLabel;
}

class OwnerMetricGrid extends StatelessWidget {
  const OwnerMetricGrid({super.key, required this.metrics, this.title});

  final List<OwnerMetric> metrics;
  final String? title;

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) return const SizedBox.shrink();
    final grid = Card(
      child: Padding(
        padding: const EdgeInsets.all(PandoraSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Semantics(
                header: true,
                child: Text(
                  title!,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: PandoraSpacing.sm),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final scaler = MediaQuery.textScalerOf(context);
                final scaled = scaler.scale(16) / 16;
                final minimumCellWidth = scaled >= 1.5 ? 168.0 : 136.0;
                final byWidth = ((constraints.maxWidth + PandoraSpacing.xs) /
                        (minimumCellWidth + PandoraSpacing.xs))
                    .floor()
                    .clamp(1, 4);
                final columns =
                    metrics.length < byWidth ? metrics.length : byWidth;
                final gap = PandoraSpacing.xs * (columns - 1);
                final width = (constraints.maxWidth - gap) / columns;
                return Wrap(
                  spacing: PandoraSpacing.xs,
                  runSpacing: PandoraSpacing.xs,
                  children: [
                    for (final metric in metrics)
                      SizedBox(
                        width: width,
                        child: _MetricCell(metric: metric),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
    final ownerCountersUnverified = metrics.length == 3 &&
        metrics[0].label == 'Needs you' &&
        metrics[1].label == 'Working now' &&
        metrics[2].label == 'Portfolio attention' &&
        metrics.every((metric) => metric.value == '—');
    if (!ownerCountersUnverified) return grid;
    return Semantics(
      container: true,
      label:
          'Approvals: not verified\nActive projects: not verified\nNeeds attention: not verified',
      child: grid,
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.metric});

  final OwnerMetric metric;

  @override
  Widget build(BuildContext context) {
    final palette = context.pandoraPalette;
    final scheme = Theme.of(context).colorScheme;
    final accent = switch (metric.tone) {
      PandoraStatusTone.verified => palette.verified,
      PandoraStatusTone.attention => palette.attention,
      PandoraStatusTone.critical => palette.critical,
      PandoraStatusTone.informative => palette.informative,
      PandoraStatusTone.neutral => scheme.onSurfaceVariant,
    };
    return Semantics(
      label: metric.semanticLabel ?? '${metric.label}: ${metric.value}',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 92),
        padding: const EdgeInsets.all(PandoraSpacing.sm),
        decoration: BoxDecoration(
          color: palette.subtleSurface,
          borderRadius: PandoraRadius.controlBorder,
          border: Border.all(color: palette.outlineSoft),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(metric.icon, size: 19, color: accent),
            const SizedBox(height: PandoraSpacing.sm),
            Text(
              metric.value,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
            ),
            const SizedBox(height: PandoraSpacing.xxs),
            Text(
              metric.label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class OwnerSectionHeading extends StatelessWidget {
  const OwnerSectionHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: PandoraSpacing.xxs),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
    if (trailing == null) return heading;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaled = MediaQuery.textScalerOf(context).scale(16) / 16;
        final stack = constraints.maxWidth <= 430 || scaled >= 1.3;
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              const SizedBox(height: PandoraSpacing.sm),
              Align(alignment: Alignment.centerLeft, child: trailing!),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heading),
            const SizedBox(width: PandoraSpacing.sm),
            Flexible(flex: 0, child: trailing!),
          ],
        );
      },
    );
  }
}

class OwnerSignal extends StatelessWidget {
  const OwnerSignal({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone = PandoraStatusTone.neutral,
  });

  final String label;
  final String value;
  final IconData icon;
  final PandoraStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.pandoraPalette;
    final scheme = Theme.of(context).colorScheme;
    final accent = switch (tone) {
      PandoraStatusTone.verified => palette.verified,
      PandoraStatusTone.attention => palette.attention,
      PandoraStatusTone.critical => palette.critical,
      PandoraStatusTone.informative => palette.informative,
      PandoraStatusTone.neutral => scheme.onSurfaceVariant,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(PandoraSpacing.sm),
      decoration: BoxDecoration(
        color: palette.subtleSurface,
        borderRadius: PandoraRadius.controlBorder,
        border: Border.all(color: palette.outlineSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: accent),
          const SizedBox(width: PandoraSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: PandoraSpacing.xxs),
                Text(value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String ownerRelativeTime(DateTime? value, {DateTime? now}) {
  if (value == null) return 'Time not verified';
  final reference = now ?? DateTime.now();
  final difference = reference.difference(value);
  if (difference.isNegative) {
    final until = value.difference(reference);
    if (until.inMinutes < 1) return 'In moments';
    if (until.inHours < 1) return 'In ${until.inMinutes}m';
    if (until.inDays < 1) return 'In ${until.inHours}h';
    return 'In ${until.inDays}d';
  }
  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

IconData providerIconFor(String provider) {
  final value = provider.toLowerCase();
  if (value.contains('github')) return Icons.code_rounded;
  if (value.contains('vercel')) return Icons.cloud_outlined;
  if (value.contains('supabase')) return Icons.storage_rounded;
  if (value.contains('posthog')) return Icons.analytics_outlined;
  if (value.contains('google')) return Icons.search_rounded;
  if (value.contains('email') || value.contains('mail')) {
    return Icons.mail_outline_rounded;
  }
  return Icons.cable_rounded;
}
