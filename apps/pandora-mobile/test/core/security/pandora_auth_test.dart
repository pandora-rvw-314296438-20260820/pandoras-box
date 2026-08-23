import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/security/pandora_auth.dart';

void main() {
  group('PandoraAuthFailure provider sanitization', () {
    test('maps invalid credentials without exposing provider text', () {
      final failure = PandoraAuthFailure.signInProvider(
        'Invalid login credentials',
      );

      expect(failure.message, 'Email or password is incorrect.');
    });

    test('maps unconfirmed email to an app-owned message', () {
      final failure = PandoraAuthFailure.signInProvider('Email not confirmed');

      expect(failure.message, 'Confirm your email before signing in.');
    });

    test('does not expose wrapped network exception details', () {
      const providerMessage =
          'ClientException: SocketException: Failed host lookup: api.example.test '
          '(OS Error: No address associated with hostname), '
          'uri=https://api.example.test/auth/v1/token?grant_type=password';

      final failure = PandoraAuthFailure.signInProvider(providerMessage);

      expect(
        failure.message,
        'Pandora could not sign you in. Check your connection and try again.',
      );
      expect(failure.message, isNot(contains('SocketException')));
      expect(failure.message, isNot(contains('https://')));
      expect(failure.message, isNot(contains('api.example.test')));
    });

    test('sanitizes password reset provider failures', () {
      final failure = PandoraAuthFailure.passwordResetProvider(
        'ClientException: uri=https://api.example.test/auth/v1/recover',
      );

      expect(
        failure.message,
        'Pandora could not request a password reset. '
        'Check your connection and try again.',
      );
      expect(failure.message, isNot(contains('https://')));
    });
  });
}
