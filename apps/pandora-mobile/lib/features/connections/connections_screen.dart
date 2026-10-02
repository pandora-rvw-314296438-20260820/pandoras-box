import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/owner_projection.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/design/pandora_tokens.dart';
import '../../core/models/pandora_models.dart';
import '../../core/network/pandora_api_error.dart';
import '../../core/state/screen_controller.dart';
import '../../core/widgets/content_state.dart';
import '../../core/widgets/owner_experience.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import '../../core/widgets/status_badge.dart';
import '../simple/ask_pandora_screen.dart';
import '../simple/pandora_v2_ui.dart';
import 'connection_presentation.dart';

class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  ScreenController<List<ConnectionSummary>>? _controller;
  UserConnectStatus? _userConnectStatus;
  bool _userConnectBusy = false;
  bool _verifyingAll = false;
  final Set<String> _busyConnections = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final repository = PandoraDependencies.of(context).repository;
    _controller = ScreenController<List<ConnectionSummary>>(
      () => repository.connections(allowCached: true),
    )..load();
    unawaited(_refreshUserConnectStatus(silent: true));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _refreshUserConnectStatus({bool silent = false}) async {
    final repository = PandoraDependencies.of(context).repository;
    final source = repository is UserConnectAuthorizationSource
        ? repository as UserConnectAuthorizationSource
        : null;
    if (source == null) return;
    if (mounted) setState(() => _userConnectBusy = true);
    try {
      final status = await source.userConnectStatus();
      if (!mounted) return;
      setState(() => _userConnectStatus = status);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status.connected
                  ? 'Vercel user access is authorized through Pandora.'
                  : 'Needs your permission to authorize Vercel user access.',
            ),
          ),
        );
      }
    } on PandoraApiError catch (error) {
      if (!mounted || silent) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _userConnectBusy = false);
    }
  }

  Future<void> _authorizeUserConnect() async {
    final repository = PandoraDependencies.of(context).repository;
    final source = repository is UserConnectAuthorizationSource
        ? repository as UserConnectAuthorizationSource
        : null;
    if (source == null) return;
    setState(() => _userConnectBusy = true);
    try {
      final authorization = await source.startUserConnectAuthorization();
      final launched = await launchUrl(
        authorization.authorizationUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            launched
                ? 'Finish authorization in the secure page, then return and verify again.'
                : 'Pandora could not open the secure authorization page.',
          ),
        ),
      );
    } on PandoraApiError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _userConnectBusy = false);
    }
  }

  bool _isVercel(ConnectionSummary connection) =>
      connection.name.toLowerCase().contains('vercel');

  ConnectionCardState _stateFor(ConnectionSummary connection) {
    final providerState = synthesizeConnectionCardState(
      state: connection.state,
      rawStatus: connection.status,
      canUseNow: connection.canRead || connection.canChange,
      accountVerified: connection.canRead || connection.canChange,
      scopesVerified: connection.canRead || connection.canChange,
      capabilityAvailability: <bool>[
        if (connection.canRead || connection.canChange) true,
      ],
    );

    if (_isVercel(connection) &&
        _userConnectStatus?.connected == true &&
        providerState != ConnectionCardState.verified) {
      return ConnectionCardState.partial;
    }

    if (providerState == ConnectionCardState.notConnected &&
        connection.state.trim().toLowerCase() == 'problem') {
      return ConnectionCardState.error;
    }
    return providerState;
  }

  Future<bool> _runVerification(
    ConnectionSummary connection, {
    bool refresh = true,
    bool announce = true,
  }) async {
    final repository = PandoraDependencies.of(context).repository;
    final source = repository is GovernedConnectionActionSource
        ? repository as GovernedConnectionActionSource
        : null;
    if (source == null) return false;

    if (mounted) {
      setState(() => _busyConnections.add(connection.id));
    }
    try {
      await source.runConnectionAction(
        connectionId: connection.id,
        action: 'test',
      );
      if (refresh) await _controller?.refresh();
      if (!mounted) return true;
      if (announce) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${connectionProviderDisplayName(connection.name)} verified through Pandora.',
            ),
          ),
        );
      }
      return true;
    } on PandoraApiError catch (error) {
      if (!mounted) return false;
      if (announce) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _busyConnections.remove(connection.id));
      }
    }
  }

  Future<void> _verifyAll(List<ConnectionSummary> items) async {
    if (_verifyingAll) return;
    setState(() => _verifyingAll = true);
    var succeeded = 0;
    try {
      for (final connection in items) {
        if (await _runVerification(
          connection,
          refresh: false,
          announce: false,
        )) {
          succeeded += 1;
        }
      }
      await _controller?.refresh();
      await _refreshUserConnectStatus(silent: true);
      if (!mounted) return;
      final remaining = items.length - succeeded;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            remaining == 0
                ? 'All ${items.length} connections were verified.'
                : '$succeeded verified · $remaining still need connection or provider support.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _verifyingAll = false);
    }
  }

  Future<void> _connect(ConnectionSummary connection) async {
    final repository = PandoraDependencies.of(context).repository;
    final source = repository is GovernedConnectionActionSource
        ? repository as GovernedConnectionActionSource
        : null;
    if (source == null) {
      _openGovernedConnectionAction(context, connection, 'Connect');
      return;
    }

    setState(() => _busyConnections.add(connection.id));
    try {
      // One owner command owns the sequence: probe current access, prepare the
      // connection/reconnection if needed, then probe again for provider truth.
      try {
        await source.runConnectionAction(
          connectionId: connection.id,
          action: 'test',
        );
      } on PandoraApiError {
        // A failed preflight is expected when authorization is missing.
      }

      await source.runConnectionAction(
        connectionId: connection.id,
        action: connection.state.trim().toLowerCase() == 'problem'
            ? 'reconnect'
            : 'connect',
      );

      try {
        await source.runConnectionAction(
          connectionId: connection.id,
          action: 'test',
        );
      } on PandoraApiError {
        // The governed connect step may require owner authorization first.
      }

      await _controller?.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pandora checked ${connectionProviderDisplayName(connection.name)} and prepared the required connection step.',
          ),
        ),
      );
    } on PandoraApiError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busyConnections.remove(connection.id));
    }
  }

  ThemeData _connectionsTheme(ThemeData base) {
    const scheme = ColorScheme.dark(
      primary: PandoraV2Colors.ink,
      onPrimary: Colors.black,
      primaryContainer: PandoraV2Colors.soft,
      onPrimaryContainer: PandoraV2Colors.ink,
      secondary: PandoraV2Colors.ink,
      onSecondary: Colors.black,
      surface: PandoraV2Colors.surface,
      onSurface: PandoraV2Colors.ink,
      error: PandoraV2Colors.danger,
      onError: Colors.black,
      outline: PandoraV2Colors.line,
      outlineVariant: PandoraV2Colors.line,
    );
    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: PandoraV2Colors.canvas,
      canvasColor: PandoraV2Colors.canvas,
      extensions: const <ThemeExtension<dynamic>>[PandoraPalette.graphite],
      textTheme: base.textTheme.apply(
        bodyColor: PandoraV2Colors.ink,
        displayColor: PandoraV2Colors.ink,
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: PandoraV2Colors.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: PandoraRadius.cardBorder,
          side: const BorderSide(color: PandoraV2Colors.line),
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: PandoraV2Colors.surface,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: PandoraV2Colors.ink),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, PandoraSize.minimumTouchTarget),
          backgroundColor: PandoraV2Colors.ink,
          foregroundColor: Colors.black,
          disabledBackgroundColor: PandoraV2Colors.soft,
          disabledForegroundColor: PandoraV2Colors.muted,
          shape: const RoundedRectangleBorder(
            borderRadius: PandoraRadius.controlBorder,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, PandoraSize.minimumTouchTarget),
          foregroundColor: PandoraV2Colors.ink,
          side: const BorderSide(color: PandoraV2Colors.line),
          shape: const RoundedRectangleBorder(
            borderRadius: PandoraRadius.controlBorder,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: PandoraV2Colors.ink,
          minimumSize: const Size.square(PandoraSize.minimumTouchTarget),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: _connectionsTheme(Theme.of(context)),
        child: Scaffold(
          backgroundColor: PandoraV2Colors.canvas,
          body: PandoraPage(
          title: 'Connections',
          subtitle: 'Provider health, capability, and verified freshness.',
          onRefresh: () async {
            await _controller!.refresh();
            await _refreshUserConnectStatus(silent: true);
          },
          child: AnimatedBuilder(
            animation: _controller!,
            builder: (context, _) {
              final controller = _controller!;
              if (controller.isLoading && controller.data == null) {
                return const ContentSkeleton(lines: 6);
              }
              if (controller.error != null && controller.data == null) {
                return ErrorContent(
                  title: 'Connections could not load',
                  message: controller.error!.message,
                  onRetry: controller.load,
                );
              }

              final items = deduplicateConnections(
                controller.data ?? const <ConnectionSummary>[],
              );
              if (items.isEmpty) {
                return const EmptyContent(
                  title: 'No connections returned',
                  message:
                      'Pandora has not returned a verified connection list.',
                );
              }

              final states = <ConnectionCardState, int>{
                for (final state in ConnectionCardState.values) state: 0,
              };
              for (final connection in items) {
                final state = _stateFor(connection);
                states[state] = (states[state] ?? 0) + 1;
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (controller.degradedReason != null ||
                      controller.error != null) ...[
                    DegradedContentNotice(
                      message:
                          controller.degradedReason ?? controller.error!.message,
                      onRetry: controller.refresh,
                    ),
                    const SizedBox(height: PandoraSpacing.md),
                  ],
                  FilledButton.icon(
                    key: const ValueKey<String>('connections-verify-all'),
                    style: FilledButton.styleFrom(
                      backgroundColor: PandoraV2Colors.ink,
                      foregroundColor: Colors.black,
                    ),
                    onPressed:
                        _verifyingAll ? null : () => _verifyAll(items),
                    icon: _verifyingAll
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_outlined),
                    label: Text('Verify all (${items.length})'),
                  ),
                  const SizedBox(height: PandoraSpacing.sm),
                  _ConnectionHealthBar(
                    verified:
                        states[ConnectionCardState.verified] ?? 0,
                    partial: states[ConnectionCardState.partial] ?? 0,
                    notConnected:
                        states[ConnectionCardState.notConnected] ?? 0,
                    errors: states[ConnectionCardState.error] ?? 0,
                  ),
                  const SizedBox(height: PandoraSpacing.lg),
                  for (var index = 0; index < items.length; index++) ...[
                    _ConnectionCard(
                      connection: items[index],
                      state: _stateFor(items[index]),
                      busy: _verifyingAll ||
                          _busyConnections.contains(items[index].id),
                      userConnectStatus:
                          _isVercel(items[index]) ? _userConnectStatus : null,
                      userConnectBusy:
                          _isVercel(items[index]) && _userConnectBusy,
                      onRefresh: () => _runVerification(items[index]),
                      onConnect: () => _connect(items[index]),
                      onAuthorize: _isVercel(items[index])
                          ? _authorizeUserConnect
                          : null,
                      onCheckUserAccess: _isVercel(items[index])
                          ? () => _refreshUserConnectStatus()
                          : null,
                      onManage: (action) => _openGovernedConnectionAction(
                        context,
                        items[index],
                        action,
                      ),
                    ),
                    if (index != items.length - 1)
                      const SizedBox(height: PandoraSpacing.sm),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
}

class _ConnectionHealthBar extends StatelessWidget {
  const _ConnectionHealthBar({
    required this.verified,
    required this.partial,
    required this.notConnected,
    required this.errors,
  });

  final int verified;
  final int partial;
  final int notConnected;
  final int errors;

  @override
  Widget build(BuildContext context) {
    final palette = context.pandoraPalette;
    return Semantics(
      label:
          '$verified verified, $partial partial, $notConnected not connected, $errors error',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  if (verified > 0)
                    Expanded(
                      flex: verified,
                      child: ColoredBox(color: palette.verified),
                    ),
                  if (partial > 0)
                    Expanded(
                      flex: partial,
                      child: ColoredBox(color: palette.attention),
                    ),
                  if (notConnected > 0)
                    Expanded(
                      flex: notConnected,
                      child: ColoredBox(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  if (errors > 0)
                    Expanded(
                      flex: errors,
                      child: ColoredBox(color: palette.critical),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: PandoraSpacing.xs),
          Text(
            '$verified verified · $partial partial · $notConnected not connected · $errors error',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.connection,
    required this.state,
    required this.busy,
    required this.onRefresh,
    required this.onConnect,
    required this.onManage,
    this.userConnectStatus,
    this.userConnectBusy = false,
    this.onAuthorize,
    this.onCheckUserAccess,
  });

  final ConnectionSummary connection;
  final ConnectionCardState state;
  final bool busy;
  final VoidCallback onRefresh;
  final VoidCallback onConnect;
  final ValueChanged<String> onManage;
  final UserConnectStatus? userConnectStatus;
  final bool userConnectBusy;
  final VoidCallback? onAuthorize;
  final VoidCallback? onCheckUserAccess;

  @override
  Widget build(BuildContext context) {
    final providerName = connectionProviderDisplayName(connection.name);
    final identity = connectionDisplayIdentity(providerName, connection.name);
    final showIdentity =
        identity.isNotEmpty && identity.toLowerCase() != providerName.toLowerCase();
    final checkedLabel = connectionVerificationLabel(
      state: state,
      checkedAt: connection.freshness.lastVerifiedAt,
    );

    return PandoraSurface(
      key: ValueKey<String>('connection-card-${connection.id}'),
      title: providerName,
      leading: Icon(providerIconFor(providerName)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusBadge(
            label: state.label,
            tone: switch (state) {
              ConnectionCardState.verified => PandoraStatusTone.verified,
              ConnectionCardState.partial => PandoraStatusTone.attention,
              ConnectionCardState.notConnected => PandoraStatusTone.neutral,
              ConnectionCardState.error => PandoraStatusTone.critical,
            },
            compact: true,
          ),
          if (state.isConnected) ...[
            const SizedBox(width: PandoraSpacing.xxs),
            SizedBox.square(
              dimension: 48,
              child: IconButton(
                key: ValueKey<String>('connection-refresh-${connection.id}'),
                tooltip: 'Re-verify $providerName',
                onPressed: busy ? null : onRefresh,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
              ),
            ),
          ],
          SizedBox.square(
            dimension: 48,
            child: PopupMenuButton<String>(
              key: ValueKey<String>('connection-more-${connection.id}'),
              tooltip: 'More $providerName actions',
              onSelected: (value) {
                switch (value) {
                  case 'authorize':
                    onAuthorize?.call();
                    break;
                  case 'check-user':
                    onCheckUserAccess?.call();
                    break;
                  default:
                    onManage(value);
                }
              },
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'Manage',
                  child: Text('Manage'),
                ),
                if (onCheckUserAccess != null)
                  const PopupMenuItem<String>(
                    value: 'check-user',
                    child: Text('Check user access'),
                  ),
                if (userConnectStatus?.authorizationRequired == true &&
                    onAuthorize != null)
                  const PopupMenuItem<String>(
                    value: 'authorize',
                    child: Text('Authorize user access'),
                  ),
                if (connection.canRead)
                  const PopupMenuItem<String>(
                    value: 'Disconnect',
                    child: Text('Disconnect'),
                  ),
              ],
              icon: const Icon(Icons.more_horiz_rounded),
            ),
          ),
        ],
      ),
      padding: const EdgeInsets.all(PandoraSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showIdentity) ...[
            Row(
              children: [
                Flexible(
                  child: Text(
                    identity,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (connectionIdentityNeedsTooltip(connection.name)) ...[
                  const SizedBox(width: PandoraSpacing.xxs),
                  Tooltip(
                    message: connection.name,
                    child: Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: PandoraSpacing.xxs),
          ],
          Text(
            checkedLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          if (userConnectStatus != null) ...[
            const SizedBox(height: PandoraSpacing.xxs),
            Text(
              'Pandora user access · ${userConnectBusy ? 'Checking…' : userConnectStatus!.connected ? 'Authorized' : userConnectStatus!.authorizationRequired ? 'Needs permission' : 'Not connected'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          if (!state.isConnected) ...[
            const SizedBox(height: PandoraSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: ValueKey<String>('connection-connect-${connection.id}'),
                onPressed: busy ? null : onConnect,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_link_rounded),
                label: const Text('Connect'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

void _openGovernedConnectionAction(
  BuildContext context,
  ConnectionSummary connection,
  String action,
) {
  final verb = action.toLowerCase();
  final provider = connectionProviderDisplayName(connection.name);
  final prompt = verb == 'disconnect'
      ? 'Disconnect $provider. Verify the impact, affected systems, rollback path, and current provider state first. Prepare the governed change for my approval; do not execute it just because I asked.'
      : 'Review and manage $provider. Test its current health and capabilities, then show me any governed change that needs my approval.';
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AskPandoraScreen(initialPrompt: prompt),
    ),
  );
}
