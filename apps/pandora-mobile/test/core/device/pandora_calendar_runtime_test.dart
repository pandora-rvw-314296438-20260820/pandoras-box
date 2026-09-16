import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/device/pandora_calendar_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pandora/calendar_runtime');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('permission state requires the bounded schema', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getPermissionState');
      return <String, Object?>{
        'schemaVersion': '1.0.0',
        'readDeclared': true,
        'readGranted': true,
        'writeDeclared': true,
        'writeGranted': false,
        'notificationDeclared': true,
        'notificationGranted': true,
        'exactAlarmAccess': false,
      };
    });
    final state = await PandoraCalendarRuntime().getPermissionState();
    expect(state['writeGranted'], isFalse);
  });

  test(
    'calendar query rejects invalid ranges before native dispatch',
    () async {
      final runtime = PandoraCalendarRuntime();
      expect(
        () => runtime.queryEvents(startEpochMs: 20, endEpochMs: 10),
        throwsArgumentError,
      );
    },
  );

  test(
    'create event sends stable operation and explicit calendar identity',
    () async {
      MethodCall? observed;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        observed = call;
        return <String, Object?>{
          'operationId': 'calendar.op-001',
          'action': 'create',
          'state': 'created',
          'terminal': true,
          'eventId': 99,
          'duplicatePrevented': false,
        };
      });
      final result = await PandoraCalendarRuntime().createEvent(
        operationId: 'calendar.op-001',
        calendarId: 7,
        title: 'Lunch',
        startEpochMs: 1000,
        endEpochMs: 2000,
        timeZoneId: 'Asia/Manila',
      );
      expect(observed?.method, 'createEvent');
      final args = observed?.arguments as Map<Object?, Object?>;
      expect(args['calendarId'], 7);
      expect(args['operationId'], 'calendar.op-001');
      expect(result['eventId'], 99);
    },
  );

  test(
    'exact reminder request preserves exactness at the channel boundary',
    () async {
      MethodCall? observed;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        observed = call;
        return <String, Object?>{
          'operationId': 'reminder.op-001',
          'state': 'special_access_required',
          'terminal': false,
          'requiredSpecialAccess': 'exact_alarm',
          'duplicatePrevented': false,
        };
      });
      final result = await PandoraCalendarRuntime().scheduleLocalReminder(
        operationId: 'reminder.op-001',
        title: 'Follow up',
        triggerEpochMs: 9999999999999,
        requireExact: true,
      );
      expect(observed?.method, 'scheduleLocalReminder');
      final args = observed?.arguments as Map<Object?, Object?>;
      expect(args['requireExact'], isTrue);
      expect(result['requiredSpecialAccess'], 'exact_alarm');
    },
  );

  test('status reads use the same operation id before retry', () async {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return <String, Object?>{
        'operationId': 'calendar.op-002',
        'action': 'update',
        'state': 'updated',
        'terminal': true,
        'eventId': 44,
      };
    });
    final result = await PandoraCalendarRuntime().getOperationStatus(
      'calendar.op-002',
    );
    expect(methods, <String>['getOperationStatus']);
    expect(result?['eventId'], 44);
  });
}
