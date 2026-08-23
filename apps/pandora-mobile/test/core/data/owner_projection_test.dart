import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/owner_projection.dart';
import 'package:pandora_mobile/core/models/pandora_models.dart';

void main() {
  const freshness = FreshnessInfo(state: FreshnessState.fresh);

  test('connection projection collapses duplicates without hiding risk', () {
    const connections = <ConnectionSummary>[
      ConnectionSummary(
        id: 'posthog-healthy',
        name: 'PostHog',
        purpose: 'Analytics',
        state: 'healthy',
        status: 'Healthy',
        canRead: true,
        canChange: false,
        freshness: freshness,
      ),
      ConnectionSummary(
        id: 'posthog-down',
        name: 'post hog',
        purpose: 'Analytics',
        state: 'down',
        status: 'Down',
        canRead: false,
        canChange: false,
        freshness: freshness,
      ),
      ConnectionSummary(
        id: 'github',
        name: 'GitHub',
        purpose: 'Source control',
        state: 'healthy',
        status: 'Healthy',
        canRead: true,
        canChange: true,
        freshness: freshness,
      ),
    ];

    final result = deduplicateConnections(connections);

    expect(result, hasLength(2));
    expect(result.first.name, 'post hog');
    expect(result.first.status, 'Down');
  });
}
