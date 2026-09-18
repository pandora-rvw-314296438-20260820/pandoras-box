import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/platform/pandora_native_io.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_command_stack.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_page_context.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fake_owner_api.dart';
import '../../helpers/test_app.dart';

class _FakeEnterpriseIntelligence extends PandoraIntelligenceApi {
  _FakeEnterpriseIntelligence()
      : super(
          client: SupabaseClient(
            'https://example.supabase.co',
            'fixture-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
          organizationId: 'org-fixture',
        );

  final StreamController<Map<String, dynamic>> events =
      StreamController<Map<String, dynamic>>();
  final Completer<PandoraIntelligenceTurn> turn =
      Completer<PandoraIntelligenceTurn>();

  String? capturedMessage;
  Map<String, Object?>? capturedContext;

  @override
  Future<PandoraIntelligenceExecution> startChatExecution({
    required String message,
    required String requestId,
    String? threadId,
    String? projectId,
    Map<String, Object?>? enterpriseContext,
    PandoraTextAttachment? textAttachment,
    PandoraImageAttachment? imageAttachment,
    PandoraIntelligenceMode mode = PandoraIntelligenceMode.auto,
  }) async {
    capturedMessage = message;
    capturedContext = enterpriseContext;
    return PandoraIntelligenceExecution(
      jobId: 'job-enterprise-1',
      events: events.stream,
      turn: turn.future,
    );
  }

  Future<void> close() => events.close();
}

Map<String, dynamic> activityResult() => <String, dynamic>{
      'projectionVersion': 1,
      'eventId': 'event-enterprise-result',
      'jobId': 'job-enterprise-1',
      'sequence': 1,
      'state': 'result',
      'message': 'Admin creation verified.',
      'occurredAt': '2026-09-18T00:30:00Z',
      'admittedAt': '2026-09-18T00:30:00Z',
      'domain': 'enterprise',
      'capability': 'organization.users.manage',
      'source': <String, dynamic>{
        'sourceType': 'provider',
        'sourceId': 'provider-users',
        'sourceEventId': 'provider-users-result-1',
        'observedAt': '2026-09-18T00:30:00Z',
      },
      'evidenceRefs': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'verification_receipt',
          'relation': 'verification',
          'ref': 'provider:user:create:verified',
        },
      ],
      'outcome': <String, dynamic>{
        'summary': 'Admin creation verified.',
        'physicalDevice': false,
      },
    };

void main() {
  testWidgets(
    'App Users command stays in workspace and carries bounded identity context',
    (tester) async {
      await setTestSurface(tester, logicalSize: const Size(390, 844));
      final intelligence = _FakeEnterpriseIntelligence();
      addTearDown(intelligence.close);

      const pageContext = EnterprisePageContext(
        surface: 'enterprise_app_users',
        route: '/enterprise/app-users',
        capabilities: <String>[
          'organization.users.read',
          'organization.users.manage',
        ],
        identityScope: 'pandora_organization',
      );

      await tester.pumpWidget(
        testApp(
          themeMode: ThemeMode.dark,
          child: PandoraDependencies(
            auth: const FakeAuth(),
            repository: FakeRepository(),
            intelligence: intelligence,
            diagnostics: DiagnosticsStore(),
            child: const Scaffold(
              body: EnterprisePageContextScope(
                pageContext: pageContext,
                child: EnterpriseCommandStack(
                  child: Center(child: Text('App Users workspace')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final commandBar =
          find.byKey(const ValueKey<String>('enterprise-command-bar'));
      final input = find.descendant(
        of: commandBar,
        matching: find.byType(TextField),
      );

      expect(find.text('App Users workspace'), findsOneWidget);
      expect(commandBar, findsOneWidget);
      await tester.enterText(
        input,
        'Create admin for fongramos@yahoo.com',
      );
      await tester.tap(find.byTooltip('Send command'));
      await tester.pump();

      expect(find.text('App Users workspace'), findsOneWidget);
      expect(
        intelligence.capturedMessage,
        'Create admin for fongramos@yahoo.com',
      );
      expect(
        intelligence.capturedContext?['surface'],
        'enterprise_app_users',
      );
      expect(
        intelligence.capturedContext?['identityScope'],
        'pandora_organization',
      );
      expect(intelligence.capturedContext?['actorRole'], isNull);
      expect(
        intelligence.capturedContext?['capabilities'],
        contains('organization.users.manage'),
      );

      intelligence.events.add(activityResult());
      intelligence.turn.complete(
        const PandoraIntelligenceTurn(
          threadId: 'thread-enterprise-1',
          reply: 'Admin created.',
          intent: 'act',
          confidence: 1,
          needsClarification: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('enterprise-activity-theatre')),
        findsOneWidget,
      );
      expect(find.text('Admin creation verified.'), findsOneWidget);
      expect(find.text('App Users workspace'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
