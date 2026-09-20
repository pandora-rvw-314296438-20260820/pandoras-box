import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/local_ai/pandora_local_ai.dart';

void main() {
  const ready = PandoraLocalAiStatus(
    supported: true,
    configured: true,
    loaded: true,
    modelName: 'Qwen3-4B-Instruct-2507-Q4_K_M.gguf',
    modelSha256:
        '1571ec5115bcfed4b4327fc27b5f44ea284806caf5331eef89326191c9b031d6',
    engineState: 'ready',
  );

  test('authorized synchronized PLP context can route today questions locally', () {
    final decision = PandoraLocalAiRouter.decide(
      message: "What is today's occupancy?",
      hasAttachment: false,
      hasProjectContext: true,
      hasSelectedCapability: false,
      hasCharacterContext: false,
      status: ready,
    );

    expect(decision.useLocal, isTrue);
    expect(decision.reason, 'authorized_local_business_context');
  });

  test('external market comparison still requires cloud capability', () {
    final decision = PandoraLocalAiRouter.decide(
      message: "Compare our occupancy with today's Boracay market average",
      hasAttachment: false,
      hasProjectContext: true,
      hasSelectedCapability: false,
      hasCharacterContext: false,
      status: ready,
    );

    expect(decision.useLocal, isFalse);
    expect(decision.reason, 'live_or_connected_data');
  });

  test('provider mutation stays off the local answer path', () {
    final decision = PandoraLocalAiRouter.decide(
      message: 'Create a staff task to inspect Room 3',
      hasAttachment: false,
      hasProjectContext: true,
      hasSelectedCapability: true,
      hasCharacterContext: false,
      status: ready,
    );

    expect(decision.useLocal, isFalse);
    expect(decision.reason, 'connected_capability');
  });
}
