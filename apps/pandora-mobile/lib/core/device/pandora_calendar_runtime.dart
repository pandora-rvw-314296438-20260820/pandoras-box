import 'package:flutter/services.dart';

final RegExp _operationIdPattern = RegExp(r'^[A-Za-z0-9._:-]{8,128}$');

Map<String, Object?> _stringMap(Object? raw, String label) {
  if (raw is! Map) throw FormatException('$label must be a map.');
  final result = <String, Object?>{};
  for (final entry in raw.entries) {
    if (entry.key is! String) {
      throw FormatException('$label contains a non-string key.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _requireOperationId(String operationId) {
  if (!_operationIdPattern.hasMatch(operationId)) {
    throw ArgumentError.value(
      operationId,
      'operationId',
      'Invalid operation id.',
    );
  }
}

void _requireRange(int startEpochMs, int endEpochMs) {
  if (startEpochMs <= 0 || endEpochMs <= startEpochMs) {
    throw ArgumentError('Calendar time range must be positive and ordered.');
  }
}

void _requireBoundedText(String value, String label, int maxLength) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > maxLength) {
    throw ArgumentError.value(
      value,
      label,
      '$label must be 1..$maxLength characters.',
    );
  }
}

List<Map<String, Object?>> _mapList(Object? raw, String label) {
  if (raw is! List) throw FormatException('$label must be a list.');
  return List.unmodifiable(raw.map((item) => _stringMap(item, label)));
}

class PandoraCalendarRuntime {
  PandoraCalendarRuntime({
    MethodChannel channel = const MethodChannel('pandora/calendar_runtime'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<Map<String, Object?>> getPermissionState() async {
    final raw = await _channel.invokeMethod<Object?>('getPermissionState');
    final result = _stringMap(raw, 'calendar permission state');
    if (result['schemaVersion'] != '1.0.0') {
      throw const FormatException('Unsupported calendar permission schema.');
    }
    return result;
  }

  Future<List<Map<String, Object?>>> listCalendars() async {
    final raw = await _channel.invokeMethod<Object?>('listCalendars');
    return _mapList(raw, 'calendars');
  }

  Future<List<Map<String, Object?>>> queryEvents({
    required int startEpochMs,
    required int endEpochMs,
    int? calendarId,
    int limit = 100,
  }) async {
    _requireRange(startEpochMs, endEpochMs);
    if (calendarId != null && calendarId <= 0) {
      throw ArgumentError.value(calendarId, 'calendarId');
    }
    if (limit < 1 || limit > 250) {
      throw ArgumentError.value(limit, 'limit', 'limit must be 1..250.');
    }
    final raw = await _channel.invokeMethod<Object?>(
      'queryEvents',
      <String, Object?>{
        'startEpochMs': startEpochMs,
        'endEpochMs': endEpochMs,
        'calendarId': calendarId,
        'limit': limit,
      },
    );
    return _mapList(raw, 'calendar events');
  }

  Map<String, Object?> _eventArguments({
    required String operationId,
    required String title,
    required int startEpochMs,
    required int endEpochMs,
    required String timeZoneId,
    String? location,
    String? description,
    String? recurrenceRule,
  }) {
    _requireOperationId(operationId);
    _requireBoundedText(title, 'title', 512);
    _requireBoundedText(timeZoneId, 'timeZoneId', 128);
    _requireRange(startEpochMs, endEpochMs);
    if ((location?.length ?? 0) > 512 || (description?.length ?? 0) > 4000) {
      throw ArgumentError('Calendar text exceeds the bounded field size.');
    }
    if ((recurrenceRule?.length ?? 0) > 512) {
      throw ArgumentError('Recurrence rule exceeds the bounded field size.');
    }
    return <String, Object?>{
      'operationId': operationId,
      'title': title.trim(),
      'startEpochMs': startEpochMs,
      'endEpochMs': endEpochMs,
      'timeZoneId': timeZoneId.trim(),
      'location': location,
      'description': description,
      'recurrenceRule': recurrenceRule,
    };
  }

  Future<Map<String, Object?>> createEvent({
    required String operationId,
    required int calendarId,
    required String title,
    required int startEpochMs,
    required int endEpochMs,
    required String timeZoneId,
    String? location,
    String? description,
    String? recurrenceRule,
  }) async {
    if (calendarId <= 0) throw ArgumentError.value(calendarId, 'calendarId');
    final arguments = _eventArguments(
      operationId: operationId,
      title: title,
      startEpochMs: startEpochMs,
      endEpochMs: endEpochMs,
      timeZoneId: timeZoneId,
      location: location,
      description: description,
      recurrenceRule: recurrenceRule,
    )..['calendarId'] = calendarId;
    final raw = await _channel.invokeMethod<Object?>('createEvent', arguments);
    return _stringMap(raw, 'calendar create result');
  }

  Future<Map<String, Object?>> updateEvent({
    required String operationId,
    required int eventId,
    required String title,
    required int startEpochMs,
    required int endEpochMs,
    required String timeZoneId,
    String? location,
    String? description,
    String? recurrenceRule,
  }) async {
    if (eventId <= 0) throw ArgumentError.value(eventId, 'eventId');
    final arguments = _eventArguments(
      operationId: operationId,
      title: title,
      startEpochMs: startEpochMs,
      endEpochMs: endEpochMs,
      timeZoneId: timeZoneId,
      location: location,
      description: description,
      recurrenceRule: recurrenceRule,
    )..['eventId'] = eventId;
    final raw = await _channel.invokeMethod<Object?>('updateEvent', arguments);
    return _stringMap(raw, 'calendar update result');
  }

  Future<Map<String, Object?>> deleteEvent({
    required String operationId,
    required int eventId,
  }) async {
    _requireOperationId(operationId);
    if (eventId <= 0) throw ArgumentError.value(eventId, 'eventId');
    final raw = await _channel.invokeMethod<Object?>(
      'deleteEvent',
      <String, Object?>{'operationId': operationId, 'eventId': eventId},
    );
    return _stringMap(raw, 'calendar delete result');
  }

  Future<Map<String, Object?>> scheduleLocalReminder({
    required String operationId,
    required String title,
    required int triggerEpochMs,
    String? body,
    bool requireExact = false,
  }) async {
    _requireOperationId(operationId);
    _requireBoundedText(title, 'title', 256);
    if (triggerEpochMs <= 0) {
      throw ArgumentError.value(triggerEpochMs, 'triggerEpochMs');
    }
    if ((body?.length ?? 0) > 1000) {
      throw ArgumentError('Reminder body exceeds 1000 characters.');
    }
    final raw = await _channel.invokeMethod<Object?>(
      'scheduleLocalReminder',
      <String, Object?>{
        'operationId': operationId,
        'title': title.trim(),
        'body': body,
        'triggerEpochMs': triggerEpochMs,
        'requireExact': requireExact,
      },
    );
    return _stringMap(raw, 'local reminder result');
  }

  Future<Map<String, Object?>> cancelLocalReminder(String operationId) async {
    _requireOperationId(operationId);
    final raw = await _channel.invokeMethod<Object?>(
      'cancelLocalReminder',
      <String, Object?>{'operationId': operationId},
    );
    return _stringMap(raw, 'local reminder cancel result');
  }

  Future<Map<String, Object?>?> getOperationStatus(String operationId) async {
    _requireOperationId(operationId);
    final raw = await _channel.invokeMethod<Object?>(
      'getOperationStatus',
      <String, Object?>{'operationId': operationId},
    );
    return raw == null ? null : _stringMap(raw, 'calendar operation status');
  }

  Future<Map<String, Object?>?> getLocalReminderStatus(
    String operationId,
  ) async {
    _requireOperationId(operationId);
    final raw = await _channel.invokeMethod<Object?>(
      'getLocalReminderStatus',
      <String, Object?>{'operationId': operationId},
    );
    return raw == null ? null : _stringMap(raw, 'local reminder status');
  }
}
