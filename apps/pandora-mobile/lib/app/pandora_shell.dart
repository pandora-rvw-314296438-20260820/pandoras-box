import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/analytics/owner_analytics.dart';
import '../core/design/pandora_tokens.dart';
import '../features/approvals/approvals_screen.dart';
import '../features/simple/ask_pandora_screen.dart';
import '../features/simple/more_screen.dart';
import '../features/simple/simple_home_screen.dart';
import '../features/simple/systems_screen.dart';

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
      0 => const SimpleHomeScreen(),
      1 => const SystemsScreen(),
      2 => const AskPandoraScreen(),
      3 => const ApprovalsScreen(),
      4 => const MoreScreen(),
      _ => const SimpleHomeScreen(),
    },
  );

  void _select(int value) {
    if (value == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = value);
    final screen = switch (value) {
      0 => 'home',
      1 => 'systems',
      2 => 'ask_pandora',
      3 => 'needs_you',
      4 => 'more',
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
    const destinations = <_Destination>[
      _Destination('Home', Icons.home_outlined, Icons.home_rounded),
      _Destination(
        'Systems',
        Icons.grid_view_outlined,
        Icons.grid_view_rounded,
      ),
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
      _Destination('More', Icons.more_horiz_rounded, Icons.more_horiz_rounded),
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
                      for (var index = 0; index < destinations.length; index++)
                        NavigationRailDestination(
                          icon: _DestinationIcon(
                            destination: destinations[index],
                            selected: false,
                          ),
                          selectedIcon: _DestinationIcon(
                            destination: destinations[index],
                            selected: true,
                          ),
                          label: Text(destinations[index].label),
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
                height: 76,
                selectedIndex: _index,
                onDestinationSelected: _select,
                destinations: [
                  for (var index = 0; index < destinations.length; index++)
                    NavigationDestination(
                      icon: _DestinationIcon(
                        destination: destinations[index],
                        selected: false,
                      ),
                      selectedIcon: _DestinationIcon(
                        destination: destinations[index],
                        selected: true,
                      ),
                      label: destinations[index].label,
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

class _DestinationIcon extends StatelessWidget {
  const _DestinationIcon({required this.destination, required this.selected});

  final _Destination destination;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(selected ? destination.selectedIcon : destination.icon);
    if (!destination.emphasized) return icon;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Ask Pandora',
      button: true,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.primary,
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: .12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(
          selected ? destination.selectedIcon : destination.icon,
          color: scheme.onPrimary,
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
