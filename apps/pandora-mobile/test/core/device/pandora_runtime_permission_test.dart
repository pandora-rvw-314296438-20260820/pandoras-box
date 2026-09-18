import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/device/pandora_device_agent.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pandora/device_agent');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
      'permission state requires fresh Android readback and app-details revocation',
      () {
    final state = PandoraPermissionState.fromMap(<String, Object?>{
      'permission': 'android.permission.CALL_PHONE',
      'declared': true,
      'granted': false,
      'stateFresh': true,
      'requestable': true,
      'userFixed': false,
      'revocationControlSurface': 'app_details',
    });
    expect(state.stateFresh, isTrue);
    expect(state.requestable, isTrue);
    expect(state.granted, isFalse);
    expect(state.revocationControlSurface, 'app_details');
  });

  test('permission state rejects stale or contradictory authority', () {
    final base = <String, Object?>{
      'permission': 'android.permission.SEND_SMS',
      'declared': true,
      'granted': false,
      'stateFresh': true,
      'requestable': true,
      'userFixed': false,
      'revocationControlSurface': 'app_details',
    };
    expect(
      () => PandoraPermissionState.fromMap(<String, Object?>{
        ...base,
        'stateFresh': false,
      }),
      throwsFormatException,
    );
    expect(
      () => PandoraPermissionState.fromMap(<String, Object?>{
        ...base,
        'granted': true,
      }),
      throwsFormatException,
    );
  });

  test('runtime result forbids automatic retry and requires re-read', () {
    final result = PandoraRuntimePermissionResult.fromMap(<String, Object?>{
      'permission': 'android.permission.CALL_PHONE',
      'status': 'denied',
      'granted': false,
      'userActionSurface': 'runtime_permission_dialog',
      'automaticRetryAllowed': false,
      'recheckRequired': true,
    });
    expect(result.granted, isFalse);
    expect(result.automaticRetryAllowed, isFalse);
    expect(result.recheckRequired, isTrue);

    expect(
      () => PandoraRuntimePermissionResult.fromMap(<String, Object?>{
        'permission': 'android.permission.CALL_PHONE',
        'status': 'denied',
        'granted': false,
        'userActionSurface': 'runtime_permission_dialog',
        'automaticRetryAllowed': true,
        'recheckRequired': true,
      }),
      throwsFormatException,
    );
  });

  test(
    'client binds permission prompt to explicit current-user action',
    () async {
      MethodCall? observed;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        observed = call;
        return <String, Object?>{
          'permission': 'android.permission.SEND_SMS',
          'status': 'granted',
          'granted': true,
          'userActionSurface': 'runtime_permission_dialog',
          'automaticRetryAllowed': false,
          'recheckRequired': true,
        };
      });

      final agent = MethodChannelPandoraDeviceAgent(channel: channel);
      final result = await agent.requestRuntimePermission(
        'android.permission.SEND_SMS',
        userInitiated: true,
      );

      expect(observed?.method, 'requestRuntimePermission');
      final arguments = observed?.arguments as Map<Object?, Object?>;
      expect(arguments['permission'], 'android.permission.SEND_SMS');
      expect(arguments['userInitiated'], isTrue);
      expect(result.status, 'granted');
      expect(result.granted, isTrue);
      expect(result.recheckRequired, isTrue);
    },
  );
}
