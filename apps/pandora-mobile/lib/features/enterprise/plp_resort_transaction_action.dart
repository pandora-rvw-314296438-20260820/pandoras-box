import 'package:supabase_flutter/supabase_flutter.dart';

class PlpResortTransactionFailure implements Exception {
  const PlpResortTransactionFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

class PlpResortTransactionResult {
  const PlpResortTransactionResult({
    required this.requestId,
    required this.action,
    required this.entityKind,
    required this.entityId,
    required this.verified,
    required this.providerReadbackVerified,
    required this.idempotentReplay,
    required this.readback,
  });

  final String requestId;
  final String action;
  final String entityKind;
  final String entityId;
  final bool verified;
  final bool providerReadbackVerified;
  final bool idempotentReplay;
  final Map<String, Object?> readback;

  factory PlpResortTransactionResult.fromMap(Map<String, Object?> map) {
    final readback = _map(map['readback']);
    return PlpResortTransactionResult(
      requestId: _text(map['requestId']),
      action: _text(map['action']),
      entityKind: _text(map['entityKind']),
      entityId: _text(map['entityId']),
      verified: map['verified'] == true,
      providerReadbackVerified: map['providerReadbackVerified'] == true,
      idempotentReplay: map['idempotentReplay'] == true,
      readback: readback,
    );
  }
}

class PlpResortTransactionAction {
  const PlpResortTransactionAction();

  Future<PlpResortTransactionResult> execute({
    required String requestId,
    required String action,
    required Map<String, Object?> payload,
  }) async {
    final normalizedRequestId = requestId.trim();
    final normalizedAction = action.trim().toLowerCase();
    if (normalizedRequestId.length < 8) {
      throw const PlpResortTransactionFailure(
        'The operation request ID is invalid.',
      );
    }
    if (normalizedAction.isEmpty) {
      throw const PlpResortTransactionFailure(
        'The resort operation is missing.',
      );
    }

    try {
      final raw = await Supabase.instance.client.rpc(
        'plp_resort_transaction_v1',
        params: <String, Object?>{
          'p_request_id': normalizedRequestId,
          'p_action': normalizedAction,
          'p_payload': payload,
        },
      );
      final result = PlpResortTransactionResult.fromMap(_map(raw));
      if (result.requestId != normalizedRequestId ||
          result.action != normalizedAction ||
          !result.verified ||
          !result.providerReadbackVerified) {
        throw const PlpResortTransactionFailure(
          'The resort operation could not be provider-verified.',
        );
      }
      return result;
    } on PlpResortTransactionFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw PlpResortTransactionFailure(_friendlyMessage(error.message));
    } catch (_) {
      throw const PlpResortTransactionFailure(
        'The resort operation could not be completed safely.',
      );
    }
  }
}

String _friendlyMessage(String message) {
  final value = message.toLowerCase();
  if (value.contains('room is not available')) {
    return 'That room is not available for the selected dates.';
  }
  if (value.contains('capacity')) {
    return 'The selected room cannot accommodate that many guests.';
  }
  if (value.contains('operator access required')) {
    return 'Your PLP access is read-only for this operation.';
  }
  if (value.contains('owner or admin')) {
    return 'Only a PLP owner or administrator can make this change.';
  }
  if (value.contains('checked in before check-out')) {
    return 'Check the guest in before checking them out.';
  }
  if (value.contains('checked-out booking cannot be cancelled')) {
    return 'A completed stay cannot be cancelled.';
  }
  if (value.contains('not due for check-in')) {
    return 'This stay is not due for check-in yet.';
  }
  if (value.contains('payment amount exceeds')) {
    return 'The payment is larger than the outstanding balance.';
  }
  if (value.contains('request_id already used')) {
    return 'This operation was already used for a different change.';
  }
  if (value.contains('booking not found')) {
    return 'The booking could not be found.';
  }
  if (value.contains('guest not found')) {
    return 'The guest could not be found.';
  }
  return message.trim().isEmpty
      ? 'The resort operation could not be completed.'
      : message.trim();
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry(key.toString(), item),
    );
  }
  return const <String, Object?>{};
}

String _text(Object? value) => value?.toString().trim() ?? '';
