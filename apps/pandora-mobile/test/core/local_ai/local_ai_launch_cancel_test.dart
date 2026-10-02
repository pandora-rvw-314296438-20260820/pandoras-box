import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/local_ai/pandora_local_ai.dart';
import 'package:pandora_mobile/core/local_ai/pandora_local_ai_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pandora/local_ai');
  final calls = <String>[];

  tearDown(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('start() with Phone AI off never calls native cancel', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });

    PandoraLocalAiRuntime.instance.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(calls, isNot(contains('cancel')));
    expect(calls, isNot(contains('unload')));
  });

  test('cancel() and unload() swallow PlatformException', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'LOCAL_AI_NATIVE', message: 'boom');
    });

    await PandoraLocalAi.instance.cancel();
    await PandoraLocalAi.instance.unload();
  });
}
