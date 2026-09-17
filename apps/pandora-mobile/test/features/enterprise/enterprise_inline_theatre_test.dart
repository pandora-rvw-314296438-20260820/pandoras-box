import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/activity/pandora_activity_projection.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_command_bar.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_inline_theatre.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_page_context.dart';

import '../../helpers/test_app.dart';

PandoraActivityProjection activityEvent({
  required int sequence,
  required PandoraActivityState state,
  required String message,
  String jobId = 'job-ent-1',
  String sourceType = 'provider',
  List<PandoraActivityEvidenceRef> evidence = const [],
  PandoraActivityBlocker? blocker,
  PandoraActivityOutcome? outcome,
}) {
  final at = DateTime.utc(2026, 9, 18, 5, 0, sequence);
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
      sourceType: sourceType,
      sourceId: 'provider-1',
      sourceEventId: 'src-$sequence',
      observedAt: at,
    ),
    evidenceRefs: evidence,
    blocker: blocker,
    outcome: outcome,
  );
}

void main() {
  testWidgets('idle theatre is fully hidden above the command bar', (
    tester,
  ) async {
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    final page = EnterprisePageContextController();
    final theatre = EnterpriseInlineTheatreController();
    addTearDown(theatre.dispose);

    await tester.pumpWidget(
      testApp(
        child: EnterpriseCommandHost(
          controller: page,
          theatreController: theatre,
          child: const Text('page-body'),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(EnterpriseCommandBar.barKey), findsOneWidget);
    expect(find.byKey(EnterpriseInlineTheatre.theatreKey), findsNothing);
    expect(find.text('Thinking'), findsNothing);
    expect(find.text('Analyzing'), findsNothing);
    expect(find.text('Running'), findsNothing);
    expect(find.text('page-body'), findsOneWidget);
    expect(theatre.phase, EnterpriseTheatrePhase.idle);
  });

  testWidgets('running state expands above bar from validated Activity only', (
    tester,
  ) async {
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    final page = EnterprisePageContextController();
    final theatre = EnterpriseInlineTheatreController();
    addTearDown(theatre.dispose);

    await tester.pumpWidget(
      testApp(
        child: EnterpriseCommandHost(
          controller: page,
          theatreController: theatre,
          child: const Text('page-body'),
        ),
      ),
    );
    await tester.pump();

    theatre.replaceWith([
      activityEvent(
        sequence: 1,
        state: PandoraActivityState.acting,
        message: 'Inviting member on App Users.',
      ),
    ], identityScope: EnterpriseIdentityScope.pandoraOrg);
    await tester.pump();

    expect(find.byKey(EnterpriseInlineTheatre.theatreKey), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Inviting member on App Users.'), findsOneWidget);
    expect(find.text('Scope pandora_org'), findsOneWidget);
    expect(find.text('page-body'), findsOneWidget);
    expect(find.byKey(EnterpriseCommandBar.barKey), findsOneWidget);

    final theatreTop =
        tester.getTopLeft(find.byKey(EnterpriseInlineTheatre.theatreKey)).dy;
    final barTop =
        tester.getTopLeft(find.byKey(EnterpriseCommandBar.barKey)).dy;
    expect(theatreTop, lessThan(barTop));
  });

  testWidgets('decorative Thinking is never admitted', (tester) async {
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    final theatre = EnterpriseInlineTheatreController();
    addTearDown(theatre.dispose);

    theatre.replaceWith([
      activityEvent(
        sequence: 1,
        state: PandoraActivityState.understanding,
        message: 'Thinking',
      ),
      activityEvent(
        sequence: 2,
        state: PandoraActivityState.planning,
        message: 'Analyzing',
      ),
    ]);
    await tester.pumpWidget(
      testApp(
        child: EnterpriseCommandHost(
          controller: EnterprisePageContextController(),
          theatreController: theatre,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();

    expect(theatre.phase, EnterpriseTheatrePhase.idle);
    expect(find.byKey(EnterpriseInlineTheatre.theatreKey), findsNothing);
    expect(find.text('Thinking'), findsNothing);
    expect(find.text('Analyzing'), findsNothing);
  });

  testWidgets('Needs You projects incomplete identity with exact scope', (
    tester,
  ) async {
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    final page = EnterprisePageContextController();
    page.updateForDestination(EnterpriseDestinations.byIndex(9)!);
    // App Users: incomplete actor/scope → Theatre Needs You.
    final theatre = EnterpriseInlineTheatreController();
    addTearDown(theatre.dispose);

    await tester.pumpWidget(
      testApp(
        child: EnterpriseCommandHost(
          controller: page,
          theatreController: theatre,
          child: const Text('app-users-page'),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(EnterpriseCommandBar.composerKey),
      'Invite an admin',
    );
    await tester.tap(find.byKey(EnterpriseCommandBar.sendKey));
    await tester.pump();

    expect(theatre.phase, EnterpriseTheatrePhase.needsYou);
    expect(find.byKey(EnterpriseInlineTheatre.theatreKey), findsOneWidget);
    expect(find.text('Needs You'), findsWidgets);
    expect(find.text('app-users-page'), findsOneWidget);
    // Must not navigate to AskPandora.
    expect(find.text('AskPandora'), findsNothing);
  });

  testWidgets('Success requires provider readback evidence', (tester) async {
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    final theatre = EnterpriseInlineTheatreController();
    addTearDown(theatre.dispose);

    await tester.pumpWidget(
      testApp(
        child: EnterpriseCommandHost(
          controller: EnterprisePageContextController(),
          theatreController: theatre,
          child: const Text('page-body'),
        ),
      ),
    );
    await tester.pump();

    // Result without readback/verification must not paint Success.
    theatre.replaceWith([
      activityEvent(
        sequence: 1,
        state: PandoraActivityState.result,
        message: 'Member invited.',
        outcome: const PandoraActivityOutcome(
          summary: 'Member invited.',
          physicalDevice: false,
        ),
      ),
    ], identityScope: EnterpriseIdentityScope.plpStaff);
    await tester.pump();
    expect(theatre.phase, EnterpriseTheatrePhase.failed);
    expect(find.text('Success'), findsNothing);
    expect(find.text('Failed'), findsOneWidget);

    theatre.replaceWith([
      activityEvent(
        sequence: 1,
        state: PandoraActivityState.acting,
        message: 'Creating invite on pandora_org.',
      ),
      activityEvent(
        sequence: 2,
        state: PandoraActivityState.result,
        message: 'Invite verified.',
        evidence: const [
          PandoraActivityEvidenceRef(
            type: 'verification_receipt',
            relation: 'verification',
            ref: 'verify-1',
          ),
        ],
        outcome: const PandoraActivityOutcome(
          summary: 'Invite verified on pandora_org.',
          physicalDevice: false,
        ),
      ),
    ], identityScope: EnterpriseIdentityScope.pandoraOrg);
    await tester.pump();

    expect(theatre.phase, EnterpriseTheatrePhase.success);
    expect(find.text('Success'), findsOneWidget);
    expect(find.text('Invite verified on pandora_org.'), findsOneWidget);
    expect(find.text('Scope pandora_org'), findsOneWidget);
    expect(find.byKey(EnterpriseInlineTheatre.receiptKey), findsOneWidget);
    expect(find.byKey(EnterpriseInlineTheatre.viewKey), findsOneWidget);

    await tester.tap(find.byKey(EnterpriseInlineTheatre.viewKey));
    await tester.pump();
    expect(find.byKey(EnterpriseInlineTheatre.historyKey), findsOneWidget);
    expect(
      find.textContaining('Creating invite on pandora_org.'),
      findsOneWidget,
    );
  });

  testWidgets('Failed stays Failed and never paints Success', (tester) async {
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    final theatre = EnterpriseInlineTheatreController();
    addTearDown(theatre.dispose);

    await tester.pumpWidget(
      testApp(
        child: EnterpriseCommandHost(
          controller: EnterprisePageContextController(),
          theatreController: theatre,
          child: const Text('page-body'),
        ),
      ),
    );
    await tester.pump();

    theatre.replaceWith([
      activityEvent(
        sequence: 1,
        state: PandoraActivityState.failed,
        message: 'Provider rejected the invite.',
        evidence: const [
          PandoraActivityEvidenceRef(
            type: 'provider_receipt',
            relation: 'failure',
            ref: 'fail-1',
          ),
        ],
      ),
    ]);
    await tester.pump();

    expect(theatre.phase, EnterpriseTheatrePhase.failed);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Success'), findsNothing);
    expect(find.text('Provider rejected the invite.'), findsOneWidget);
  });

  test('phase mapping is deterministic from Activity projection', () {
    final theatre = EnterpriseInlineTheatreController();
    addTearDown(theatre.dispose);

    expect(theatre.phase, EnterpriseTheatrePhase.idle);

    theatre.admit(
      activityEvent(
        sequence: 1,
        state: PandoraActivityState.verifying,
        message: 'Checking provider readback.',
      ),
    );
    expect(theatre.phase, EnterpriseTheatrePhase.running);

    theatre.replaceWith([
      activityEvent(
        sequence: 1,
        state: PandoraActivityState.needsYou,
        message: 'Choose identity scope.',
        blocker: const PandoraActivityBlocker(
          reasonCode: 'missing_consequential_user_choice',
          reason: 'Identity scope is required.',
          requiredAction: 'Select pandora_org or plp_staff.',
          approvalRequired: true,
        ),
      ),
    ], identityScope: null);
    expect(theatre.phase, EnterpriseTheatrePhase.needsYou);
    expect(theatre.requiredAction, 'Select pandora_org or plp_staff.');
  });
}
