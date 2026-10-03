import 'package:supabase_flutter/supabase_flutter.dart';

class PlpResortLifecycleFailure implements Exception {
  const PlpResortLifecycleFailure(this.message);
  final String message;
}

abstract interface class PlpResortLifecycleGateway {
  Future<Map<String, Object?>> reservationDetail(String bookingReference);

  Future<Map<String, Object?>> createReservation({
    required String requestId,
    required String guestName,
    required String guestEmail,
    String? guestPhone,
    required String accommodationId,
    required DateTime checkIn,
    required DateTime checkOut,
    required int guestCount,
    String? specialRequests,
  });

  Future<Map<String, Object?>> updateReservation({
    required String requestId,
    required String bookingReference,
    required Map<String, Object?> patch,
  });

  Future<Map<String, Object?>> transitionReservation({
    required String requestId,
    required String bookingReference,
    required String action,
  });

  Future<Map<String, Object?>> updateGuest({
    required String requestId,
    required String bookingReference,
    required Map<String, Object?> patch,
  });

  Future<Map<String, Object?>> recordPayment({
    required String requestId,
    required String bookingReference,
    required num amountPhp,
    required String method,
    String? reference,
  });

  Future<Map<String, Object?>> updateRoom({
    required String requestId,
    required String accommodationId,
    required Map<String, Object?> patch,
  });
}

class SupabasePlpResortLifecycleGateway
    implements PlpResortLifecycleGateway {
  const SupabasePlpResortLifecycleGateway();

  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<Map<String, Object?>> reservationDetail(
    String bookingReference,
  ) =>
      _rpc(
        'plp_reservation_detail_v1',
        <String, Object?>{'p_booking_reference': bookingReference},
      );

  @override
  Future<Map<String, Object?>> createReservation({
    required String requestId,
    required String guestName,
    required String guestEmail,
    String? guestPhone,
    required String accommodationId,
    required DateTime checkIn,
    required DateTime checkOut,
    required int guestCount,
    String? specialRequests,
  }) =>
      _rpc(
        'plp_reservation_create_v1',
        <String, Object?>{
          'p_request_id': requestId,
          'p_guest_name': guestName,
          'p_guest_email': guestEmail,
          'p_guest_phone': guestPhone,
          'p_accommodation_id': accommodationId,
          'p_check_in': _date(checkIn),
          'p_check_out': _date(checkOut),
          'p_guest_count': guestCount,
          'p_special_requests': specialRequests,
        },
      );

  @override
  Future<Map<String, Object?>> updateReservation({
    required String requestId,
    required String bookingReference,
    required Map<String, Object?> patch,
  }) =>
      _rpc(
        'plp_reservation_update_v1',
        <String, Object?>{
          'p_request_id': requestId,
          'p_booking_reference': bookingReference,
          'p_patch': patch,
        },
      );

  @override
  Future<Map<String, Object?>> transitionReservation({
    required String requestId,
    required String bookingReference,
    required String action,
  }) =>
      _rpc(
        'plp_reservation_transition_v1',
        <String, Object?>{
          'p_request_id': requestId,
          'p_booking_reference': bookingReference,
          'p_action': action,
        },
      );

  @override
  Future<Map<String, Object?>> updateGuest({
    required String requestId,
    required String bookingReference,
    required Map<String, Object?> patch,
  }) =>
      _rpc(
        'plp_guest_update_v1',
        <String, Object?>{
          'p_request_id': requestId,
          'p_booking_reference': bookingReference,
          'p_patch': patch,
        },
      );

  @override
  Future<Map<String, Object?>> recordPayment({
    required String requestId,
    required String bookingReference,
    required num amountPhp,
    required String method,
    String? reference,
  }) =>
      _rpc(
        'plp_payment_record_v1',
        <String, Object?>{
          'p_request_id': requestId,
          'p_booking_reference': bookingReference,
          'p_amount_php': amountPhp,
          'p_method': method,
          'p_reference': reference,
        },
      );

  @override
  Future<Map<String, Object?>> updateRoom({
    required String requestId,
    required String accommodationId,
    required Map<String, Object?> patch,
  }) =>
      _rpc(
        'plp_room_update_v1',
        <String, Object?>{
          'p_request_id': requestId,
          'p_accommodation_id': accommodationId,
          'p_patch': patch,
        },
      );

  Future<Map<String, Object?>> _rpc(
    String function,
    Map<String, Object?> params,
  ) async {
    try {
      final raw = await _client.rpc(function, params: params);
      final result = _map(raw);
      if (result.isEmpty) {
        throw const PlpResortLifecycleFailure(
          'The resort operation returned no provider readback.',
        );
      }
      if (result['verified'] == false ||
          result['providerReadbackVerified'] == false) {
        throw const PlpResortLifecycleFailure(
          'The resort operation could not be verified.',
        );
      }
      return result;
    } on PlpResortLifecycleFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw PlpResortLifecycleFailure(
        error.message.trim().isEmpty
            ? 'The resort operation was rejected.'
            : error.message,
      );
    } catch (_) {
      throw const PlpResortLifecycleFailure(
        'The resort operation could not be completed.',
      );
    }
  }

  String _date(DateTime value) {
    final local = DateTime(value.year, value.month, value.day);
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
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
