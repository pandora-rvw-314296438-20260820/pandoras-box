import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/device/pandora_connectivity_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pandora/connectivity');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('connectivity state accepts bounded non-identifying transport truth', () {
    final state = PandoraConnectivityState.fromMap(<String, Object?>{
      'schemaVersion': '1.0.0',
      'capturedAtElapsedRealtimeMs': 42,
      'connected': true,
      'internetCapable': true,
      'validated': true,
      'captivePortal': false,
      'metered': true,
      'transports': <String, Object?>{
        'wifi': false,
        'cellular': true,
        'bluetooth': false,
        'ethernet': false,
        'vpn': false,
        'usb': false,
      },
      'userControlOnly': true,
      'silentMutationAllowed': false,
      'normalOperationRequiresDesktop': false,
      'rootRequired': false,
    });
    expect(state.connected, isTrue);
    expect(state.transports['cellular'], isTrue);
    expect(state.transports['wifi'], isFalse);
  });

  test('connectivity state rejects network identifiers', () {
    expect(
      () => PandoraConnectivityState.fromMap(<String, Object?>{
        'schemaVersion': '1.0.0',
        'capturedAtElapsedRealtimeMs': 1,
        'connected': true,
        'internetCapable': true,
        'validated': true,
        'captivePortal': false,
        'metered': false,
        'transports': <String, Object?>{
          'wifi': true,
          'cellular': false,
          'bluetooth': false,
          'ethernet': false,
          'vpn': false,
          'usb': false,
        },
        'ssid': 'forbidden',
        'userControlOnly': true,
        'silentMutationAllowed': false,
        'normalOperationRequiresDesktop': false,
        'rootRequired': false,
      }),
      throwsFormatException,
    );
  });

  test('settings handoff remains explicitly user controlled', () async {
    MethodCall? observed;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      observed = call;
      return <String, Object?>{
        'schemaVersion': '1.0.0',
        'target': 'wifi',
        'opened': true,
        'userActionRequired': true,
        'silentMutation': false,
      };
    });
    final runtime = MethodChannelPandoraConnectivityRuntime();
    final result = await runtime.openSettings(
      PandoraConnectivitySettingsTarget.wifi,
    );
    expect(observed?.method, 'openConnectivitySettings');
    expect((observed?.arguments as Map<Object?, Object?>)['target'], 'wifi');
    expect(result.opened, isTrue);
    expect(result.target, PandoraConnectivitySettingsTarget.wifi);
  });

  test('settings result rejects silent mutation semantics', () {
    expect(
      () => PandoraConnectivitySettingsResult.fromMap(<String, Object?>{
        'schemaVersion': '1.0.0',
        'target': 'mobile',
        'opened': true,
        'userActionRequired': false,
        'silentMutation': true,
      }),
      throwsFormatException,
    );
  });
}
