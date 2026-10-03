import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_chat_shell.dart';
import '../../app/pandora_dependencies.dart';
import '../../app/pandora_member_workspace_gate.dart';
import '../../app/pandora_shell.dart';
import '../../core/data/pandora_enterprise_api.dart';
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
  Future<bool>? _ownerAccessFuture;
  var _ownerAccessGeneration = 0;
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
      _beginOwnerAccessCheck();
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
            _beginOwnerAccessCheck();
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

  void _beginOwnerAccessCheck() {
    _ownerAccessGeneration += 1;
    _ownerAccessFuture =
        _sessionUserId == null ? null : _auth!.hasActiveOwnerAccess();
  }

  void _retryOwnerAccess() {
    setState(_beginOwnerAccessCheck);
  }

  Future<void> _recheckAuthorization() async {
    if (_recheckingAuthorization) return;
    final failure = _authorizationFailure;
    final userId = _auth?.currentSession?.userId;
    if (failure == null || userId == null) return;
    final attempt = ++_authorizationAttempt;
    setState(() => _recheckingAuthorization = true);
    try {
      final hasOwnerAccess = await _auth!.hasActiveOwnerAccess();
      if (!_isCurrentAuthorizationAttempt(attempt, userId)) return;
      if (!hasOwnerAccess) {
        _repository!.clearReadOnlyCache();
        setState(() {
          _ownerAccessGeneration += 1;
          _ownerAccessFuture = Future<bool>.value(false);
          _authorizationFailure = null;
          _authenticatedNavigatorKey = GlobalKey<NavigatorState>();
        });
        return;
      }
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
    final session = _auth?.currentSession;
    if (session == null) return const SignInScreen();
    final check = _ownerAccessFuture;
    if (check == null) {
      return _WorkspaceAccessScreen(
        title: 'Checking workspace access',
        message: 'Pandora is verifying your account.',
        busy: true,
        onRecheck: _retryOwnerAccess,
        onSignOut: _signOut,
      );
    }
    return FutureBuilder<bool>(
      key: ValueKey<String>(
        'owner-access-${session.userId}-$_ownerAccessGeneration',
      ),
      future: check,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _WorkspaceAccessScreen(
            title: 'Checking workspace access',
            message: 'Pandora is verifying your account.',
            busy: true,
            onRecheck: _retryOwnerAccess,
            onSignOut: _signOut,
          );
        }
        if (snapshot.hasError) {
          return _WorkspaceAccessScreen(
            title: 'Workspace access could not be checked',
            message: 'Check your connection and try again.',
            busy: _signingOut,
            onRecheck: _retryOwnerAccess,
            onSignOut: _signOut,
          );
        }
        final memberAccess = _auth is PandoraWorkspaceAccessSource
            ? _auth as PandoraWorkspaceAccessSource
            : null;
        if (snapshot.data != true && memberAccess == null) {
          return _WorkspaceAccessScreen(
            title: 'Your account is ready',
            message: "Your Pandora's Box account is signed in. "
                'A workspace invitation is needed before private projects '
                'are available.',
            busy: _signingOut,
            onRecheck: _retryOwnerAccess,
            onSignOut: _signOut,
          );
        }
        final authorizationFailure = _authorizationFailure;
        if (authorizationFailure != null) {
          return _AuthorizationRecheckScreen(
            message: authorizationFailure.message,
            busy: _recheckingAuthorization || _signingOut,
            onRecheck: _recheckAuthorization,
            onSignOut: _signOut,
          );
        }
        final dependencies = PandoraDependencies.of(context);
        final Widget authenticatedHome = snapshot.data != true
            ? PandoraMemberWorkspaceGate(
                auth: _auth!, accessSource: memberAccess!)
            : dependencies.intelligence == null
                ? const PandoraShell()
                : const PandoraChatShell();
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
              builder: (_) => authenticatedHome,
            ),
          ),
        );
      },
    );
  }
}

class _WorkspaceAccessScreen extends StatelessWidget {
  const _WorkspaceAccessScreen({
    required this.title,
    required this.message,
    required this.busy,
    required this.onRecheck,
    required this.onSignOut,
  });

  final String title;
  final String message;
  final bool busy;
  final VoidCallback onRecheck;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: PandoraPage(
          title: title,
          subtitle: 'Signed in to Pandora\'s Box',
          child: PandoraSurface(
            title: 'Workspace access',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(message),
                const SizedBox(height: PandoraSpacing.lg),
                if (busy)
                  const Center(child: CircularProgressIndicator())
                else
                  FilledButton(
                    onPressed: onRecheck,
                    child: const Text('Recheck access'),
                  ),
                const SizedBox(height: PandoraSpacing.xs),
                TextButton(
                  onPressed: onSignOut,
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      );
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
          subtitle:
              'Protected content has been cleared while Pandora verifies this session.',
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
