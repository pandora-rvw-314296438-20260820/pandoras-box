import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_chat_shell.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/activity/pandora_activity_projection.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_command_bar.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_inline_theatre.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_page_context.dart';

import '../../helpers/fake_owner_api.dart';
import '../../helpers/test_app.dart';

PandoraActivityProjection _activityEvent({
  required int sequence,
  required PandoraActivityState state,
  required String message,
  String jobId = 'job-ent-drawer-1',
  List<PandoraActivityEvidenceRef> evidence = const [],
  PandoraActivityOutcome? outcome,
}) {
  final at = DateTime.utc(2026, 9, 18, 6, 0, sequence);
  return PandoraActivityProjection(
    eventId: '$jobId-$sequence',
    jobId: jobId,
    sequence: sequence,
    state: state,
    message: message,
    occurredAt: at,
    admittedAt: at,
    domain: 'enterprise',
    capability: 'enterprise_command',
    executionId: '$jobId-exec',
    source: PandoraActivitySource(
      sourceType: 'provider',
      sourceId: 'provider-1',
      sourceEventId: 'src-$sequence',
      observedAt: at,
    ),
    evidenceRefs: evidence,
    outcome: outcome,
  );
}

void main() {
  Future<void> mountShell(WidgetTester tester) async {
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    await tester.pumpWidget(
      testApp(
        child: PandoraDependencies(
          auth: const FakeAuth(),
          repository: FakeRepository(),
          diagnostics: DiagnosticsStore(),
          child: const PandoraChatShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'phone shell drawer scrim uses Material alpha 0.54 (not .02)',
    (tester) async {
      await mountShell(tester);

      final menu = find.byTooltip('Open navigation');
      expect(menu, findsOneWidget);
      await tester.tap(menu);
      await tester.pumpAndSettle();

      expect(find.byType(Drawer), findsOneWidget);

      final scaffolds = tester.widgetList<Scaffold>(find.byType(Scaffold));
      final phoneScaffold = scaffolds.firstWhere(
        (s) => s.drawer != null,
        orElse: () => throw StateError('phone Scaffold with drawer missing'),
      );
      final scrim = phoneScaffold.drawerScrimColor!;
      expect(scrim.a, closeTo(PandoraChatShell.drawerScrimAlpha, 0.001));
      expect(scrim.a, greaterThanOrEqualTo(0.4));
      expect(scrim.a, isNot(closeTo(0.02, 0.001)));
      expect(PandoraChatShell.drawerScrimAlpha, 0.54);
      expect(
        PandoraChatShell.drawerScrimColor.a,
        closeTo(0.54, 0.001),
      );
      expect(find.byType(ModalBarrier), findsWidgets);
    },
  );

  testWidgets(
    'drawer overlays theatre + command bar; no tap-through; close-on-select',
    (tester) async {
      await setTestSurface(tester, logicalSize: const Size(390, 844));
      final page = EnterprisePageContextController();
      page.updateForDestination(EnterpriseDestinations.byIndex(8)!);
      page.setActor(actorRole: 'owner', capabilities: {'command'});
      final theatre = EnterpriseInlineTheatreController();
      addTearDown(theatre.dispose);

      final scaffoldKey = GlobalKey<ScaffoldState>();
      var bodyTaps = 0;
      var sendSubmissions = 0;

      await tester.pumpWidget(
        testApp(
          child: Scaffold(
            key: scaffoldKey,
            drawerScrimColor: PandoraChatShell.drawerScrimColor,
            onDrawerChanged: (_) {},
            drawer: Drawer(
              child: ListView(
                children: [
                  ListTile(
                    title: const Text('Projects'),
                    onTap: () => Navigator.of(
                      scaffoldKey.currentContext!,
                    ).pop(),
                  ),
                  ListTile(
                    title: const Text('Overview'),
                    onTap: () => Navigator.of(
                      scaffoldKey.currentContext!,
                    ).pop(),
                  ),
                ],
              ),
            ),
            body: EnterpriseCommandHost(
              controller: page,
              theatreController: theatre,
              onSubmit: (_) => sendSubmissions++,
              child: Center(
                child: TextButton(
                  onPressed: () => bodyTaps++,
                  child: const Text('page-body'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Running theatre with View control (success + verification evidence).
      theatre.replaceWith([
        _activityEvent(
          sequence: 1,
          state: PandoraActivityState.acting,
          message: 'Creating invite on pandora_org.',
        ),
        _activityEvent(
          sequence: 2,
          state: PandoraActivityState.result,
          message: 'Invite verified.',
          evidence: const [
            PandoraActivityEvidenceRef(
              type: 'verification_receipt',
              relation: 'verification',
              ref: 'verify-drawer-1',
            ),
          ],
          outcome: const PandoraActivityOutcome(
            summary: 'Invite verified on pandora_org.',
            physicalDevice: false,
          ),
        ),
      ], identityScope: EnterpriseIdentityScope.pandoraOrg);
      await tester.pump();

      expect(find.byKey(EnterpriseInlineTheatre.theatreKey), findsOneWidget);
      expect(find.byKey(EnterpriseCommandBar.barKey), findsOneWidget);
      expect(find.byKey(EnterpriseInlineTheatre.viewKey), findsOneWidget);

      scaffoldKey.currentState!.openDrawer();
      await tester.pumpAndSettle();

      expect(find.byType(Drawer), findsOneWidget);
      expect(find.byType(ModalBarrier), findsWidgets);

      final drawerScaffold = tester.widget<Scaffold>(
        find.byKey(scaffoldKey),
      );
      expect(
        drawerScaffold.drawerScrimColor!.a,
        closeTo(PandoraChatShell.drawerScrimAlpha, 0.001),
      );
      expect(drawerScaffold.drawerScrimColor!.a, greaterThanOrEqualTo(0.4));

      // No tap-through: underlying controls must not activate.
      await tester.tap(
        find.byKey(EnterpriseCommandBar.sendKey),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(sendSubmissions, 0);

      await tester.tap(
        find.byKey(EnterpriseInlineTheatre.viewKey),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(find.byKey(EnterpriseInlineTheatre.historyKey), findsNothing);

      await tester.tap(find.text('page-body'), warnIfMissed: false);
      await tester.pump();
      expect(bodyTaps, 0);

      // Drawer remains open after blocked taps.
      expect(find.byType(Drawer), findsOneWidget);

      // Close-on-select: tapping a nav destination closes the drawer.
      await tester.tap(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.widgetWithText(ListTile, 'Projects'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsNothing);
    },
  );

  testWidgets(
    'PandoraChatShell close-on-select closes drawer after nav tap',
    (tester) async {
      await mountShell(tester);
      final menu = find.byTooltip('Open navigation');

      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.widgetWithText(ListTile, 'Projects'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsNothing);
      expect(find.byTooltip('Create project'), findsOneWidget);
    },
  );
}
