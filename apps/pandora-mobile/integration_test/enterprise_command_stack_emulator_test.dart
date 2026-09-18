import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pandora_mobile/app/pandora_chat_shell.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/platform/pandora_native_io.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../test/helpers/fake_owner_api.dart';
import '../test/helpers/test_app.dart';

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

  Map<String, Object?>? capturedContext;

  @override
  Future<PandoraIntelligenceExecution> startChatExecution({
    required String message,
    required String requestId,
    String? threadId,
    String? projectId,
    Map<String, Object?>? enterpriseContext,
    PandoraModelOption? modelSelection,
    PandoraTextAttachment? textAttachment,
    PandoraImageAttachment? imageAttachment,
    PandoraIntelligenceMode mode = PandoraIntelligenceMode.auto,
  }) async {
    capturedContext = enterpriseContext;
    return PandoraIntelligenceExecution(
      jobId: 'job-emulator-enterprise',
      events: events.stream,
      turn: turn.future,
    );
  }

  Future<void> close() => events.close();
}

Map<String, dynamic> _activityResult() => <String, dynamic>{
      'projectionVersion': 1,
      'eventId': 'event-emulator-result',
      'jobId': 'job-emulator-enterprise',
      'sequence': 1,
      'state': 'result',
      'message': 'Admin creation verified.',
      'occurredAt': '2026-09-18T01:30:00Z',
      'admittedAt': '2026-09-18T01:30:00Z',
      'domain': 'enterprise',
      'capability': 'organization.users.manage',
      'source': <String, dynamic>{
        'sourceType': 'provider',
        'sourceId': 'provider-users',
        'sourceEventId': 'provider-users-result-emulator',
        'observedAt': '2026-09-18T01:30:00Z',
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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Enterprise App Users remains usable on an Android emulator',
    (tester) async {
      final intelligence = _FakeEnterpriseIntelligence();
      addTearDown(intelligence.close);

      await tester.pumpWidget(
        testApp(
          themeMode: ThemeMode.dark,
          child: PandoraDependencies(
            auth: const FakeAuth(),
            repository: FakeRepository(),
            intelligence: intelligence,
            diagnostics: DiagnosticsStore(),
            child: const PandoraChatShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final menu = find.byTooltip('Open navigation');
      expect(menu, findsOneWidget);
      await tester.tap(menu);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enterprise'));
      await tester.pumpAndSettle();

      final appUsers = find.descendant(
        of: find.byType(Drawer),
        matching: find.widgetWithText(ListTile, 'App Users'),
      );
      expect(appUsers, findsOneWidget);
      await tester.tap(appUsers);
      await tester.pumpAndSettle();

      final stack =
          find.byKey(const ValueKey<String>('enterprise-command-stack'));
      final commandBar =
          find.byKey(const ValueKey<String>('enterprise-command-bar'));
      final input = find.descendant(
        of: commandBar,
        matching: find.byType(TextField),
      );

      expect(stack, findsOneWidget);
      expect(commandBar, findsOneWidget);
      expect(input, findsOneWidget);
      expect(find.text('App Users'), findsWidgets);

      final logicalSize =
          tester.view.physicalSize / tester.view.devicePixelRatio;
      final commandRect = tester.getRect(commandBar);
      expect(commandRect.left, greaterThanOrEqualTo(0));
      expect(commandRect.right, lessThanOrEqualTo(logicalSize.width + 1));
      expect(commandRect.bottom, lessThanOrEqualTo(logicalSize.height + 1));

      await tester.enterText(input, 'Create admin for fongramos@yahoo.com');
      await tester.pump();
      final submit = find.byTooltip('Send command');
      expect(submit, findsOneWidget);
      final submitSize = tester.getSize(submit);
      expect(submitSize.width, greaterThanOrEqualTo(48));
      expect(submitSize.height, greaterThanOrEqualTo(48));

      await tester.tap(submit);
      await tester.pump();

      expect(
        intelligence.capturedContext?['surface'],
        'enterprise_app_users',
      );
      expect(
        intelligence.capturedContext?['identityScope'],
        'pandora_organization',
      );

      intelligence.events.add(_activityResult());
      intelligence.turn.complete(
        const PandoraIntelligenceTurn(
          threadId: 'thread-emulator-enterprise',
          reply: 'Admin created.',
          intent: 'act',
          confidence: 1,
          needsClarification: false,
        ),
      );
      await tester.pumpAndSettle();

      final theatre =
          find.byKey(const ValueKey<String>('enterprise-activity-theatre'));
      expect(theatre, findsOneWidget);
      expect(find.text('Admin creation verified.'), findsOneWidget);
      expect(commandBar, findsOneWidget);
      expect(find.text('App Users'), findsWidgets);

      final theatreRect = tester.getRect(theatre);
      final updatedCommandRect = tester.getRect(commandBar);
      expect(theatreRect.bottom, lessThanOrEqualTo(updatedCommandRect.top + 1));
      expect(tester.takeException(), isNull);
    },
  );
}
