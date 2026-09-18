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

  test('owner overview keeps only business decision surfaces', () {
    expect(source, contains('Property overview'));
    expect(source, contains("_sectionTitle(Icons.insights_rounded, 'Today')"));
    expect(source, contains('Needs your attention'));
    expect(source, contains('Pandora handled'));
    expect(source, isNot(contains('Pandora brief')));
    expect(source, isNot(contains('Quick actions')));
    expect(source, isNot(contains('Business data coverage')));
    expect(source, isNot(contains('Today’s report')));
    expect(source, isNot(contains('Create task')));
    expect(source, isNot(contains('System, account and environment summary')));
    expect(source, isNot(contains('system context')));
    expect(source, contains('PRIVATE OPERATING SYSTEM'));
    expect(source, contains('final baseHeight = narrow ? 190.0 : 224.0;'));
    expect(source, contains('border: Border.all(color: const Color(0x2ED0A16F))'));
  });

  test('owner overview relies on the persistent page command bar', () {
    expect(source, isNot(contains('Widget _quickActions()')));
    expect(source, isNot(contains('Widget _actionButton(')));
    expect(source, contains('Command prepared in the Pandora bar below.'));
  });

  test('overview preserves meaning at large text and minimum action targets', () {
    expect(source, contains('MediaQuery.textScalerOf(context).scale(1)'));
    expect(source, contains('textScale >= 1.8'));
    expect(source, contains('minimumSize: const Size(48, 48)'));
    expect(source, isNot(contains("Text(label, overflow: TextOverflow.ellipsis)")));
  });

  test('empty operational state does not fabricate hotel metrics', () {
    expect(
        source, contains('Awaiting the first verified live business update'));
    expect(source,
        contains('Business alerts will appear after live operating data connects.'));
    expect(source, contains('Nothing needs your attention'));
    expect(source, isNot(contains('Completed business actions will appear here')));
    expect(source, isNot(contains('No current Pandora system blockers')));
  });
}