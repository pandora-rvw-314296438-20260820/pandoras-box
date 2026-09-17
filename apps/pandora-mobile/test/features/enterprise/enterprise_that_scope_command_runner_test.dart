import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_command_bar.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_inline_theatre.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_page_context.dart';
import 'package:pandora_mobile/features/enterprise/enterprise_that_scope_command_runner.dart';

import '../../helpers/test_app.dart';

class _FakeThatScopePort implements EnterpriseThatScopeProviderPort {
  _FakeThatScopePort({
    this.payload,
    this.throwError,
  });

  final Map<String, dynamic>? payload;
  final Object? throwError;

  int callCount = 0;
  String? lastAction;
  String? lastRepositoryUrl;
  String? lastDeploymentId;

  @override
  Future<Map<String, dynamic>> invoke(
    String action, {
    required String repositoryUrl,
    String? deploymentId,
  }) async {
    callCount += 1;
    lastAction = action;
    lastRepositoryUrl = repositoryUrl;
    lastDeploymentId = deploymentId;
    if (throwError != null) {
      throw throwError!;
    }
    return payload ??
        <String, dynamic>{
          'ok': true,
          'inspection': <String, dynamic>{
            'repository': <String, dynamic>{'fullName': 'owner/repository'},
          },
        };
  }
}

EnterprisePageContextController _codePage({
  String? selectedObject,
  String actorRole = 'owner',
}) {
  final page = EnterprisePageContextController(
    initial: EnterprisePageContext(
      project: 'plp-boracay',
      surface: 'code',
      route: 'enterprise_code',
      actorRole: actorRole,
      selectedObject: selectedObject,
      identityScope: EnterpriseIdentityScope.pandoraOrg,
    ),
  );
  return page;
}

EnterprisePageContextController _appUsersPage() {
  return EnterprisePageContextController(
    initial: const EnterprisePageContext(
      project: 'plp-boracay',
      surface: 'app_users',
      route: 'enterprise_app_users',
      actorRole: 'owner',
      identityScope: EnterpriseIdentityScope.pandoraOrg,
    ),
  );
}

void main() {
  testWidgets(
    'accepted Code submit with verification evidence → theatre Success + gate',
    (tester) async {
      await setTestSurface(tester, logicalSize: const Size(390, 844));
      final port = _FakeThatScopePort(
        payload: <String, dynamic>{
          'ok': true,
          'inspection': <String, dynamic>{
            'repository': <String, dynamic>{'fullName': 'acme/app'},
          },
        },
      );
      final runner = EnterpriseThatScopeCommandRunner(provider: port);
      final page = _codePage(
        selectedObject: 'https://github.com/acme/app',
      );
      final theatre = EnterpriseInlineTheatreController();
      addTearDown(theatre.dispose);

      await tester.pumpWidget(
        testApp(
          child: EnterpriseCommandHost(
            controller: page,
            theatreController: theatre,
            thatScopeCommandRunner: runner,
            child: const Text('code-page'),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byKey(EnterpriseCommandBar.composerKey),
        'Inspect repository health',
      );
      await tester.tap(find.byKey(EnterpriseCommandBar.sendKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(port.callCount, 1);
      expect(port.lastAction, 'inspect');
      expect(port.lastRepositoryUrl, 'https://github.com/acme/app');
      expect(theatre.phase, EnterpriseTheatrePhase.success);
      expect(find.text('Success'), findsOneWidget);
      expect(
        enterpriseActivityHasReadbackGate(theatre.events.last),
        isTrue,
      );
      expect(find.textContaining('Code that-scope'), findsWidgets);
      expect(find.text('code-page'), findsOneWidget);
    },
  );

  testWidgets(
    'Code provider throw → Failed, never Success',
    (tester) async {
      await setTestSurface(tester, logicalSize: const Size(390, 844));
      final port = _FakeThatScopePort(
        throwError: StateError('Provider unreachable.'),
      );
      final runner = EnterpriseThatScopeCommandRunner(provider: port);
      final page = _codePage(
        selectedObject: 'https://github.com/acme/app',
      );
      final theatre = EnterpriseInlineTheatreController();
      addTearDown(theatre.dispose);

      await tester.pumpWidget(
        testApp(
          child: EnterpriseCommandHost(
            controller: page,
            theatreController: theatre,
            thatScopeCommandRunner: runner,
            child: const Text('code-page'),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byKey(EnterpriseCommandBar.composerKey),
        'Inspect repository',
      );
      await tester.tap(find.byKey(EnterpriseCommandBar.sendKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(port.callCount, 1);
      expect(theatre.phase, EnterpriseTheatrePhase.failed);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Success'), findsNothing);
    },
  );

  testWidgets(
    'Code provider ok:false → Failed, never Success',
    (tester) async {
      await setTestSurface(tester, logicalSize: const Size(390, 844));
      final port = _FakeThatScopePort(
        payload: <String, dynamic>{
          'ok': false,
          'code': 'GITHUB_REPOSITORY_UNAVAILABLE',
        },
      );
      final runner = EnterpriseThatScopeCommandRunner(provider: port);
      final page = _codePage(
        selectedObject: 'https://github.com/acme/app',
      );
      final theatre = EnterpriseInlineTheatreController();
      addTearDown(theatre.dispose);

      await tester.pumpWidget(
        testApp(
          child: EnterpriseCommandHost(
            controller: page,
            theatreController: theatre,
            thatScopeCommandRunner: runner,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byKey(EnterpriseCommandBar.composerKey),
        'Inspect',
      );
      await tester.tap(find.byKey(EnterpriseCommandBar.sendKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(theatre.phase, EnterpriseTheatrePhase.failed);
      expect(find.text('Success'), findsNothing);
      expect(find.text('Failed'), findsOneWidget);
    },
  );

  testWidgets(
    'Code missing repo URL and deployment id → Needs You, port not called',
    (tester) async {
      await setTestSurface(tester, logicalSize: const Size(390, 844));
      final port = _FakeThatScopePort();
      final runner = EnterpriseThatScopeCommandRunner(provider: port);
      final page = _codePage();
      final theatre = EnterpriseInlineTheatreController();
      addTearDown(theatre.dispose);

      await tester.pumpWidget(
        testApp(
          child: EnterpriseCommandHost(
            controller: page,
            theatreController: theatre,
            thatScopeCommandRunner: runner,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byKey(EnterpriseCommandBar.composerKey),
        'Check deployment',
      );
      await tester.tap(find.byKey(EnterpriseCommandBar.sendKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(port.callCount, 0);
      expect(theatre.phase, EnterpriseTheatrePhase.needsYou);
      expect(find.text('Success'), findsNothing);
    },
  );

  testWidgets(
    'app_users accepted path does NOT call provider port (P0-019)',
    (tester) async {
      await setTestSurface(tester, logicalSize: const Size(390, 844));
      final port = _FakeThatScopePort();
      final runner = EnterpriseThatScopeCommandRunner(provider: port);
      final page = _appUsersPage();
      final theatre = EnterpriseInlineTheatreController();
      addTearDown(theatre.dispose);

      await tester.pumpWidget(
        testApp(
          child: EnterpriseCommandHost(
            controller: page,
            theatreController: theatre,
            thatScopeCommandRunner: runner,
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
      await tester.pump(const Duration(milliseconds: 50));

      expect(port.callCount, 0);
      expect(theatre.phase, EnterpriseTheatrePhase.idle);
      expect(find.text('Success'), findsNothing);
      expect(find.text('app-users-page'), findsOneWidget);
    },
  );

  testWidgets(
    'Code status path uses deployment id from message',
    (tester) async {
      await setTestSurface(tester, logicalSize: const Size(390, 844));
      final port = _FakeThatScopePort(
        payload: <String, dynamic>{
          'ok': true,
          'deployment': <String, dynamic>{
            'id': 'dpl_abc123',
            'status': 'READY',
          },
        },
      );
      final runner = EnterpriseThatScopeCommandRunner(provider: port);
      final page = _codePage();
      final theatre = EnterpriseInlineTheatreController();
      addTearDown(theatre.dispose);

      await tester.pumpWidget(
        testApp(
          child: EnterpriseCommandHost(
            controller: page,
            theatreController: theatre,
            thatScopeCommandRunner: runner,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byKey(EnterpriseCommandBar.composerKey),
        'Refresh status for dpl_abc123',
      );
      await tester.tap(find.byKey(EnterpriseCommandBar.sendKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(port.callCount, 1);
      expect(port.lastAction, 'status');
      expect(port.lastDeploymentId, 'dpl_abc123');
      expect(theatre.phase, EnterpriseTheatrePhase.success);
      expect(enterpriseActivityHasReadbackGate(theatre.events.last), isTrue);
    },
  );

  test('resolveRepositoryUrl and resolveDeploymentId are deterministic', () {
    final withRepo = EnterpriseCommandSubmission(
      message: 'Please inspect https://github.com/acme/app.git now',
      envelope: const EnterprisePageContext(
        project: 'p',
        surface: 'code',
        route: 'enterprise_code',
        actorRole: 'owner',
      ),
      accepted: true,
    );
    expect(
      EnterpriseThatScopeCommandRunner.resolveRepositoryUrl(withRepo),
      'https://github.com/acme/app',
    );

    final withDpl = EnterpriseCommandSubmission(
      message: 'status dpl_ZZ9',
      envelope: const EnterprisePageContext(
        project: 'p',
        surface: 'code',
        route: 'enterprise_code',
        actorRole: 'owner',
      ),
      accepted: true,
    );
    expect(
      EnterpriseThatScopeCommandRunner.resolveDeploymentId(withDpl),
      'dpl_ZZ9',
    );
  });
}
