import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_command_bar.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_inline_theatre.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_page_context.dart';

import '../../helpers/test_app.dart';

void main() {
  testWidgets('command bar mounts for every Enterprise destination surface', (
    tester,
  ) async {
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    final controller = EnterprisePageContextController();

    for (final destination in EnterpriseDestinations.entries) {
      controller.updateForDestination(destination);
      await tester.pumpWidget(
        testApp(
          child: EnterpriseCommandHost(
            controller: controller,
            showBar: true,
            child: Center(child: Text(destination.label)),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(EnterpriseCommandBar.barKey),
        findsOneWidget,
        reason: 'Bar must mount on ${destination.label}',
      );
      expect(find.byKey(EnterpriseCommandBar.composerKey), findsOneWidget);
      expect(find.text(destination.label), findsOneWidget);
      expect(find.text(EnterpriseCommandBar.accessibleName), findsOneWidget);
    }
  });

  testWidgets('composer tap target is at least 44px tall', (tester) async {
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    final controller = EnterprisePageContextController();
    await tester.pumpWidget(
      testApp(
        child: EnterpriseCommandHost(
          controller: controller,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();

    final composer = tester.getSize(
      find.byKey(EnterpriseCommandBar.composerKey),
    );
    final send = tester.getSize(find.byKey(EnterpriseCommandBar.sendKey));
    expect(composer.height, greaterThanOrEqualTo(44));
    expect(send.height, greaterThanOrEqualTo(44));
    expect(send.width, greaterThanOrEqualTo(44));
  });

  testWidgets('submit attaches envelope and does not push AskPandora route', (
    tester,
  ) async {
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    final controller = EnterprisePageContextController();
    controller.updateForDestination(EnterpriseDestinations.byIndex(8)!);
    controller.setActor(actorRole: 'owner', capabilities: {'command'});

    final submissions = <EnterpriseCommandSubmission>[];
    var navigatedToAskPandora = false;

    await tester.pumpWidget(
      testApp(
        child: EnterpriseCommandHost(
          controller: controller,
          onSubmit: (submission) {
            submissions.add(submission);
            // BAR contract: submit handlers must not route to AskPandora.
            // This test proves the host/bar themselves never push that route.
          },
          child: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () {
                  navigatedToAskPandora = true;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      settings: const RouteSettings(name: '/ask-pandora'),
                      builder: (_) => const Scaffold(body: Text('AskPandora')),
                    ),
                  );
                },
                child: const Text('probe-nav'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(EnterpriseCommandBar.composerKey),
      'What is on Overview?',
    );
    await tester.tap(find.byKey(EnterpriseCommandBar.sendKey));
    await tester.pump();

    expect(submissions, hasLength(1));
    expect(submissions.single.accepted, isTrue);
    expect(submissions.single.envelope.surface, 'overview');
    expect(submissions.single.envelope.route, 'enterprise_overview');
    expect(submissions.single.envelope.project, isNotEmpty);
    expect(submissions.single.envelope.actorRole, 'owner');
    expect(submissions.single.envelope.capabilities, contains('command'));
    expect(navigatedToAskPandora, isFalse);
    expect(find.text('AskPandora'), findsNothing);
    expect(find.byKey(EnterpriseCommandBar.barKey), findsOneWidget);
    // Originating page content remains mounted.
    expect(find.text('probe-nav'), findsOneWidget);
  });

  testWidgets(
    'incomplete identity shows Needs You stub without inventing role',
    (tester) async {
      await setTestSurface(tester, logicalSize: const Size(390, 844));
      final controller = EnterprisePageContextController();
      controller.updateForDestination(EnterpriseDestinations.byIndex(11)!);

      await tester.pumpWidget(
        testApp(
          child: EnterpriseCommandHost(
            controller: controller,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byKey(EnterpriseCommandBar.composerKey),
        'Show analytics',
      );
      await tester.tap(find.byKey(EnterpriseCommandBar.sendKey));
      await tester.pump();

      expect(find.byKey(EnterpriseCommandBar.needsYouKey), findsOneWidget);
      // Theatre + bar both surface Needs You for incomplete identity (P0-003/P0-006).
      expect(find.textContaining('Needs You'), findsWidgets);
      expect(find.byKey(EnterpriseInlineTheatre.theatreKey), findsOneWidget);
      expect(controller.envelope.actorRole, isNull);
      expect(controller.lastSubmission?.accepted, isFalse);
    },
  );

  testWidgets('idle host shows bar only (no empty theatre chrome)', (
    tester,
  ) async {
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    final controller = EnterprisePageContextController();
    await tester.pumpWidget(
      testApp(
        child: EnterpriseCommandHost(
          controller: controller,
          child: const Text('page-body'),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(EnterpriseCommandBar.barKey), findsOneWidget);
    expect(find.byKey(EnterpriseCommandBar.needsYouKey), findsNothing);
    expect(find.byKey(EnterpriseInlineTheatre.theatreKey), findsNothing);
    expect(find.text('Thinking'), findsNothing);
    expect(find.text('Analyzing'), findsNothing);
    expect(find.text('page-body'), findsOneWidget);
  });

  testWidgets('showBar false hides the command bar', (tester) async {
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    final controller = EnterprisePageContextController();
    await tester.pumpWidget(
      testApp(
        child: EnterpriseCommandHost(
          controller: controller,
          showBar: false,
          child: const Text('chat-body'),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(EnterpriseCommandBar.barKey), findsNothing);
    expect(find.text('chat-body'), findsOneWidget);
  });
}
