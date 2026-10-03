import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Qwen residency is application-owned, not chat-screen-owned', () {
    final screen = File(
      'lib/features/simple/ask_pandora_screen.dart',
    ).readAsStringSync();
    final adapters = File(
      'lib/features/simple/chat/pandora_chat_action_adapters.dart',
    ).readAsStringSync();
    final runtime = File(
      'lib/core/local_ai/pandora_local_ai_runtime.dart',
    ).readAsStringSync();
    final app = File('lib/app/pandora_app.dart').readAsStringSync();
    final plpApp = File('lib/app/plp_enterprise_app.dart').readAsStringSync();

    final dispose =
        RegExp(r'  void dispose\(\) \{[\s\S]*?\n  \}').firstMatch(screen);
    final lifecycle = RegExp(
      r'  void didChangeAppLifecycleState\(AppLifecycleState state\) \{[\s\S]*?\n  \}',
    ).firstMatch(screen);
    expect(dispose, isNotNull);
    expect(lifecycle, isNotNull);
    for (final block in [dispose!.group(0)!, lifecycle!.group(0)!]) {
      expect(block, isNot(contains('PandoraLocalAi.instance.cancel()')));
      expect(block, isNot(contains('PandoraLocalAi.instance.unload()')));
      expect(block, isNot(contains('PandoraLocalAiRuntime.instance.stop()')));
    }
    // The screen may persist/reconcile its conversation on lifecycle changes;
    // model residency and application suspension still belong to the runtime.
    expect(lifecycle.group(0), contains('AppLifecycleState.resumed'));
    expect(lifecycle.group(0), contains('_reconcilePending()'));
    expect(lifecycle.group(0), contains('_store!.save(_chat.state)'));
    expect(
      adapters,
      contains('PandoraLocalAiRuntime.instance.cancelIdleUnload()'),
    );
    expect(
      adapters,
      contains('PandoraLocalAiRuntime.instance.keepResident()'),
    );

    final cloudRequest = adapters.indexOf(
      "normalized == '[[PANDORA_CLOUD_REQUIRED]]'",
    );
    final cloudReturn = adapters.indexOf('return false;', cloudRequest);
    expect(cloudRequest, greaterThanOrEqualTo(0));
    expect(cloudReturn, greaterThan(cloudRequest));
    final cloudFallback = adapters.substring(cloudRequest, cloudReturn);
    expect(cloudFallback, contains('_chat.prepareCloudFallback(token)'));
    expect(
      cloudFallback,
      isNot(contains('.unload()')),
    );

    expect(
      runtime,
      contains('class PandoraLocalAiRuntime with WidgetsBindingObserver'),
    );
    expect(
      runtime,
      contains('defaultIdleUnloadDelay = Duration(minutes: 2)'),
    );
    expect(runtime, contains('WidgetsBinding.instance.addObserver(this)'));
    expect(runtime, contains('AppLifecycleState.paused'));
    expect(runtime, contains('AppLifecycleState.hidden'));
    expect(runtime, contains('AppLifecycleState.detached'));
    expect(runtime, contains('PandoraLocalAi.instance.unload()'));
    expect(runtime, contains('PandoraLocalAiPreference.load()'));
    expect(runtime, contains('PandoraLocalAiPreference.cachedEnabled'));
    expect(runtime, contains('unawaited(unload())'));

    final localAi =
        File('lib/core/local_ai/pandora_local_ai.dart').readAsStringSync();
    expect(localAi, contains("storageKey = 'pandora.use_phone_ai.v1'"));
    expect(localAi, contains("return _record(false, 'phone_ai_disabled')"));
    expect(localAi,
        contains('if (!await PandoraLocalAiPreference.load()) return false;'));
    expect(localAi,
        contains("throw const PandoraLocalAiException('Phone AI is off.')"));

    expect(app, contains('PandoraLocalAiRuntime.instance.start()'));
    expect(plpApp, contains('PandoraLocalAiRuntime.instance.start()'));
    expect(app, contains('PandoraLocalAiRuntime.instance.stop()'));
    expect(plpApp, contains('PandoraLocalAiRuntime.instance.stop()'));
  });
}
