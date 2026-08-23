import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../diagnostics/diagnostic_event.dart';
import '../diagnostics/diagnostics_sanitizer.dart';
import 'pandora_api_error.dart';
import 'session_token_provider.dart';

class PandoraApiResponse {
  const PandoraApiResponse({
    required this.data,
    required this.statusCode,
    required this.duration,
    required this.identityEpoch,
    this.requestId,
  });

  final Object? data;
  final int statusCode;
  final Duration duration;
  final int identityEpoch;
  final String? requestId;
}

class PandoraApiClient {
  PandoraApiClient({
    required Uri baseUri,
    required String organizationId,
    required SessionTokenProvider sessionTokenProvider,
    http.Client? httpClient,
    DiagnosticsSink diagnostics = const NoopDiagnosticsSink(),
    this.timeout = const Duration(seconds: 20),
    this.maxResponseBytes = 1024 * 1024,
    DateTime Function()? clock,
  })  : baseUri = _validatedBaseUri(baseUri),
        organizationId = organizationId.trim(),
        _sessionTokenProvider = sessionTokenProvider,
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _diagnostics = diagnostics,
        _clock = clock ?? DateTime.now {
    if (this.organizationId.isEmpty) {
      throw ArgumentError.value(
        organizationId,
        'organizationId',
        'A canonical organization ID is required.',
      );
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }
    if (maxResponseBytes < 1024 || maxResponseBytes > 10 * 1024 * 1024) {
      throw ArgumentError.value(
        maxResponseBytes,
        'maxResponseBytes',
        'Must be between 1 KiB and 10 MiB.',
      );
    }
  }

  final Uri baseUri;
  final String organizationId;
  final Duration timeout;
  final int maxResponseBytes;
  final SessionTokenProvider _sessionTokenProvider;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final DiagnosticsSink _diagnostics;
  final DateTime Function() _clock;
  var _identityEpoch = 0;

  Future<PandoraApiResponse> getJson({
    required List<String> pathSegments,
    required String operation,
    required String routeTemplate,
    Map<String, String>? queryParameters,
  }) =>
      _request(
        method: 'GET',
        pathSegments: pathSegments,
        operation: operation,
        routeTemplate: routeTemplate,
        queryParameters: queryParameters,
      );

  Future<PandoraApiResponse> postJson({
    required List<String> pathSegments,
    required String operation,
    required String routeTemplate,
    required Map<String, Object?> body,
    String? idempotencyKey,
  }) =>
      _request(
        method: 'POST',
        pathSegments: pathSegments,
        operation: operation,
        routeTemplate: routeTemplate,
        body: body,
        idempotencyKey: idempotencyKey,
      );

  Future<PandoraApiResponse> _request({
    required String method,
    required List<String> pathSegments,
    required String operation,
    required String routeTemplate,
    Map<String, String>? queryParameters,
    Map<String, Object?>? body,
    String? idempotencyKey,
  }) async {
    final identityEpoch = _identityEpoch;
    final startedAt = _clock();
    final stopwatch = Stopwatch()..start();
    var diagnosticsRecorded = false;
    int? statusCode;
    String? requestId;
    try {
      final token = await _sessionTokenProvider.accessToken();
      if (token == null || token.isEmpty) {
        throw const PandoraApiError(
          kind: PandoraApiErrorKind.sessionExpired,
          message: 'Your Pandora session has expired. Sign in again.',
          code: 'SIGN_IN_REQUIRED',
          statusCode: 401,
        );
      }

      final uri = _buildUri(pathSegments, queryParameters);
      final request = http.Request(method, uri)
        ..headers.addAll(<String, String>{
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Organization-Id': organizationId,
        });
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.bodyBytes = utf8.encode(jsonEncode(body));
      }
      if (idempotencyKey != null) {
        request.headers['Idempotency-Key'] = _validatedIdempotencyKey(
          idempotencyKey,
        );
      }

      final streamed =
          await _httpClient.send(request).timeout(_remaining(stopwatch));
      final responseStatusCode = streamed.statusCode;
      statusCode = responseStatusCode;
      requestId = _safeMetadata(streamed.headers['x-request-id']);
      final bytes = await _readResponse(
        streamed,
        method: method,
      ).timeout(_remaining(stopwatch));
      final responseText = utf8.decode(bytes, allowMalformed: false).trim();
      Object? decoded;
      if (responseText.isNotEmpty) {
        try {
          decoded = jsonDecode(responseText);
        } on FormatException {
          if (responseStatusCode >= 200 && responseStatusCode < 300) {
            throw _responseReadError(
              method: method,
              statusCode: responseStatusCode,
              requestId: requestId,
              message: 'Pandora returned an unreadable response.',
              code: 'INVALID_JSON_RESPONSE',
            );
          }
        }
      }
      requestId ??= _requestIdFromBody(decoded);

      if (responseStatusCode < 200 || responseStatusCode >= 300) {
        final responseError = _errorFromResponse(
          statusCode: responseStatusCode,
          decoded: decoded,
          requestId: requestId,
        );
        final error = method == 'POST' && responseStatusCode >= 500
            ? PandoraApiError(
                kind: PandoraApiErrorKind.ambiguousMutation,
                message:
                    'Pandora could not confirm whether that request completed.',
                code: responseError.code,
                statusCode: responseStatusCode,
                requestId: requestId,
              )
            : responseError;
        _recordIfCurrent(
          identityEpoch: identityEpoch,
          occurredAt: startedAt,
          operation: operation,
          method: method,
          routeTemplate: routeTemplate,
          outcome: DiagnosticOutcome.failed,
          duration: stopwatch.elapsed,
          statusCode: responseStatusCode,
          requestId: requestId,
          errorCode: error.code,
        );
        diagnosticsRecorded = true;
        throw error;
      }

      _recordIfCurrent(
        identityEpoch: identityEpoch,
        occurredAt: startedAt,
        operation: operation,
        method: method,
        routeTemplate: routeTemplate,
        outcome: DiagnosticOutcome.succeeded,
        duration: stopwatch.elapsed,
        statusCode: responseStatusCode,
        requestId: requestId,
      );
      diagnosticsRecorded = true;
      return PandoraApiResponse(
        data: decoded,
        statusCode: responseStatusCode,
        duration: stopwatch.elapsed,
        identityEpoch: identityEpoch,
        requestId: requestId,
      );
    } on PandoraApiError catch (error) {
      if (!diagnosticsRecorded) {
        _recordIfCurrent(
          identityEpoch: identityEpoch,
          occurredAt: startedAt,
          operation: operation,
          method: method,
          routeTemplate: routeTemplate,
          outcome: DiagnosticOutcome.failed,
          duration: stopwatch.elapsed,
          statusCode: error.statusCode ?? statusCode,
          requestId: error.requestId ?? requestId,
          errorCode: error.code,
        );
      }
      rethrow;
    } on ArgumentError {
      const error = PandoraApiError(
        kind: PandoraApiErrorKind.invalidRequest,
        message: 'Pandora could not safely send that request.',
        code: 'INVALID_CLIENT_REQUEST',
      );
      _recordTransportFailure(
        identityEpoch,
        startedAt,
        stopwatch,
        operation,
        method,
        routeTemplate,
        error,
        statusCode,
        requestId,
      );
      throw error;
    } on JsonUnsupportedObjectError {
      const error = PandoraApiError(
        kind: PandoraApiErrorKind.invalidRequest,
        message: 'Pandora could not safely encode that request.',
        code: 'INVALID_JSON_REQUEST',
      );
      _recordTransportFailure(
        identityEpoch,
        startedAt,
        stopwatch,
        operation,
        method,
        routeTemplate,
        error,
        statusCode,
        requestId,
      );
      throw error;
    } on TimeoutException {
      final error = _transportError(
        method: method,
        code: 'REQUEST_TIMEOUT',
        message: method == 'POST'
            ? 'Pandora could not confirm whether that request was received.'
            : 'Pandora took too long to respond.',
      );
      _recordTransportFailure(
        identityEpoch,
        startedAt,
        stopwatch,
        operation,
        method,
        routeTemplate,
        error,
        statusCode,
        requestId,
      );
      throw error;
    } on http.ClientException {
      final error = _transportError(
        method: method,
        code: 'NETWORK_UNAVAILABLE',
        message: method == 'POST'
            ? 'Pandora could not confirm whether that request was received.'
            : 'Pandora cannot reach that service right now.',
      );
      _recordTransportFailure(
        identityEpoch,
        startedAt,
        stopwatch,
        operation,
        method,
        routeTemplate,
        error,
        statusCode,
        requestId,
      );
      throw error;
    } on FormatException {
      final error = _responseReadError(
        method: method,
        statusCode: statusCode,
        requestId: requestId,
        message: 'Pandora returned an unreadable response.',
        code: 'INVALID_RESPONSE_ENCODING',
      );
      _recordTransportFailure(
        identityEpoch,
        startedAt,
        stopwatch,
        operation,
        method,
        routeTemplate,
        error,
        statusCode,
        requestId,
      );
      throw error;
    } catch (_) {
      final error = _transportError(
        method: method,
        code: 'PANDORA_CLIENT_FAILURE',
        message: method == 'POST'
            ? 'Pandora could not confirm whether that request was received.'
            : 'Pandora cannot load that information right now.',
      );
      _recordTransportFailure(
        identityEpoch,
        startedAt,
        stopwatch,
        operation,
        method,
        routeTemplate,
        error,
        statusCode,
        requestId,
      );
      throw error;
    } finally {
      stopwatch.stop();
    }
  }

  Future<Uint8List> _readResponse(
    http.StreamedResponse response, {
    required String method,
  }) async {
    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in response.stream) {
      received += chunk.length;
      if (received > maxResponseBytes) {
        throw _responseReadError(
          method: method,
          statusCode: response.statusCode,
          requestId: _safeMetadata(response.headers['x-request-id']),
          message:
              'Pandora returned more data than this screen can safely load.',
          code: 'RESPONSE_TOO_LARGE',
        );
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Uri _buildUri(
    List<String> pathSegments,
    Map<String, String>? queryParameters,
  ) {
    final segments = <String>[
      ...baseUri.pathSegments.where((segment) => segment.isNotEmpty),
      ...pathSegments.map(_validatedPathSegment),
    ];
    final query = queryParameters == null
        ? null
        : <String, String>{
            for (final entry in queryParameters.entries)
              if (entry.key.trim().isNotEmpty) entry.key.trim(): entry.value,
          };
    return baseUri.replace(
      pathSegments: segments,
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  Duration _remaining(Stopwatch stopwatch) {
    final remaining = timeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException('Request timed out.');
    }
    return remaining;
  }

  PandoraApiError _errorFromResponse({
    required int statusCode,
    required Object? decoded,
    required String? requestId,
  }) {
    final json = decoded is Map ? decoded : const <Object?, Object?>{};
    final code = _safeCode(
      json['code']?.toString(),
      fallback: 'HTTP_$statusCode',
    );
    final plainMessage = _safeMessage(
      json['plainMessage']?.toString(),
      fallback: _fallbackMessage(statusCode),
    );
    return PandoraApiError(
      kind: _kindForStatus(statusCode),
      message: plainMessage,
      code: code,
      statusCode: statusCode,
      requestId: requestId,
    );
  }

  PandoraApiError _transportError({
    required String method,
    required String code,
    required String message,
  }) =>
      PandoraApiError(
        kind: method == 'POST'
            ? PandoraApiErrorKind.ambiguousMutation
            : PandoraApiErrorKind.unavailable,
        message: message,
        code: code,
      );

  PandoraApiError _responseReadError({
    required String method,
    required int? statusCode,
    required String? requestId,
    required String message,
    required String code,
  }) {
    final ambiguousMutation =
        method == 'POST' && (statusCode == null || statusCode >= 200);
    return PandoraApiError(
      kind: ambiguousMutation
          ? PandoraApiErrorKind.ambiguousMutation
          : PandoraApiErrorKind.contract,
      message: ambiguousMutation
          ? 'Pandora may have received the request, but this app could not confirm its resulting state.'
          : message,
      code: code,
      statusCode: statusCode,
      requestId: requestId,
    );
  }

  void _recordTransportFailure(
    int identityEpoch,
    DateTime startedAt,
    Stopwatch stopwatch,
    String operation,
    String method,
    String routeTemplate,
    PandoraApiError error,
    int? statusCode,
    String? requestId,
  ) {
    _recordIfCurrent(
      identityEpoch: identityEpoch,
      occurredAt: startedAt,
      operation: operation,
      method: method,
      routeTemplate: routeTemplate,
      outcome: DiagnosticOutcome.failed,
      duration: stopwatch.elapsed,
      statusCode: statusCode,
      requestId: requestId,
      errorCode: error.code,
    );
  }

  void _recordIfCurrent({
    required int identityEpoch,
    required DateTime occurredAt,
    required String operation,
    required String method,
    required String routeTemplate,
    required DiagnosticOutcome outcome,
    required Duration duration,
    int? statusCode,
    String? requestId,
    String? errorCode,
  }) {
    if (identityEpoch != _identityEpoch) return;
    _record(
      occurredAt: occurredAt,
      operation: operation,
      method: method,
      routeTemplate: routeTemplate,
      outcome: outcome,
      duration: duration,
      statusCode: statusCode,
      requestId: requestId,
      errorCode: errorCode,
    );
  }

  void beginAuthenticatedIdentityEpoch() {
    _identityEpoch += 1;
  }

  void _record({
    required DateTime occurredAt,
    required String operation,
    required String method,
    required String routeTemplate,
    required DiagnosticOutcome outcome,
    required Duration duration,
    int? statusCode,
    String? requestId,
    String? errorCode,
  }) {
    _diagnostics.record(
      DiagnosticEvent(
        occurredAt: occurredAt,
        operation: _safeMetadata(operation) ?? 'request',
        method: method,
        routeTemplate: _safeMetadata(routeTemplate) ?? '/unknown',
        outcome: outcome,
        duration: duration,
        statusCode: statusCode,
        requestId: _safeMetadata(requestId),
        errorCode: errorCode == null
            ? null
            : _safeCode(errorCode, fallback: 'UNKNOWN_ERROR'),
      ),
    );
  }

  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }

  /// Records a typed-decoding failure after a successful HTTP response.
  ///
  /// Callers provide only bounded metadata; response payloads are deliberately
  /// not accepted by this API.
  void recordContractFailure({
    required int identityEpoch,
    required String operation,
    required String routeTemplate,
    required int statusCode,
    required String errorCode,
    required Duration duration,
    String? requestId,
  }) {
    _recordIfCurrent(
      identityEpoch: identityEpoch,
      occurredAt: _clock(),
      operation: operation,
      method: 'PARSE',
      routeTemplate: routeTemplate,
      outcome: DiagnosticOutcome.failed,
      duration: duration,
      statusCode: statusCode,
      requestId: requestId,
      errorCode: errorCode,
    );
  }

  static Uri _validatedBaseUri(Uri value) {
    final isLocalHttp = value.scheme == 'http' &&
        const <String>{'localhost', '127.0.0.1', '::1'}.contains(value.host);
    if ((value.scheme != 'https' && !isLocalHttp) ||
        value.host.isEmpty ||
        value.hasQuery ||
        value.hasFragment) {
      throw ArgumentError.value(
        value,
        'baseUri',
        'Use one explicit HTTPS API base without query or fragment.',
      );
    }
    final path = value.path.replaceFirst(RegExp(r'/+$'), '');
    return value.replace(path: path);
  }

  static String _validatedIdempotencyKey(String value) {
    final key = value.trim();
    if (key.isEmpty ||
        key.length > 200 ||
        !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(key)) {
      throw ArgumentError.value(
        value,
        'idempotencyKey',
        'Use 1-200 letters, numbers, dots, underscores, colons, or hyphens.',
      );
    }
    return key;
  }

  static String _validatedPathSegment(String value) {
    final segment = value.trim();
    if (segment.isEmpty ||
        segment == '.' ||
        segment == '..' ||
        segment.length > 500 ||
        segment.contains(RegExp(r'[/\\?#\x00-\x1F\x7F]'))) {
      throw ArgumentError.value(
        value,
        'pathSegment',
        'Path segments must be non-empty and contain no path delimiters.',
      );
    }
    return segment;
  }

  static PandoraApiErrorKind _kindForStatus(int statusCode) =>
      switch (statusCode) {
        400 => PandoraApiErrorKind.invalidRequest,
        401 => PandoraApiErrorKind.sessionExpired,
        403 => PandoraApiErrorKind.forbidden,
        404 => PandoraApiErrorKind.notFound,
        409 => PandoraApiErrorKind.conflict,
        429 => PandoraApiErrorKind.rateLimited,
        _ => statusCode >= 500
            ? PandoraApiErrorKind.unavailable
            : PandoraApiErrorKind.contract,
      };

  static String _fallbackMessage(int statusCode) => switch (statusCode) {
        400 => 'Please check that information and try again.',
        401 => 'Please sign in again.',
        403 => 'You do not have permission for this yet.',
        404 => 'Pandora could not find that item.',
        409 => 'That item changed before Pandora could continue.',
        429 => 'Please wait a moment before trying again.',
        _ => 'Pandora cannot reach that service right now.',
      };

  static String? _requestIdFromBody(Object? decoded) {
    if (decoded is! Map) return null;
    return _safeMetadata(decoded['requestId']?.toString());
  }

  static String _safeMessage(String? value, {required String fallback}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return fallback;
    final sanitized =
        const DiagnosticsSanitizer(maxStringLength: 500).sanitizeText(text);
    return sanitized;
  }

  static String _safeCode(String? value, {required String fallback}) {
    final text = value?.trim().toUpperCase() ?? '';
    if (text.isEmpty || !RegExp(r'^[A-Z0-9_.:-]{1,100}$').hasMatch(text)) {
      return fallback;
    }
    return text;
  }

  static String? _safeMetadata(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final sanitized = text.replaceAll(RegExp(r'[^A-Za-z0-9_./:-]'), '_');
    return sanitized.length <= 200 ? sanitized : sanitized.substring(0, 200);
  }
}
