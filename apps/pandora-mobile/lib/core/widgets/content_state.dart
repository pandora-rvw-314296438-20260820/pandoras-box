import 'package:flutter/material.dart';

import '../design/pandora_tokens.dart';
import 'pandora_surface.dart';

class ContentSkeleton extends StatelessWidget {
  const ContentSkeleton({super.key, this.lines = 4});

  final int lines;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Semantics(
      label: 'Loading content',
      liveRegion: true,
      child: ExcludeSemantics(
        child: PandoraSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 22,
                width: 160,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(PandoraRadius.control),
                ),
              ),
              const SizedBox(height: PandoraSpacing.lg),
              for (var index = 0; index < lines; index++) ...[
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: index == lines - 1 ? 0.62 : 1,
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(
                        PandoraRadius.control,
                      ),
                    ),
                  ),
                ),
                if (index != lines - 1)
                  const SizedBox(height: PandoraSpacing.sm),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyContent extends StatelessWidget {
  const EmptyContent({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => PandoraSurface(
        child: Semantics(
          label: '$title. $message',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: PandoraSpacing.xl),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 38,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: PandoraSpacing.md),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: PandoraSpacing.xs),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: PandoraSpacing.lg),
                  OutlinedButton(
                      onPressed: onAction, child: Text(actionLabel!)),
                ],
              ],
            ),
          ),
        ),
      );
}

class ErrorContent extends StatelessWidget {
  const ErrorContent({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) => PandoraSurface(
        child: Semantics(
          liveRegion: true,
          label: '$title. $message',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: PandoraSpacing.lg),
            child: Column(
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 38,
                  color: context.pandoraPalette.attention,
                ),
                const SizedBox(height: PandoraSpacing.md),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: PandoraSpacing.xs),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: PandoraSpacing.lg),
                  FilledButton.tonalIcon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(retryLabel),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

class DegradedContentNotice extends StatelessWidget {
  const DegradedContentNotice({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => PandoraSurface(
        child: Semantics(
          liveRegion: true,
          label: 'Showing saved information. $message',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.history_rounded,
                  color: context.pandoraPalette.attention),
              const SizedBox(width: PandoraSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Showing saved information',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: PandoraSpacing.xxs),
                    Text(message),
                    const SizedBox(height: PandoraSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Check live state'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
