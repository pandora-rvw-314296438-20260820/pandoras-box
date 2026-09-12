import 'package:flutter/material.dart';

/// Shared by shell roots. Pushed routes retain their normal back navigation.
class PandoraNavigationScope extends InheritedWidget {
  const PandoraNavigationScope({
    super.key,
    required this.openDrawer,
    required super.child,
  });

  final VoidCallback? openDrawer;

  static PandoraNavigationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PandoraNavigationScope>();

  @override
  bool updateShouldNotify(PandoraNavigationScope oldWidget) =>
      openDrawer != oldWidget.openDrawer;
}

class PandoraPageHeader extends StatelessWidget {
  const PandoraPageHeader({
    super.key,
    required this.title,
    this.actions = const <Widget>[],
  });

  final String title;
  final List<Widget> actions;

  @Override
  Widget build(BuildContext context) {
    final openDrawer = PandoraNavigationScope.maybeOf(context)?.openDrawer;
    final showPandoraChevron = title == 'Pandora';
    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: openDrawer != null
                ? IconButton(
                    key: const ValueKey<String>('pandora-side-panel-open'),
                    tooltip: 'Open navigation',
                    onPressed: openDrawer,
                    icon: const Icon(Icons.menu_rounded),
                  )
                : const SizedBox(width: 48),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 64),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -.2,
                        ),
                  ),
                ),
                if (showPandoraChevron) ...[
                  const SizedBox(width: 3),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 17),
                ],
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                  ...actions,
                  const SizedBox(width: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
