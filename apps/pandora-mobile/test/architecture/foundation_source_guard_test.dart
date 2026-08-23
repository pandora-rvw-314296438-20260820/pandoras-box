import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/design/pandora_tokens.dart';

List<File> dartFiles(String directory) =>
    Directory(directory)
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

  test('canonical shell has five owner destinations in order', () {
    final source = File('lib/app/pandora_shell.dart').readAsStringSync();
    final positions = <String>[
      "'Home'",
      "'Projects'",
      "'Command'",
      "'Approvals'",
      "'Activity'",
    ].map(source.indexOf).toList(growable: false);
    expect(positions, everyElement(greaterThanOrEqualTo(0)));
    expect(List<int>.from(positions)..sort(), positions);
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
    final source = File('lib/core/data/read_only_memory_cache.dart')
        .readAsStringSync();
    expect(source, contains('List<ProjectSummary>'));
    expect(source, contains('List<AuditEvent>'));
    expect(source, contains('List<ConnectionSummary>'));
    expect(source, isNot(contains('ProjectDetail')));
    expect(source, isNot(contains('ApprovalSummary')));
    expect(source, isNot(contains('SafetyOverview')));
    expect(source, isNot(contains('IntakeReceipt')));
  });
}
