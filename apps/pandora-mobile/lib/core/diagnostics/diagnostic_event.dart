enum DiagnosticOutcome { succeeded, failed }

class DiagnosticEvent {
  const DiagnosticEvent({
    required this.occurredAt,
    required this.operation,
    required this.method,
    required this.routeTemplate,
    required this.outcome,
    required this.duration,
    this.statusCode,
    this.requestId,
    this.errorCode,
  });

  final DateTime occurredAt;
  final String operation;
  final String method;
  final String routeTemplate;
  final DiagnosticOutcome outcome;
  final Duration duration;
  final int? statusCode;
  final String? requestId;
  final String? errorCode;

  Map<String, Object?> toSafeJson() => <String, Object?>{
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        'operation': operation,
        'method': method,
        'routeTemplate': routeTemplate,
        'outcome': outcome.name,
        'durationMs': duration.inMilliseconds,
        if (statusCode != null) 'statusCode': statusCode,
        if (requestId != null) 'requestId': requestId,
        if (errorCode != null) 'errorCode': errorCode,
      };
}

abstract interface class DiagnosticsSink {
  void record(DiagnosticEvent event);
}

class NoopDiagnosticsSink implements DiagnosticsSink {
  const NoopDiagnosticsSink();

  @override
  void record(DiagnosticEvent event) {}
}
