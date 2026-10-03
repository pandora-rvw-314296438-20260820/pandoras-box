import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/features/simple/pandora_model_picker.dart';

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
}
