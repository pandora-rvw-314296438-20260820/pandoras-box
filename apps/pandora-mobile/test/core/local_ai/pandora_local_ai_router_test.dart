import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/local_ai/pandora_local_ai.dart';

void main() {
  group('PandoraLocalAiRouter', () {
    test('keeps routine conversation local', () {
      expect(
        PandoraLocalAiRouter.shouldUseLocal(
          message: 'Explain this idea in simple words.',
          hasAttachment: false,
          hasProjectContext: false,
          hasSelectedCapability: false,
          hasCharacterContext: false,
          status: const PandoraLocalAiStatus(supported: true, configured: true, loaded: true,
            diagnostics: {'localReady': true, 'healthTokenEvents': 2}),
        ),
        isTrue,
      );
    });

    test('routes provider work to cloud intelligence', () {
      expect(
        PandoraLocalAiRouter.shouldUseLocal(
          message: 'Check GitHub for failing CI.',
          hasAttachment: false,
          hasProjectContext: false,
          hasSelectedCapability: false,
          hasCharacterContext: false,
          status: const PandoraLocalAiStatus(supported: true, configured: true, loaded: true,
            diagnostics: {'localReady': true, 'healthTokenEvents': 2}),
        ),
        isFalse,
      );
    });

    test('routes external mutations away from local AI', () {
      expect(
        PandoraLocalAiRouter.shouldUseLocal(
          message: 'Deploy the latest build.',
          hasAttachment: false,
          hasProjectContext: false,
          hasSelectedCapability: false,
          hasCharacterContext: false,
          status: const PandoraLocalAiStatus(supported: true, configured: true, loaded: true,
            diagnostics: {'localReady': true, 'healthTokenEvents': 2}),
        ),
        isFalse,
      );
    });

    test('routes low-memory runtime away from local AI', () {
      final decision = PandoraLocalAiRouter.decide(
        message: 'Summarize this note.',
        hasAttachment: false,
        hasProjectContext: false,
        hasSelectedCapability: false,
        hasCharacterContext: false,
        status: const PandoraLocalAiStatus(
          supported: true,
          configured: true,
          loaded: true,
          diagnostics: <String, Object?>{
      'localReady': true, 'healthTokenEvents': 2,'memoryLow': true},
        ),
      );
      expect(decision.useLocal, isFalse);
      expect(decision.reason, 'android_memory_pressure');
    });

    test('routes severe thermal runtime away from local AI', () {
      final decision = PandoraLocalAiRouter.decide(
        message: 'Summarize this note.',
        hasAttachment: false,
        hasProjectContext: false,
        hasSelectedCapability: false,
        hasCharacterContext: false,
        status: const PandoraLocalAiStatus(
          supported: true,
          configured: true,
          loaded: true,
          diagnostics: <String, Object?>{
      'localReady': true, 'healthTokenEvents': 2,'thermalStatus': 'severe'},
        ),
      );
      expect(decision.useLocal, isFalse);
      expect(decision.reason, 'thermal_pressure');
    });

    test('routes low unplugged battery away from local AI', () {
      final decision = PandoraLocalAiRouter.decide(
        message: 'Summarize this note.',
        hasAttachment: false,
        hasProjectContext: false,
        hasSelectedCapability: false,
        hasCharacterContext: false,
        status: const PandoraLocalAiStatus(
          supported: true,
          configured: true,
          loaded: true,
          diagnostics: <String, Object?>{
      'localReady': true, 'healthTokenEvents': 2,
            'batteryPercent': 10,
            'charging': false,
          },
        ),
      );
      expect(decision.useLocal, isFalse);
      expect(decision.reason, 'low_battery');
    });

    test('keeps low battery local while charging', () {
      final decision = PandoraLocalAiRouter.decide(
        message: 'Summarize this note.',
        hasAttachment: false,
        hasProjectContext: false,
        hasSelectedCapability: false,
        hasCharacterContext: false,
        status: const PandoraLocalAiStatus(
          supported: true,
          configured: true,
          loaded: true,
          diagnostics: <String, Object?>{
      'localReady': true, 'healthTokenEvents': 2,
            'batteryPercent': 10,
            'charging': true,
          },
        ),
      );
      expect(decision.useLocal, isTrue);
      expect(decision.reason, 'routine_local_sufficient');
    });

    test('routes contextual turns away from local AI', () {
      expect(
        PandoraLocalAiRouter.shouldUseLocal(
          message: 'Summarize this.',
          hasAttachment: true,
          hasProjectContext: false,
          hasSelectedCapability: false,
          hasCharacterContext: false,
          status: const PandoraLocalAiStatus(supported: true, configured: true, loaded: true,
            diagnostics: {'localReady': true, 'healthTokenEvents': 2}),
        ),
        isFalse,
      );
    });
  });
}
