import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/eurofish_enterprise_shell.dart';
import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/security/pandora_auth.dart';
import 'sign_in_screen.dart';

class EurofishAuthGate extends StatefulWidget {
  const EurofishAuthGate({super.key});

  @override
  State<EurofishAuthGate> createState() => _EurofishAuthGateState();
}

class _EurofishAuthGateState extends State<EurofishAuthGate> {
  GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<PandoraSession?>? _subscription;
  PandoraAuth? _auth;
  String? _sessionUserId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = PandoraDependencies.of(context);
    final auth = dependencies.auth;
    if (identical(auth, _auth)) return;

    _subscription?.cancel();
    _auth = auth;
    _sessionUserId = auth.currentSession?.userId;
    _subscription = auth.changes.listen(
      (session) {
        if (session?.userId != _sessionUserId) {
          final repository = dependencies.repository;
          if (repository is AuthenticatedIdentityBoundary) {
            (repository as AuthenticatedIdentityBoundary)
                .beginAuthenticatedIdentityEpoch();
          } else {
            repository.clearReadOnlyCache();
          }
          dependencies.diagnostics.clear();
          _sessionUserId = session?.userId;
          _navigatorKey = GlobalKey<NavigatorState>();
        }
        if (mounted) setState(() {});
      },
      onError: (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_auth?.currentSession == null) return const SignInScreen();

    return NavigatorPopHandler(
      onPopWithResult: (_) {
        unawaited(
          _navigatorKey.currentState?.maybePop() ??
              Future<bool>.value(false),
        );
      },
      child: Navigator(
        key: _navigatorKey,
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const EurofishEnterpriseShell(),
        ),
      ),
    );
  }
}
