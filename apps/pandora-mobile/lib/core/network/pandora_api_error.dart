enum PandoraApiErrorKind {
  invalidRequest,
  sessionExpired,
  forbidden,
  notFound,
  conflict,
  rateLimited,
  unavailable,
  contract,
  ambiguousMutation,
}

class PandoraApiError implements Exception {
  const PandoraApiError({
    required this.kind,
    required this.message,
    required this.code,
    this.statusCode,
    this.requestId,
  });

  final PandoraApiErrorKind kind;
  final String message;
  final String code;
  final int? statusCode;
  final String? requestId;

  bool get outcomeMayBeUnknown => kind == PandoraApiErrorKind.ambiguousMutation;

  bool get retryable => switch (kind) {
        PandoraApiErrorKind.rateLimited ||
        PandoraApiErrorKind.unavailable =>
          true,
        _ => false,
      };

  @override
  String toString() => message;
}
