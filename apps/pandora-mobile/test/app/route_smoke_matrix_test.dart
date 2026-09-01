import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/features/activity/activity_screen.dart';
import 'package:pandora_mobile/features/approvals/approvals_screen.dart';
import 'package:pandora_mobile/features/command/command_screen.dart';
import 'package:pandora_mobile/features/connections/connections_screen.dart';
import 'package:pandora_mobile/features/diagnostics/developer_diagnostics_screen.dart';
import 'package:pandora_mobile/features/home/home_screen.dart';
import 'package:pandora_mobile/features/intelligence/owner_intelligence_screen.dart';
import 'package:pandora_mobile/features/projects/project_detail_screen.dart';
import 'package:pandora_mobile/features/projects/projects_screen.dart';
import 'package:pandora_mobile/features/safety/safety_screen.dart';
import 'package:pandora_mobile/features/settings/settings_screen.dart';

import '../helpers/fake_owner_api.dart';
import '../helpers/test_app.dart';

/// All-route smoke matrix.
///
/// Owner navigation must raise zero uncaught Flutter exceptions. Every owner
/// destination is pushed as its own route — the path that produced the
/// Portfolio Intelligence crash on a physical device — in both themes, while
/// the provider is healthy and while it is failing.
///
/// This is the regression net that would have caught P0.1 before release.
void main() {
  final destinations = <String, Widget Function()>{
    'Home': () => const HomeScreen(),
    'Projects': () => const ProjectsScreen(),
    'Command': () => const CommandScreen(),
    'Approvals': () => const ApprovalsScreen(),
    'Activity': () => const ActivityScreen(),
    'Settings': () => const SettingsScreen(),
    'Connections': () => const ConnectionsScreen(),
    'Safety': () => const SafetyScreen(),
    'Developer diagnostics': () => const DeveloperDiagnosticsScreen(),
    'Project detail': () => const ProjectDetailScreen(project: fixtureProject),
    for (final section in OwnerIntelligenceSection.values)
      'Portfolio intelligence / ${section.name}': () =>
          OwnerIntelligenceScreen(initialSection: section),
  };

  Future<void> pushDestination(
    WidgetTester tester,
    Widget Function() build, {
    required ThemeMode themeMode,
    required bool failing,
  }) async {
    final repository = FakeRepository()..failing = failing;
    // Dependencies sit above MaterialApp, matching PandoraApp, so that routes
    // pushed onto the app navigator inherit them.
    await tester.pumpWidget(
      PandoraDependencies(
        auth: const FakeAuth(),
        repository: repository,
        diagnostics: DiagnosticsStore(),
        child: testApp(
          themeMode: themeMode,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => build())),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  for (final entry in destinations.entries) {
    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      final theme = themeMode == ThemeMode.dark ? 'Graphite' : 'Porcelain';

      testWidgets('${entry.key} renders in $theme', (tester) async {
        await pushDestination(
          tester,
          entry.value,
          themeMode: themeMode,
          failing: false,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '${entry.key} raised a framework exception in $theme.',
        );
      });

      testWidgets('${entry.key} survives a failing provider in $theme', (
        tester,
      ) async {
        await pushDestination(
          tester,
          entry.value,
          themeMode: themeMode,
          failing: true,
        );
        // A provider outage is an expected condition, never a crash.
        expect(
          tester.takeException(),
          isNull,
          reason: '${entry.key} crashed instead of degrading in $theme.',
        );
      });
    }
  }
}
