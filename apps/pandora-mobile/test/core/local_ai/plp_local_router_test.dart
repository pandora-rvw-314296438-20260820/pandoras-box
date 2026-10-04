import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/local_ai/pandora_local_ai.dart';

void main() {
  setUp(() {
    PandoraLocalAiPreference.setCachedForTesting(true);
  });

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
      'recommendedModelSha256':
          '626b4a6678b86442240e33df819e00132d3ba7dddfe1cdc4fbb18e0a9615c62d',
      'safeModelMaxBytes': 2300 * 1024 * 1024,
      'availableRamBytes': 4 * 1024 * 1024 * 1024,
    },
  );

  test('authorized synchronized PLP context can route today questions locally',
      () {
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
  test(
      'PLP Alfred source does not bypass local AI and recovers verified cloud result',
      () {
    final screenSource =
        File('lib/features/simple/ask_pandora_screen.dart').readAsStringSync();
    final adapters = File(
      'lib/features/simple/chat/pandora_chat_action_adapters.dart',
    ).readAsStringSync();
    final localStart = adapters.indexOf(
      'Future<bool> _executePhoneAi(',
    );
    final localStatus = adapters.indexOf(
      'status = await PandoraLocalAi.instance',
      localStart,
    );
    expect(localStart, greaterThanOrEqualTo(0));
    expect(localStatus, greaterThan(localStart));

    final admissionPrelude = adapters.substring(localStart, localStatus);
    expect(admissionPrelude, isNot(contains('_isPlpEnterpriseContext')));
    expect(admissionPrelude, isNot(contains('input.isPlp')));
    final localRoute = screenSource.indexOf(
      'await _executeLocalRoute(dispatch, input, dependencies)',
    );
    final cloudRoute = screenSource.indexOf(
      'intelligence.executeChatTurn(dispatch)',
      localRoute,
    );
    expect(localRoute, greaterThanOrEqualTo(0));
    expect(cloudRoute, greaterThan(localRoute));
    expect(
      screenSource.substring(localRoute, cloudRoute),
      contains('if (handled || !_current(token)) return;'),
    );
    expect(
      screenSource,
      contains('readChatTurn(turnId: token.turnId)'),
    );
    expect(
      screenSource,
      contains('_applyWireEvent(_dispatchFor(token), event, reconciled: true)'),
    );
    expect(
      screenSource,
      contains('event.requireIdentity('),
    );
    for (final identity in [
      'turnId: token.turnId',
      'attemptId: token.attemptId',
      'generation: token.generation',
      'threadId: _chat.state.threadId ?? dispatch.threadId',
    ]) {
      expect(screenSource, contains(identity));
    }

    final apiSource =
        File('lib/core/data/pandora_intelligence_api.dart').readAsStringSync();
    final readbackStart = apiSource.indexOf('readChatTurn({');
    final readbackEnd = apiSource.indexOf('cancelChatTurn({', readbackStart);
    expect(readbackStart, greaterThanOrEqualTo(0));
    expect(readbackEnd, greaterThan(readbackStart));
    final readback = apiSource.substring(readbackStart, readbackEnd);
    expect(readback, contains("'protocolVersion': 2"));
    expect(readback, contains("'operation': 'readback'"));
    expect(readback, contains("if (response['found'] == false) return null"));
    expect(
      readback,
      contains(
          'event.requireIdentity(organizationId: _organizationId, turnId: turnId)'),
    );
    // Legacy callers retain verified terminal-state recovery during rollout.
    expect(apiSource, contains('recoverCompletedChatTurn('));
    expect(
      apiSource,
      contains(".select('terminal_state,execution_state,execution_result')"),
    );
    expect(apiSource, contains("_text(json['execution_state']) != 'complete'"));
    expect(apiSource, contains("terminalState != 'result'"));
  });

  test('Qwen warm recovery clears poisoned Error state and serializes cleanup',
      () {
    final kotlinSource = File(
      'platform/android/app/src/main/kotlin/com/banataosystems/pandora_mobile/'
      'PandoraLocalAiChannel.kt',
    ).readAsStringSync();

    expect(kotlinSource, contains('private suspend fun warmWithRecovery()'));
    expect(
      kotlinSource,
      contains('if (engine.state.value is InferenceEngine.State.Error)'),
    );
    expect(
      kotlinSource,
      contains('activeGeneration?.cancelAndJoin()'),
    );
    expect(kotlinSource,
        contains('private const val WARM_DEADLINE_MS = 180_000L'));
    expect(kotlinSource, contains('engine.requestCancel()'));
    expect(kotlinSource, contains('engine.clearCancelRequest()'));
    expect(kotlinSource, contains('activeWarm?.cancel()'));
    expect(kotlinSource, contains('withTimeoutOrNull(5_000L)'));
    expect(kotlinSource, isNot(contains('activeWarm?.cancelAndJoin()')));
    final cppSource = File('platform/android/app/src/main/cpp/ai_chat.cpp')
        .readAsStringSync();
    expect(cppSource, contains('PREFERRED_GPU_LAYERS    = 0'));
    expect(cppSource,
        contains('model_params.progress_callback = model_load_progress;'));
    expect(cppSource,
        contains('g_cancel_requested.load(std::memory_order_relaxed)'));
    expect(
        cppSource,
        contains(
            'if (!model && !g_cancel_requested.load(std::memory_order_relaxed))'));
    expect(cppSource, contains('cpu_safe_vulkan_compiled'));
    final localAiSource =
        File('lib/core/local_ai/pandora_local_ai.dart').readAsStringSync();
    expect(localAiSource, contains('const Duration(seconds: 128)'));
    expect(kotlinSource, contains('private suspend fun warmWithDeadline()'));
    expect(
      kotlinSource,
      isNot(contains(
        'if (loadedModelPath != null &&\n'
        '            (state is InferenceEngine.State.ModelReady ||\n'
        '                state is InferenceEngine.State.Error)',
      )),
    );

    final modelResident = kotlinSource.indexOf(
      'loadedModelPath = canonicalPath',
      kotlinSource.indexOf('private suspend fun warmInternal()'),
    );
    final systemPrompt = kotlinSource.indexOf(
      'engine.setSystemPrompt(SYSTEM_PROMPT.trim())',
      modelResident,
    );
    expect(modelResident, greaterThanOrEqualTo(0));
    expect(systemPrompt, greaterThan(modelResident));
  });

  test('PLP local prompt keeps bounded resort context and safe Qwen prewarm',
      () {
    final screenSource =
        File('lib/features/simple/ask_pandora_screen.dart').readAsStringSync();
    final adapters = File(
      'lib/features/simple/chat/pandora_chat_action_adapters.dart',
    ).readAsStringSync();

    expect(screenSource, contains('_prewarmPlpLocalAiIfSafe()'));
    expect(
      adapters,
      contains(
          'Previously synchronized resort snapshot; answer only from included fields and do not claim a fresh read.'),
    );
    expect(adapters, contains("if (!input.isPlp) return ''"));
    expect(adapters,
        contains("local['payload'] ?? input.enterpriseContext['today']"));
    expect(
        adapters, contains("'authoritativeAsOf': local['authoritativeAsOf']"));
    expect(adapters,
        contains("'sourceHealth': input.enterpriseContext['sourceHealth']"));
    expect(adapters, contains("if (encoded.length > 3600) return ''"));
    expect(adapters, contains('.timeout(const Duration(seconds: 120))'));

    final localStart = adapters.indexOf(
      'Future<bool> _executePhoneAi(',
    );
    final coldGuard =
        adapters.indexOf('if (!status.loaded && !forceLocal)', localStart);
    final coldFallback = adapters.indexOf(
        'unawaited(PandoraLocalAiRuntime.instance.prewarm(', coldGuard);
    final coldReturn = adapters.indexOf('return false;', coldFallback);
    final warm = adapters.indexOf(
      'if (!await runtime.ensureWarm())',
      coldFallback,
    );
    final reset = adapters.indexOf(
      'await PandoraLocalAi.instance.resetConversation()',
      warm,
    );
    expect(coldGuard, greaterThan(localStart));
    expect(coldFallback, greaterThan(coldGuard));
    expect(coldReturn, greaterThan(coldFallback));
    expect(warm, greaterThan(coldReturn));
    expect(reset, greaterThan(warm));
    expect(adapters, contains('runtime.canContinueConversation('));
    expect(adapters, contains('loaded: status.loaded'));
    expect(adapters, contains('previousTurnId: previous.last.id'));
    expect(adapters, contains('_boundedConversationPrompt(dispatch.message)'));
    expect(adapters, contains('runtime.recordConversation('));
    expect(adapters, contains('residencyEpoch: residencyEpoch'));
  });
}
