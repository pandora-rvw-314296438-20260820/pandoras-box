import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

typedef PandoraCoreRecord = Map<String, dynamic>;

abstract interface class PandoraCoreGateway {
  Future<PandoraCoreRecord> snapshot(
    String section, {
    String? organizationId,
  });

  Future<PandoraCoreRecord> operate(
    String operation, {
    String? organizationId,
    required PandoraCoreRecord payload,
    required String idempotencyKey,
  });

  Future<PandoraCoreRecord> enterClient(
    String organizationId, {
    required String reason,
  });
}

abstract interface class PandoraCoreEntryGateway {
  Future<bool> validateEntry(String entryId, String organizationId);
  Future<void> leaveClient(String entryId);
}

/// All Core authority is evaluated by the signed-in server RPC. Presentation
/// fields, email addresses and workspace labels never grant operator access.
class SupabasePandoraCoreGateway
    implements PandoraCoreGateway, PandoraCoreEntryGateway {
  SupabasePandoraCoreGateway({SupabaseClient? client})
      : _providedClient = client;

  final SupabaseClient? _providedClient;
  SupabaseClient get _client => _providedClient ?? Supabase.instance.client;

  Future<PandoraCoreRecord> _invoke(
    String function,
    PandoraCoreRecord parameters,
  ) async {
    try {
      if (_client.auth.currentSession == null) {
        throw const PandoraCoreFailure(
          'SIGN_IN_REQUIRED',
          'Sign in again to continue.',
        );
      }
      final result =
          coreRecord(await _client.rpc(function, params: parameters));
      if (result.isEmpty) {
        throw const PandoraCoreFailure(
          'INVALID_RESPONSE',
          'Pandora could not verify this response. Refresh and try again.',
        );
      }
      return result;
    } on PandoraCoreFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw PandoraCoreFailure.fromServer(error.code, error.message);
    } on AuthException {
      throw const PandoraCoreFailure(
        'SIGN_IN_REQUIRED',
        'Your session needs attention. Sign in again.',
      );
    } catch (_) {
      throw const PandoraCoreFailure(
        'UNAVAILABLE',
        'Pandora could not connect. Check your connection and try again.',
      );
    }
  }

  @override
  Future<PandoraCoreRecord> snapshot(
    String section, {
    String? organizationId,
  }) =>
      _invoke('pandora_core_snapshot_v1', {
        'p_section': section,
        'p_organization_id': organizationId,
      });

  @override
  Future<PandoraCoreRecord> operate(
    String operation, {
    String? organizationId,
    required PandoraCoreRecord payload,
    required String idempotencyKey,
  }) =>
      _invoke('pandora_core_operate_v1', {
        'p_operation': operation,
        'p_organization_id': organizationId,
        'p_payload': payload,
        'p_idempotency_key': idempotencyKey,
      });

  @override
  Future<PandoraCoreRecord> enterClient(
    String organizationId, {
    required String reason,
  }) =>
      _invoke('pandora_core_enter_client_v1', {
        'p_organization_id': organizationId,
        'p_reason': reason,
      });

  @override
  Future<bool> validateEntry(String entryId, String organizationId) async {
    try {
      return await _client.rpc('pandora_core_validate_entry_v1', params: {
            'p_entry_id': entryId,
            'p_organization_id': organizationId,
          }) ==
          true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> leaveClient(String entryId) async {
    await _client.rpc('pandora_core_leave_client_v1', params: {
      'p_entry_id': entryId,
    });
  }
}

class PandoraCoreFailure implements Exception {
  const PandoraCoreFailure(this.code, this.message);
  final String code;
  final String message;

  bool get requiresStepUp => code == 'STEP_UP_REQUIRED';

  factory PandoraCoreFailure.fromServer(String? code, String message) {
    final normalized = '${code ?? ''} $message'.toUpperCase();
    if (normalized.contains('STEP_UP') ||
        normalized.contains('AAL2') ||
        normalized.contains('MFA_REQUIRED')) {
      return const PandoraCoreFailure(
        'STEP_UP_REQUIRED',
        'Verify your identity to continue.',
      );
    }
    const actionable = <String, String>{
      'CURRENCY_MISMATCH': 'Use the same currency as the plan or invoice.',
      'AMOUNT_EXCEEDS_BALANCE':
          'The amount exceeds the recorded balance. Review the invoice first.',
      'ISSUED_INVOICE_REQUIRED':
          'Issue the invoice before recording a payment.',
      'GO_LIVE_VERIFICATION_REQUIRED':
          'Complete the onboarding prerequisites and record verification before go-live.',
      'WORKSPACE_ADAPTER_REQUIRED':
          'This client workspace still needs a verified runtime before go-live.',
      'RESOLUTION_REQUIRED': 'Record the resolution before closing this case.',
      'PLAN_IN_USE_CREATE_NEW_VERSION':
          'This plan is already in use. Create a new plan version.',
    };
    for (final item in actionable.entries) {
      if (normalized.contains(item.key)) {
        return PandoraCoreFailure('INVALID_REQUEST', item.value);
      }
    }
    if (normalized.contains('ACCESS_DENIED') ||
        normalized.contains('OPERATOR') ||
        normalized.contains('MEMBERSHIP_REQUIRED') ||
        normalized.contains('42501') ||
        normalized.contains('PERMISSION_DENIED')) {
      return const PandoraCoreFailure(
        'ACCESS_DENIED',
        'Your account is not authorized for this action.',
      );
    }
    if (normalized.contains('SIGN_IN') || normalized.contains('SESSION')) {
      return const PandoraCoreFailure(
        'SIGN_IN_REQUIRED',
        'Your session needs attention. Sign in again.',
      );
    }
    if (normalized.contains('IDEMPOTENCY') ||
        normalized.contains('CONFLICT') ||
        normalized.contains('23505')) {
      return const PandoraCoreFailure(
        'CONFLICT',
        'This record changed or already exists. Refresh before trying again.',
      );
    }
    if (normalized.contains('INVALID') ||
        normalized.contains('REQUIRED') ||
        normalized.contains('23514') ||
        normalized.contains('22P02')) {
      return const PandoraCoreFailure(
        'INVALID_REQUEST',
        'Check the required fields and permitted values, then try again.',
      );
    }
    if (normalized.contains('NOT_FOUND')) {
      return const PandoraCoreFailure(
        'NOT_FOUND',
        'This record is no longer available. Refresh to continue.',
      );
    }
    return const PandoraCoreFailure(
      'UNAVAILABLE',
      'Pandora could not verify this action. Refresh before retrying.',
    );
  }

  @override
  String toString() => message;
}

PandoraCoreRecord coreRecord(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : <String, dynamic>{};

List<PandoraCoreRecord> coreRecords(Object? value) => value is List
    ? value.whereType<Map>().map(coreRecord).toList(growable: false)
    : const <PandoraCoreRecord>[];

String coreText(Object? value, [String fallback = '—']) {
  if (value == null || value is Map || value is List) return fallback;
  final result = value.toString().trim();
  return result.isEmpty ? fallback : result;
}

/// Decimal capture is exact: no floating point conversion or silent rounding.
int? parseCoreMoneyMicros(String input) {
  final value = input.trim();
  if (!RegExp(r'^\d+(?:\.\d{1,6})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  final whole = BigInt.tryParse(parts.first);
  final fraction = parts.length == 2 ? parts[1].padRight(6, '0') : '000000';
  if (whole == null) return null;
  final micros = whole * BigInt.from(1000000) + BigInt.parse(fraction);
  if (micros > BigInt.from(100000000000000)) return null;
  return micros.toInt();
}

String formatCoreMoneyMicros(Object? value) {
  final micros = int.tryParse(value?.toString() ?? '');
  if (micros == null) return '—';
  final sign = micros < 0 ? '-' : '';
  final amount = micros.abs();
  final fractional = (amount % 1000000).toString().padLeft(6, '0');
  var end = 6;
  while (end > 2 && fractional[end - 1] == '0') {
    end--;
  }
  return '$sign${amount ~/ 1000000}.${fractional.substring(0, end)}';
}

String newCoreIdempotencyKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final value =
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
      '${value.substring(12, 16)}-${value.substring(16, 20)}-'
      '${value.substring(20)}';
}
