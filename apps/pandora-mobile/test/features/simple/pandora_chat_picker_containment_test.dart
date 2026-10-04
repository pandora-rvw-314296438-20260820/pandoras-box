import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/chat/pandora_chat_state.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/local_ai/pandora_local_ai.dart';
import 'package:pandora_mobile/features/simple/ask_pandora_screen.dart';
import 'package:pandora_mobile/features/simple/chat/pandora_chat_viewport.dart';
import 'package:pandora_mobile/features/simple/pandora_model_picker.dart';

import '../../helpers/fake_chat_intelligence.dart';
import '../../helpers/fake_owner_api.dart';
import '../../helpers/test_app.dart';

const _model = PandoraChatModelOption(
  routingProvider: 'bedrock',
  providerName: 'Fixture',
  modelId: 'fixture.kimi',
  modelName: 'Kimi K2.5',
  selectable: true,
  availability: 'available',
);

void main() {
  testWidgets(
      'opaque clipped picker stays within cutout and remaining IME area',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var transcriptTaps = 0;
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          padding: EdgeInsets.only(top: 47, bottom: 24),
          viewPadding: EdgeInsets.only(top: 47, bottom: 24),
          viewInsets: EdgeInsets.only(bottom: 312),
        ),
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => transcriptTaps += 1,
                  child: const ColoredBox(
                    color: Colors.white,
                    child: Text('Conversation text under every options row'),
                  ),
                ),
              ),
              PandoraModelPickerOverlay(
                models: const [_model],
                selection: const PandoraChatModelSelection.auto(),
                reasoningMode: PandoraIntelligenceMode.auto,
                onDismiss: () {},
                onModelSelected: (_) {},
                onReasoningSelected: (_) {},
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final surface =
        find.byKey(const ValueKey<String>('pandora-model-picker-surface'));
    final material = tester.widget<Material>(surface);
    expect(material.color!.a, 1);
    expect(material.clipBehavior, Clip.antiAlias);
    expect(material.elevation, greaterThan(0));
    final rect = tester.getRect(surface);
    expect(rect.top, greaterThanOrEqualTo(47));
    expect(rect.bottom, lessThanOrEqualTo(844 - 312 - 12));
    expect(rect.left, greaterThanOrEqualTo(12));
    expect(rect.right, lessThanOrEqualTo(390 - 12));
    await tester.tapAt(const Offset(2, 100));
    await tester.tap(find.byKey(const ValueKey<String>('model-picker-auto')));
    expect(transcriptTaps, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Auto remains the selected preference when a model is available',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PandoraModelPickerOverlay(
          models: const [_model],
          selection: const PandoraChatModelSelection.auto(),
          reasoningMode: PandoraIntelligenceMode.deep,
          generationActive: true,
          onDismiss: () {},
          onModelSelected: (_) {},
          onReasoningSelected: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Changes apply to your next message.'), findsOneWidget);
    expect(find.text('Kimi K2.5'), findsNothing);
    expect(
        tester
            .getSemantics(
                find.byKey(const ValueKey<String>('model-picker-auto')))
            .flagsCollection
            .isSelected,
        Tristate.isTrue);
    await tester.tap(
        find.byKey(const ValueKey<String>('pandora-model-picker-advanced')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
        find.byKey(const ValueKey<String>('model-picker-fixture.kimi')));
    await tester.pumpAndSettle();
    expect(
        tester
            .getSemantics(
                find.byKey(const ValueKey<String>('model-picker-fixture.kimi')))
            .flagsCollection
            .isSelected,
        Tristate.isFalse);
    semantics.dispose();
  });

  testWidgets('compact large-text options remain scrollable and Escape closes',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var dismissed = 0;
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 568),
          textScaler: TextScaler.linear(2),
          padding: EdgeInsets.only(top: 32, bottom: 24),
        ),
        child: Scaffold(
          body: PandoraModelPickerOverlay(
            models: const [_model],
            selection: const PandoraChatModelSelection.manual(
                provider: 'bedrock', model: 'fixture.kimi'),
            reasoningMode: PandoraIntelligenceMode.auto,
            onDismiss: () => dismissed += 1,
            onModelSelected: (_) {},
            onReasoningSelected: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final model =
        find.byKey(const ValueKey<String>('model-picker-fixture.kimi'));
    await tester.ensureVisible(model);
    await tester.pumpAndSettle();
    expect(model.hitTestable(), findsOneWidget);
    expect(tester.getSize(model).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(dismissed, 1);
  });

  testWidgets(
      'Advanced end retains a visible close control and chat reading anchor',
      (tester) async {
    await setTestSurface(tester, logicalSize: const Size(390, 844));
    PandoraLocalAiPreference.setCachedForTesting(false);
    addTearDown(PandoraLocalAiPreference.resetForTesting);
    final chatKey = GlobalKey<AskPandoraScreenState>();
    final intelligence = FakeChatIntelligence();
    await tester.pumpWidget(testApp(
      themeMode: ThemeMode.dark,
      child: PandoraDependencies(
        auth: const FakeAuth(),
        repository: FakeRepository(),
        intelligence: intelligence,
        diagnostics: DiagnosticsStore(),
        child: AskPandoraScreen(
          key: chatKey,
          enterpriseContext: const {
            'route': '/enterprise/core/home',
            'identityScope': 'pandora_organization',
            'selectedObject': {'coreMode': 'owner'},
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    for (var i = 0; i < 12; i++) {
      await tester.enterText(
          find.byKey(const ValueKey<String>('ask-pandora-objective')),
          'Conversation turn $i');
      await tester
          .tap(find.byKey(const ValueKey<String>('ask-pandora-submit')));
      await tester.pumpAndSettle();
      expect(chatKey.currentState!.debugChatState.turns.last.phase,
          PandoraChatPhase.completed);
    }
    final conversation = chatKey.currentState!.debugChatState;
    final viewport =
        tester.widget<PandoraChatViewport>(find.byType(PandoraChatViewport));
    final reading = viewport.controller!;
    await tester.drag(
        find.byKey(const ValueKey<String>('pandora-chat-transcript')),
        const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(reading.followingLatest, isFalse);
    final anchor = reading.anchor!;
    final anchoredTurn =
        find.bySemanticsIdentifier('pandora.chat.turn.${anchor.messageId}');
    final beforeTop = tester.getRect(anchoredTurn).top;

    chatKey.currentState!.debugShowModelPicker(PandoraChatModelPickerSnapshot(
      models: [
        for (var i = 0; i < 40; i++)
          PandoraChatModelOption(
            routingProvider: 'bedrock',
            providerName: 'Fixture',
            modelId: 'scroll-model-${i.toString().padLeft(2, '0')}',
            modelName: 'Model ${i.toString().padLeft(2, '0')}',
            selectable: true,
            availability: 'available',
          ),
      ],
      selection: const PandoraChatModelSelection.auto(),
      reasoningMode: PandoraIntelligenceMode.auto,
    ));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey<String>('pandora-model-picker-advanced')));
    await tester.pumpAndSettle();
    final close =
        find.byKey(const ValueKey<String>('pandora-model-picker-close'));
    final closeRect = tester.getRect(close);
    final list =
        find.byKey(const ValueKey<String>('pandora-model-picker-list'));
    final lastModel =
        find.byKey(const ValueKey<String>('model-picker-scroll-model-39'));
    await tester.scrollUntilVisible(lastModel, 500,
        scrollable:
            find.descendant(of: list, matching: find.byType(Scrollable)));
    await tester.pumpAndSettle();
    expect(lastModel.hitTestable(), findsOneWidget);
    expect(close.hitTestable(), findsOneWidget);
    expect(tester.getRect(close), closeRect);
    expect(find.text('Pandora options').hitTestable(), findsOneWidget);
    expect(tester.getRect(anchoredTurn).top, closeTo(beforeTop, .1));

    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byType(PandoraModelPickerOverlay), findsNothing);
    expect(reading.followingLatest, isFalse);
    expect(reading.anchor?.messageId, anchor.messageId);
    expect(reading.anchor?.offset, closeTo(anchor.offset, .1));
    expect(tester.getRect(anchoredTurn).top, closeTo(beforeTop, .1));
    expect(chatKey.currentState!.debugChatState.conversationId,
        conversation.conversationId);
    expect(chatKey.currentState!.debugChatState.turns, hasLength(12));
    expect(intelligence.dispatches, hasLength(12));
    expect(tester.takeException(), isNull);
  });
}
