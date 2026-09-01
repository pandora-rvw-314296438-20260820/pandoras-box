import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Simple Mode keeps the canonical four-layer safety board', () {
    final source = File('lib/features/simple/simple_safety_screen.dart')
        .readAsStringSync();

    for (final label in const [
      'Identity & Access',
      'Approval & Execution',
      'Source Authority',
      'Runtime & Secrets',
      'Healthy',
      'Needs attention',
      'Blocked',
      'Not checked',
      'Not applicable',
    ]) {
      expect(source, contains(label));
    }
    expect(source, contains('No aggregate score'));
    expect(source, isNot(contains('security score')));
  });

  test('Simple Mode uses rail navigation on large screens', () {
    final source = File('lib/app/pandora_shell.dart').readAsStringSync();
    expect(source, contains('constraints.maxWidth >= 900'));
    expect(source, contains('NavigationRail('));
    expect(source, contains('_PandoraV2BottomBar('));
  });

  test('professional safety details remain behind More', () {
    final source = File('lib/features/simple/more_screen.dart')
        .readAsStringSync();
    expect(source, contains('const SimpleSafetyScreen()'));
    expect(source, contains("title: 'Safety details'"));
    expect(source, contains('const SafetyScreen()'));
  });

  test('owner journeys cover the remaining source-level master-plan gaps', () {
    final more = File('lib/features/simple/more_screen.dart')
        .readAsStringSync();
    final projects = File('lib/features/projects/projects_screen.dart')
        .readAsStringSync();
    final connections = File('lib/features/connections/connections_screen.dart')
        .readAsStringSync();
    final approvals = File('lib/features/approvals/approvals_screen.dart')
        .readAsStringSync();
    expect(more, contains("title: 'Daily briefing'"));
    expect(more, contains("title: 'Saved evidence'"));
    for (final label in const [
      'Needs me',
      'Active',
      'Blocked',
      'Stale',
      'Recently changed',
      'Production verified',
    ]) {
      expect(projects, contains(label));
    }
    for (final label in const [
      'Test now',
      'Connect',
      'Reconnect',
      'Disconnect',
    ]) {
      expect(connections, contains(label));
    }
    expect(approvals, contains('View details'));
    expect(approvals, contains('Sanitized change summary'));
    expect(approvals, contains('Undo available'));
  });

  test('Simple Mode avoids internal state and cache jargon', () {
    final systems = File('lib/features/simple/systems_screen.dart')
        .readAsStringSync();
    final briefing = File('lib/features/simple/simple_briefing_screen.dart')
        .readAsStringSync();

    expect(systems, contains('systems currently visible to you.'));
    expect(systems, isNot(contains('current owner state')));
    expect(briefing, contains("_metric('Working'"));
    expect(briefing, contains('latest saved information'));
    expect(briefing, isNot(contains('last-known cached evidence')));
    expect(briefing, isNot(contains('Some live checks are degraded')));
  });

  test('Simple Home keeps fail-closed truth in owner language', () {
    final home = File('lib/features/simple/simple_home_screen.dart')
        .readAsStringSync();

    expect(home, contains('summary.countersVerified'));
    expect(home, contains('summary.approvalCount > 0'));
    expect(home, contains('Your work is still safe'));
    expect(home, contains('Pandora could not load it yet.'));
    expect(home, isNot(contains('Decision counters have not been verified.')));
    expect(home, isNot(contains('No active work is verified')));
  });

  test('build preview separates prototype from live execution', () {
    final source = File('lib/features/simple/build_preview_flow.dart')
        .readAsStringSync();
    expect(
      source,
      contains('final waitingForDecision = receipt.needsApproval;'),
    );
    expect(source, contains('active: !waitingForDecision'));
    expect(source, contains('Prototype preview'));
    expect(
      source,
      contains('This is a prototype. It is not live or production verified.'),
    );
    expect(
      source,
      contains(
        'Nothing will change until you approve the decision in Needs You.',
      ),
    );
    expect(source, contains('Independent checks have not finished yet'));
    expect(source, contains('supporting proof.'));
    expect(source, isNot(contains('Provider and exact-source checks')));
    expect(source, isNot(contains('governed work')));
    expect(source, isNot(contains('Live preview available')));
    expect(
      source,
      isNot(
        contains(
          'Pandora will continue working and notify you when a decision is needed',
        ),
      ),
    );
  });
}
