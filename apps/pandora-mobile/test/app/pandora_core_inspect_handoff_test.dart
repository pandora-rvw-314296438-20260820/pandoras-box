import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:pandora_mobile/app/pandora_chat_shell.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/data/pandora_core_api.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/local_ai/pandora_local_ai.dart';
import 'package:pandora_mobile/core/platform/pandora_native_io.dart';
import 'package:pandora_mobile/features/core/pandora_core_screen.dart';
import 'package:pandora_mobile/features/simple/ask_pandora_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/fake_owner_api.dart';
import '../helpers/test_app.dart';

const _organization = '11111111-1111-4111-8111-111111111111';
const _ownerContext = <String, Object?>{
  'surface': 'enterprise_settings',
  'route': '/enterprise/core/home',
  'identityScope': 'pandora_organization',
  'selectedObject': <String, String>{
    'coreMode': 'owner',
    'coreSection': 'home',
  },
};

class _CoreGateway implements PandoraCoreGateway {
  final reads = <PandoraCoreRecord>[];
  int writes = 0;

  @override
  Future<PandoraCoreRecord> snapshot(
    String section, {
    String? organizationId,
  }) async {
    reads.add(<String, dynamic>{
      'section': section,
      'organization_id': organizationId,
    });
    const client = <String, dynamic>{
      'organization_id': _organization,
      'display_name': 'Harbor client',
      'workspace_type': 'generic',
      'industry': 'Trade',
      'lifecycle_state': 'active',
      'can_enter': false,
    };
    return <String, dynamic>{
      'clients': <PandoraCoreRecord>[client],
      if (organizationId != null) 'client': client,
    };
  }

  @override
  Future<PandoraCoreRecord> operate(
    String operation, {
    String? organizationId,
    required PandoraCoreRecord payload,
    required String idempotencyKey,
  }) async {
    writes++;
    throw StateError('An inspection must not mutate records.');
  }

  @override
  Future<PandoraCoreRecord> enterClient(
    String organizationId, {
    required String reason,
  }) async {
    throw StateError('An inspection must not enter a client workspace.');
  }
}

class _ReplyIntelligence extends PandoraIntelligenceApi {
  _ReplyIntelligence(SupabaseClient client, this.answer, this.history)
      : super(client: client, organizationId: 'fixture-owner');

  final PandoraIntelligenceTurn Function(String message) answer;
  final List<PandoraCoreRecord> history;
  final submittedMessages = <String>[];
  final contexts = <Map<String, Object?>?>[];
  final historyReads = <String>[];

  @override
  Future<List<PandoraIntelligenceThread>> recentThreads(
          {int limit = 30}) async =>
      history.isEmpty
          ? const <PandoraIntelligenceThread>[]
          : <PandoraIntelligenceThread>[
              PandoraIntelligenceThread(
                id: 'restored-thread',
                title: 'Saved Harbor inspection',
                status: 'active',
                lastMessageAt: DateTime.utc(2026, 10, 3),
                createdAt: DateTime.utc(2026, 10, 3),
              ),
            ];

  @override
  Future<List<PandoraIntelligenceMessage>> messages(
    String threadId, {
    int limit = 200,
  }) async {
    historyReads.add(threadId);
    return history.map(PandoraIntelligenceMessage.fromJson).toList();
  }

  @override
  Future<PandoraChatModelPickerSnapshot> modelPicker(
          {String? threadId}) async =>
      const PandoraChatModelPickerSnapshot(
        models: <PandoraChatModelOption>[],
        selection: PandoraChatModelSelection.auto(),
        reasoningMode: PandoraIntelligenceMode.auto,
      );

  @override
  Future<PandoraIntelligenceTurn?> recoverCompletedChatTurn(
          String jobId) async =>
      null;

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
    PandoraChatModelSelection modelSelection =
        const PandoraChatModelSelection.auto(),
  }) async {
    submittedMessages.add(message);
    contexts.add(enterpriseContext);
    return PandoraIntelligenceExecution(
      jobId: 'fixture-inspect-${submittedMessages.length}',
      events: const Stream<Map<String, dynamic>>.empty(),
      turn: Future<PandoraIntelligenceTurn>.value(answer(message)),
    );
  }
}

Future<_ReplyIntelligence> _intelligence(
  WidgetTester tester,
  PandoraIntelligenceTurn Function(String message) answer, {
  List<PandoraCoreRecord> history = const <PandoraCoreRecord>[],
}) async {
  final client = await tester.runAsync(() async => SupabaseClient(
        'https://inspect-fixture.invalid',
        'test-placeholder',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async => throw StateError(
            'Unexpected provider request: ${request.url.path}')),
      ));
  addTearDown(() async {
    await tester.runAsync(client!.dispose);
  });
  return _ReplyIntelligence(client!, answer, history);
}

PandoraIntelligenceTurn _turn(
  String reply,
  PandoraIntelligenceHandoff handoff,
) =>
    PandoraIntelligenceTurn(
      threadId: 'fixture-inspect-thread',
      reply: reply,
      intent: 'core_owner',
      confidence: 1,
      needsClarification: false,
      handoff: handoff,
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> _mount(
  WidgetTester tester,
  _CoreGateway gateway,
  _ReplyIntelligence intelligence, {
  Widget? child,
}) async {
  PandoraLocalAiPreference.setCachedForTesting(false);
  addTearDown(PandoraLocalAiPreference.resetForTesting);
  await setTestSurface(tester, logicalSize: const Size(390, 844));
  const channel = MethodChannel('pandora/local_ai');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    channel,
    (call) async => call.method == 'status'
        ? <String, Object?>{
            'supported': false,
            'configured': false,
            'loaded': false,
          }
        : null,
  );
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  await tester.pumpWidget(testApp(
    themeMode: ThemeMode.dark,
    child: PandoraDependencies(
      auth: const FakeAuth(),
      repository: FakeRepository(),
      diagnostics: DiagnosticsStore(),
      intelligence: intelligence,
      child: child ??
          PandoraChatShell(
            startPage: PandoraStartPage.home,
            coreGateway: gateway,
          ),
    ),
  ));
  await _settle(tester);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await _settle(tester);
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await _settle(tester);
}

Finder _assistant(String reply) => find.byWidgetPredicate(
      (widget) => widget is SelectableText && widget.data == reply,
    );

Future<void> _submit(
  WidgetTester tester,
  String query,
  String reply,
) async {
  final composer = find.byKey(const ValueKey('ask-pandora-objective'));
  expect(composer.hitTestable(), findsOneWidget);
  await tester.enterText(composer, query);
  await _tap(tester, find.byKey(const ValueKey('ask-pandora-submit')));
  for (var i = 0; i < 30 && _assistant(reply).evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
  expect(_assistant(reply), findsOneWidget);
  expect(find.byKey(const ValueKey('ask-pandora-composer')), findsOneWidget);
}

Map<dynamic, dynamic> _selected(WidgetTester tester) => tester
    .widget<AskPandoraScreen>(find.byType(AskPandoraScreen))
    .enterpriseContext!['selectedObject'] as Map;

Future<void> _drawerSelection(WidgetTester tester, String background) async {
  await _tap(tester, find.byTooltip('Open navigation'));
  final drawer =
      find.byKey(const ValueKey('pandora-primary-navigation-drawer'));
  final pandora = find.descendant(
    of: drawer,
    matching: find.widgetWithText(ListTile, 'Pandora'),
  );
  expect(tester.widget<ListTile>(pandora).selected, isTrue);
  final backgroundTile = find.descendant(
    of: drawer,
    matching: find.widgetWithText(ListTile, background),
  );
  expect(tester.widget<ListTile>(backgroundTile).selected, isFalse);
  await tester.binding.handlePopRoute();
  await _settle(tester);
}

void main() {
  testWidgets(
      'submitted Home inspection waits for its accessible details button',
      (tester) async {
    final gateway = _CoreGateway();
    final reply =
        List<String>.filled(240, 'Measured model evidence. ').join().trim();
    final intelligence = await _intelligence(
        tester,
        (_) => _turn(
              reply,
              const PandoraIntelligenceHandoff(
                request: 'Open platform details',
                kind: 'core_navigation',
                action: 'inspect',
                section: 'platform',
              ),
            ));
    await _mount(tester, gateway, intelligence);
    final homeState = tester.state(find.byType(PandoraCoreScreen));
    const query = 'What is the current model routing evidence?';

    await _submit(tester, query, reply);

    expect(intelligence.submittedMessages, <String>[query]);
    expect(
        (intelligence.contexts.single!['selectedObject'] as Map)['coreSection'],
        'home');
    expect(_selected(tester)['coreSection'], 'home');
    expect(
      tester.state(find.byType(PandoraCoreScreen, skipOffstage: false)),
      same(homeState),
    );
    expect(gateway.reads.map((read) => read['section']), <String>['home']);
    await _drawerSelection(tester, 'Home');
    expect(_selected(tester)['coreSection'], 'home');

    final assistantSemantics = find.byWidgetPredicate((widget) =>
        widget is Semantics &&
        widget.properties.label == 'Pandora: $reply');
    expect(assistantSemantics, findsOneWidget);
    final inspect = find.byKey(const ValueKey('pandora-core-inspect-action'));
    expect(inspect, findsOneWidget);
    expect(find.descendant(of: assistantSemantics, matching: inspect),
        findsNothing);
    expect(tester.widget<TextButton>(inspect).onPressed, isNotNull);

    await _tap(tester, inspect);

    final destination = tester.widget<PandoraCoreScreen>(
      find.byType(PandoraCoreScreen),
    );
    expect(destination.section, 'platform');
    expect(destination.organizationId, isNull);
    expect(destination.initialAction, 'inspect');
    expect(_selected(tester)['coreSection'], 'platform');
    expect(gateway.reads.last, <String, dynamic>{
      'section': 'platform',
      'organization_id': null,
    });
    expect(gateway.writes, 0);
    expect(find.byKey(const ValueKey('ask-pandora-composer')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
  });

  testWidgets(
      'inspection preserves the selected client until the button is used',
      (tester) async {
    final gateway = _CoreGateway();
    const reply = 'Harbor has no verified billing provider in this snapshot.';
    final intelligence = await _intelligence(
        tester,
        (_) => _turn(
              reply,
              const PandoraIntelligenceHandoff(
                request: 'Open Harbor details',
                kind: 'core_navigation',
                action: 'inspect',
                section: 'clients',
                organizationId: _organization,
              ),
            ));
    await _mount(tester, gateway, intelligence);
    await _tap(tester, find.byTooltip('Open navigation'));
    final drawer =
        find.byKey(const ValueKey('pandora-primary-navigation-drawer'));
    await _tap(
      tester,
      find.descendant(
        of: drawer,
        matching: find.widgetWithText(ListTile, 'Clients'),
      ),
    );
    await _tap(
        tester, find.byKey(const ValueKey('core-manage-$_organization')));
    expect(_selected(tester)['coreSection'], 'client');
    expect(_selected(tester)['organizationId'], _organization);
    final readsBeforeQuery = gateway.reads.length;
    const query = 'What billing evidence is available for this client?';

    await _submit(tester, query, reply);

    expect(intelligence.submittedMessages, <String>[query]);
    final submitted = intelligence.contexts.single!['selectedObject'] as Map;
    expect(submitted['coreSection'], 'client');
    expect(submitted['organizationId'], _organization);
    expect(gateway.reads, hasLength(readsBeforeQuery));
    await _drawerSelection(tester, 'Clients');
    expect(_selected(tester)['coreSection'], 'client');
    expect(_selected(tester)['organizationId'], _organization);

    await _tap(
        tester, find.byKey(const ValueKey('pandora-core-inspect-action')));

    final destination = tester.widget<PandoraCoreScreen>(
      find.byType(PandoraCoreScreen),
    );
    expect(destination.section, 'clients');
    expect(destination.organizationId, _organization);
    expect(destination.initialAction, 'inspect');
    expect(gateway.reads.last, <String, dynamic>{
      'section': 'client',
      'organization_id': _organization,
    });
    expect(gateway.writes, 0);
    expect(find.byKey(const ValueKey('ask-pandora-composer')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
  });

  testWidgets('restored inspection retains its reply after scoped navigation',
      (tester) async {
    final gateway = _CoreGateway();
    const reply = 'Saved evidence identifies the selected Harbor client.';
    final intelligence = await _intelligence(
      tester,
      (_) => throw StateError('Restoring a thread must not submit a new turn.'),
      history: <PandoraCoreRecord>[
        <String, dynamic>{
          'id': 'restored-message',
          'thread_id': 'restored-thread',
          'author_role': 'assistant',
          'content': reply,
          'created_at': '2026-10-03T12:00:00Z',
          'structured_response': <String, dynamic>{
            'handoff': <String, dynamic>{
              'required': true,
              'kind': 'core_navigation',
              'action': 'inspect',
              'section': 'clients',
              'request': 'Open saved Harbor details',
              'organizationId': _organization,
            },
          },
        },
      ],
    );
    await _mount(tester, gateway, intelligence);
    await _tap(tester, find.byTooltip('Open navigation'));
    final drawer =
        find.byKey(const ValueKey('pandora-primary-navigation-drawer'));
    await _tap(
      tester,
      find.descendant(
        of: drawer,
        matching: find.widgetWithText(ListTile, 'Pandora'),
      ),
    );
    await _tap(tester, find.byKey(const ValueKey('pandora-recent-chats')));
    await _tap(
        tester, find.byKey(const ValueKey('pandora-thread-restored-thread')));

    expect(intelligence.historyReads, <String>['restored-thread']);
    expect(_assistant(reply), findsOneWidget);
    expect(_selected(tester)['coreSection'], 'home');
    expect(gateway.reads.map((read) => read['section']), <String>['home']);
    final conversation =
        tester.state<AskPandoraScreenState>(find.byType(AskPandoraScreen));
    final inspect = find.byKey(const ValueKey('pandora-core-inspect-action'));
    await _tap(tester, inspect);

    final destination =
        tester.widget<PandoraCoreScreen>(find.byType(PandoraCoreScreen));
    expect(destination.section, 'clients');
    expect(destination.organizationId, _organization);
    expect(gateway.reads.last, <String, dynamic>{
      'section': 'client',
      'organization_id': _organization,
    });
    await tester.binding.handlePopRoute();
    await _settle(tester);
    await _tap(tester, find.byTooltip('Open navigation'));
    await _tap(
      tester,
      find.descendant(
        of: drawer,
        matching: find.widgetWithText(ListTile, 'Pandora'),
      ),
    );

    expect(_assistant(reply), findsOneWidget);
    expect(inspect, findsOneWidget);
    expect(
      tester.state<AskPandoraScreenState>(find.byType(AskPandoraScreen)),
      same(conversation),
    );
    expect(find.byKey(const ValueKey('ask-pandora-composer')), findsOneWidget);
    expect(intelligence.submittedMessages, isEmpty);
    expect(intelligence.historyReads, <String>['restored-thread']);
    expect(gateway.writes, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
  });

  testWidgets(
      'explicit create manage and return commands still dispatch directly',
      (tester) async {
    const commands = <String, String>{
      'Create an enterprise client': 'create_client',
      'Manage this client users': 'manage_users',
      'Return to Pandora': 'return_owner',
    };
    final dispatched = <PandoraIntelligenceHandoff>[];
    final intelligence = await _intelligence(
        tester,
        (query) => _turn(
              'Accepted command: ${commands[query]}.',
              PandoraIntelligenceHandoff(
                request: query,
                kind: 'core_navigation',
                action: commands[query],
                section: 'clients',
                organizationId:
                    commands[query] == 'manage_users' ? _organization : null,
              ),
            ));
    await _mount(
      tester,
      _CoreGateway(),
      intelligence,
      child: Scaffold(
        body: AskPandoraScreen(
          enterpriseContext: _ownerContext,
          onCoreNavigate: dispatched.add,
        ),
      ),
    );

    for (final command in commands.entries) {
      await _submit(tester, command.key, 'Accepted command: ${command.value}.');
      expect(dispatched.last.action, command.value);
      expect(dispatched.last.request, command.key);
      expect(find.byKey(const ValueKey('pandora-core-inspect-action')),
          findsNothing);
    }
    expect(dispatched.map((handoff) => handoff.action), commands.values);
    expect(dispatched[1].organizationId, _organization);
    expect(intelligence.submittedMessages, commands.keys);
    expect(find.byKey(const ValueKey('ask-pandora-composer')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
  });
}
