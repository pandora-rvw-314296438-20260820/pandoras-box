import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_shared_conversation_scope.dart';
import 'package:pandora_mobile/core/network/pandora_api_error.dart';

void main() {
  test('Lane E H maps all required failure states to customer-safe copy', () {
    const codes = <String>[
      'provider_unavailable',
      'network_interruption',
      'authentication_failed',
      'connection_expired',
      'ai_unavailable',
      'partial_execution',
      'invalid_request',
    ];
    for (final code in codes) {
      final message = pandoraNaturalFailureMessage(code);
      expect(message, isNotEmpty, reason: code);
      expect(message, isNot(contains('HTTP')), reason: code);
      expect(message, isNot(contains('requestId')), reason: code);
      expect(message, isNot(contains('stack')), reason: code);
      expect(message, isNot(contains('503')), reason: code);
    }
  });

  test('Lane E H classifies API failures without exposing telemetry', () {
    const expired = PandoraApiError(
      kind: PandoraApiErrorKind.sessionExpired,
      message: 'raw',
      code: 'RAW_AUTH_CODE',
      statusCode: 401,
      requestId: 'internal-request-id',
    );
    const partial = PandoraApiError(
      kind: PandoraApiErrorKind.ambiguousMutation,
      message: 'raw',
      code: 'RAW_UNKNOWN_OUTCOME',
      statusCode: 500,
      requestId: 'internal-request-id',
    );
    expect(pandoraFailureCodeForApiError(expired), 'authentication_failed');
    expect(pandoraFailureCodeForApiError(partial), 'partial_execution');
    expect(
      pandoraNaturalFailureMessage(pandoraFailureCodeForApiError(expired)),
      isNot(contains('RAW_AUTH_CODE')),
    );
  });
}
