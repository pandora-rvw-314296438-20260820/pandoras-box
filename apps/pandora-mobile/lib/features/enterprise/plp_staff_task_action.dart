import 'package:supabase_flutter/supabase_flutter.dart';

class PlpStaffTaskCommand {
  const PlpStaffTaskCommand({
    required this.bookingReference,
    required this.title,
    required this.note,
    required this.category,
    required this.priority,
  });

  final String bookingReference;
  final String title;
  final String note;
  final String category;
  final String priority;

  static PlpStaffTaskCommand? tryParse(String input) {
    final value = input.trim();
    final match = RegExp(
      r'^(?:please\s+)?create\s+(?:a\s+)?staff\s+task\s+to\s+(.+?)[.!]?\s*$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return null;

    final instruction = match.group(1)?.trim() ?? '';
    if (instruction.length < 3 || instruction.length > 220) return null;

    final room = RegExp(
      r'\broom\s+([A-Za-z0-9][A-Za-z0-9-]*)\b',
      caseSensitive: false,
    ).firstMatch(instruction);
    final bookingReference =
        room == null ? 'PLP' : 'Room ' + room.group(1)!;
    final lower = instruction.toLowerCase();
    final category = RegExp(
      r'\b(room|inspect|inspection|clean|cleaning|housekeep|linen|amenit)',
      caseSensitive: false,
    ).hasMatch(lower)
        ? 'housekeeping'
        : 'admin';

    final title = instruction[0].toUpperCase() + instruction.substring(1);
    return PlpStaffTaskCommand(
      bookingReference: bookingReference,
      title: title,
      note: 'Created from authenticated PLP Pandora mobile command: "' +
          value +
          '"',
      category: category,
      priority: 'normal',
    );
  }
}

class PlpStaffTaskActionResult {
  const PlpStaffTaskActionResult({
    required this.activityJobId,
    required this.taskId,
    required this.bookingReference,
    required this.title,
    required this.status,
    required this.providerReadbackVerified,
    required this.idempotentReplay,
  });

  final String activityJobId;
  final String taskId;
  final String bookingReference;
  final String title;
  final String status;
  final bool providerReadbackVerified;
  final bool idempotentReplay;

  factory PlpStaffTaskActionResult.fromMap(Map<String, Object?> value) {
    String requiredText(String key) {
      final text = value[key]?.toString().trim();
      if (text == null || text.isEmpty) {
        throw PlpStaffTaskActionException(
          'PLP task provider response is missing ' + key + '.',
        );
      }
      return text;
    }

    final verified = value['providerReadbackVerified'] == true &&
        value['verified'] == true;
    if (!verified) {
      throw const PlpStaffTaskActionException(
        'PLP task provider readback was not verified.',
      );
    }

    return PlpStaffTaskActionResult(
      activityJobId: requiredText('activityJobId'),
      taskId: requiredText('taskId'),
      bookingReference: requiredText('bookingReference'),
      title: requiredText('title'),
      status: requiredText('status'),
      providerReadbackVerified: true,
      idempotentReplay: value['idempotentReplay'] == true,
    );
  }
}

class PlpStaffTaskActionException implements Exception {
  const PlpStaffTaskActionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PlpStaffTaskAction {
  const PlpStaffTaskAction();

  Future<PlpStaffTaskActionResult> execute({
    required String requestId,
    required PlpStaffTaskCommand command,
  }) async {
    try {
      final raw = await Supabase.instance.client.rpc(
        'plp_create_staff_task_v1',
        params: <String, Object?>{
          'p_request_id': requestId,
          'p_booking_reference': command.bookingReference,
          'p_title': command.title,
          'p_note': command.note,
          'p_category': command.category,
          'p_priority': command.priority,
        },
      );
      if (raw is! Map) {
        throw const PlpStaffTaskActionException(
          'PLP task provider returned an invalid response.',
        );
      }
      final value = <String, Object?>{
        for (final entry in raw.entries) entry.key.toString(): entry.value,
      };
      return PlpStaffTaskActionResult.fromMap(value);
    } on PlpStaffTaskActionException {
      rethrow;
    } catch (error) {
      throw PlpStaffTaskActionException(
        'PLP staff-task outcome could not be confirmed: ' + error.toString(),
      );
    }
  }
}
