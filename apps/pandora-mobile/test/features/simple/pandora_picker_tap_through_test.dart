import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/features/simple/pandora_model_picker.dart';

void main() {
  testWidgets('model picker taps through to exact manual selection', (tester) async {
    PandoraChatModelSelection? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const ValueKey<String>('open-model-picker'),
              onPressed: () async {
                result = await showModalBottomSheet<PandoraChatModelSelection>(
                  context: context,
                  builder: (_) => const PandoraModelPickerSheet(
                    selection: PandoraChatModelSelection.auto(),
                    models: <PandoraChatModelOption>[
                      PandoraChatModelOption(
                        routingProvider: 'bedrock',
                        providerName: 'Mistral AI',
                        modelId: 'fixture.mistral',
                        modelName: 'Mistral Verified',
                        selectable: true,
                        availability: 'available',
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Open model'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('open-model-picker')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('model-picker-fixture.mistral')), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('model-picker-fixture.mistral')),
    );
    await tester.pumpAndSettle();

    expect(result?.selection, 'manual');
    expect(result?.provider, 'bedrock');
    expect(result?.model, 'fixture.mistral');
    expect(result?.fallbackMode, 'strict');
  });

  testWidgets('reasoning picker taps through to Deep', (tester) async {
    PandoraIntelligenceMode? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const ValueKey<String>('open-reasoning-picker'),
              onPressed: () async {
                result = await showModalBottomSheet<PandoraIntelligenceMode>(
                  context: context,
                  builder: (_) => const PandoraReasoningPickerSheet(
                    selection: PandoraIntelligenceMode.auto,
                  ),
                );
              },
              child: const Text('Open reasoning'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('open-reasoning-picker')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('reasoning-picker-deep')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('reasoning-picker-deep')),
    );
    await tester.pumpAndSettle();

    expect(result, PandoraIntelligenceMode.deep);
  });
}
