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

abstract interface class PandoraAuth {
  PandoraSession? get currentSession;

  Stream<PandoraSession?> get changes;

  Future<void> signIn({required String email, required String password});

  Future<void> requestPasswordReset(String email);

  Future<void> signOut();
}

class SupabasePandoraAuth implements PandoraAuth {
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
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      throw const PandoraAuthFailure('Pandora could not sign out safely.');
    }
  }
}
