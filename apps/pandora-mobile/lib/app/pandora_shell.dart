import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/analytics/owner_analytics.dart';
import '../core/design/pandora_tokens.dart';
import '../features/activity/activity_screen.dart';
import '../features/approvals/approvals_screen.dart';
import '../features/command/command_screen.dart';
import '../features/home/home_screen.dart';
import '../features/projects/projects_screen.dart';

class PandoraShell extends StatefulWidget {
  const PandoraShell({super.key});

  @override
  State<PandoraShell> createState() => _PandoraShellState();
}

class _PandoraShellState extends State<PandoraShell> {
  int _index = 0;
  final Map<int, Widget> _pages = <int, Widget>{};

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

  Widget _page(int index) => _pages.putIfAbsent(
        index,
        () => switch (index) {
          0 => const HomeScreen(),
          1 => const ProjectsScreen(),
          2 => const CommandScreen(),
          3 => const ApprovalsScreen(),
          4 => const ActivityScreen(),
          _ => const HomeScreen(),
        },
      );

  void _select(int value) {
    if (value == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = value);
    final screen = switch (value) {
      0 => 'home',
      1 => 'projects',
      2 => 'command',
      3 => 'approvals',
      4 => 'activity',
      _ => 'home',
    };
    unawaited(
      OwnerAnalytics.shared.capture(
        OwnerAnalyticsEvent.screenViewed,
        resultClass: screen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final destinations = <_Destination>[
      const _Destination('Home', Icons.home_outlined, Icons.home_rounded),
      const _Destination(
        'Projects',
        Icons.workspaces_outline,
        Icons.workspaces_rounded,
      ),
      const _Destination(
        'Command',
        Icons.auto_awesome_outlined,
        Icons.auto_awesome_rounded,
      ),
      const _Destination(
        'Approvals',
        Icons.approval_outlined,
        Icons.approval_rounded,
      ),
      const _Destination(
        'Activity',
        Icons.history_outlined,
        Icons.history_rounded,
      ),
    ];
    final body = IndexedStack(
      index: _index,
      children: [
        for (var index = 0; index < destinations.length; index++)
          _pages.containsKey(index) || index == _index
              ? _page(index)
              : const SizedBox.shrink(),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= PandoraSize.wideBreakpoint;
        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: _select,
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (final destination in destinations)
                        NavigationRailDestination(
                          icon: Icon(destination.icon),
                          selectedIcon: Icon(destination.selectedIcon),
                          label: Text(destination.label),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }
        final palette = context.pandoraPalette;
        return Scaffold(
          body: body,
          bottomNavigationBar: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.strongSurface,
              border: Border(top: BorderSide(color: palette.outlineSoft)),
            ),
            child: SafeArea(
              top: false,
              child: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: _select,
                destinations: [
                  for (final destination in destinations)
                    NavigationDestination(
                      icon: Icon(destination.icon),
                      selectedIcon: Icon(destination.selectedIcon),
                      label: destination.label,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
