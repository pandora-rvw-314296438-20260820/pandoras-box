import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Qwen residency is application-owned, not chat-screen-owned', () {
    final screen = File(
      'lib/features/simple/ask_pandora_screen.dart',
    ).readAsStringSync();
    final runtime = File(
      'lib/core/local_ai/pandora_local_ai_runtime.dart',
    ).readAsStringSync();
    final app = File('lib/app/pandora_app.dart').readAsStringSync();
    final plpApp = File('lib/app/plp_enterprise_app.dart').readAsStringSync();

    final disposeStart = screen.indexOf('  void dispose() {');
    final disposeEnd = screen.indexOf(
      '  @override\n  void didChangeMetrics()',
      disposeStart,
    );
    expect(disposeStart, greaterThanOrEqualTo(0));
    expect(disposeEnd, greaterThan(disposeStart));
    final disposeBlock = screen.substring(disposeStart, disposeEnd);

    expect(
      disposeBlock,
      isNot(contains('PandoraLocalAi.instance.cancel()')),
    );
    expect(
      disposeBlock,
      isNot(contains('PandoraLocalAi.instance.unload()')),
    );
    expect(
      screen,
      isNot(contains('void didChangeAppLifecycleState(AppLifecycleState state)')),
    );
    expect(
      screen,
      contains('PandoraLocalAiRuntime.instance.cancelIdleUnload()'),
    );
    expect(
      screen,
      contains('PandoraLocalAiRuntime.instance.keepResident()'),
    );

    final cloudRequest = screen.indexOf("reason: 'model_requested_cloud'");
    final cloudReturn = screen.indexOf('return false;', cloudRequest);
    expect(cloudRequest, greaterThanOrEqualTo(0));
    expect(cloudReturn, greaterThan(cloudRequest));
    expect(
      screen.substring(cloudRequest, cloudReturn),
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

    expect(app, contains('PandoraLocalAiRuntime.instance.start()'));
    expect(plpApp, contains('PandoraLocalAiRuntime.instance.start()'));
    expect(app, contains('PandoraLocalAiRuntime.instance.stop()'));
    expect(plpApp, contains('PandoraLocalAiRuntime.instance.stop()'));
  });
}
