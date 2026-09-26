import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/eurofish_workspace_api.dart';

void main() {
  test('workspace snapshot preserves provider truth coverage', () {
    final snapshot = EurofishWorkspaceSnapshot.fromJson({
      'projectKey': 'enterprise-eurofish',
      'memoryNamespace': 'real_life',
      'profile': {'displayName': '1064 Euro-Fish Trading'},
      'facts': [
        {'key': 'verified', 'truthStatus': 'verified'},
        {'key': 'review', 'truthStatus': 'requires_current_verification'},
      ],
      'sources': [
        {'key': 'provider', 'status': 'connected'},
        {'key': 'manual', 'status': 'not_connected'},
      ],
      'generatedAt': '2026-09-26T00:00:00Z',
    });

    expect(snapshot.projectKey, 'enterprise-eurofish');
    expect(snapshot.memoryNamespace, 'real_life');
    expect(snapshot.verifiedEvidenceCount, 1);
    expect(snapshot.needsVerificationCount, 1);
    expect(snapshot.connectedSourceCount, 1);
    expect(snapshot.notConnectedSourceCount, 1);
  });
}
