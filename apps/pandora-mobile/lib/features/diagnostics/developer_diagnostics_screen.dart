import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/design/pandora_tokens.dart';
import '../../core/diagnostics/diagnostic_event.dart';
import '../../core/widgets/detail_row.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import '../../pandora_config.dart';

class DeveloperDiagnosticsScreen extends StatefulWidget {
  const DeveloperDiagnosticsScreen({super.key});

  @override
  State<DeveloperDiagnosticsScreen> createState() =>
      _DeveloperDiagnosticsScreenState();
}

class _DeveloperDiagnosticsScreenState extends State<DeveloperDiagnosticsScreen>
    with WidgetsBindingObserver {
  static const _authorizationTtl = Duration(seconds: 30);
  static const _authorizationRequestTimeout = Duration(seconds: 8);

  Future<bool>? _authorization;
  Timer? _authorizationTimer;
  String? _sessionUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = PandoraDependencies.of(context).auth.currentSession?.userId;
    if (_authorization == null || userId != _sessionUserId) {
      _sessionUserId = userId;
      _startAuthorizationCheck(notify: false);
    }
  }

  Future<bool> _verifyOwnerAccess() async {
    final dependencies = PandoraDependencies.of(context);
    if (dependencies.auth.currentSession == null) return false;
    try {
      await dependencies.repository.home().timeout(
            _authorizationRequestTimeout,
          );
      return true;
    } catch (_) {
      return false;
    }
  }

  void _startAuthorizationCheck({required bool notify}) {
    _authorizationTimer?.cancel();
    final check = _verifyOwnerAccess();
    void assign() {
      _authorization = check;
    }

    if (notify) {
      setState(assign);
    } else {
      assign();
    }
    check.then((allowed) {
      if (!mounted || !identical(_authorization, check) || !allowed) return;
      _authorizationTimer = Timer(_authorizationTtl, _retryAuthorization);
    });
  }

  void _retryAuthorization() {
    if (mounted) _startAuthorizationCheck(notify: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _retryAuthorization();
  }

  @override
  void dispose() {
    _authorizationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = PandoraDependencies.of(context);
    if (dependencies.auth.currentSession == null) {
      return const PandoraPage(
        title: 'Developer diagnostics',
        child: PandoraSurface(
          title: 'Authentication required',
          child: Text('Sign in again before viewing diagnostic metadata.'),
        ),
      );
    }
    return FutureBuilder<bool>(
      future: _authorization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const PandoraPage(
            title: 'Developer diagnostics',
            child: PandoraSurface(
              title: 'Checking owner access',
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: PandoraSpacing.md),
                  Expanded(
                    child: Text(
                      'Verifying this session before diagnostic metadata is shown.',
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.data != true) {
          return PandoraPage(
            title: 'Developer diagnostics',
            child: PandoraSurface(
              title: 'Owner access could not be verified',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Diagnostic metadata stays hidden until the live owner '
                    'API verifies this session and organization.',
                  ),
                  const SizedBox(height: PandoraSpacing.md),
                  OutlinedButton(
                    onPressed: _retryAuthorization,
                    child: const Text('Verify owner access'),
                  ),
                ],
              ),
            ),
          );
        }
        return _buildAuthorized(context, dependencies);
      },
    );
  }

  Widget _buildAuthorized(
    BuildContext context,
    PandoraDependencies dependencies,
  ) {
    final diagnostics = dependencies.diagnostics;
    final events = diagnostics.events;
    return PandoraPage(
      title: 'Developer diagnostics',
      subtitle:
          'Temporary support metadata. Credentials, request bodies, and raw responses are never stored here.',
      actions: [
        IconButton(
          tooltip: 'Reverify and refresh diagnostics',
          onPressed: _retryAuthorization,
          icon: const Icon(Icons.refresh_rounded),
        ),
        IconButton(
          tooltip: 'Clear diagnostics',
          onPressed: events.isEmpty ? null : () => setState(diagnostics.clear),
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PandoraSurface(
            title: 'Runtime',
            child: Column(
              children: [
                DetailRow(
                  label: 'App version',
                  value: PandoraConfig.appVersion,
                ),
                DetailRow(
                  label: 'Source revision',
                  value: PandoraConfig.sourceRevision,
                ),
                DetailRow(
                  label: 'Endpoint',
                  value: PandoraConfig.ownerApiEndpointLabel,
                ),
                DetailRow(
                  label: 'Organization',
                  value: PandoraConfig.organizationId,
                ),
              ],
            ),
          ),
          const SizedBox(height: PandoraSpacing.md),
          if (events.isEmpty)
            const PandoraSurface(
              title: 'No diagnostic events',
              child: Text('Use Pandora, then refresh this page.'),
            )
          else
            for (var index = 0; index < events.length; index++) ...[
              _DiagnosticEventCard(event: events[index]),
              if (index != events.length - 1)
                const SizedBox(height: PandoraSpacing.sm),
            ],
        ],
      ),
    );
  }
}

class _DiagnosticEventCard extends StatelessWidget {
  const _DiagnosticEventCard({required this.event});

  final DiagnosticEvent event;

  @override
  Widget build(BuildContext context) {
    final status = event.statusCode?.toString() ?? 'No response';
    return PandoraSurface(
      title: event.operation,
      subtitle: '${event.method} ${event.routeTemplate}',
      child: Column(
        children: [
          DetailRow(label: 'Outcome', value: event.outcome.name),
          DetailRow(label: 'Status', value: status),
          DetailRow(
            label: 'Duration',
            value: '${event.duration.inMilliseconds} ms',
          ),
          if (event.requestId != null)
            DetailRow(label: 'Request ID', value: event.requestId!),
          if (event.errorCode != null)
            DetailRow(label: 'Error code', value: event.errorCode!),
          DetailRow(
            label: 'Observed',
            value: event.occurredAt.toLocal().toIso8601String(),
          ),
        ],
      ),
    );
  }
}
