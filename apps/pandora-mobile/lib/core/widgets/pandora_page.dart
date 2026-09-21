import 'package:flutter/material.dart';

import '../design/pandora_tokens.dart';
import 'pandora_mark.dart';
import 'pandora_navigation.dart';
import 'pandora_route_boundary.dart';

class PandoraPage extends StatelessWidget {
  const PandoraPage({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const <Widget>[],
    this.onRefresh,
    this.showProductMark = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final Future<void> Function()? onRefresh;
  final bool showProductMark;

  @override
  Widget build(BuildContext context) {
    final navigation = PandoraNavigationScope.maybeOf(context);
    final openDrawer = navigation?.openDrawer;
    final topInset = MediaQuery.paddingOf(context).top;
    const chromeHeight = 60.0;

    final content = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            PandoraSpacing.md,
            topInset + chromeHeight + PandoraSpacing.sm,
            PandoraSpacing.md,
            PandoraSpacing.xxl,
          ),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: PandoraSize.contentMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (showProductMark) ...[
                          const PandoraMark(size: 36),
                          const SizedBox(width: PandoraSpacing.sm),
                        ],
                        Expanded(
                          child: Text(
                            title,
                            key: const ValueKey<String>('pandora-page-title'),
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -.45,
                                ),
                          ),
                        ),
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: PandoraSpacing.sm),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                    const SizedBox(height: PandoraSpacing.md),
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    final scrollable = onRefresh == null
        ? content
        : RefreshIndicator(onRefresh: onRefresh!, child: content);

    return PandoraRouteBoundary(
      child: Stack(
        children: [
          Positioned.fill(child: scrollable),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    if (openDrawer != null)
                      PandoraMenuButton(
                        key: const ValueKey<String>('pandora-side-panel-open'),
                        onPressed: openDrawer,
                      )
                    else if (Navigator.of(context).canPop())
                      const SizedBox.square(
                        dimension: 44,
                        child: BackButton(),
                      )
                    else
                      const SizedBox.square(dimension: 44),
                    const Spacer(),
                    ...actions,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
