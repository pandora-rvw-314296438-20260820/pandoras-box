import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PLP Overview is a light owner command center with composer-only bottom chrome', () {
    final shell = File('lib/app/plp_enterprise_shell.dart').readAsStringSync();
    final overview =
        File('lib/features/enterprise/plp_enterprise_overview.dart').readAsStringSync();

    expect(shell, contains('PlpEnterpriseOverview('));
    expect(shell, contains('showNavigation: _index != 5'));
    expect(shell, contains('overviewMode: _index == 5'));
    expect(shell, contains('Ask Pandora anything…'));
    expect(shell, contains('Show today’s arrivals'));
    expect(shell, contains('What needs attention?'));
    expect(shell, contains('Summarize revenue'));
    expect(shell, contains('startVoiceInput()'));

    expect(overview, contains('Color(0xFFFAF8F3)'));
    expect(overview, contains('assets/workspaces/plp-hero.webp'));
    expect(overview, contains('POWERED BY PANDORA'));
    expect(overview, contains('Needs attention'));
    expect(overview, contains('Quick actions'));
    expect(overview, contains('Pandora is waiting for a complete verified resort snapshot'));
    expect(overview, isNot(contains('+18% vs. yesterday')));
    expect(overview, isNot(contains('Mostly sunny')));
  });

  test('PLP Overview bundles the canonical resort sunset hero', () {
    final hero = File('assets/workspaces/plp-hero.webp');
    expect(hero.existsSync(), isTrue);
    expect(hero.lengthSync(), 154842);
  });
}
