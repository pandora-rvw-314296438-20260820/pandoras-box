import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String screenSource;
  late String gatewaySource;

  setUpAll(() {
    screenSource = File(
      'lib/features/simple/plp_overview_screen.dart',
    ).readAsStringSync();
    gatewaySource = File(
      'lib/core/data/enterprise_plp_overview_api.dart',
    ).readAsStringSync();
  });

  test('PLP owner overview never reads engineering audit telemetry', () {
    expect(screenSource, isNot(contains("from('audit_events')")));
    expect(screenSource, isNot(contains('refs/heads')));
    expect(screenSource, isNot(contains('projectos_projects')));
    expect(screenSource, isNot(contains('github •')));
    expect(screenSource, isNot(contains('vercel •')));
    expect(gatewaySource, isNot(contains("from('audit_events')")));
  });

  test('owner overview reads only normalized business surfaces', () {
    // Surface reads live in the foundation gateway so feature widgets stay
    // free of supabase_flutter (foundation_source_guard).
    expect(gatewaySource, contains("from('enterprise_property_overview_v1')"));
    expect(gatewaySource, contains("from('enterprise_source_connections')"));
    expect(gatewaySource, contains("from('enterprise_attention_items')"));
    expect(gatewaySource, contains("from('enterprise_business_activity')"));
    expect(screenSource, contains('enterprise_plp_overview_api.dart'));
    expect(screenSource, isNot(contains('supabase_flutter')));
  });

  test('owner copy and quick actions are customer facing', () {
    expect(screenSource, contains('PLP Boracay command center'));
    expect(screenSource, contains('Today at a glance'));
    expect(screenSource, contains('Needs your attention'));
    expect(screenSource, contains('Pandora handled'));
    expect(screenSource, contains('Ask Pandora'));
    expect(screenSource, contains('Today’s report'));
    expect(screenSource, contains('Create task'));
    expect(screenSource,
        isNot(contains('System, account and environment summary')));
    expect(screenSource, isNot(contains('system context')));
  });

  test('quick actions force readable foreground and background colors', () {
    expect(screenSource, contains('foregroundColor: PandoraV2Colors.ink'));
    expect(screenSource, contains('backgroundColor: PandoraV2Colors.soft'));
  });

  test('empty operational state does not fabricate hotel metrics', () {
    expect(screenSource,
        contains('Awaiting the first verified live business update'));
    expect(screenSource, contains('Business alerts will appear here'));
    expect(
        screenSource, contains('Completed business actions will appear here'));
    expect(screenSource, isNot(contains('No current Pandora system blockers')));
  });
}
