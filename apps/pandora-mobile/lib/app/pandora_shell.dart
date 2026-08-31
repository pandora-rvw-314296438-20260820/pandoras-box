import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/analytics/owner_analytics.dart';
import '../features/approvals/approvals_screen.dart';
import '../features/simple/pandora_v2_ui.dart';
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
    _Destination('Work', Icons.view_agenda_outlined, Icons.view_agenda_rounded),
    _Destination(
      'Needs You',
      Icons.check_circle_outline_rounded,
      Icons.check_circle_rounded,
    ),
  ];

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

  void _select(int value) {
    if (value < 0 || value >= _destinations.length || value == _index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _index = value;
      _visited.add(value);
    });
    final screen = switch (value) {
      0 => 'home',
      1 => 'work',
      2 => 'needs_you',
      _ => 'home',
    };
    unawaited(
      OwnerAnalytics.shared.capture(
        OwnerAnalyticsEvent.screenViewed,
        resultClass: screen,
      ),
    );
  }

  Widget _root(int index) => _roots.putIfAbsent(
        index,
        () => switch (index) {
          0 => SimpleHomeScreen(
              onOpenSystems: () => _select(1),
              onOpenNeedsYou: () => _select(2),
            ),
          1 => const ProjectsScreen(),
          2 => const ApprovalsScreen(),
          _ => const SimpleHomeScreen(),
        },
      );

  ThemeData _theme(ThemeData base) {
    const scheme = ColorScheme.light(
      primary: PandoraV2Colors.ink,
      onPrimary: Colors.white,
      primaryContainer: PandoraV2Colors.soft,
      onPrimaryContainer: PandoraV2Colors.ink,
      secondary: PandoraV2Colors.ink,
      onSecondary: Colors.white,
      surface: PandoraV2Colors.surface,
      onSurface: PandoraV2Colors.ink,
      error: PandoraV2Colors.danger,
      onError: Colors.white,
      outline: PandoraV2Colors.line,
      outlineVariant: PandoraV2Colors.line,
    );
    return base.copyWith(
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: PandoraV2Colors.canvas,
      canvasColor: PandoraV2Colors.canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: PandoraV2Colors.canvas,
        foregroundColor: PandoraV2Colors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: PandoraV2Colors.line,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PandoraV2Colors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: PandoraV2Colors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: PandoraV2Colors.ink, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: PandoraV2Colors.danger),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: _theme(Theme.of(context)),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final body = IndexedStack(
              index: _index,
              children: [
                for (var i = 0; i < _destinations.length; i++)
                  _visited.contains(i) || i == _index
                      ? _root(i)
                      : const SizedBox.shrink(),
              ],
            );
            if (constraints.maxWidth >= 900) {
              return Scaffold(
                backgroundColor: PandoraV2Colors.canvas,
                body: Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _index,
                      onDestinationSelected: _select,
                      backgroundColor: PandoraV2Colors.surface,
                      indicatorColor: PandoraV2Colors.soft,
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        for (final destination in _destinations)
                          NavigationRailDestination(
                            icon: Icon(destination.icon),
                            selectedIcon: Icon(destination.selectedIcon),
                            label: Text(destination.label),
                          ),
                      ],
                    ),
                    const VerticalDivider(
                        width: 1, color: PandoraV2Colors.line),
                    Expanded(child: body),
                  ],
                ),
              );
            }
            return Scaffold(
              backgroundColor: PandoraV2Colors.canvas,
              body: body,
              bottomNavigationBar: _PandoraV2BottomBar(
                destinations: _destinations,
                selectedIndex: _index,
                onSelected: _select,
              ),
            );
          },
        ),
      );
}

class _PandoraV2BottomBar extends StatelessWidget {
  const _PandoraV2BottomBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_Destination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: PandoraV2Colors.canvas,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Container(
            height: 66,
            decoration: BoxDecoration(
              color: PandoraV2Colors.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: PandoraV2Colors.line),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x12000000),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                for (var index = 0; index < destinations.length; index++)
                  Expanded(
                    child: InkResponse(
                      onTap: () => onSelected(index),
                      radius: 34,
                      child: Semantics(
                        selected: index == selectedIndex,
                        button: true,
                        label: destinations[index].label,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              index == selectedIndex
                                  ? destinations[index].selectedIcon
                                  : destinations[index].icon,
                              color: index == selectedIndex
                                  ? PandoraV2Colors.ink
                                  : PandoraV2Colors.muted,
                              size: 22,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              destinations[index].label,
                              style: TextStyle(
                                color: index == selectedIndex
                                    ? PandoraV2Colors.ink
                                    : PandoraV2Colors.muted,
                                fontSize: 10.5,
                                fontWeight: index == selectedIndex
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
