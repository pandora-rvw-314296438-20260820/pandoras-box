import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_page_context.dart';

void main() {
  group('EnterpriseDestinations', () {
    test('locks the 15 WAVE1 Enterprise surfaces', () {
      expect(EnterpriseDestinations.entries, hasLength(EnterpriseDestinations.count));
      expect(
        EnterpriseDestinations.entries.map((e) => e.label).toList(),
        [
          'Overview',
          'App Users',
          'Data',
          'Analytics',
          'Marketing',
          'Domains',
          'Integrations',
          'Security',
          'Code',
          'Agents',
          'Workflows',
          'Logs',
          'API',
          'Settings',
          'MCP',
        ],
      );
      expect(
        EnterpriseDestinations.entries.map((e) => e.destinationIndex).toSet(),
        {8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22},
      );
    });
  });

  group('EnterprisePageContextController', () {
    test('envelope always carries required P0-003 fields', () {
      final controller = EnterprisePageContextController();
      final map = controller.envelope.toDiagnosticsMap();
      expect(map.keys, containsAll([
        'project',
        'surface',
        'route',
        'selectedObject',
        'actorRole',
        'capabilities',
      ]));
      expect(map.containsKey('password'), isFalse);
      expect(map.containsKey('token'), isFalse);
      expect(map.containsKey('credential'), isFalse);
    });

    test('updates surface/route on destination change and clears selection', () {
      final controller = EnterprisePageContextController();
      controller.setSelectedObject('user-1');
      expect(controller.envelope.selectedObject, 'user-1');

      final data = EnterpriseDestinations.byIndex(10)!;
      controller.updateForDestination(data);

      expect(controller.envelope.surface, 'data');
      expect(controller.envelope.route, 'enterprise_data');
      expect(controller.envelope.selectedObject, isNull);
      expect(controller.envelope.project, 'plp-boracay');
    });

    test('submit attaches current envelope and stays accepted when ready', () {
      final controller = EnterprisePageContextController();
      controller.updateForDestination(EnterpriseDestinations.byIndex(8)!);
      controller.setActor(actorRole: 'owner', capabilities: {'command'});

      final submission = controller.submit('Summarize this page');
      expect(submission.accepted, isTrue);
      expect(submission.envelope.surface, 'overview');
      expect(submission.envelope.route, 'enterprise_overview');
      expect(submission.envelope.actorRole, 'owner');
      expect(submission.needsYouReason, isNull);
    });

    test('incomplete identity routes to Needs You without inventing credentials', () {
      final controller = EnterprisePageContextController();
      controller.updateForDestination(EnterpriseDestinations.byIndex(9)!);

      final submission = controller.submit('Create admin for someone');
      expect(submission.accepted, isFalse);
      expect(submission.needsYouReason, contains('Actor role'));
      expect(controller.needsYouReason, isNotNull);
      // Envelope must not invent email/role/credentials.
      expect(submission.envelope.actorRole, isNull);
      expect(submission.envelope.toDiagnosticsMap()['actorRole'], isNull);
    });

    test('App Users without identityScope is Needs You (OD-1)', () {
      final controller = EnterprisePageContextController();
      controller.updateForDestination(EnterpriseDestinations.byIndex(9)!);
      controller.setActor(actorRole: 'admin', capabilities: {'invite'});

      final submission = controller.submit('Invite a member');
      expect(submission.accepted, isFalse);
      expect(submission.needsYouReason, contains('identity scope'));
    });

    test('submit does not mutate destination indices catalog', () {
      expect(EnterpriseDestinations.count, 15);
      final controller = EnterprisePageContextController();
      controller.updateForDestination(EnterpriseDestinations.entries.last);
      controller.setActor(
        actorRole: 'viewer',
        identityScope: EnterpriseIdentityScope.pandoraOrg,
      );
      controller.submit('List MCP tools');
      expect(EnterpriseDestinations.entries.last.route, 'enterprise_mcp');
    });
  });
}
