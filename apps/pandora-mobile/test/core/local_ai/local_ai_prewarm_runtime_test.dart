import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/local_ai/pandora_local_ai.dart';
import 'package:pandora_mobile/core/local_ai/pandora_local_ai_runtime.dart';

const _channel = MethodChannel('pandora/local_ai');
const _delay = Duration(milliseconds: 40);

class _NativeModel {
  final calls = <String>[];
  bool loaded = false;
  final statusOverrides = <String, Object?>{};
  Completer<Map<String, Object?>>? statusResult;
  Completer<bool>? warmResult;
  Completer<void>? unloadResult;

  Map<String, Object?> get status => <String, Object?>{
        'supported': true,
        'configured': true,
        'loaded': loaded,
        'modelName': 'qwen2.5-3b-instruct-q4_k_m.gguf',
        'modelBytes': 2100000000,
        'modelSha256':
            '626b4a6678b86442240e33df819e00132d3ba7dddfe1cdc4fbb18e0a9615c62d',
        'recommendedModelSha256':
            '626b4a6678b86442240e33df819e00132d3ba7dddfe1cdc4fbb18e0a9615c62d',
        'safeModelMaxBytes': 2300 * 1024 * 1024,
        'availableRamBytes': 4 * 1024 * 1024 * 1024,
        'engineState': loaded ? 'ready' : 'initialized',
        ...statusOverrides,
      };

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'status':
        return statusResult?.future ?? status;
      case 'warm':
        final result = warmResult == null ? true : await warmResult!.future;
        loaded = result;
        return result;
      case 'cancel':
        return null;
      case 'unload':
        await unloadResult?.future;
        loaded = false;
        return null;
      default:
        throw StateError(
            'Unexpected native work during prewarm: ${call.method}');
    }
  }

  void release() {
    if (statusResult != null && !statusResult!.isCompleted) {
      statusResult!.complete(status);
    }
    if (warmResult != null && !warmResult!.isCompleted) {
      warmResult!.complete(false);
    }
    if (unloadResult != null && !unloadResult!.isCompleted) {
      unloadResult!.complete();
    }
  }
}

void _runtimeTest(
  String name,
  Future<void> Function(WidgetTester, PandoraLocalAiRuntime, _NativeModel) body,
) {
  testWidgets(name, (tester) async {
    final native = _NativeModel();
    final runtime = PandoraLocalAiRuntime.instance;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, native.handle);
    await runtime.stop();
    PandoraLocalAiPreference.setCachedForTesting(true);
    runtime.start();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    native.calls.clear();
    try {
      await body(tester, runtime, native);
    } finally {
      native.release();
      await tester.pump();
      await runtime.stop();
      await tester.pump(const Duration(seconds: 1));
      PandoraLocalAiPreference.resetForTesting();
      messenger.setMockMethodCallHandler(_channel, null);
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  _runtimeTest('prewarm coalesces callers without resetting or generating',
      (tester, runtime, native) async {
    final first = runtime.prewarm(stillEligible: () => true, delay: _delay);
    final second = runtime.prewarm(stillEligible: () => true, delay: _delay);
    await tester.pump(const Duration(milliseconds: 39));
    expect(native.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(native.calls, ['status', 'warm']);
    expect(native.loaded, isTrue);
  });

  _runtimeTest('revoked eligibility prevents delayed native work',
      (tester, runtime, native) async {
    var eligible = true;
    final warm = runtime.prewarm(stillEligible: () => eligible, delay: _delay);
    eligible = false;
    await tester.pump(_delay);
    expect(await warm, isFalse);
    expect(native.calls, isEmpty);
  });

  _runtimeTest('disabled Phone AI prevents delayed native work',
      (tester, runtime, native) async {
    final warm = runtime.prewarm(stillEligible: () => true, delay: _delay);
    PandoraLocalAiPreference.setCachedForTesting(false);
    await tester.pump(_delay);
    expect(await warm, isFalse);
    expect(native.calls, isEmpty);
  });

  _runtimeTest('eligibility is checked again after an asynchronous status read',
      (tester, runtime, native) async {
    var eligible = true;
    native.statusResult = Completer<Map<String, Object?>>();
    final warm = runtime.prewarm(stillEligible: () => eligible, delay: _delay);
    await tester.pump(_delay);
    expect(native.calls, ['status']);
    eligible = false;
    native.statusResult!.complete(native.status);
    await tester.pump();
    expect(await warm, isFalse);
    expect(native.calls, ['status']);
  });

  _runtimeTest('current insufficient RAM prevents a deferred cold warm',
      (tester, runtime, native) async {
    final warm = runtime.prewarm(stillEligible: () => true, delay: _delay);
    native.statusOverrides['availableRamBytes'] = 2 * 1024 * 1024 * 1024;
    await tester.pump(_delay);
    expect(await warm, isFalse);
    expect(native.calls, ['status']);
  });

  _runtimeTest(
      'backgrounding invalidates a scheduled prewarm before native work',
      (tester, runtime, native) async {
    final epoch = runtime.residencyEpoch;
    final warm = runtime.prewarm(stillEligible: () => true, delay: _delay);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(runtime.residencyEpoch, greaterThan(epoch));
    await tester.pump(_delay);
    expect(await warm, isFalse);
    expect(native.calls, ['cancel', 'unload']);
  });

  _runtimeTest('late warm completion cannot restore foreground residency',
      (tester, runtime, native) async {
    native.warmResult = Completer<bool>();
    final epoch = runtime.residencyEpoch;
    final warm = runtime.prewarm(stillEligible: () => true, delay: _delay);
    await tester.pump(_delay);
    expect(native.calls, ['status', 'warm']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(runtime.residencyEpoch, greaterThan(epoch));
    await tester.pump();
    native.warmResult!.complete(true);
    await tester.pump();
    expect(await warm, isFalse);
    expect(native.calls, ['status', 'warm', 'cancel', 'unload', 'unload']);
    expect(native.loaded, isFalse);
  });

  _runtimeTest('unload invalidates the native session before cleanup completes',
      (tester, runtime, native) async {
    native.loaded = true;
    native.unloadResult = Completer<void>();
    final epoch = runtime.residencyEpoch;
    final unloading = runtime.unload();
    expect(runtime.residencyEpoch, greaterThan(epoch));
    await tester.pump();
    expect(native.calls, ['cancel', 'unload']);
    expect(native.loaded, isTrue);
    native.unloadResult!.complete();
    await tester.pump();
    await unloading;
    expect(native.loaded, isFalse);
  });

  _runtimeTest('a resident model is checked without duplicate warm work',
      (tester, runtime, native) async {
    native.loaded = true;
    final warm = runtime.prewarm(stillEligible: () => true, delay: _delay);
    await tester.pump(_delay);
    expect(await warm, isTrue);
    expect(native.calls, ['status']);
  });

  _runtimeTest(
      'native continuation requires the live scope, turn and loaded model',
      (tester, runtime, native) async {
    runtime.recordConversation(
        conversationKey: 'scope-a:epoch-1:conversation-a',
        completedTurnId: 'turn-a',
        residencyEpoch: runtime.residencyEpoch);
    bool canContinue({String? key, String? turn, bool loaded = true}) =>
        runtime.canContinueConversation(
            conversationKey: key ?? 'scope-a:epoch-1:conversation-a',
            previousTurnId: turn ?? 'turn-a',
            loaded: loaded);
    expect(canContinue(), isTrue);
    expect(canContinue(loaded: false), isFalse);
    expect(canContinue(key: 'scope-a:epoch-1:conversation-b'), isFalse);
    expect(canContinue(key: 'scope-b:epoch-1:conversation-a'), isFalse);
    expect(canContinue(turn: 'turn-b'), isFalse);
    runtime.invalidateConversation();
    expect(canContinue(), isFalse);
    expect(native.calls, isEmpty);
  });

  _runtimeTest('a late completion cannot restore a conversation after unload',
      (tester, runtime, native) async {
    final oldEpoch = runtime.residencyEpoch;
    runtime.recordConversation(
        conversationKey: 'scope-a:conversation-a',
        completedTurnId: 'turn-a',
        residencyEpoch: oldEpoch);
    await runtime.unload();
    runtime.recordConversation(
        conversationKey: 'scope-a:conversation-a',
        completedTurnId: 'turn-late',
        residencyEpoch: oldEpoch);
    expect(
        runtime.canContinueConversation(
            conversationKey: 'scope-a:conversation-a',
            previousTurnId: 'turn-late',
            loaded: true),
        isFalse);
    runtime.recordConversation(
        conversationKey: 'scope-a:conversation-a',
        completedTurnId: 'turn-current',
        residencyEpoch: runtime.residencyEpoch);
    expect(
        runtime.canContinueConversation(
            conversationKey: 'scope-a:conversation-a',
            previousTurnId: 'turn-current',
            loaded: true),
        isTrue);
    expect(native.calls, ['cancel', 'unload']);
  });
}
