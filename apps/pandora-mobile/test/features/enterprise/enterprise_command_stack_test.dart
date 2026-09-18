import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/platform/pandora_native_io.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_command_stack.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_page_context.dart';
import 'package:pandora_mobile/features/enterprise/plp_alfred_profile.dart';
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

Map<String, dynamic> activityNeedsYou() => <String, dynamic>{
      'projectionVersion': 1,
      'eventId': 'event-enterprise-needs-you',
      'jobId': 'job-enterprise-1',
      'sequence': 1,
      'state': 'needs_you',
      'message': 'Owner approval is required.',
      'occurredAt': '2026-09-18T00:31:00Z',
      'admittedAt': '2026-09-18T00:31:00Z',
      'domain': 'enterprise',
      'capability': 'organization.users.manage',
      'source': <String, dynamic>{
        'sourceType': 'provider',
        'sourceId': 'provider-users',
        'sourceEventId': 'provider-users-needs-you-1',
        'observedAt': '2026-09-18T00:31:00Z',
      },
      'evidenceRefs': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'policy_decision',
          'relation': 'policy',
          'ref': 'policy:organization-users-manage',
        },
      ],
      'blocker': <String, dynamic>{
        'reasonCode': 'authorization_required',
        'reason': 'This action requires owner authorization.',
        'requiredAction': 'Approve the organization user change.',
        'approvalRequired': true,
        'policyRef': 'organization.users.manage',
      },
    };

Map<String, dynamic> activityFailure() => <String, dynamic>{
      'projectionVersion': 1,
      'eventId': 'event-enterprise-failure',
      'jobId': 'job-enterprise-1',
      'sequence': 1,
      'state': 'failed',
      'message': 'User creation was denied.',
      'occurredAt': '2026-09-18T00:32:00Z',
      'admittedAt': '2026-09-18T00:32:00Z',
      'domain': 'enterprise',
      'capability': 'organization.users.manage',
      'source': <String, dynamic>{
        'sourceType': 'provider',
        'sourceId': 'provider-users',
        'sourceEventId': 'provider-users-failure-1',
        'observedAt': '2026-09-18T00:32:00Z',
      },
      'evidenceRefs': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'policy_decision',
          'relation': 'failure',
          'ref': 'policy:user-create-denied',
        },
      ],
    };

void main() {
  testWidgets(
    'App Users command stays in workspace and carries bounded identity context',
    (tester) async {
      await setTestSurface(tester, logicalSize: const Size(390, 844));
      final intelligence = _FakeEnterpriseIntelligence();
      addTearDown(intelligence.close);
      var pageStatus = 'No admin yet';
      StateSetter? setPageState;
      var verifiedResultCallbacks = 0;

      const pageContext = EnterprisePageContext(
        surface: 'enterprise_app_users',
        route: '/enterprise/app-users',
        capabilities: <String>[
          'organization.users.read',
          'organization.users.manage',
        ],
        identityScope: 'pandora_organization',
        tenantSlug: PlpAlfredProfile.tenantSlug,
        personaId: PlpAlfredProfile.personaId,
        personaLabel: PlpAlfredProfile.assistantLabel,
        assistantRole: PlpAlfredProfile.assistantRole,
      );

      await tester.pumpWidget(
        testApp(
          themeMode: ThemeMode.dark,
          child: PandoraDependencies(
            auth: const FakeAuth(),
            repository: FakeRepository(),
            intelligence: intelligence,
            diagnostics: DiagnosticsStore(),
            child: Scaffold(
              body: EnterprisePageContextScope(
                pageContext: pageContext,
                child: EnterpriseCommandStack(
                  onVerifiedResult: (_) {
                    verifiedResultCallbacks += 1;
                    setPageState?.call(() {
                      pageStatus = 'fongramos@yahoo.com — Admin';
                    });
                  },
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      setPageState = setState;
                      return Center(child: Text(pageStatus));
                    },
                  ),
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

      expect(find.text('No admin yet'), findsOneWidget);
      expect(commandBar, findsOneWidget);
      expect(find.text('Ask Alfred about this page'), findsOneWidget);
      final submitSize = tester.getSize(find.byTooltip('Send command'));
      expect(submitSize.width, greaterThanOrEqualTo(48));
      expect(submitSize.height, greaterThanOrEqualTo(48));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await tester.enterText(
        input,
        'Create admin for fongramos@yahoo.com',
      );
      await tester.tap(find.byTooltip('Send command'));
      await tester.pump();

      expect(find.text('No admin yet'), findsOneWidget);
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
      expect(intelligence.capturedContext?['tenantSlug'], 'plp-boracay');
      expect(intelligence.capturedContext?['personaId'], 'plp_alfred_v1');
      expect(
        intelligence.capturedContext?['assistantRole'],
        'Private Chief of Staff & Resort Intelligence',
      );
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
      expect(find.text('fongramos@yahoo.com — Admin'), findsOneWidget);
      expect(verifiedResultCallbacks, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'wide Enterprise failure stays inline and never replaces the workspace',
    (tester) async {
      await setTestSurface(tester, logicalSize: const Size(1280, 900));
      final intelligence = _FakeEnterpriseIntelligence();
      addTearDown(intelligence.close);
      var verifiedResultCallbacks = 0;

      const pageContext = EnterprisePageContext(
        surface: 'enterprise_app_users',
        route: '/enterprise/app-users',
        capabilities: <String>[
          'organization.users.read',
          'organization.users.manage',
        ],
        identityScope: 'pandora_organization',
        tenantSlug: PlpAlfredProfile.tenantSlug,
        personaId: PlpAlfredProfile.personaId,
        personaLabel: PlpAlfredProfile.assistantLabel,
        assistantRole: PlpAlfredProfile.assistantRole,
      );

      await tester.pumpWidget(
        testApp(
          themeMode: ThemeMode.dark,
          child: PandoraDependencies(
            auth: const FakeAuth(),
            repository: FakeRepository(),
            intelligence: intelligence,
            diagnostics: DiagnosticsStore(),
            child: Scaffold(
              body: EnterprisePageContextScope(
                pageContext: pageContext,
                child: EnterpriseCommandStack(
                  onVerifiedResult: (_) {
                    verifiedResultCallbacks += 1;
                  },
                  child: const Center(child: Text('Wide App Users workspace')),
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

      expect(find.text('Wide App Users workspace'), findsOneWidget);
      expect(commandBar, findsOneWidget);

      await tester.enterText(input, 'Create admin for denied@example.com');
      await tester.tap(find.byTooltip('Send command'));
      await tester.pump();

      intelligence.events.add(activityFailure());
      intelligence.turn.complete(
        const PandoraIntelligenceTurn(
          threadId: 'thread-enterprise-failure',
          reply: 'No changes were made.',
          intent: 'act',
          confidence: 1,
          needsClarification: false,
        ),
      );
      await tester.pumpAndSettle();

      final theatre =
          find.byKey(const ValueKey<String>('enterprise-activity-theatre'));
      expect(theatre, findsOneWidget);
      expect(find.text('User creation was denied.'), findsOneWidget);
      expect(find.text('Wide App Users workspace'), findsOneWidget);
      expect(commandBar, findsOneWidget);
      expect(verifiedResultCallbacks, 0);

      final theatreRect = tester.getRect(theatre);
      final commandRect = tester.getRect(commandBar);
      expect(theatreRect.bottom, lessThanOrEqualTo(commandRect.top + 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Needs You is announced with the required authorization action',
    (tester) async {
      await setTestSurface(tester, logicalSize: const Size(390, 844));
      final intelligence = _FakeEnterpriseIntelligence();
      addTearDown(intelligence.close);
      final semantics = tester.ensureSemantics();
      var verifiedResultCallbacks = 0;

      const pageContext = EnterprisePageContext(
        surface: 'enterprise_app_users',
        route: '/enterprise/app-users',
        capabilities: <String>[
          'organization.users.read',
          'organization.users.manage',
        ],
        identityScope: 'pandora_organization',
        tenantSlug: PlpAlfredProfile.tenantSlug,
        personaId: PlpAlfredProfile.personaId,
        personaLabel: PlpAlfredProfile.assistantLabel,
        assistantRole: PlpAlfredProfile.assistantRole,
      );

      await tester.pumpWidget(
        testApp(
          themeMode: ThemeMode.dark,
          child: PandoraDependencies(
            auth: const FakeAuth(),
            repository: FakeRepository(),
            intelligence: intelligence,
            diagnostics: DiagnosticsStore(),
            child: Scaffold(
              body: EnterprisePageContextScope(
                pageContext: pageContext,
                child: EnterpriseCommandStack(
                  onVerifiedResult: (_) {
                    verifiedResultCallbacks += 1;
                  },
                  child: const Center(child: Text('Authorization workspace')),
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

      await tester.enterText(input, 'Create admin for approval@example.com');
      await tester.tap(find.byTooltip('Send command'));
      await tester.pump();

      intelligence.events.add(activityNeedsYou());
      intelligence.turn.complete(
        const PandoraIntelligenceTurn(
          threadId: 'thread-enterprise-needs-you',
          reply: 'Owner approval is required.',
          intent: 'act',
          confidence: 1,
          needsClarification: true,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Authorization workspace'), findsOneWidget);
      expect(
        find.text('Required action: Approve the organization user change.'),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.liveRegion == true &&
              (widget.properties.label ?? '').contains('Needs You') &&
              (widget.properties.label ?? '')
                  .contains('Approve the organization user change.'),
        ),
        findsOneWidget,
      );
      expect(intelligence.capturedContext?['actorRole'], isNull);
      expect(verifiedResultCallbacks, 0);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
