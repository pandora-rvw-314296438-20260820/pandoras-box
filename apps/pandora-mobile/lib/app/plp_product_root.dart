import 'package:flutter/material.dart';

import '../core/data/pandora_core_api.dart';
import '../features/enterprise/plp_editorial_surfaces.dart';
import 'pandora_chat_shell.dart';
import 'plp_enterprise_shell.dart';
import 'plp_product_scope.dart';

/// Opens Pandora owner surfaces for a verified operator, and the existing
/// Pueblo La Perla workspace for everyone else. Authorization stays on the
/// Core RPC. This widget does not grant access.
class PlpProductRoot extends StatefulWidget {
  const PlpProductRoot({super.key, this.gateway});

  final PandoraCoreGateway? gateway;

  @override
  State<PlpProductRoot> createState() => _PlpProductRootState();
}

class _PlpProductRootState extends State<PlpProductRoot> {
  late final PandoraCoreGateway _gateway =
      widget.gateway ?? SupabasePandoraCoreGateway();
  Future<PlpProductScope>? _scope;
  bool _openResort = false;

  @override
  void initState() {
    super.initState();
    _scope = _resolve();
  }

  Future<PlpProductScope> _resolve() async {
    try {
      final snapshot = await _gateway.snapshot('home');
      return plpProductScopeFromSnapshot(snapshot);
    } on PandoraCoreFailure catch (error) {
      if (plpCoreFailureIsCustomerScope(error)) {
        return PlpProductScope.customerWorkspace;
      }
      rethrow;
    }
  }

  void _retry() {
    setState(() {
      _openResort = false;
      _scope = _resolve();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_openResort) return const PlpEnterpriseShell();
    return FutureBuilder<PlpProductScope>(
      future: _scope,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _PlpScopeWait(
            title: 'Pandora',
            message: 'Checking which workspace this sign-in can open.',
          );
        }
        if (snapshot.hasError) {
          return _PlpScopeWait(
            title: 'Pandora',
            message:
                'Pandora could not verify operator access. The resort workspace is still available.',
            onRetry: _retry,
            onResort: () => setState(() => _openResort = true),
          );
        }
        if (snapshot.data == PlpProductScope.pandoraOwner) {
          return PandoraChatShell(
            startPage: PandoraStartPage.home,
            coreGateway: _gateway,
            mirrorPlpNavigation: true,
          );
        }
        return const PlpEnterpriseShell();
      },
    );
  }
}

class _PlpScopeWait extends StatelessWidget {
  const _PlpScopeWait({
    required this.title,
    required this.message,
    this.onRetry,
    this.onResort,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onResort;

  @override
  Widget build(BuildContext context) => Material(
        color: plpCanvas,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: plpInk,
                    fontFamily: 'serif',
                    fontSize: 16,
                    letterSpacing: 2.6,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  message,
                  style: const TextStyle(
                    color: plpMuted,
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
                if (onRetry == null) ...[
                  const SizedBox(height: 28),
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
                if (onRetry != null) ...[
                  const SizedBox(height: 22),
                  TextButton(onPressed: onRetry, child: const Text('Retry')),
                ],
                if (onResort != null)
                  TextButton(
                    key: const ValueKey('plp-open-resort-workspace'),
                    onPressed: onResort,
                    child: const Text('Open Pueblo La Perla'),
                  ),
              ],
            ),
          ),
        ),
      );
}
