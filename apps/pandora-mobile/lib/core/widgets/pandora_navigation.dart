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

  @override
  Widget build(BuildContext context) {
    final openDrawer = PandoraNavigationScope.maybeOf(context)?.openDrawer;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          if (openDrawer != null)
            IconButton(
              key: const ValueKey<String>('pandora-side-panel-open'),
              tooltip: 'Open navigation',
              onPressed: openDrawer,
              icon: const Icon(Icons.menu_rounded),
            )
          else
            const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          ...actions,
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
