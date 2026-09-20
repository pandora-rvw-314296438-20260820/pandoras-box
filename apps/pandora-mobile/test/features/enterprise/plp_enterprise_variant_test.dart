
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_workspace_home.dart';

void main() {
  test('PLP enterprise target resolves only PLP Boracay', () {
    final workspaces = resolveEnterpriseWorkspaces('plp-boracay');

    expect(workspaces, hasLength(1));
    expect(workspaces.single.key, 'plp-boracay');
    expect(workspaces.single.name, 'PLP Boracay');
  });

  test('PLP enterprise target resolves the workspace home route', () {
    final selection = resolveEnterpriseWorkspaceHome('plp-boracay');

    expect(selection, isNotNull);
    expect(selection!.workspace.key, 'plp-boracay');
    expect(selection.section.routeSlug, 'home');
    expect(
      selection.enterpriseContext['route'],
      '/enterprise/workspaces/plp-boracay/home',
    );
  });

  test('unknown enterprise target fails closed', () {
    expect(resolveEnterpriseWorkspaces('not-a-workspace'), isEmpty);
    expect(resolveEnterpriseWorkspaceHome('not-a-workspace'), isNull);
  });
}
