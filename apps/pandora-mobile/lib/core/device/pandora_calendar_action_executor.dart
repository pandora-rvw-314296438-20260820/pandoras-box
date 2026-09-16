
import 'package:flutter/services.dart';

import 'pandora_calendar_command.dart';
import 'pandora_calendar_runtime.dart';

typedef PandoraCalendarActivityReporter = Future<void> Function(
  PandoraCalendarActivityFact fact,
);

class PandoraCalendarActivityFact {
  const PandoraCalendarActivityFact({
    required this.capability,
    required this.stage,
    required this.observedAt,
  });

  final String capability;
  final String stage;
  final DateTime observedAt;
}

class PandoraCalendarExecutionResult {
  const PandoraCalendarExecutionResult({
    required this.reply,
    required this.terminalStage,
    required this.capability,
    required this.observedAt,
    this.needsUserAction = false,
  });

  final String reply;
  final String terminalStage;
  final String capability;
  final DateTime observedAt;
  final bool needsUserAction;
}

class PandoraCalendarActionExecutor {
  PandoraCalendarActionExecutor({
    PandoraCalendarRuntime? runtime,
    PandoraCalendarActivityReporter? reporter,
    DateTime Function()? clock,
  })  : _runtime = runtime ?? PandoraCalendarRuntime(),
        _reporter = reporter,
        _clock = clock ?? DateTime.now;

  final PandoraCalendarRuntime _runtime;
  final PandoraCalendarActivityReporter? _reporter;
  final DateTime Function() _clock;

  Future<PandoraCalendarExecutionResult> execute(
    PandoraCalendarCommand command, {
    required String operationId,
  }) async {
    final capability = command.kind == PandoraCalendarCommandKind.reminder
        ? 'reminder.local'
        : 'calendar.events';
    await _report(capability, 'acting', _clock());
    try {
      switch (command.kind) {
        case PandoraCalendarCommandKind.query:
          return await _query(command);
        case PandoraCalendarCommandKind.create:
          return await _create(command, operationId);
        case PandoraCalendarCommandKind.update:
          return await _update(command, operationId);
        case PandoraCalendarCommandKind.delete:
          return await _delete(command, operationId);
        case PandoraCalendarCommandKind.reminder:
          return await _reminder(command, operationId);
      }
    } on PlatformException catch (error) {
      final permission = error.code == 'CALENDAR_PERMISSION_REQUIRED';
      return _finish(
        capability,
        permission ? 'needs_permission' : 'failed',
        permission
            ? 'Calendar permission is required. Grant it in Android app permissions, then try again.'
            : 'Android could not complete that calendar action. No success was reported.',
        needsUserAction: permission,
      );
    } on FormatException {
      return _finish(
        capability,
        'failed',
        'Android returned calendar data Pandora could not verify. No success was reported.',
      );
    } on ArgumentError {
      return _finish(
        capability,
        'failed',
        'That calendar request was not safe to execute as written. No change was made.',
      );
    }
  }

  Future<PandoraCalendarExecutionResult> _query(
    PandoraCalendarCommand command,
  ) async {
    final permission = await _runtime.getPermissionState();
    if (permission['readGranted'] != true) {
      return _finish(
        'calendar.events',
        'needs_permission',
        'Calendar read permission is required. Grant Calendar access, then try again.',
        needsUserAction: true,
      );
    }
    final events = await _runtime.queryEvents(
      startEpochMs: command.rangeStart!.millisecondsSinceEpoch,
      endEpochMs: command.rangeEnd!.millisecondsSinceEpoch,
    );
    await _report('calendar.events', 'verifying', _clock());
    if (events.isEmpty) {
      return _finish(
        'calendar.events',
        'result',
        'Your Android calendar has no events in that time window.',
      );
    }
    final lines = events.take(6).map((event) {
      final title = _text(event['title'], fallback: 'Untitled event');
      final start = _date(event['startEpochMs']);
      return '${_formatTime(start)} — $title';
    }).join('\n');
    final suffix =
        events.length > 6 ? '\nAnd ${events.length - 6} more event(s).' : '';
    return _finish('calendar.events', 'result', '$lines$suffix');
  }

  Future<PandoraCalendarExecutionResult> _create(
    PandoraCalendarCommand command,
    String operationId,
  ) async {
    final permission = await _runtime.getPermissionState();
    final gap = _writePermissionGap(permission);
    if (gap != null) return gap;
    final selection = await _selectWritableCalendar();
    if (selection.result != null) return selection.result!;
    final result = await _runtime.createEvent(
      operationId: operationId,
      calendarId: _int(selection.calendar!['id']),
      title: command.title!,
      startEpochMs: command.start!.millisecondsSinceEpoch,
      endEpochMs: command.end!.millisecondsSinceEpoch,
      timeZoneId: _text(permission['deviceTimeZoneId'], fallback: 'UTC'),
      recurrenceRule: command.recurrenceRule,
    );
    return _mutationResult(result, 'created', 'created');
  }

  Future<PandoraCalendarExecutionResult> _update(
    PandoraCalendarCommand command,
    String operationId,
  ) async {
    final permission = await _runtime.getPermissionState();
    final gap = _writePermissionGap(permission);
    if (gap != null) return gap;
    final match = await _findUnique(command);
    if (match.result != null) return match.result!;
    final event = match.event!;
    final oldStart = _date(event['startEpochMs']);
    final oldEnd = _date(event['endEpochMs']);
    final newStart = command.start!;
    final result = await _runtime.updateEvent(
      operationId: operationId,
      eventId: _int(event['id']),
      title: _text(event['title'], fallback: command.title ?? 'Event'),
      startEpochMs: newStart.millisecondsSinceEpoch,
      endEpochMs:
          newStart.add(oldEnd.difference(oldStart)).millisecondsSinceEpoch,
      timeZoneId: _text(
        event['timeZoneId'],
        fallback: _text(permission['deviceTimeZoneId'], fallback: 'UTC'),
      ),
      location: _nullableText(event['location']),
      description: _nullableText(event['description']),
      recurrenceRule: _nullableText(event['recurrenceRule']),
    );
    return _mutationResult(result, 'updated', 'moved');
  }

  Future<PandoraCalendarExecutionResult> _delete(
    PandoraCalendarCommand command,
    String operationId,
  ) async {
    final permission = await _runtime.getPermissionState();
    final gap = _writePermissionGap(permission);
    if (gap != null) return gap;
    final match = await _findUnique(command);
    if (match.result != null) return match.result!;
    final title = _text(match.event!['title'], fallback: 'Event');
    final result = await _runtime.deleteEvent(
      operationId: operationId,
      eventId: _int(match.event!['id']),
    );
    if (_text(result['state']) == 'deleted') {
      return _finish(
        'calendar.events',
        'result',
        '$title was cancelled and Android confirmed it is gone.',
        observedAt: _fromEpoch(result['updatedAtEpochMs']),
      );
    }
    return _failureFromState(result);
  }

  Future<PandoraCalendarExecutionResult> _reminder(
    PandoraCalendarCommand command,
    String operationId,
  ) async {
    final permission = await _runtime.getPermissionState();
    if (permission['notificationGranted'] != true) {
      return _finish(
        'reminder.local',
        'needs_permission',
        'Notification permission is required for local reminders. Grant Notifications for Pandora, then try again.',
        needsUserAction: true,
      );
    }
    final scheduled = await _runtime.scheduleLocalReminder(
      operationId: operationId,
      title: command.title!,
      triggerEpochMs: command.start!.millisecondsSinceEpoch,
      requireExact: command.requireExactReminder,
    );
    final state = _text(scheduled['state']);
    if (state == 'special_access_required') {
      return _finish(
        'reminder.local',
        'needs_special_access',
        'Android exact-alarm access is required. Enable Alarms & reminders for Pandora, then try again.',
        observedAt: _fromEpoch(scheduled['updatedAtEpochMs']),
        needsUserAction: true,
      );
    }
    if (state != 'scheduled') {
      return _finish(
        'reminder.local',
        'failed',
        'Android did not confirm that reminder was scheduled.',
        observedAt: _fromEpoch(scheduled['updatedAtEpochMs']),
      );
    }
    final readback = await _runtime.getLocalReminderStatus(operationId);
    await _report(
      'reminder.local',
      'verifying',
      _fromEpoch(readback?['updatedAtEpochMs']),
    );
    if (readback == null || readback['state'] != 'scheduled') {
      return _finish(
        'reminder.local',
        'failed',
        'The reminder schedule could not be verified from Android state. No success was reported.',
      );
    }
    return _finish(
      'reminder.local',
      'result',
      'Reminder scheduled on this device for ${_formatDateTime(command.start!)}. It will continue locally without cloud access.',
      observedAt: _fromEpoch(readback['updatedAtEpochMs']),
    );
  }

  PandoraCalendarExecutionResult? _writePermissionGap(
    Map<String, Object?> permission,
  ) {
    if (permission['readGranted'] == true &&
        permission['writeGranted'] == true) {
      return null;
    }
    return PandoraCalendarExecutionResult(
      capability: 'calendar.events',
      terminalStage: 'needs_permission',
      reply:
          'Calendar read and write permission are required. Grant Calendar access for Pandora, then try again.',
      observedAt: _clock(),
      needsUserAction: true,
    );
  }

  Future<_CalendarSelection> _selectWritableCalendar() async {
    final calendars = await _runtime.listCalendars();
    final writable = calendars
        .where((row) => row['writable'] == true && row['visible'] == true)
        .toList(growable: false);
    if (writable.isEmpty) {
      return _CalendarSelection.result(
        await _finish(
          'calendar.events',
          'failed',
          'Android did not expose a visible writable calendar. No event was created.',
        ),
      );
    }
    if (writable.length == 1) {
      return _CalendarSelection.calendar(writable.single);
    }
    final names = writable
        .take(4)
        .map((row) => _text(row['displayName'], fallback: 'Calendar'))
        .join(', ');
    return _CalendarSelection.result(
      await _finish(
        'calendar.events',
        'needs_choice',
        'More than one writable calendar is available ($names). Choose the calendar before I make the change.',
        needsUserAction: true,
      ),
    );
  }

  Future<_EventMatch> _findUnique(PandoraCalendarCommand command) async {
    final events = await _runtime.queryEvents(
      startEpochMs: command.rangeStart!.millisecondsSinceEpoch,
      endEpochMs: command.rangeEnd!.millisecondsSinceEpoch,
    );
    final needle = (command.title ?? '').toLowerCase();
    final candidates = events.where((event) {
      if (needle.isNotEmpty &&
          !_text(event['title']).toLowerCase().contains(needle)) {
        return false;
      }
      if (command.oldMinuteOfDay != null) {
        final start = _date(event['startEpochMs']);
        if (start.hour * 60 + start.minute != command.oldMinuteOfDay) {
          return false;
        }
      }
      return true;
    }).toList(growable: false);
    if (candidates.isEmpty) {
      return _EventMatch.result(
        await _finish(
          'calendar.events',
          'result',
          'I could not find a matching calendar event. No change was made.',
        ),
      );
    }
    if (candidates.length > 1) {
      return _EventMatch.result(
        await _finish(
          'calendar.events',
          'needs_choice',
          'I found more than one matching calendar event. Tell me which one you mean before I change anything.',
          needsUserAction: true,
        ),
      );
    }
    return _EventMatch.event(candidates.single);
  }

  Future<PandoraCalendarExecutionResult> _mutationResult(
    Map<String, Object?> result,
    String successState,
    String verb,
  ) async {
    if (_text(result['state']) != successState) {
      return _failureFromState(result);
    }
    final event = _map(result['event']);
    if (event.isEmpty) {
      return _finish(
        'calendar.events',
        'failed',
        'Android accepted the write but Pandora could not verify provider readback.',
      );
    }
    final observedAt = _fromEpoch(result['updatedAtEpochMs']);
    await _report('calendar.events', 'verifying', observedAt);
    final title = _text(event['title'], fallback: 'Calendar event');
    final provider =
        _text(event['providerKind'], fallback: 'local') == 'connected'
            ? 'connected calendar'
            : 'device calendar';
    return _finish(
      'calendar.events',
      'result',
      '$title was $verb and verified by Android $provider readback.',
      observedAt: observedAt,
    );
  }

  Future<PandoraCalendarExecutionResult> _failureFromState(
    Map<String, Object?> result,
  ) async {
    final state = _text(result['state']);
    if (state == 'resource_not_found') {
      return _finish(
        'calendar.events',
        'result',
        'That calendar event no longer exists. No duplicate change was made.',
        observedAt: _fromEpoch(result['updatedAtEpochMs']),
      );
    }
    return _finish(
      'calendar.events',
      'failed',
      state == 'operation_conflict'
          ? 'Pandora stopped a duplicate calendar operation because its operation identity was reused with different input.'
          : 'Android did not verify that calendar change. No success was reported.',
      observedAt: _fromEpoch(result['updatedAtEpochMs']),
    );
  }

  Future<PandoraCalendarExecutionResult> _finish(
    String capability,
    String stage,
    String reply, {
    DateTime? observedAt,
    bool needsUserAction = false,
  }) async {
    final at = observedAt ?? _clock();
    await _report(capability, stage, at);
    return PandoraCalendarExecutionResult(
      reply: reply,
      terminalStage: stage,
      capability: capability,
      observedAt: at,
      needsUserAction: needsUserAction,
    );
  }

  Future<void> _report(String capability, String stage, DateTime at) async {
    final reporter = _reporter;
    if (reporter == null) return;
    try {
      await reporter(
        PandoraCalendarActivityFact(
          capability: capability,
          stage: stage,
          observedAt: at,
        ),
      );
    } catch (_) {
      // Native execution remains idempotent and truthful if Activity transport
      // is temporarily offline; provider state remains available for readback.
    }
  }

  DateTime _fromEpoch(Object? value) {
    final epoch = _int(value);
    return epoch > 0 ? DateTime.fromMillisecondsSinceEpoch(epoch) : _clock();
  }

  DateTime _date(Object? value) {
    final epoch = _int(value);
    if (epoch <= 0) throw const FormatException('Invalid calendar timestamp.');
    return DateTime.fromMillisecondsSinceEpoch(epoch);
  }

  String _formatTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  String _formatDateTime(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${_formatTime(value)}';

  String _text(Object? value, {String fallback = ''}) =>
      value is String && value.trim().isNotEmpty ? value.trim() : fallback;

  String? _nullableText(Object? value) {
    final text = _text(value);
    return text.isEmpty ? null : text;
  }

  int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Map<String, Object?> _map(Object? value) => value is Map
      ? value.map((key, value) => MapEntry(key.toString(), value))
      : <String, Object?>{};
}

class _CalendarSelection {
  const _CalendarSelection._({this.calendar, this.result});
  const _CalendarSelection.calendar(Map<String, Object?> value)
      : this._(calendar: value);
  const _CalendarSelection.result(PandoraCalendarExecutionResult value)
      : this._(result: value);

  final Map<String, Object?>? calendar;
  final PandoraCalendarExecutionResult? result;
}

class _EventMatch {
  const _EventMatch._({this.event, this.result});
  const _EventMatch.event(Map<String, Object?> value) : this._(event: value);
  const _EventMatch.result(PandoraCalendarExecutionResult value)
      : this._(result: value);

  final Map<String, Object?>? event;
  final PandoraCalendarExecutionResult? result;
}
