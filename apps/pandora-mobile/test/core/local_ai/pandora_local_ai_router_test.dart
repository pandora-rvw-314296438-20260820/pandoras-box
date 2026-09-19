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
        ),
        isFalse,
      );
    });

    test('routes contextual turns away from local AI', () {
      expect(
        PandoraLocalAiRouter.shouldUseLocal(
          message: 'Summarize this.',
          hasAttachment: true,
          hasProjectContext: false,
          hasSelectedCapability: false,
          hasCharacterContext: false,
        ),
        isFalse,
      );
    });
  });
}
