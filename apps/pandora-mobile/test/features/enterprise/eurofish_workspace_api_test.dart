import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/eurofish_workspace_api.dart';

void main() {
  test('Euro-Fish surfaces map to stable RPC names', () {
    expect(EurofishSurface.values.length, 11);
    expect(EurofishSurface.commandCenter.rpcName, 'overview');
    expect(EurofishSurface.importOperations.rpcName, 'import_operations');
    expect(EurofishSurface.floriculture.rpcName, 'floriculture');
    expect(EurofishSurface.integrations.rpcName, 'integrations');
  });

  test('workspace snapshot preserves truth and source coverage', () {
    final snapshot = EurofishWorkspaceSnapshot.fromJson({
      'projectKey': 'enterprise-eurofish',
      'memoryNamespace': 'real_life',
      'surface': 'overview',
      'profile': {'displayName': '1064 Euro-Fish Trading'},
      'facts': [
        {
          'key': 'bfar',
          'truthStatus': 'verified',
          'sourceName': 'BFAR',
        },
        {
          'key': 'npqsd',
          'truthStatus': 'requires_current_verification',
          'sourceName': 'NPQSD',
        },
      ],
      'sources': [
        {'key': 'bfar_registry', 'status': 'verified'},
        {'key': 'orders_quotes', 'status': 'not_connected'},
      ],
      'generatedAt': '2026-09-18T08:00:00Z',
    });

    expect(snapshot.projectKey, 'enterprise-eurofish');
    expect(snapshot.memoryNamespace, 'real_life');
    expect(snapshot.verifiedEvidenceCount, 1);
    expect(snapshot.needsVerificationCount, 1);
    expect(snapshot.connectedSourceCount, 1);
    expect(snapshot.notConnectedSourceCount, 1);
    expect(snapshot.source('orders_quotes')?['status'], 'not_connected');
  });
}
