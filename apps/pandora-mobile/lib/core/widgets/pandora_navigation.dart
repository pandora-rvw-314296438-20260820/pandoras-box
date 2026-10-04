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
  });

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: Material(
            color: const Color(0xE6333333),
            surfaceTintColor: Colors.transparent,
            shape: const CircleBorder(
              side: BorderSide(color: Color(0x22FFFFFF)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              child: const SizedBox.square(
                dimension: 48,
                child: Center(child: _PandoraMenuGlyph()),
              ),
            ),
          ),
        ),
      );
}

class PandoraTopScrim extends StatelessWidget {
  const PandoraTopScrim({
    super.key,
    this.topOpacity = .72,
    this.midOpacity = .28,
  });

  final double topOpacity;
  final double midOpacity;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: DecoratedBox(
          key: const ValueKey<String>('pandora-top-scrim'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.black.withValues(alpha: topOpacity),
                Colors.black.withValues(alpha: midOpacity),
                Colors.transparent,
              ],
              stops: const <double>[0, .46, 1],
            ),
          ),
        ),
      );
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
    final isSecondaryRoute = ModalRoute.of(context)?.isFirst == false;
    final showPandoraChevron = title == 'Pandora';
    return SizedBox(
      key: const ValueKey<String>('pandora-page-header-floating'),
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSecondaryRoute)
                  const SizedBox.square(
                    dimension: 48,
                    child: BackButton(),
                  ),
                if (openDrawer != null)
                  PandoraMenuButton(
                    key: const ValueKey<String>('pandora-side-panel-open'),
                    onPressed: openDrawer,
                  ),
                if (!isSecondaryRoute && openDrawer == null)
                  const SizedBox(width: 52),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isSecondaryRoute && openDrawer != null ? 108 : 70,
            ),
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
          if (actions.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Material(
                key: const ValueKey<String>('pandora-header-action-capsule'),
                color: const Color(0xE6333333),
                surfaceTintColor: Colors.transparent,
                shape: const StadiumBorder(
                  side: BorderSide(color: Color(0x22FFFFFF)),
                ),
                clipBehavior: Clip.antiAlias,
                child: IconTheme(
                  data: const IconThemeData(color: Color(0xFFF2F4F7)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: actions,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PandoraMenuGlyph extends StatelessWidget {
  const _PandoraMenuGlyph();

  @override
  Widget build(BuildContext context) {
    const foreground = Color(0xFFF2F4F7);
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
