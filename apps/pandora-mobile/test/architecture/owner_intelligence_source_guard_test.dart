import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('owner intelligence remains owner-readable and governed', () {
    final source = File(
      'lib/features/intelligence/owner_intelligence_screen.dart',
    ).readAsStringSync();

    expect(source, contains('Portfolio intelligence'));
    expect(source, contains('Memory & learning'));
    expect(source, contains('Universal search'));
    expect(source, contains('Notifications'));
    expect(source, contains('Autopilot'));
    expect(source, contains('Release center'));
    expect(source, contains('Continue safe work'));
    expect(source, contains('production release'));
    expect(source, contains('review-gated'));

    expect(source, contains('repository.home()'));
    expect(source, contains('repository.projects'));
    expect(source, contains('repository.approvals()'));
    expect(source, contains('repository.activity'));
    expect(source, contains('repository.connections'));

    expect(source, isNot(contains('http://')));
    expect(source, isNot(contains('https://')));
    expect(source, isNot(contains('service_role')));
    expect(source, isNot(contains('access_token')));
    expect(source, isNot(contains('refresh_token')));
    expect(source, isNot(contains('executePlan')));
    expect(source, isNot(contains('merge-pull-request')));
    expect(source, isNot(contains('deploy production')));
  });

  test('settings exposes the complete secondary owner suite', () {
    final source = File('lib/features/settings/settings_screen.dart')
        .readAsStringSync();

    for (final label in <String>[
      'Portfolio intelligence',
      'Memory & learning',
      'Universal search',
      'Notifications',
      'Autopilot',
      'Release center',
      'Connections',
      'Safety',
      'Developer diagnostics',
    ]) {
      expect(source, contains(label));
    }

    expect(source, contains('clearReadOnlyCache'));
    expect(source, contains('diagnostics.clear'));
    expect(source, contains('auth.signOut'));
  });
}
