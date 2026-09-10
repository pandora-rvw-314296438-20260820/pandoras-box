import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/analytics/owner_analytics.dart';
import '../core/widgets/pandora_mark.dart';
import '../core/widgets/pandora_navigation.dart';
import '../features/activity/activity_screen.dart';
import '../features/connections/connections_screen.dart';
import '../features/simple/offline_evidence_screen.dart';
import '../features/simple/simple_safety_screen.dart';
import '../features/approvals/approvals_screen.dart';
import '../features/simple/ask_pandora_screen.dart';
import '../features/simple/more_screen.dart';
import '../features/simple/pandora_v2_ui.dart';
import '../features/simple/projects_screen.dart';

class PandoraChatShell extends StatefulWidget {
  const PandoraChatShell({super.key});

  @override
  State<PandoraChatShell> createState() => _PandoraChatShellState();
}

class _PandoraChatShellState extends State<PandoraChatShell> {
  static const _destinations = <_ChatDestination>[
    _ChatDestination(
      'Pandora',
      Icons.chat_bubble_outline_rounded,
      Icons.chat_bubble_rounded,
    ),
    _ChatDestination(
      'Projects',
      Icons.folder_outlined,
      Icons.folder_rounded,
    ),
    _ChatDestination(
      'Needs You',
      Icons.check_circle_outline_rounded,
      Icons.check_circle_rounded,
    ),
    _ChatDestination(
      'More',
      Icons.more_horiz_rounded,
      Icons.more_horiz_rounded,
    ),
    _ChatDestination(
      'Activity',
      Icons.history_rounded,
      Icons.history_rounded,
    ),
    _ChatDestination(
      'Connections',
      Icons.cable_outlined,
      Icons.cable_rounded,
    ),
    _ChatDestination(
      'Saved evidence',
      Icons.offline_pin_outlined,
      Icons.offline_pin_rounded,
    ),
    _ChatDestination(
      'Verify & Safety',
      Icons.shield_outlined,
      Icons.shield_rounded,
    ),
  ];

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
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
        resultClass: 'pandora_chat',
      ),
    );
  }

  void _select(int value) {
    if (value < 0 || value >= _destinations.length) return;
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
    if (value == _index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _index = value;
      _visited.add(value);
    });
    final screen = switch (value) {
      0 => 'pandora_chat',
      1 => 'projects',
      2 => 'needs_you',
      3 => 'more',
      4 => 'activity',
      5 => 'connections',
      6 => 'saved_evidence',
      7 => 'verify_safety',
      _ => 'pandora_chat',
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
          0 => const AskPandoraScreen(),
          1 => const ProjectsScreen(),
          2 => const ApprovalsScreen(),
          3 => const MoreScreen(),
          4 => const ActivityScreen(),
          5 => const ConnectionsScreen(),
          6 => const OfflineEvidenceScreen(),
          7 => const SimpleSafetyScreen(),
          _ => const AskPandoraScreen(),
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
                    SizedBox(
                      width: 264,
                      child: SafeArea(
                        child: _PandoraSidePanel(
                          destinations: _destinations,
                          selectedIndex: _index,
                          onSelected: _select,
                        ),
                      ),
                    ),
                    const VerticalDivider(
                      width: 1,
                      color: PandoraV2Colors.line,
                    ),
                    Expanded(
                      child: PandoraNavigationScope(
                        openDrawer: null,
                        child: body,
                      ),
                    ),
                  ],
                ),
              );
            }

            return Scaffold(
              key: _scaffoldKey,
              backgroundColor: PandoraV2Colors.canvas,
              drawer: Drawer(
                width: 286,
                backgroundColor: PandoraV2Colors.surface,
                surfaceTintColor: Colors.transparent,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: SafeArea(
                  child: _PandoraSidePanel(
                    destinations: _destinations,
                    selectedIndex: _index,
                    onSelected: _select,
                  ),
                ),
              ),
              body: PandoraNavigationScope(
                openDrawer: () => _scaffoldKey.currentState?.openDrawer(),
                child: body,
              ),
            );
          },
        ),
      );
}

class _PandoraSidePanel extends StatelessWidget {
  const _PandoraSidePanel({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_ChatDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: PandoraV2Colors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 22, 18, 18),
              child: Row(
                children: [
                  PandoraMark(size: 28),
                  SizedBox(width: 11),
                  Text(
                    'Pandora',
                    style: TextStyle(
                      color: PandoraV2Colors.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.35,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: PandoraV2Colors.line),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
                children: [
                  for (final index in const <int>[0, 1, 2, 4, 5, 6, 7, 3])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        selected: index == selectedIndex,
                        selectedColor: PandoraV2Colors.ink,
                        iconColor: PandoraV2Colors.muted,
                        textColor: PandoraV2Colors.ink,
                        selectedTileColor: PandoraV2Colors.soft,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        leading: Icon(
                          index == selectedIndex
                              ? destinations[index].selectedIcon
                              : destinations[index].icon,
                          size: 22,
                        ),
                        title: Text(
                          destinations[index].label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: index == selectedIndex
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        onTap: () => onSelected(index),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ChatDestination {
  const _ChatDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
