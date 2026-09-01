import 'package:flutter/material.dart';

import '../design/pandora_tokens.dart';

class PandoraSurface extends StatelessWidget {
  const PandoraSurface({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.padding = const EdgeInsets.all(PandoraSpacing.lg),
    this.semanticContainer = true,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final bool semanticContainer;

  @override
  Widget build(BuildContext context) {
    final heading = title == null
        ? null
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: PandoraSpacing.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title!,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
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
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: PandoraSpacing.sm),
                trailing!,
              ],
            ],
          );
    return Semantics(
      container: semanticContainer,
      child: Card(
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (heading != null) ...[
                heading,
                const SizedBox(height: PandoraSpacing.md),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}
