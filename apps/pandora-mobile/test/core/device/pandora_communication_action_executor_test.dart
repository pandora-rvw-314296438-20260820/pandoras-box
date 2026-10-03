import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/device/pandora_communication_action_executor.dart';
import 'package:pandora_mobile/core/device/pandora_communication_command.dart';
import 'package:pandora_mobile/core/device/pandora_communications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pandora/device_agent');
  const operationId = 'communication.test-operation';
  const phone = '+15555550123';
  final resolved = <String, Object?>{
    'source': 'android_contacts',
    'status': 'resolved',
    'requiredPermission': 'android.permission.READ_CONTACTS',
    'candidates': <Object?>[],
    'phoneNumber': phone,
    'normalizedPhoneNumber': phone,
    'displayName': 'Test Contact',
  };

  PandoraDeviceCommunicationCommand command({
    PandoraCommunicationKind kind = PandoraCommunicationKind.sms,
    String recipient = phone,
  }) =>
      PandoraDeviceCommunicationCommand(
        kind: kind,
        recipient: recipient,
        message: kind == PandoraCommunicationKind.sms ? 'Test message' : null,
      );

  Map<String, Object?> receipt(String state, {bool accepted = true}) =>
      <String, Object?>{
        'operationId': operationId,
        'kind': 'sms',
        'state': state,
        'terminal': <String>{'delivered', 'failed', 'fallback_required'}
            .contains(state),
        'acceptedByPlatform': accepted,
        'duplicatePrevented': false,
        'updatedAtEpochMs': 1791072000000,
      };

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final kind in PandoraCommunicationKind.values) {
    test('cancellation during contact lookup prevents ${kind.name} dispatch',
        () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final calls = <String>[];
      final stages = <String>[];
      var cancelled = false;
      var effectChecks = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'resolvePhoneContact') {
          entered.complete();
          await release.future;
          return resolved;
        }
        throw StateError('Unexpected dispatch: ${call.method}');
      });
      final execution = PandoraCommunicationActionExecutor(
        beforeEffect: () {
          effectChecks += 1;
          return !cancelled;
        },
        reporter: (fact) async => stages.add(fact.stage),
      ).execute(command(kind: kind, recipient: 'Test Contact'),
          operationId: operationId);
      await entered.future;
      expect(effectChecks, 0);
      cancelled = true;
      release.complete();
      final result = await execution;
      expect(effectChecks, 1);
      expect(calls, <String>['resolvePhoneContact']);
      expect(result.terminalStage, 'cancelled');
      expect(result.outcomeUnknown, isFalse);
      expect(stages.last, 'cancelled');
    });
  }

  for (final delay in <String>['contact cache', 'Activity']) {
    test('cancellation during $delay preparation prevents native dispatch',
        () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final calls = <String>[];
      var cancelled = false;
      var effectChecks = 0;
      Future<void> pause() async {
        entered.complete();
        await release.future;
      }

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'resolvePhoneContact') return resolved;
        throw StateError('Unexpected dispatch: ${call.method}');
      });
      final execution = PandoraCommunicationActionExecutor(
        beforeEffect: () {
          effectChecks += 1;
          return !cancelled;
        },
        resolvedContactObserver:
            delay == 'contact cache' ? (_, __) => pause() : null,
        reporter: delay == 'Activity'
            ? (fact) async {
                if (fact.stage == 'acting') await pause();
              }
            : null,
      ).execute(command(recipient: 'Test Contact'), operationId: operationId);
      await entered.future;
      expect(effectChecks, 0);
      cancelled = true;
      release.complete();
      final result = await execution;
      expect(effectChecks, 1);
      expect(calls, <String>['resolvePhoneContact']);
      expect(result.terminalStage, 'cancelled');
    });
  }

  test(
      'cancel after native fallback decision prevents a late system UI handoff',
      () async {
    final calls = <String>[];
    var cancelled = false;
    var effectChecks = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'executeDirectCommunication') {
        cancelled = true;
        return receipt('fallback_required', accepted: false);
      }
      throw StateError('Unexpected handoff: ${call.method}');
    });
    final result = await PandoraCommunicationActionExecutor(
      beforeEffect: () {
        effectChecks += 1;
        return !cancelled;
      },
    ).execute(command(), operationId: operationId);
    expect(effectChecks, 2);
    expect(calls, <String>['executeDirectCommunication']);
    expect(result.terminalStage, 'cancelled');
    expect(result.outcomeUnknown, isFalse);
  });

  test('cancellation after native dispatch still returns the verified result',
      () async {
    final entered = Completer<void>();
    final nativeReceipt = Completer<Object?>();
    final calls = <String>[];
    var cancelled = false;
    var effectChecks = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      expect(effectChecks, 1);
      expect((call.arguments as Map<Object?, Object?>)['operationId'],
          operationId);
      entered.complete();
      return nativeReceipt.future;
    });
    final execution = PandoraCommunicationActionExecutor(
      beforeEffect: () {
        effectChecks += 1;
        return !cancelled;
      },
      reporter: (_) async => throw StateError('Activity offline'),
    ).execute(command(), operationId: operationId);
    await entered.future;
    cancelled = true;
    nativeReceipt.complete(receipt('delivered'));
    final result = await execution;
    expect(calls, <String>['executeDirectCommunication']);
    expect(effectChecks, 1);
    expect(result.terminalStage, 'result');
    expect(result.reply, contains('verified the SMS was delivered'));
  });

  test(
      'native failure with no conclusive readback remains unknown without redispatch',
      () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      expect((call.arguments as Map<Object?, Object?>)['operationId'],
          operationId);
      if (call.method == 'executeDirectCommunication') {
        throw PlatformException(code: 'NATIVE_RESPONSE_LOST');
      }
      if (call.method == 'getDirectCommunicationStatus') return null;
      throw StateError('Unexpected native call: ${call.method}');
    });
    final result = await PandoraCommunicationActionExecutor(
      reporter: (_) async => throw StateError('Activity offline'),
    ).execute(command(), operationId: operationId);
    expect(calls,
        <String>['executeDirectCommunication', 'getDirectCommunicationStatus']);
    expect(result.terminalStage, 'verifying');
    expect(result.outcomeUnknown, isTrue);
  });

  test('existing callers retain explicit-confirmation fallback with no hook',
      () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'executeDirectCommunication') {
        return receipt('fallback_required', accepted: false);
      }
      if (call.method == 'openCommunicationComposer') {
        return <String, Object?>{
          'kind': 'sms',
          'status': 'opened',
          'handoff': 'system_sms_composer',
          'userConfirmationRequired': true,
        };
      }
      throw StateError('Unexpected native call: ${call.method}');
    });
    final result = await PandoraCommunicationActionExecutor()
        .execute(command(), operationId: operationId);
    expect(calls,
        <String>['executeDirectCommunication', 'openCommunicationComposer']);
    expect(result.terminalStage, 'needs_choice');
    expect(result.needsUserAction, isTrue);
    expect(result.outcomeUnknown, isFalse);
  });

  test('known cancellation survives offline Activity reporting', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      throw StateError('Unexpected native call: ${call.method}');
    });
    final result = await PandoraCommunicationActionExecutor(
      beforeEffect: () => false,
      reporter: (_) async => throw StateError('Activity offline'),
    ).execute(command(), operationId: operationId);
    expect(calls, isEmpty);
    expect(result.terminalStage, 'cancelled');
    expect(result.outcomeUnknown, isFalse);
  });
}
