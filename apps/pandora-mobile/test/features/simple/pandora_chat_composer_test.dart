import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/simple/chat/pandora_chat_composer.dart';

void main() {
  late TextEditingController text;
  late FocusNode focus;
  late ValueNotifier<PandoraComposerState> intent;
  late List<String> sent;
  late int stopped;
  late int voice;

  setUp(() {
    text = TextEditingController();
    focus = FocusNode();
    intent = ValueNotifier(const PandoraComposerState());
    sent = [];
    stopped = 0;
    voice = 0;
  });

  tearDown(() {
    text.dispose();
    focus.dispose();
    intent.dispose();
  });

  Future<void> mount(WidgetTester tester,
      {double textScale = 1, ValueChanged<double>? onHeight}) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PandoraChatComposer(
              controller: text,
              focusNode: focus,
              state: intent,
              onSend: (value) {
                sent.add(value);
                text.clear();
                intent.value = const PandoraComposerState(
                    phase: PandoraComposerPhase.generating);
              },
              onStop: () {
                stopped += 1;
                intent.value = const PandoraComposerState();
              },
              onVoice: () => voice += 1,
              onModelOptions: () {},
              onHeightChanged: onHeight,
              leading: const Icon(Icons.add_rounded),
            ),
          ),
        ),
      ),
    ));
  }

  final input = find.byKey(const ValueKey<String>('ask-pandora-objective'));
  final send = find.byKey(const ValueKey<String>('ask-pandora-submit'));
  final stop = find.byKey(const ValueKey<String>('ask-pandora-stop'));

  testWidgets('current text sends through an old empty/voice frame',
      (tester) async {
    await mount(tester);
    text.text = 'Hi';
    // Intentionally no pump between controller change and action activation.
    await tester.tap(send);
    await tester.tap(send);
    expect(sent, ['Hi']);
    expect(voice, 0);
    expect(text.text, isEmpty);
    await tester.pump();
    expect(find.text('Message Pandora…'), findsOneWidget);
    expect(find.text('Follow up'), findsNothing);
    expect(find.text('Back'), findsNothing);
  });

  testWidgets(
      'clearing a visible Send frame cannot start voice or an empty turn',
      (tester) async {
    await mount(tester);
    text.text = 'About to clear';
    await tester.pump();
    text.clear();
    await tester.tap(send);
    expect(sent, isEmpty);
    expect(voice, 0);
  });

  testWidgets('live queued admission rejects a stale enabled Send callback',
      (tester) async {
    await mount(tester);
    text.text = 'Preserve this next draft';
    await tester.pump();
    intent.value =
        const PandoraComposerState(phase: PandoraComposerPhase.queued);
    await tester.tap(send);
    expect(sent, isEmpty);
    expect(text.text, 'Preserve this next draft');
    expect(voice, 0);
  });

  testWidgets(
      'typing into an empty generating frame sends without another frame',
      (tester) async {
    intent.value = const PandoraComposerState(
      phase: PandoraComposerPhase.generating,
      generationIdentity: 'turn-a:attempt-1',
    );
    await mount(tester);
    text.text = 'Send this next';
    // This was an empty disabled Voice frame, not an enabled Send frame.
    // The physical action must still read the new editor value synchronously.
    await tester.tap(send);
    expect(sent, ['Send this next']);
    expect(voice, 0);
  });

  testWidgets(
      'live generation identity projection rejects an obsolete Stop tap',
      (tester) async {
    intent.value =
        const PandoraComposerState(phase: PandoraComposerPhase.generating);
    await mount(tester);
    intent.value = const PandoraComposerState();
    await tester.tap(stop);
    expect(stopped, 0);
  });

  testWidgets('typing during generation keeps the input and stop slot stable',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester);
    final element = tester.element(input);
    final idleInputRect = tester.getRect(input);
    final idleStopRect = tester.getRect(stop);
    intent.value =
        const PandoraComposerState(phase: PandoraComposerPhase.generating);
    await tester.pump();
    text.text = 'A follow-up';
    await tester.pump();
    expect(identical(tester.element(input), element), isTrue);
    expect(tester.getRect(input).width, idleInputRect.width);
    expect(tester.getRect(stop), idleStopRect);
    await tester.tap(stop);
    expect(stopped, 1);
    expect(sent, isEmpty);
    expect(text.text, 'A follow-up');
  });

  testWidgets('a Stop from the prior generation cannot cancel its successor',
      (tester) async {
    intent.value = const PandoraComposerState(
      phase: PandoraComposerPhase.generating,
      generationIdentity: 'turn-a:attempt-1',
    );
    await mount(tester);
    intent.value = const PandoraComposerState(
      phase: PandoraComposerPhase.generating,
      generationIdentity: 'turn-b:attempt-1',
    );
    // The old frame still presents Stop for A while the controller already
    // owns B. It must neither cancel B nor fall through to another action.
    await tester.tap(stop);
    expect(stopped, 0);
    await tester.pump();
    await tester.tap(stop);
    expect(stopped, 1);
  });

  testWidgets('multiline and enlarged text grow within a measured bound',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final heights = <double>[];
    await mount(tester, textScale: 2, onHeight: heights.add);
    await tester.pump();
    final initial = tester.getSize(input).height;
    text.text = List.generate(12, (i) => 'Line $i').join('\n');
    await tester.pumpAndSettle();
    final grown = tester.getSize(input).height;
    expect(grown, greaterThan(initial));
    expect(grown, lessThanOrEqualTo(160));
    expect(heights.last, closeTo(grown + 12, 1));
    expect(tester.takeException(), isNull);
    expect(text.text.split('\n').length, 12);
  });

  testWidgets('keyboard Send admits current text and newline remains editable',
      (tester) async {
    await mount(tester);
    await tester.showKeyboard(input);
    await tester.enterText(input, 'One\nTwo');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    expect(sent, ['One\nTwo']);
    expect(text.text, isEmpty);
    await tester.pump();
    text.text = 'Editable';
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(sent.last, 'Editable');
  });
}
