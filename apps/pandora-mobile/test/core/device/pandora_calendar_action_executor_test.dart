import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/device/pandora_calendar_action_executor.dart';
import 'package:pandora_mobile/core/device/pandora_calendar_command.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pandora/calendar_runtime');
  final at = DateTime.utc(2026, 10, 4, 15);
  final permission = <String, Object?>{
    'schemaVersion': '1.0.0',
    'readGranted': true,
    'writeGranted': true,
    'notificationGranted': true,
    'deviceTimeZoneId': 'UTC',
  };
  final event = <String, Object?>{
    'id': 12,
    'title': 'Appointment',
    'startEpochMs': at.millisecondsSinceEpoch,
    'endEpochMs': at.add(const Duration(hours: 1)).millisecondsSinceEpoch,
    'timeZoneId': 'UTC',
    'providerKind': 'connected',
  };
  final cases = <(PandoraCalendarCommandKind, String, String, String)>[
    (
      PandoraCalendarCommandKind.create,
      'listCalendars',
      'createEvent',
      'created'
    ),
    (
      PandoraCalendarCommandKind.update,
      'queryEvents',
      'updateEvent',
      'updated'
    ),
    (
      PandoraCalendarCommandKind.delete,
      'queryEvents',
      'deleteEvent',
      'deleted'
    ),
    (
      PandoraCalendarCommandKind.reminder,
      'getPermissionState',
      'scheduleLocalReminder',
      'scheduled'
    ),
  ];

  PandoraCalendarCommand command(PandoraCalendarCommandKind kind) =>
      PandoraCalendarCommand(
        kind: kind,
        title: 'Appointment',
        start: at.add(const Duration(hours: 2)),
        end: at.add(const Duration(hours: 3)),
        rangeStart: DateTime.utc(2026, 10, 4),
        rangeEnd: DateTime.utc(2026, 10, 5),
      );

  Object? preflight(String method) => switch (method) {
        'getPermissionState' => permission,
        'listCalendars' => <Object?>[
            <String, Object?>{'id': 7, 'writable': true, 'visible': true}
          ],
        'queryEvents' => <Object?>[event],
        _ => throw StateError('Unexpected native call: $method'),
      };

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final (kind, preparation, mutation, state) in cases) {
    test('cancellation during $preparation prevents $mutation', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final calls = <String>[];
      final stages = <String>[];
      var cancelled = false;
      var effectChecks = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == preparation) {
          entered.complete();
          await release.future;
        }
        return preflight(call.method);
      });
      final execution = PandoraCalendarActionExecutor(
        beforeEffect: () {
          effectChecks += 1;
          return !cancelled;
        },
        reporter: (fact) async => stages.add(fact.stage),
      ).execute(command(kind), operationId: 'calendar.cancel.${kind.name}');

      await entered.future;
      expect(effectChecks, 0,
          reason: 'preparation has not crossed the effect boundary');
      cancelled = true;
      release.complete();
      final result = await execution;
      expect(effectChecks, 1);
      expect(calls, isNot(contains(mutation)));
      expect(result.terminalStage, 'cancelled');
      expect(result.needsUserAction, isFalse);
      expect(stages.last, 'cancelled');
      expect(stages, isNot(contains('result')));
    });

    test('$mutation preserves native verification with no cancellation hook',
        () async {
      final calls = <String>[];
      final operationId = 'calendar.allowed.${kind.name}';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == mutation ||
            call.method == 'getLocalReminderStatus') {
          expect((call.arguments as Map<Object?, Object?>)['operationId'],
              operationId);
          return <String, Object?>{
            'state': state,
            'event': event,
            'updatedAtEpochMs': at.millisecondsSinceEpoch,
          };
        }
        return preflight(call.method);
      });
      final result = await PandoraCalendarActionExecutor()
          .execute(command(kind), operationId: operationId);
      expect(calls.where((method) => method == mutation), hasLength(1));
      expect(result.terminalStage, 'result');
      if (kind == PandoraCalendarCommandKind.reminder) {
        expect(calls.last, 'getLocalReminderStatus');
      }
    });
  }

  test(
      'cancellation after native dispatch preserves the actual verified result',
      () async {
    final entered = Completer<void>();
    final receipt = Completer<Object?>();
    var cancelled = false;
    var effectStarted = false;
    var effectChecks = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'createEvent') {
        expect(effectStarted, isTrue);
        entered.complete();
        return receipt.future;
      }
      expect(effectStarted, isFalse);
      return preflight(call.method);
    });
    final execution = PandoraCalendarActionExecutor(
      beforeEffect: () {
        effectChecks += 1;
        if (cancelled) return false;
        effectStarted = true;
        return true;
      },
    ).execute(command(PandoraCalendarCommandKind.create),
        operationId: 'calendar.inflight');
    await entered.future;
    cancelled = true;
    receipt.complete(<String, Object?>{
      'state': 'created',
      'event': event,
      'updatedAtEpochMs': at.millisecondsSinceEpoch,
    });
    final result = await execution;
    expect(effectChecks, 1);
    expect(result.terminalStage, 'result');
    expect(result.reply, contains('verified by Android'));
  });

  test('cancelled result survives offline Activity reporting', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return preflight(call.method);
    });
    final result = await PandoraCalendarActionExecutor(
      beforeEffect: () => false,
      reporter: (_) async => throw StateError('Activity offline'),
    ).execute(command(PandoraCalendarCommandKind.create),
        operationId: 'calendar.offline');
    expect(result.terminalStage, 'cancelled');
    expect(calls, isNot(contains('createEvent')));
  });
}
