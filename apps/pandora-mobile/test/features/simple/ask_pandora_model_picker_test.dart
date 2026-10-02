import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/features/simple/ask_pandora_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fake_owner_api.dart';
import '../../helpers/test_app.dart';

class _FakeModelIntelligence extends PandoraIntelligenceApi {
  _FakeModelIntelligence()
      : super(
          client: SupabaseClient(
            'https://example.supabase.co',
            'fixture-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
          organizationId: 'org-fixture',
        );

  PandoraChatModelSelection? sentSelection;
  PandoraIntelligenceMode? sentMode;

  @override
  Future<PandoraIntelligenceModelCatalog> modelCatalog() async =>
      PandoraIntelligenceModelCatalog(
        observedAt: DateTime.utc(2026, 10, 3),
        contractVersion: 'fixture',
        models: const <PandoraIntelligenceModelCatalogEntry>[
          PandoraIntelligenceModelCatalogEntry.auto(),
          PandoraIntelligenceModelCatalogEntry(
            provider: 'bedrock',model: 'fixture.verified',label: 'Verified model',
            providerLabel: 'Provider A',available: true,state: 'ready',
            routable: true,runtimeVerificationStatus: 'passed',
          ),
          PandoraIntelligenceModelCatalogEntry(
            provider: 'bedrock',model: 'fixture.payment',label: 'Payment blocked model',
            providerLabel: 'Provider B',available: false,state: 'unavailable',
            routable: false,runtimeVerificationStatus: 'failed',
            unavailableReason: 'Payment blocked',
          ),
          PandoraIntelligenceModelCatalogEntry(
            provider: 'bedrock',model: 'fixture.access',label: 'Access denied model',
            providerLabel: 'Provider C',available: false,state: 'unavailable',
            routable: false,runtimeVerificationStatus: 'failed',
            unavailableReason: 'Access denied',
          ),
          PandoraIntelligenceModelCatalogEntry(
            provider: 'bedrock',model: 'fixture.entitlement',label: 'Not entitled model',
            providerLabel: 'Provider D',available: false,state: 'unavailable',
            routable: false,runtimeVerificationStatus: 'failed',
            unavailableReason: 'Not entitled',
          ),
        ],
      );

  @override
  Future<PandoraThreadModelState> threadModelState(String threadId) async =>
      const PandoraThreadModelState(
        selection: PandoraChatModelSelection.manual(
          provider: 'bedrock',model: 'fixture.verified',label: 'fixture.verified',
        ),
        reasoningMode: PandoraIntelligenceMode.deep,
        executedProvider: 'bedrock',
        executedModel: 'fixture.verified',
      );

  @override
  Future<List<PandoraIntelligenceMessage>> messages(String threadId,{int limit = 200}) async =>
      <PandoraIntelligenceMessage>[
        PandoraIntelligenceMessage(
          id: 'message-1',threadId: threadId,authorRole: 'assistant',
          content: 'Saved thread.',createdAt: DateTime.utc(2026, 10, 3),
        ),
      ];

  @override
  Future<PandoraIntelligenceExecution> startChatExecution({
    required String message,required String requestId,String? threadId,String? projectId,
    Map<String, Object?>? enterpriseContext,PandoraTextAttachment? textAttachment,
    PandoraImageAttachment? imageAttachment,
    PandoraIntelligenceMode mode = PandoraIntelligenceMode.auto,
    PandoraChatModelSelection? modelSelection,
  }) async {
    sentSelection=modelSelection;sentMode=mode;
    return PandoraIntelligenceExecution(
      jobId: 'job-picker',
      events: const Stream<Map<String,dynamic>>.empty(),
      turn: Future<PandoraIntelligenceTurn>.value(
        PandoraIntelligenceTurn(
          threadId: threadId ?? 'thread-picker',reply: 'Done.',intent: 'chat',
          confidence: 1,needsClarification: false,
          routing: const PandoraIntelligenceRouting(
            requestedSelection: 'manual',requestedProvider: 'bedrock',
            requestedModel: 'fixture.verified',executedProvider: 'bedrock',
            executedModel: 'fixture.verified',
          ),
        ),
      ),
    );
  }
}

void main() {
  const localAiChannel=MethodChannel('pandora/local_ai');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(localAiChannel,(call) async =>
        call.method=='status'?<String,Object?>{
          'supported':false,'configured':false,'loaded':false,
        }:null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(localAiChannel,null);
  });

  testWidgets('model and reasoning controls use live catalog choices',(tester) async {
    await setTestSurface(tester,logicalSize:const Size(390,844));
    final intelligence=_FakeModelIntelligence();
    await tester.pumpWidget(testApp(
      themeMode:ThemeMode.dark,
      child:PandoraDependencies(
        auth:const FakeAuth(),repository:FakeRepository(),intelligence:intelligence,
        diagnostics:DiagnosticsStore(),child:const AskPandoraScreen(shellOverlay:true),
      ),
    ));
    await tester.pumpAndSettle();

    final modelControl=find.byKey(const ValueKey<String>('ask-pandora-model-control'));
    final reasoningControl=find.byKey(const ValueKey<String>('ask-pandora-reasoning-control'));
    expect(modelControl,findsOneWidget);expect(reasoningControl,findsOneWidget);
    expect(find.text('Model · '),findsOneWidget);
    expect(find.text('Reasoning · '),findsOneWidget);
    expect(find.text('Auto'),findsNWidgets(2));
    expect(find.byKey(const ValueKey<String>('ask-pandora-plus')),findsOneWidget);
    expect(find.byKey(const ValueKey<String>('ask-pandora-submit')),findsOneWidget);

    await tester.tap(modelControl);await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('pandora-model-picker-sheet')),findsOneWidget);
    expect(find.text('Verified model'),findsOneWidget);
    expect(find.text('Payment blocked model'),findsOneWidget);
    expect(find.text('Access denied model'),findsOneWidget);
    expect(find.text('Not entitled model'),findsOneWidget);

    final paymentRow=find.byKey(
      const ValueKey<String>('pandora-model-option-bedrock-fixture.payment'),
    );
    final paymentInk=find.descendant(of:paymentRow,matching:find.byType(InkWell));
    expect(tester.widget<InkWell>(paymentInk).onTap,isNull);

    await tester.tap(find.byKey(
      const ValueKey<String>('pandora-model-option-bedrock-fixture.verified'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Verified model'),findsOneWidget);

    await tester.tap(reasoningControl);await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('pandora-reasoning-picker-sheet')),findsOneWidget);
    await tester.tap(find.byKey(
      const ValueKey<String>('pandora-reasoning-option-deep'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Deep'),findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('ask-pandora-objective')),
      'Use the selected settings.',
    );
    await tester.tap(find.byKey(const ValueKey<String>('ask-pandora-submit')));
    await tester.pumpAndSettle();

    expect(intelligence.sentSelection?.selection,'manual');
    expect(intelligence.sentSelection?.provider,'bedrock');
    expect(intelligence.sentSelection?.model,'fixture.verified');
    expect(intelligence.sentSelection?.fallbackMode,'allow_fallback');
    expect(intelligence.sentMode,PandoraIntelligenceMode.deep);
  });

  testWidgets('thread load restores saved model and reasoning settings',(tester) async {
    await setTestSurface(tester,logicalSize:const Size(390,844));
    final intelligence=_FakeModelIntelligence();
    await tester.pumpWidget(testApp(
      themeMode:ThemeMode.dark,
      child:PandoraDependencies(
        auth:const FakeAuth(),repository:FakeRepository(),intelligence:intelligence,
        diagnostics:DiagnosticsStore(),child:const AskPandoraScreen(shellOverlay:true),
      ),
    ));
    await tester.pumpAndSettle();
    final state=tester.state<AskPandoraScreenState>(find.byType(AskPandoraScreen));
    await state.loadThread('thread-saved');await tester.pumpAndSettle();
    expect(find.text('Verified model'),findsOneWidget);
    expect(find.text('Deep'),findsOneWidget);
    expect(find.text('Saved thread.'),findsOneWidget);
  });
}
