import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/analytics/owner_analytics.dart';
import '../core/widgets/pandora_mark.dart';
import '../features/approvals/approvals_screen.dart';
import '../features/simple/ask_pandora_screen.dart';
import '../features/simple/business_screen.dart';
import '../features/simple/pandora_simple_ui.dart';
import '../features/simple/projects_screen.dart';
import '../features/simple/simple_home_screen.dart';

class PandoraShell extends StatefulWidget {
  const PandoraShell({super.key});

  @override
  State<PandoraShell> createState() => _PandoraShellState();
}

class _PandoraShellState extends State<PandoraShell> {
  static const _destinations = <_Destination>[
    _Destination('Home', Icons.home_outlined, Icons.home_rounded),
    _Destination('Projects', Icons.folder_outlined, Icons.folder_rounded),
    _Destination(
      'Ask Pandora',
      Icons.auto_awesome_outlined,
      Icons.auto_awesome_rounded,
      emphasized: true,
    ),
    _Destination(
      'Needs You',
      Icons.notifications_none_rounded,
      Icons.notifications_rounded,
    ),
    _Destination('Business', Icons.insights_outlined, Icons.insights_rounded),
  ];

  final List<GlobalKey<NavigatorState>> _navigatorKeys = List.generate(
    _destinations.length,
    (_) => GlobalKey<NavigatorState>(),
  );
  final Map<int, Widget> _roots = <int, Widget>{};
  final Set<int> _visited = <int>{0};
  int _index = 0;

  @override
  void initState() {
    super.initState();
    unawaited(OwnerAnalytics.shared.capture(OwnerAnalyticsEvent.appOpened));
    unawaited(
      OwnerAnalytics.shared.capture(
        OwnerAnalyticsEvent.screenViewed,
        resultClass: 'home',
      ),
    );
  }

  Widget _root(int index) => _roots.putIfAbsent(
        index,
        () => switch (index) {
          0 => SimpleHomeScreen(
              onAskPandora: (prompt) => _openAskPandora(prompt),
              onOpenSystems: () => _select(1),
              onOpenNeedsYou: () => _select(3),
            ),
          1 => const ProjectsScreen(),
          2 => const AskPandoraScreen(),
          3 => const ApprovalsScreen(),
          4 => const SimpleBusinessScreen(),
          _ => const SimpleHomeScreen(),
        },
      );

  Widget _tabNavigator(int index) => Navigator(
        key: _navigatorKeys[index],
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => _root(index),
        ),
      );

  void _openAskPandora([String? prompt]) {
    _select(2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = _navigatorKeys[2].currentState;
      if (navigator == null || prompt == null || prompt.trim().isEmpty) return;
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => AskPandoraScreen(initialPrompt: prompt),
        ),
      );
    });
  }

  void _select(int value) {
    if (value < 0 || value >= _destinations.length) return;
    if (value == _index) {
      final navigator = _navigatorKeys[value].currentState;
      if (navigator != null && navigator.canPop()) {
        navigator.popUntil((route) => route.isFirst);
      }
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _index = value;
      _visited.add(value);
    });
    final screen = switch (value) {
      0 => 'home',
      1 => 'projects',
      2 => 'ask_pandora',
      3 => 'needs_you',
      4 => 'business',
      _ => 'home',
    };
    unawaited(
      OwnerAnalytics.shared.capture(
        OwnerAnalyticsEvent.screenViewed,
        resultClass: screen,
      ),
    );
  }

  ThemeData _simpleTheme(ThemeData base) {
    const scheme = ColorScheme.light(
      primary: PandoraSimpleColors.red,
      onPrimary: Colors.white,
      primaryContainer: PandoraSimpleColors.blush,
      onPrimaryContainer: PandoraSimpleColors.deepRed,
      secondary: PandoraSimpleColors.red,
      onSecondary: Colors.white,
      surface: PandoraSimpleColors.surface,
      onSurface: PandoraSimpleColors.ink,
      error: Color(0xFFB42318),
      onError: Colors.white,
      outline: PandoraSimpleColors.line,
      outlineVariant: Color(0xFFF0EFEC),
    );
    return base.copyWith(
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: PandoraSimpleColors.canvas,
      canvasColor: PandoraSimpleColors.canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: PandoraSimpleColors.canvas,
        foregroundColor: PandoraSimpleColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: PandoraSimpleColors.line,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: PandoraSimpleColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: PandoraSimpleColors.red,
            width: 1.4,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFB42318)),
        ),
      ),
    );
  }

  void _handleBack(bool didPop, Object? result) {
    if (didPop) return;
    final navigator = _navigatorKeys[_index].currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return;
    }
    if (_index != 0) _select(0);
  }

  @override
  Widget build(BuildContext context) {
    final body = IndexedStack(
      index: _index,
      children: [
        for (var index = 0; index < _destinations.length; index++)
          _visited.contains(index) || index == _index
              ? _tabNavigator(index)
              : const SizedBox.shrink(),
      ],
    );

    return Theme(
      data: _simpleTheme(Theme.of(context)),
      child: PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: _handleBack,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useRail = constraints.maxWidth >= 900;
            if (!useRail) {
              return Scaffold(
                backgroundColor: PandoraSimpleColors.canvas,
                body: body,
                bottomNavigationBar: _PandoraBottomBar(
                  destinations: _destinations,
                  selectedIndex: _index,
                  onSelected: _select,
                ),
              );
            }
            return Scaffold(
              backgroundColor: PandoraSimpleColors.canvas,
              body: Row(
                children: [
                  NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: _select,
                    backgroundColor: PandoraSimpleColors.surface,
                    indicatorColor: PandoraSimpleColors.blush,
                    labelType: NavigationRailLabelType.all,
                    minWidth: 92,
                    groupAlignment: -0.55,
                    leading: const Padding(
                      padding: EdgeInsets.only(top: 18, bottom: 18),
                      child: PandoraMark(
                        size: 44,
                        color: PandoraSimpleColors.red,
                      ),
                    ),
                    destinations: [
                      for (final destination in _destinations)
                        NavigationRailDestination(
                          icon: destination.emphasized
                              ? const PandoraMark(
                                  size: 25,
                                  color: PandoraSimpleColors.red,
                                )
                              : Icon(destination.icon),
                          selectedIcon: destination.emphasized
                              ? const PandoraMark(
                                  size: 27,
                                  color: PandoraSimpleColors.deepRed,
                                )
                              : Icon(destination.selectedIcon),
                          label: Text(destination.label),
                        ),
                    ],
                  ),
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: PandoraSimpleColors.line,
                  ),
                  Expanded(child: body),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PandoraBottomBar extends StatelessWidget {
  const _PandoraBottomBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_Destination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          color: PandoraSimpleColors.surface,
          border: Border(top: BorderSide(color: PandoraSimpleColors.line)),
          boxShadow: [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 18,
              offset: Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 86,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var index = 0; index < destinations.length; index++)
                  Expanded(
                    child: _BottomDestination(
                      destination: destinations[index],
                      selected: index == selectedIndex,
                      onTap: () => onSelected(index),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}

class _BottomDestination extends StatelessWidget {
  const _BottomDestination({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground =
        selected ? PandoraSimpleColors.red : const Color(0xFF4E4E4B);
    if (destination.emphasized) {
      return Semantics(
        selected: selected,
        button: true,
        label: destination.label,
        child: InkResponse(
          onTap: onTap,
          radius: 42,
          child: Transform.translate(
            offset: const Offset(0, -15),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 66,
                  height: 66,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: PandoraSimpleColors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 5),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x36000000),
                        blurRadius: 16,
                        offset: Offset(0, 7),
                      ),
                    ],
                  ),
                  child: const PandoraMark(size: 34, color: Colors.white),
                ),
                const SizedBox(height: 3),
                Text(
                  destination.label,
                  maxLines: 1,
                  style: const TextStyle(
                    color: PandoraSimpleColors.deepRed,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      child: InkResponse(
        onTap: onTap,
        radius: 34,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                color: foreground,
                size: 27,
              ),
              const SizedBox(height: 6),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                style: TextStyle(
                  color: foreground,
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 34 : 0,
                height: 3,
                decoration: BoxDecoration(
                  color: PandoraSimpleColors.red,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Destination {
  const _Destination(
    this.label,
    this.icon,
    this.selectedIcon, {
    this.emphasized = false,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool emphasized;
}
