import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = <String>[
      File('lib/features/simple/plp_overview_screen.dart').readAsStringSync(),
      File('lib/core/data/plp_overview_repository.dart').readAsStringSync(),
    ].join('\n');
  });

  test('PLP owner overview never reads engineering audit telemetry', () {
    expect(source, isNot(contains("from('audit_events')")));
    expect(source, isNot(contains('refs/heads')));
    expect(source, isNot(contains('projectos_projects')));
    expect(source, isNot(contains('github •')));
    expect(source, isNot(contains('vercel •')));
  });

  test('owner overview reads only normalized business surfaces', () {
    expect(source, contains("from('enterprise_property_overview_v1')"));
    expect(source, contains("from('enterprise_source_connections')"));
    expect(source, contains("from('enterprise_attention_items')"));
    expect(source, contains("from('enterprise_business_activity')"));
  });

  test('owner copy and quick actions are customer facing', () {
    expect(source, contains('Your property at a glance.'));
    expect(source, contains('Today at a glance'));
    expect(source, contains('Needs your attention'));
    expect(source, contains('Pandora handled'));
    expect(source, contains('Ask Pandora'));
    expect(source, contains('Today’s report'));
    expect(source, contains('Create task'));
    expect(source, isNot(contains('System, account and environment summary')));
    expect(source, isNot(contains('system context')));
  });

  test('quick actions force readable foreground and background colors', () {
    expect(source, contains('foregroundColor: PandoraV2Colors.ink'));
    expect(source, contains('backgroundColor: PandoraV2Colors.soft'));
  });

  test('empty operational state does not fabricate hotel metrics', () {
    expect(
        source, contains('Awaiting the first verified live business update'));
    expect(source, contains('Business alerts will appear here'));
    expect(source, contains('Completed business actions will appear here'));
    expect(source, isNot(contains('No current Pandora system blockers')));
  });
}
