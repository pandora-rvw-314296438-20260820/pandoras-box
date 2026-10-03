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

/// Shared defence for production history. Explicit test markers and legacy
/// test-source labels are excluded before summaries, counts, and feed rows.
List<Map<String, Object?>> plpProductionActivityRecords(Object? value) {
  if (value is! List) return const <Map<String, Object?>>[];
  bool truthy(Object? v) =>
      v == true || const {'true', '1', 'yes'}.contains(v?.toString().toLowerCase());
  bool production(Map<String, Object?> row) {
    for (final key in const ['isMock', 'isTestData', 'isTest', 'synthetic', 'mock']) {
      if (truthy(row[key])) return false;
    }
    for (final key in const ['sourceLabel', 'sourceType', 'source']) {
      final source = row[key]?.toString().trim().toLowerCase() ?? '';
      if (source.startsWith('qa_') || source.contains('mock') ||
          source.contains('synthetic')) return false;
    }
    for (final key in const ['title', 'summary', 'message']) {
      final text = row[key]?.toString().toLowerCase() ?? '';
      if (text.contains('[mock qa]') || text.startsWith('synthetic ')) return false;
    }
    return true;
  }
  return value.whereType<Map>()
      .map((row) => row.map((key, value) => MapEntry(key.toString(), value)))
      .where(production).take(80).toList(growable: false);
}
