import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/pandora_repository.dart';

void main() {
  test(
    'fallback safety integrations collapse duplicate providers fail closed',
    () {
      final overview = SafetyOverview.fromJson(<String, Object?>{
        'state': 'degraded',
        'plainStatus': 'Needs attention',
        'auditIntegrity': <String, Object?>{'valid': true},
        'integrations': <Object?>[
          <String, Object?>{
            'provider': 'PostHog',
            'status': 'healthy',
            'freshness': 'fresh',
          },
          <String, Object?>{
            'provider': 'post hog',
            'status': 'down',
            'freshness': 'stale',
          },
          <String, Object?>{
            'provider': 'Supabase',
            'status': 'healthy',
            'freshness': 'fresh',
          },
        ],
      });

      expect(overview.sections, hasLength(1));
      expect(overview.sections.single.items, hasLength(2));
      expect(overview.sections.single.items.first.title, 'post hog');
      expect(overview.sections.single.items.first.status, 'Stale');
    },
  );
}
