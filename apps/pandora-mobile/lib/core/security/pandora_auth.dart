import 'package:supabase_flutter/supabase_flutter.dart';

class PandoraAuthFailure implements Exception {
  const PandoraAuthFailure(this.message);

  factory PandoraAuthFailure.signInProvider(String providerMessage) =>
      PandoraAuthFailure(_safeSignInMessage(providerMessage));

  factory PandoraAuthFailure.passwordResetProvider(String providerMessage) =>
      PandoraAuthFailure(_safePasswordResetMessage(providerMessage));

  final String message;

  @override
  String toString() => message;
}

String _safeSignInMessage(String providerMessage) {
  final normalized = providerMessage.trim().toLowerCase();
  if (normalized.contains('invalid login credentials') ||
      normalized.contains('invalid credentials')) {
    return 'Email or password is incorrect.';
  }
  if (normalized.contains('email not confirmed')) {
    return 'Confirm your email before signing in.';
  }
  if (normalized.contains('rate limit') ||
      normalized.contains('too many requests')) {
    return 'Too many sign-in attempts. Try again later.';
  }
  return 'Pandora could not sign you in. Check your connection and try again.';
}

String _safePasswordResetMessage(String providerMessage) {
  final normalized = providerMessage.trim().toLowerCase();
  if (normalized.contains('rate limit') ||
      normalized.contains('too many requests')) {
    return 'Too many reset attempts. Try again later.';
  }
  return 'Pandora could not request a password reset. Check your connection and try again.';
}

class PandoraSession {
  const PandoraSession({required this.userId});

  final String userId;
}

class ExtraIdentityFactor {
  const ExtraIdentityFactor({required this.id, required this.label});

  final String id;
  final String label;
}

abstract interface class ExtraIdentityVerificationSource {
  Future<List<ExtraIdentityFactor>> verifiedExtraIdentityFactors();

  Future<void> verifyExtraIdentity({
    required String factorId,
    required String code,
  });
}

abstract interface class PandoraAuth {
  PandoraSession? get currentSession;

  Stream<PandoraSession?> get changes;

  Future<void> signIn({required String email, required String password});

  Future<void> requestPasswordReset(String email);

  Future<void> signOut();
}

class SupabasePandoraAuth
    implements PandoraAuth, ExtraIdentityVerificationSource {
  SupabasePandoraAuth(this._client);

  final SupabaseClient _client;

  @override
  PandoraSession? get currentSession {
    final session = _client.auth.currentSession;
    return session == null ? null : PandoraSession(userId: session.user.id);
  }

  @override
  Stream<PandoraSession?> get changes => _client.auth.onAuthStateChange.map(
        (event) => event.session == null
            ? null
            : PandoraSession(userId: event.session!.user.id),
      );

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (error) {
      throw PandoraAuthFailure.signInProvider(error.message);
    } catch (_) {
      throw const PandoraAuthFailure(
        'Pandora could not sign you in. Check your connection and try again.',
      );
    }
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
    } on AuthException catch (error) {
      throw PandoraAuthFailure.passwordResetProvider(error.message);
    } catch (_) {
      throw const PandoraAuthFailure(
        'Pandora could not request a password reset. Check your connection and try again.',
      );
    }
  }

  @override
  Future<List<ExtraIdentityFactor>> verifiedExtraIdentityFactors() async {
    try {
      final dynamic response = await _client.auth.mfa.listFactors();
      final dynamic rawTotp = response.totp;
      final factors = rawTotp is List ? rawTotp : const <dynamic>[];
      final result = <ExtraIdentityFactor>[];
      for (final dynamic factor in factors) {
        final id = '${factor.id}'.trim();
        final status = '${factor.status}'.toLowerCase();
        if (id.isEmpty || !status.contains('verified')) continue;
        var label = 'Authenticator';
        try {
          final candidate = '${factor.friendlyName}'.trim();
          if (candidate.isNotEmpty && candidate.toLowerCase() != 'null') {
            label = candidate;
          }
        } catch (_) {
          // Friendly names are optional provider metadata.
        }
        result.add(ExtraIdentityFactor(id: id, label: label));
      }
      return List<ExtraIdentityFactor>.unmodifiable(result);
    } on AuthException catch (_) {
      throw const PandoraAuthFailure(
        'Pandora could not verify your extra identity methods.',
      );
    } catch (_) {
      throw const PandoraAuthFailure(
        'Pandora could not verify your extra identity methods.',
      );
    }
  }

  @override
  Future<void> verifyExtraIdentity({
    required String factorId,
    required String code,
  }) async {
    final normalizedFactorId = factorId.trim();
    final normalizedCode = code.trim();
    if (normalizedFactorId.isEmpty || !RegExp(r'^[0-9]{6,8}
).hasMatch(normalizedCode)) {
      throw const PandoraAuthFailure(
        'Enter the current code from your authenticator app.',
      );
    }
    try {
      await _client.auth.mfa.challengeAndVerify(
        factorId: normalizedFactorId,
        code: normalizedCode,
      );
    } on AuthException catch (_) {
      throw const PandoraAuthFailure(
        'That authenticator code was not accepted.',
      );
    } catch (_) {
      throw const PandoraAuthFailure(
        'Pandora could not complete the extra identity check.',
      );
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      throw const PandoraAuthFailure('Pandora could not sign out safely.');
    }
  }
}
