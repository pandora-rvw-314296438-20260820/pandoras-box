import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_chat_shell.dart';
import 'package:pandora_mobile/app/pandora_dependencies.dart';
import 'package:pandora_mobile/core/chat/pandora_chat_state.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/diagnostics/diagnostics_store.dart';
import 'package:pandora_mobile/core/local_ai/pandora_local_ai.dart';
import 'package:pandora_mobile/core/widgets/pandora_mark.dart';
import 'package:pandora_mobile/features/simple/ask_pandora_screen.dart';

import '../helpers/fake_chat_intelligence.dart';
import '../helpers/fake_owner_api.dart';
import '../helpers/test_app.dart';

const _surfaceKey = ValueKey<String>('lane-h-golden-surface');
const _phoneSize = Size(390, 844);
const _fontFamily = 'Roboto';
const _iconFontFamily = 'MaterialIcons';

/// A deterministic accepted/completed wire lifecycle, with an execution receipt
/// that is deliberately different from the requested manual model. Routing
/// evidence must never overwrite the user's selected preference.
class _VisualChatIntelligence extends FakeChatIntelligence {
  _VisualChatIntelligence({super.onReply, super.events});

  @override
  Stream<PandoraChatWireEvent> executeChatTurn(
    PandoraChatDispatch dispatch,
  ) async* {
    await for (final event in super.executeChatTurn(dispatch)) {
      yield event.status == 'completed'
          ? PandoraChatWireEvent.fromJson({
              ...event.data,
              'routing': {
                'executedProvider': 'bedrock',
                'executedModel': 'fixture.model.2',
              },
            })
          : event;
    }
  }
}

Future<void> _loadFonts() async {
  final separator = Platform.pathSeparator;
  final roots = <String>{};
  final configuredRoot = Platform.environment['FLUTTER_ROOT'];
  if (configuredRoot != null && configuredRoot.isNotEmpty) {
    roots.add(configuredRoot);
  }
  var cursor = File(Platform.resolvedExecutable).parent;
  for (var depth = 0; depth < 12; depth += 1) {
    roots.add(cursor.path);
    final parent = cursor.parent;
    if (parent.path == cursor.path) break;
    cursor = parent;
  }

  File? textFont;
  File? iconFont;
  for (final root in roots) {
    final materialFonts =
        [root, 'bin', 'cache', 'artifacts', 'material_fonts'].join(separator);
    final textCandidate = File('$materialFonts${separator}Roboto-Regular.ttf');
    final iconCandidate =
        File('$materialFonts${separator}MaterialIcons-Regular.otf');
    if (textFont == null && textCandidate.existsSync()) {
      textFont = textCandidate;
    }
    if (iconFont == null && iconCandidate.existsSync()) {
      iconFont = iconCandidate;
    }
    if (textFont != null && iconFont != null) break;
  }
  if (textFont == null || iconFont == null) {
    throw StateError('Pinned Flutter visual fonts were not found.');
  }

  final textLoader = FontLoader(_fontFamily)
    ..addFont(
      Future<ByteData>.value(
        ByteData.sublistView(await textFont.readAsBytes()),
      ),
    );
  final iconLoader = FontLoader(_iconFontFamily)
    ..addFont(
      Future<ByteData>.value(
        ByteData.sublistView(await iconFont.readAsBytes()),
      ),
    );
  await Future.wait(<Future<void>>[textLoader.load(), iconLoader.load()]);
}

Widget _withFonts(Widget child) => Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: _fontFamily),
            primaryTextTheme:
                theme.primaryTextTheme.apply(fontFamily: _fontFamily),
          ),
          child: child,
        );
      },
    );

List<PandoraChatModelOption> _pickerModels() {
  const names = <String>[
    'Mistral Large 3',
    'DeepSeek V3.2',
    'Kimi K2.5',
    'GLM 5',
    'Qwen3 VL 235B',
    'Nemotron 3 Super 120B',
    'MiniMax M2.5',
    'Kimi K2 Thinking',
    'Devstral 2 123B',
    'Qwen3 Next 80B',
    'Qwen3 Coder Next',
    'GLM 4.7',
    'MiniMax M2.1',
    'Magistral Small',
    'Gemma 3 27B',
    'Nemotron Nano 3 30B',
    'MiniMax M2',
    'Ministral 14B',
    'GLM 4.7 Flash',
    'Gemma 3 12B',
    'Nemotron Nano 12B VL',
    'Ministral 8B',
    'Nemotron Nano 9B',
    'Palmyra Vision 7B',
    'Gemma 3 4B',
    'Ministral 3B',
  ];
  return <PandoraChatModelOption>[
    for (var i = 0; i < names.length; i += 1)
      PandoraChatModelOption(
        routingProvider: 'bedrock',
        providerName: 'Verified',
        modelId: 'fixture.model.$i',
        modelName: names[i],
        selectable: true,
        availability: 'available',
      ),
    for (var i = 0; i < 48; i += 1)
      PandoraChatModelOption(
        routingProvider: 'bedrock',
        providerName: 'Unavailable',
        modelId: 'fixture.locked.$i',
        modelName: 'Unavailable $i',
        selectable: false,
        availability: 'unavailable',
      ),
  ];
}

PandoraChatModelPickerSnapshot _snapshot() => PandoraChatModelPickerSnapshot(
      models: _pickerModels(),
      selection: const PandoraChatModelSelection.auto(),
      reasoningMode: PandoraIntelligenceMode.auto,
    );

Future<void> _pumpVisualFrames(WidgetTester tester) async {
  for (final duration in <Duration>[
    Duration.zero,
    Duration(milliseconds: 50),
    Duration(milliseconds: 200),
    Duration(milliseconds: 500),
  ]) {
    await tester.pump(duration);
  }
}

Future<void> _precacheMark(WidgetTester tester) async {
  final mark = find.byType(PandoraMark);
  if (mark.evaluate().isEmpty) return;
  await tester.runAsync(() async {
    await precacheImage(
      const AssetImage(PandoraMark.assetPath),
      tester.element(mark.first),
    );
  });
  await tester.pump();
}

Future<void> _mount(
  WidgetTester tester, {
  PandoraIntelligenceApi? intelligence,
}) async {
  PandoraLocalAiPreference.setCachedForTesting(false);
  addTearDown(PandoraLocalAiPreference.resetForTesting);
  await setTestSurface(tester, logicalSize: _phoneSize);
  await tester.pumpWidget(
    PandoraDependencies(
      auth: const FakeAuth(),
      repository: FakeRepository(),
      intelligence: intelligence ?? FakeChatIntelligence(),
      diagnostics: DiagnosticsStore(),
      child: testApp(
        themeMode: ThemeMode.dark,
        child: _withFonts(
          const RepaintBoundary(
            key: _surfaceKey,
            child: PandoraChatShell(),
          ),
        ),
      ),
    ),
  );
  await _pumpVisualFrames(tester);
  await _precacheMark(tester);
}

AskPandoraScreenState _chat(WidgetTester tester) =>
    tester.state<AskPandoraScreenState>(find.byType(AskPandoraScreen));

void _expectComposer(WidgetTester tester, {double keyboardInset = 0}) {
  final composer = find.byKey(const ValueKey<String>('ask-pandora-composer'));
  final rect = tester.getRect(composer);
  expect(rect.left, closeTo(14, .1));
  expect(rect.right, closeTo(_phoneSize.width - 14, .1));
  expect(rect.height, closeTo(54, .1));
  expect(rect.bottom, lessThanOrEqualTo(_phoneSize.height - keyboardInset));
  final input = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('ask-pandora-objective')));
  expect(input.decoration?.hintText, 'Message Pandora…');
  for (final key in [
    'ask-pandora-plus',
    'ask-pandora-model-control',
    'ask-pandora-stop',
    'ask-pandora-submit',
  ]) {
    final control = find.byKey(ValueKey<String>(key));
    expect(tester.getRect(control).bottom, lessThanOrEqualTo(rect.bottom));
  }
  expect(find.text('Back'), findsNothing);
  expect(tester.takeException(), isNull);
}

void _expectContainedPicker(WidgetTester tester) {
  final surface =
      find.byKey(const ValueKey<String>('pandora-model-picker-surface'));
  final material = tester.widget<Material>(surface);
  expect(material.color?.a, 1);
  expect(material.clipBehavior, Clip.antiAlias);
  expect(material.elevation, greaterThan(0));
  final rect = tester.getRect(surface);
  expect(rect.left, greaterThanOrEqualTo(12));
  expect(rect.right, lessThanOrEqualTo(_phoneSize.width - 12));
  expect(rect.top, greaterThanOrEqualTo(12));
  expect(rect.bottom, lessThanOrEqualTo(_phoneSize.height - 12));
  final close =
      find.byKey(const ValueKey<String>('pandora-model-picker-close'));
  expect(close.hitTestable(), findsOneWidget);
  expect(rect.contains(tester.getCenter(close)), isTrue);
  final input = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('ask-pandora-objective')));
  expect(input.focusNode?.hasFocus, isFalse);
  expect(tester.takeException(), isNull);
}

Future<void> _waitForCompletion(WidgetTester tester) async {
  for (var i = 0;
      i < 40 &&
          _chat(tester).debugChatState.turns.last.phase !=
              PandoraChatPhase.completed;
      i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
  expect(_chat(tester).debugChatState.turns.last.phase,
      PandoraChatPhase.completed);
  expect(find.text('Pandora is working…'), findsNothing);
  expect(tester.takeException(), isNull);
}

Future<void> _capture(WidgetTester tester, String name) async {
  await _pumpVisualFrames(tester);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_surfaceKey),
  );
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
    } finally {
      image.dispose();
    }
  });
  expect(bytes, isNotNull);
  final output = File('build/lane-h-goldens/$name.png');
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(bytes!);
  expect(output.lengthSync(), greaterThan(0));

  final baseline = File('test/goldens/owner_screens/$name.png');
  expect(baseline.existsSync(), isTrue,
      reason: 'Every reviewed Lane H capture must have a tracked baseline.');
  if (!Platform.isWindows) {
    await expectLater(
      find.byKey(_surfaceKey),
      matchesGoldenFile('owner_screens/$name.png'),
    );
  }
}

void main() {
  setUpAll(() async {
    await _loadFonts();
  });

  testWidgets('captures lane_h_landing_resting_390x844', (tester) async {
    await _mount(tester);
    _expectComposer(tester);
    expect(_chat(tester).debugChatState.turns, isEmpty);
    await _capture(tester, 'lane_h_landing_resting_390x844');
  });

  testWidgets('captures lane_h_keyboard_open_390x844', (tester) async {
    await _mount(tester);
    addTearDown(tester.view.resetViewInsets);
    final restingComposer = tester
        .getRect(find.byKey(const ValueKey<String>('ask-pandora-composer')));
    await tester.tap(
      find.byKey(const ValueKey<String>('ask-pandora-objective')),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await _capture(tester, 'lane_h_keyboard_open_390x844');
    _expectComposer(tester, keyboardInset: 320);
    final raisedComposer = tester
        .getRect(find.byKey(const ValueKey<String>('ask-pandora-composer')));
    expect(raisedComposer.size, restingComposer.size);
    expect(raisedComposer.bottom, closeTo(restingComposer.bottom - 320, .1));
    tester.view.resetViewInsets();
    await _pumpVisualFrames(tester);
    expect(
        tester.getRect(
            find.byKey(const ValueKey<String>('ask-pandora-composer'))),
        restingComposer);
  });

  // Preserve the historical asset path while asserting the authoritative
  // per-turn pending state. Activity is an opt-in Details surface, and a normal
  // greeting must not open a second execution transcript or Activity stream.
  testWidgets('captures accepted greeting and resolves the same logical turn',
      (tester) async {
    final pending = Completer<PandoraIntelligenceTurn>();
    var activitySubscriptions = 0;
    final activity = StreamController<Map<String, dynamic>>.broadcast(
        onListen: () => activitySubscriptions++);
    final intelligence = _VisualChatIntelligence(
        onReply: (_) => pending.future, events: activity.stream);
    try {
      await _mount(tester, intelligence: intelligence);
      final objective =
          find.byKey(const ValueKey<String>('ask-pandora-objective'));
      await tester.tap(objective);
      await tester.enterText(objective, 'Hello');
      await tester.tap(
        find.byKey(const ValueKey<String>('ask-pandora-submit')),
      );
      await tester.pump();
      expect(intelligence.dispatches, hasLength(1));
      expect(intelligence.lastMessage, 'Hello');
      expect(intelligence.lastEnterpriseContext?['selectedObject'],
          containsPair('coreMode', 'owner'));
      final admitted = _chat(tester).debugChatState.turns.single;
      expect(admitted.phase, PandoraChatPhase.accepted);
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('Pandora is working…'), findsOneWidget);
      expect(find.text('Ready.'), findsNothing);
      expect(find.text('Thinking through the request…'), findsNothing);
      expect(find.byKey(const ValueKey('ask-pandora-activity-theatre')),
          findsNothing);
      _expectComposer(tester);
      await _capture(tester, 'lane_h_after_send_thinking_390x844');
      pending.complete(const PandoraIntelligenceTurn(
          threadId: 'fixture-chat-thread',
          reply: 'Ready.',
          intent: 'conversation',
          confidence: 1,
          needsClarification: false));
      await _waitForCompletion(tester);
      final completed = _chat(tester).debugChatState.turns.single;
      expect(completed.id, admitted.id);
      expect(completed.attempt?.token, admitted.attempt?.token);
      expect(completed.receipt?.model, 'fixture.model.2');
      expect(_chat(tester).debugChatState.preferences.isAuto, isTrue);
      expect(find.text('Ready.'), findsOneWidget);
      expect(intelligence.dispatches, hasLength(1));
      expect(activitySubscriptions, 0);
    } finally {
      // A failed pixel comparison must also release the fake provider future;
      // otherwise stream cancellation during test disposal hides the mismatch
      // behind a timeout. Closing an unlistened broadcast stream is finite.
      if (!pending.isCompleted) {
        pending.complete(const PandoraIntelligenceTurn(
            threadId: 'fixture-chat-thread',
            reply: 'Ready.',
            intent: 'conversation',
            confidence: 1,
            needsClarification: false));
      }
      await _pumpVisualFrames(tester);
      await activity.close();
    }
  });

  testWidgets('captures lane_h_picker_open_390x844', (tester) async {
    await _mount(tester);
    final semantics = tester.ensureSemantics();
    try {
      _chat(tester).debugShowModelPicker(_snapshot());
      await _capture(tester, 'lane_h_picker_open_390x844');
      _expectContainedPicker(tester);
      expect(
          tester
              .getSemantics(
                  find.byKey(const ValueKey<String>('model-picker-auto')))
              .flagsCollection
              .isSelected,
          ui.Tristate.isTrue);
      expect(find.text('Kimi K2.5'), findsNothing);
      expect(
          tester
              .widget<ChoiceChip>(find
                  .byKey(const ValueKey<String>('reasoning-picker-balanced')))
              .selected,
          isTrue);
      await tester
          .tap(find.byKey(const ValueKey<String>('reasoning-picker-fast')));
      await _pumpVisualFrames(tester);
      expect(find.byKey(const ValueKey('pandora-model-picker-surface')),
          findsNothing);
      expect(_chat(tester).debugChatState.preferences.reasoningMode, 'fast');
      expect(_chat(tester).debugChatState.preferences.isAuto, isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('captures lane_h_picker_end_390x844', (tester) async {
    await _mount(tester);
    _chat(tester).debugShowModelPicker(_snapshot(), startAtEnd: true);
    await _capture(tester, 'lane_h_picker_end_390x844');
    _expectContainedPicker(tester);
    expect(find.text('Ministral 3B').hitTestable(), findsOneWidget);
    expect(find.text('48 more unavailable').hitTestable(), findsOneWidget);
    final list = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey<String>('pandora-model-picker-list')));
    expect(list.controller!.offset,
        closeTo(list.controller!.position.maxScrollExtent, .1));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _pumpVisualFrames(tester);
    expect(find.byKey(const ValueKey('pandora-model-picker-surface')),
        findsNothing);
  });

  testWidgets('captures lane_h_non_auto_tag_390x844', (tester) async {
    final intelligence = _VisualChatIntelligence();
    await _mount(tester, intelligence: intelligence);
    final semantics = tester.ensureSemantics();
    try {
      const selected = PandoraChatModelSelection.manual(
        provider: 'bedrock',
        model: 'fixture.model.24',
        fallbackMode: 'allow_fallback',
      );
      _chat(tester).debugSetModelSelection(selected, 'Gemma 3 4B');
      await tester.enterText(
          find.byKey(const ValueKey<String>('ask-pandora-objective')), 'Hi');
      await tester
          .tap(find.byKey(const ValueKey<String>('ask-pandora-submit')));
      await _waitForCompletion(tester);
      final state = _chat(tester).debugChatState;
      expect(state.turns.single.receipt?.model, 'fixture.model.2');
      expect(state.preferences.model, 'fixture.model.24');
      expect(state.preferences.isAuto, isFalse);
      expect(state.turns.single.preferences.model, 'fixture.model.24');

      // The historical asset name is retained for the evidence workflow. Manual
      // model names no longer occupy the default composer; capture the selected
      // row on the contained Advanced surface where the preference is visible.
      _chat(tester).debugShowModelPicker(_snapshot());
      await _pumpVisualFrames(tester);
      expect(
          tester
              .getSemantics(
                  find.byKey(const ValueKey<String>('model-picker-auto')))
              .flagsCollection
              .isSelected,
          ui.Tristate.isFalse);
      final manual =
          find.byKey(const ValueKey<String>('model-picker-fixture.model.24'));
      await tester.ensureVisible(manual);
      await _pumpVisualFrames(tester);
      expect(tester.getSemantics(manual).flagsCollection.isSelected,
          ui.Tristate.isTrue);
      _expectContainedPicker(tester);
      await _capture(tester, 'lane_h_non_auto_tag_390x844');
      await tester.tap(manual);
      await _pumpVisualFrames(tester);
      expect(find.byKey(const ValueKey('pandora-model-picker-surface')),
          findsNothing);
      expect(
          _chat(tester).debugChatState.preferences.model, 'fixture.model.24');
      expect(intelligence.dispatches, hasLength(1));
    } finally {
      semantics.dispose();
    }
  });
}
