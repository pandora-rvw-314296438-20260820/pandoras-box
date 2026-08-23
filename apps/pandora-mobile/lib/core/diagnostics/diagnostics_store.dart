import 'dart:collection';

import 'diagnostic_event.dart';
import 'diagnostics_sanitizer.dart';

class DiagnosticsStore implements DiagnosticsSink {
  DiagnosticsStore({
    int capacity = 100,
    DiagnosticsSanitizer sanitizer = const DiagnosticsSanitizer(),
  })  : capacity = capacity.clamp(1, 500).toInt(),
        _sanitizer = sanitizer;

  final int capacity;
  final DiagnosticsSanitizer _sanitizer;
  final Queue<DiagnosticEvent> _events = Queue<DiagnosticEvent>();

  List<DiagnosticEvent> get events =>
      List<DiagnosticEvent>.unmodifiable(_events.toList().reversed);

  @override
  void record(DiagnosticEvent event) {
    _events.addLast(
      DiagnosticEvent(
        occurredAt: event.occurredAt,
        operation: _safeText(event.operation),
        method: _safeText(event.method),
        routeTemplate: _safeText(event.routeTemplate),
        outcome: event.outcome,
        duration: event.duration,
        statusCode: event.statusCode,
        requestId: event.requestId == null ? null : _safeText(event.requestId!),
        errorCode: event.errorCode == null ? null : _safeText(event.errorCode!),
      ),
    );
    while (_events.length > capacity) {
      _events.removeFirst();
    }
  }

  String _safeText(String value) {
    final sanitized = _sanitizer.sanitize(value);
    return sanitized is String ? sanitized : '[REDACTED]';
  }

  void clear() => _events.clear();
}
