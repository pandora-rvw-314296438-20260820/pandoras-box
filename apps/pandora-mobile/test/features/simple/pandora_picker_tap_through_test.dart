import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/features/simple/pandora_model_picker.dart';

void main() {
  const selectable = PandoraChatModelOption(
    routingProvider: 'bedrock',
    providerName: 'Google',
    modelId: 'fixture.gemma-3-4b',
    modelName: 'Gemma 3 4B',
    selectable: true,
    availability: 'available',
  );

  testWidgets('model picker taps through to exact manual selection',
      (tester) async {
    PandoraModelPickerChoice? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          body: PandoraModelPickerOverlay(
            models: const <PandoraChatModelOption>[selectable],
            selection: const PandoraChatModelSelection.auto(),
            reasoningMode: PandoraIntelligenceMode.auto,
            onDismiss: () {},
            onModelSelected: (choice) => result = choice,
            onReasoningSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(
      const ValueKey<String>('pandora-model-picker-advanced'),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(
      const ValueKey<String>('model-picker-fixture.gemma-3-4b'),
    ));
    await tester.tap(
      find.byKey(const ValueKey<String>('model-picker-fixture.gemma-3-4b')),
    );
    await tester.pump();

    expect(result?.selection.selection, 'manual');
    expect(result?.selection.provider, 'bedrock');
    expect(result?.selection.model, 'fixture.gemma-3-4b');
    expect(result?.selection.fallbackMode, 'strict');
    expect(result?.label, 'Gemma 3 4B');
  });

  testWidgets('reasoning picker taps through to Deep', (tester) async {
    PandoraIntelligenceMode? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          body: PandoraModelPickerOverlay(
            models: const <PandoraChatModelOption>[selectable],
            selection: const PandoraChatModelSelection.auto(),
            reasoningMode: PandoraIntelligenceMode.auto,
            onDismiss: () {},
            onModelSelected: (_) {},
            onReasoningSelected: (mode) => result = mode,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey<String>('reasoning-picker-deep')),
    );
    await tester.pump();
    expect(result, PandoraIntelligenceMode.deep);
  });

  testWidgets('locked catalog entries collapse to one unavailable count',
      (tester) async {
    const locked = PandoraChatModelOption(
      routingProvider: 'bedrock',
      providerName: 'Locked',
      modelId: 'fixture.locked',
      modelName: 'Locked Model',
      selectable: false,
      availability: 'unavailable',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          body: PandoraModelPickerOverlay(
            models: const <PandoraChatModelOption>[selectable, locked],
            selection: const PandoraChatModelSelection.auto(),
            reasoningMode: PandoraIntelligenceMode.auto,
            onDismiss: () {},
            onModelSelected: (_) {},
            onReasoningSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Locked Model'), findsNothing);
    expect(find.text('1 more unavailable'), findsNothing);
    await tester.tap(find.byKey(
      const ValueKey<String>('pandora-model-picker-advanced'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('1 more unavailable'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('model-picker-local-device')),
      findsOneWidget,
    );
  });
}
