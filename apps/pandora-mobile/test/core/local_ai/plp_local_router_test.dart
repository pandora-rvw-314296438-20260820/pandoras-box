import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/local_ai/pandora_local_ai.dart';

void main() {
  const ready = PandoraLocalAiStatus(
    supported: true,
    configured: true,
    loaded: true,
    modelName: 'qwen2.5-3b-instruct-q4_k_m.gguf',
    modelBytes: 2100000000,
    modelSha256:
        '626b4a6678b86442240e33df819e00132d3ba7dddfe1cdc4fbb18e0a9615c62d',
    engineState: 'ready',
    diagnostics: <String, Object?>{
      'localReady': true, 'healthTokenEvents': 2,
      'recommendedModelSha256':
          '626b4a6678b86442240e33df819e00132d3ba7dddfe1cdc4fbb18e0a9615c62d',
      'safeModelMaxBytes': 2300 * 1024 * 1024,
      'availableRamBytes': 4 * 1024 * 1024 * 1024,
    },
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

  test('unvalidated local model routes to cloud before warm', () {
    const unvalidated = PandoraLocalAiStatus(
      supported: true,
      configured: true,
      loaded: false,
      modelName: 'other.gguf',
      modelBytes: 1900000000,
      modelSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      engineState: 'initialized',
      diagnostics: <String, Object?>{
      'localReady': true, 'healthTokenEvents': 2,
        'recommendedModelSha256':
            '626b4a6678b86442240e33df819e00132d3ba7dddfe1cdc4fbb18e0a9615c62d',
        'safeModelMaxBytes': 2300 * 1024 * 1024,
        'availableRamBytes': 4 * 1024 * 1024 * 1024,
      },
    );
    final decision = PandoraLocalAiRouter.decide(
      message: 'Summarize our resort status.',
      hasAttachment: false,
      hasProjectContext: true,
      hasSelectedCapability: false,
      hasCharacterContext: false,
      status: unvalidated,
    );

    expect(decision.useLocal, isFalse);
    expect(decision.reason, 'local_model_not_validated');
  });

  test('oversized local model routes to cloud before Android pressure', () {
    const oversized = PandoraLocalAiStatus(
      supported: true,
      configured: true,
      loaded: true,
      modelName: 'oversized.gguf',
      modelBytes: 2497279136,
      engineState: 'ready',
      diagnostics: <String, Object?>{
      'localReady': true, 'healthTokenEvents': 2,
        'safeModelMaxBytes': 2300 * 1024 * 1024,
      },
    );
    final decision = PandoraLocalAiRouter.decide(
      message: 'Summarize our resort status.',
      hasAttachment: false,
      hasProjectContext: true,
      hasSelectedCapability: false,
      hasCharacterContext: false,
      status: oversized,
    );

    expect(decision.useLocal, isFalse);
    expect(decision.reason, 'model_exceeds_phone_safe_profile');
  });

  test('cold load with insufficient free RAM routes to cloud', () {
    const constrained = PandoraLocalAiStatus(
      supported: true,
      configured: true,
      loaded: false,
      modelName: 'qwen2.5-3b-instruct-q4_k_m.gguf',
      modelBytes: 2100000000,
      modelSha256:
          '626b4a6678b86442240e33df819e00132d3ba7dddfe1cdc4fbb18e0a9615c62d',
      engineState: 'initialized',
      diagnostics: <String, Object?>{
      'localReady': true, 'healthTokenEvents': 2,
        'recommendedModelSha256':
            '626b4a6678b86442240e33df819e00132d3ba7dddfe1cdc4fbb18e0a9615c62d',
        'safeModelMaxBytes': 2300 * 1024 * 1024,
        'availableRamBytes': 2 * 1024 * 1024 * 1024,
      },
    );
    final decision = PandoraLocalAiRouter.decide(
      message: 'Summarize our resort status.',
      hasAttachment: false,
      hasProjectContext: true,
      hasSelectedCapability: false,
      hasCharacterContext: false,
      status: constrained,
    );

    expect(decision.useLocal, isFalse);
    expect(decision.reason, 'insufficient_cold_load_ram');
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
