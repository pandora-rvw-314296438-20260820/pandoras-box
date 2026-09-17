import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/design/pandora_tokens.dart';

List<File> dartFiles(String directory) => Directory(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .toList(growable: false);

void main() {
  test('bootstrap owns initialization, not feature presentation', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source.split('\n').length, lessThan(80));
    expect(source, isNot(contains('Scaffold(')));
    expect(source, isNot(contains('class Home')));
    expect(source, contains('PandoraApp('));
  });

  test('startup keeps independent I/O concurrent and maintenance post-frame',
      () {
    final source = File('lib/main.dart').readAsStringSync();
    final localFuture = source.indexOf('final localStoreFuture =');
    final supabaseFuture = source.indexOf('final supabaseInitialization =');
    final firstAwait =
        source.indexOf('final localStore = await localStoreFuture;');
    final runAppAt = source.indexOf('runApp(');
    final purgeAt = source.indexOf('localStore.purgeExpired(');
    expect(localFuture, greaterThanOrEqualTo(0));
    expect(supabaseFuture, greaterThan(localFuture));
    expect(firstAwait, greaterThan(supabaseFuture));
    expect(purgeAt, greaterThan(runAppAt));
    expect(source, contains('addPostFrameCallback'));
  });

  test('activity stream teardown never blocks the next owner action', () {
    final source = File(
      'lib/core/activity/pandora_activity_timeline_controller.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('await previous.cancel()')));
    expect(
      'unawaited(previous.cancel())'.allMatches(source).length,
      greaterThanOrEqualTo(2),
    );
  });

  test(
    'feature widgets do not import transport, Supabase, or JSON rendering',
    () {
      final combined = dartFiles('lib/features')
          .map((file) => file.readAsStringSync())
          .join('\n');
      expect(combined, isNot(contains('package:http/')));
      expect(combined, isNot(contains('supabase_flutter')));
      expect(combined, isNot(contains('Supabase.instance')));
      expect(combined, isNot(contains('jsonDecode(')));
      expect(combined, isNot(contains('JsonView')));
    },
  );

  test('canonical shell keeps the three V2 owner destinations', () {
    final source = File('lib/app/pandora_shell.dart').readAsStringSync();
    final positions = <String>[
      "'Home'",
      "'Work'",
      "'Needs You'",
    ].map(source.indexOf).toList(growable: false);
    expect(positions, everyElement(greaterThanOrEqualTo(0)));
    expect(List<int>.from(positions)..sort(), positions);
    expect(source, contains('NavigationRail('));
    expect(source, contains('_PandoraV2BottomBar('));
    expect(source, isNot(contains("_Destination('Ask Pandora'")));

    final home =
        File('lib/features/simple/simple_home_screen.dart').readAsStringSync();
    expect(home, contains('PandoraV2IntentSurface('));
    expect(home, contains("hintText: 'Tell Pandora what you want…'"));
  });

  test('foundation geometry and minimum target are canonical', () {
    expect(
      <double>[
        PandoraSpacing.xxs,
        PandoraSpacing.xs,
        PandoraSpacing.sm,
        PandoraSpacing.md,
        PandoraSpacing.lg,
        PandoraSpacing.xl,
        PandoraSpacing.xxl,
        PandoraSpacing.xxxl,
        PandoraSpacing.display,
      ],
      <double>[4, 8, 12, 16, 20, 24, 32, 40, 48],
    );
    expect(PandoraSize.minimumTouchTarget, 48);
  });

  test('no incompatible owner API fallback is configured', () {
    final source = File('lib/pandora_config.dart').readAsStringSync();
    expect(source, isNot(contains('ownerApiFallbackBaseUrl')));
    expect(source, isNot(contains('ownerApiBaseUrls')));
    expect(source, isNot(contains('mcpmaster.vercel.app/api/operator')));
  });

  test('memory cache is limited to explicitly safe summary lists', () {
    final source =
        File('lib/core/data/read_only_memory_cache.dart').readAsStringSync();
    expect(source, contains('List<ProjectSummary>'));
    expect(source, contains('List<AuditEvent>'));
    expect(source, contains('List<ConnectionSummary>'));
    expect(source, isNot(contains('ProjectDetail')));
    expect(source, isNot(contains('ApprovalSummary')));
    expect(source, isNot(contains('SafetyOverview')));
    expect(source, isNot(contains('IntakeReceipt')));
  });
}
