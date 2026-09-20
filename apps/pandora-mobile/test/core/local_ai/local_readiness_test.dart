import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/local_ai/pandora_local_ai.dart';

void main() {
  bool route(PandoraLocalAiStatus? status) => PandoraLocalAiRouter.shouldUseLocal(
    message: 'Explain photosynthesis simply.',
    hasAttachment: false, hasProjectContext: false,
    hasSelectedCapability: false, hasCharacterContext: false, status: status,
  );

  test('unknown and cold states immediately select cloud', () {
    expect(route(null), isFalse);
    for (final phase in ['WAITING', 'DOWNLOADING', 'INITIALIZING', 'HEALTH_TEST', 'RECOVERING']) {
      expect(route(PandoraLocalAiStatus(
        supported: true, configured: true, loaded: false, engineState: phase,
      )), isFalse);
    }
  });

  test('loaded bytes and a declared ready state cannot replace real token proof', () {
    expect(route(const PandoraLocalAiStatus(
      supported: true, configured: true, loaded: true,
      diagnostics: {'localReady': true, 'healthTokenEvents': 0},
    )), isFalse);
    expect(route(const PandoraLocalAiStatus(
      supported: true, configured: true, loaded: true,
      diagnostics: {'localReady': true, 'healthTokenEvents': 2},
    )), isTrue);
  });

  test('worker disconnect immediately invalidates earlier health proof', () {
    expect(route(const PandoraLocalAiStatus(
      supported: true, configured: true, loaded: false,
      diagnostics: {'localReady': false, 'healthTokenEvents': 2},
    )), isFalse);
  });
}
