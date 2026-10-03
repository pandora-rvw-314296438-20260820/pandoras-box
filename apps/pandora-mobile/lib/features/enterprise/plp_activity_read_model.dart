import 'dart:async';

import 'package:flutter/foundation.dart';

/// One bounded activity snapshot for a PLP shell. Constructing it does no I/O.
/// Parent and detail consume the same filtered result; refresh errors retain it.
class PlpActivityReadModel extends ChangeNotifier {
  PlpActivityReadModel({required this.loader});

  final Future<Map<String, Object?>> Function() loader;
  Map<String, Object?>? _data;
  Object? _error;
  Future<Map<String, Object?>>? _pending;
  bool _disposed = false;

  Map<String, Object?>? get data => _data;
  Object? get error => _error;
  bool get loading => _pending != null;
  List<Map<String, Object?>> get items =>
      _data?['items'] as List<Map<String, Object?>>? ??
      const <Map<String, Object?>>[];

  Future<Map<String, Object?>> load({bool force = false}) {
    if (_disposed) return Future.error(StateError('Activity model is disposed.'));
    final pending = _pending;
    if (pending != null) return pending;
    if (!force && _data != null) return Future.value(_data!);
    _error = null;
    final operation = _read();
    _pending = operation;
    notifyListeners();
    return operation;
  }

  Future<Map<String, Object?>> _read() async {
    try {
      final payload = await Future<Map<String, Object?>>.sync(loader)
          .timeout(const Duration(seconds: 12));
      if (payload['items'] is! List) {
        throw StateError('Activity did not return a verified list.');
      }
      final result = Map<String, Object?>.unmodifiable({
        ...payload,
        'items': List<Map<String, Object?>>.unmodifiable(
            plpProductionActivityRecords(payload['items'])),
      });
      if (!_disposed) _data = result;
      return result;
    } catch (error) {
      if (!_disposed) _error = error;
      rethrow;
    } finally {
      _pending = null;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final _plpTestSource = RegExp(
  r'^(qa|mock|synthetic|fixture|test|demo)([\s_:/.-]|$)',
  caseSensitive: false,
);

/// Classify explicit test provenance, not ordinary staff names or guest text.
/// Mirrors private.plp_activity_record_is_test_v2 at the provider boundary.
bool plpRecordIsTestData(Map<String, Object?> record) {
  bool truthy(Object? value) => value == true ||
      const {'true', '1', 'yes'}
          .contains(value?.toString().toLowerCase());
  for (final scope in <Object?>[
    record,
    record['metadata'],
    record['provenance'],
  ]) {
    if (scope is! Map) continue;
    for (final flag in const [
      'isMock', 'is_mock', 'isTestData', 'is_test_data',
      'isTest', 'is_test', 'synthetic', 'mock', 'testOnly', 'test_only',
    ]) {
      if (truthy(scope[flag])) return true;
    }
  }
  final provenance = record['provenance'];
  for (final source in <Object?>[
    record['sourceLabel'],
    record['sourceType'],
    record['source'],
    if (provenance is Map) provenance['sourceType'],
  ]) {
    if (_plpTestSource.hasMatch(source?.toString().trim() ?? '')) return true;
  }
  for (final key in const ['title', 'summary', 'message', 'note']) {
    final text = record[key]?.toString().toLowerCase() ?? '';
    if (text.contains('[mock qa]')) return true;
  }
  final reference = (record['booking_reference'] ?? record['bookingReference'])
      ?.toString().toUpperCase() ?? '';
  return reference.startsWith('MOCK-');
}

/// The parent, counts and detail use the same bounded production-only list.
List<Map<String, Object?>> plpProductionActivityRecords(Object? value) {
  if (value is! List) return const <Map<String, Object?>>[];
  return value.whereType<Map>()
      .map((row) => row.map((key, value) => MapEntry(key.toString(), value)))
      .where((row) => !plpRecordIsTestData(row))
      .take(80)
      .toList(growable: false);
}
