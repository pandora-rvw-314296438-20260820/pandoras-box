import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../app/plp_enterprise_shell.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/security/pandora_auth.dart';
import 'sign_in_screen.dart';

class PlpAuthGate extends StatefulWidget {
  const PlpAuthGate({super.key});

  @override
  State<PlpAuthGate> createState() => _PlpAuthGateState();
}

class _PlpAuthGateState extends State<PlpAuthGate> {
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
          _navigatorKey.currentState?.maybePop() ?? Future<bool>.value(false),
        );
      },
      child: Navigator(
        key: _navigatorKey,
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const PlpEnterpriseShell(),
        ),
      ),
    );
  }
}
