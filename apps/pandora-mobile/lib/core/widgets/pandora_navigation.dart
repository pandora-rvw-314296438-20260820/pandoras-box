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

class PandoraMenuButton extends StatelessWidget {
  const PandoraMenuButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Open navigation',
    this.editorial = false,
  });

  final VoidCallback onPressed;
  final String tooltip;
  final bool editorial;

  @override
  Widget build(BuildContext context) {
    final foreground =
        editorial ? const Color(0xFF171512) : const Color(0xFFF2F4F7);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: editorial ? Colors.transparent : const Color(0xD914171C),
          surfaceTintColor: Colors.transparent,
          shape: editorial
              ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
              : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                  side: const BorderSide(color: Color(0x22FFFFFF)),
                ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 44,
              child: Center(
                child: _PandoraMenuGlyph(color: foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
    final showPandoraChevron = title == 'Pandora';
    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: openDrawer != null
                ? PandoraMenuButton(
                    key: const ValueKey<String>('pandora-side-panel-open'),
                    onPressed: openDrawer,
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
                          decoration: TextDecoration.none,
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

class _PandoraMenuGlyph extends StatelessWidget {
  const _PandoraMenuGlyph({this.color = const Color(0xFFF2F4F7)});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final foreground = color;
    return SizedBox(
      width: 20,
      height: 16,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MenuBar(width: 20, color: foreground),
          Align(
            alignment: Alignment.centerRight,
            child: _MenuBar(width: 14, color: foreground),
          ),
          _MenuBar(width: 17, color: foreground),
        ],
      ),
    );
  }
}

class _MenuBar extends StatelessWidget {
  const _MenuBar({required this.width, required this.color});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: 2,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(99),
        ),
      );
}
