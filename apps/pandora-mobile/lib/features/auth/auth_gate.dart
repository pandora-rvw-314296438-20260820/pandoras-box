import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../app/pandora_shell.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/design/pandora_tokens.dart';
import '../../core/security/pandora_auth.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import 'sign_in_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  GlobalKey<NavigatorState> _authenticatedNavigatorKey =
      GlobalKey<NavigatorState>();
  StreamSubscription<PandoraSession?>? _subscription;
  StreamSubscription<AuthorizationInvalidation>? _authorizationSubscription;
  PandoraAuth? _auth;
  PandoraRepository? _repository;
  String? _sessionUserId;
  AuthorizationInvalidation? _authorizationFailure;
  bool _recheckingAuthorization = false;
  bool _signingOut = false;
  var _authorizationAttempt = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = PandoraDependencies.of(context);
    final auth = dependencies.auth;
    if (!identical(auth, _auth)) {
      _subscription?.cancel();
      _auth = auth;
      _sessionUserId = auth.currentSession?.userId;
      _subscription = auth.changes.listen(
        (session) {
          if (session?.userId != _sessionUserId) {
            final repository = dependencies.repository;
            if (repository is AuthenticatedIdentityBoundary) {
              final identityBoundary =
                  repository as AuthenticatedIdentityBoundary;
              identityBoundary.beginAuthenticatedIdentityEpoch();
            } else {
              repository.clearReadOnlyCache();
            }
            dependencies.diagnostics.clear();
            _sessionUserId = session?.userId;
            _authorizationFailure = null;
            _authorizationAttempt += 1;
            _recheckingAuthorization = false;
            _authenticatedNavigatorKey = GlobalKey<NavigatorState>();
          }
          if (mounted) setState(() {});
        },
        onError: (_) {
          if (mounted) setState(() {});
        },
      );
    }
    final repository = dependencies.repository;
    if (!identical(repository, _repository)) {
      _authorizationSubscription?.cancel();
      _repository = repository;
      if (repository is AuthorizationInvalidationSource) {
        final invalidationSource =
            repository as AuthorizationInvalidationSource;
        _authorizationSubscription = invalidationSource
            .authorizationInvalidations
            .listen((invalidation) {
              dependencies.diagnostics.clear();
              _authorizationFailure = invalidation;
              _authorizationAttempt += 1;
              _recheckingAuthorization = false;
              _authenticatedNavigatorKey = GlobalKey<NavigatorState>();
              if (mounted) setState(() {});
            });
      }
    }
  }

  Future<void> _recheckAuthorization() async {
    if (_recheckingAuthorization) return;
    final failure = _authorizationFailure;
    final userId = _auth?.currentSession?.userId;
    if (failure == null || userId == null) return;
    final attempt = ++_authorizationAttempt;
    setState(() => _recheckingAuthorization = true);
    try {
      await _repository!.home();
      if (!_isCurrentAuthorizationAttempt(attempt, userId)) return;
      _repository!.clearReadOnlyCache();
      setState(() {
        _authorizationFailure = null;
        _authenticatedNavigatorKey = GlobalKey<NavigatorState>();
      });
    } on PandoraRepositoryException catch (error) {
      if (!_isCurrentAuthorizationAttempt(attempt, userId)) return;
      setState(() {
        _authorizationFailure = AuthorizationInvalidation(
          generation: _authorizationFailure?.generation ?? 0,
          kind: error.kind,
          message: error.message,
        );
      });
    } catch (_) {
      if (!_isCurrentAuthorizationAttempt(attempt, userId)) return;
      setState(() {
        _authorizationFailure = AuthorizationInvalidation(
          generation: _authorizationFailure?.generation ?? 0,
          kind: failure.kind,
          message: 'Pandora could not recheck owner access. Try again.',
        );
      });
    } finally {
      if (_isCurrentAuthorizationAttempt(attempt, userId)) {
        setState(() => _recheckingAuthorization = false);
      }
    }
  }

  bool _isCurrentAuthorizationAttempt(int attempt, String userId) =>
      mounted &&
      attempt == _authorizationAttempt &&
      _auth?.currentSession?.userId == userId;

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await _auth!.signOut();
    } on PandoraAuthFailure catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pandora could not sign out. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _authorizationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_auth?.currentSession == null) return const SignInScreen();
    final authorizationFailure = _authorizationFailure;
    if (authorizationFailure != null) {
      return _AuthorizationRecheckScreen(
        message: authorizationFailure.message,
        busy: _recheckingAuthorization || _signingOut,
        onRecheck: _recheckAuthorization,
        onSignOut: _signOut,
      );
    }
    return NavigatorPopHandler(
      onPopWithResult: (_) {
        unawaited(
          _authenticatedNavigatorKey.currentState?.maybePop() ??
              Future<bool>.value(false),
        );
      },
      child: Navigator(
        key: _authenticatedNavigatorKey,
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const PandoraShell(),
        ),
      ),
    );
  }
}

class _AuthorizationRecheckScreen extends StatelessWidget {
  const _AuthorizationRecheckScreen({
    required this.message,
    required this.busy,
    required this.onRecheck,
    required this.onSignOut,
  });

  final String message;
  final bool busy;
  final Future<void> Function() onRecheck;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: PandoraPage(
      title: 'Owner access needs rechecking',
      subtitle: 'Protected content has been cleared while Pandora verifies this session.',
      child: PandoraSurface(
        title: 'Access paused',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message),
            const SizedBox(height: PandoraSpacing.lg),
            FilledButton.icon(
              onPressed: busy ? null : onRecheck,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_user_outlined),
              label: Text(
                busy ? 'Rechecking owner access…' : 'Recheck owner access',
              ),
            ),
            const SizedBox(height: PandoraSpacing.xs),
            TextButton(
              onPressed: busy ? null : onSignOut,
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    ),
  );
}
