import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/owner_projection.dart';
import '../../core/data/pandora_intelligence_api.dart';
import '../../core/models/pandora_models.dart';
import '../../core/state/screen_controller.dart';
import '../../core/widgets/owner_experience.dart';
import '../../core/widgets/pandora_navigation.dart';
import '../simple/ask_pandora_screen.dart';
import '../simple/pandora_v2_ui.dart';

class PluginsScreen extends StatefulWidget {
  const PluginsScreen({super.key});

  @override
  State<PluginsScreen> createState() => _PluginsScreenState();
}

class _PluginsScreenState extends State<PluginsScreen> {
  ScreenController<List<ConnectionSummary>>? _controller;
  final TextEditingController _search = TextEditingController();
  String _query = '';
  bool _personal = false;
  bool _runtimeLoading = false;
  List<PandoraCapabilityProvider>? _runtimeProviders;
  DateTime? _runtimeObservedAt;
  String? _runtimeError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final dependencies = PandoraDependencies.of(context);
    _controller = ScreenController<List<ConnectionSummary>>(
      () => dependencies.repository.connections(allowCached: true),
    )..load();
    unawaited(_loadRuntimeRegistry());
  }

  Future<void> _loadRuntimeRegistry() async {
    final intelligence = PandoraDependencies.of(context).intelligence;
    if (intelligence == null) return;
    setState(() {
      _runtimeLoading = true;
      _runtimeError = null;
    });
    try {
      final registry = await intelligence.capabilityRegistry();
      if (!mounted) return;
      setState(() {
        _runtimeProviders = registry.providers;
        _runtimeObservedAt = registry.observedAt;
        _runtimeLoading = false;
      });
    } on PandoraIntelligenceException {
      if (!mounted) return;
      setState(() {
        _runtimeLoading = false;
        _runtimeError = 'Pandora could not verify live plugin details.';
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _controller?.dispose();
    super.dispose();
  }

  List<_PluginViewModel> _items(List<ConnectionSummary> raw) {
    final runtime = _runtimeProviders;
    if (runtime != null && runtime.isNotEmpty) {
      return runtime
          .map(_PluginViewModel.fromRuntime)
          .toList(growable: false);
    }
    return deduplicateConnections(raw)
        .map(_PluginViewModel.fromConnection)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: PandoraV2Colors.canvas,
        body: SafeArea(
          child: AnimatedBuilder(
            animation: _controller!,
            builder: (context, _) {
              final controller = _controller!;
              final items = _items(controller.data ?? const <ConnectionSummary>[]);
              final installed = items
                  .where((item) => item.installed)
                  .toList(growable: false);
              final needsYou = items
                  .where((item) => item.state == 'Needs authorization')
                  .toList(growable: false);
              final available = items.where((item) {
                if (_query.isNotEmpty) {
                  final haystack =
                      '${item.name} ${item.purpose} ${item.state}'.toLowerCase();
                  if (!haystack.contains(_query.toLowerCase())) return false;
                }
                return !_personal || item.accountVerified;
              }).toList(growable: false);

              return RefreshIndicator(
                onRefresh: () async {
                  await Future.wait<void>([
                    controller.refresh(),
                    _loadRuntimeRegistry(),
                  ]);
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                  children: [
                    Row(
                      children: [
                        Builder(
                          builder: (context) {
                            final navigation =
                                PandoraNavigationScope.maybeOf(context);
                            if (navigation?.openDrawer == null) {
                              return const SizedBox(width: 48);
                            }
                            return IconButton(
                              key: const ValueKey<String>(
                                'pandora-side-panel-open',
                              ),
                              tooltip: 'Open navigation',
                              onPressed: navigation!.openDrawer,
                              icon: const Icon(Icons.menu_rounded),
                            );
                          },
                        ),
                        const Expanded(
                          child: Text(
                            'Plugins',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.35,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh plugin state',
                          onPressed: () {
                            unawaited(controller.refresh());
                            unawaited(_loadRuntimeRegistry());
                          },
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _search,
                      onChanged: (value) =>
                          setState(() => _query = value.trim()),
                      decoration: InputDecoration(
                        hintText: 'Search plugins',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _query = '');
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                    if (_runtimeError != null) ...[
                      const SizedBox(height: 12),
                      _RuntimeNotice(
                        message: _runtimeError!,
                        onRetry: _loadRuntimeRegistry,
                      ),
                    ],
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Installed',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_runtimeLoading)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (controller.isLoading &&
                        controller.data == null &&
                        _runtimeProviders == null)
                      const SizedBox(
                        height: 68,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (installed.isEmpty)
                      const Text(
                        'No verified plugins are connected right now.',
                        style: TextStyle(
                          color: PandoraV2Colors.muted,
                          fontSize: 13,
                        ),
                      )
                    else
                      SizedBox(
                        height: 74,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: installed.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) => _InstalledPlugin(
                            plugin: installed[index],
                            onTap: () => _showPlugin(installed[index]),
                          ),
                        ),
                      ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        _FilterChip(
                          label: 'Public',
                          selected: !_personal,
                          onTap: () => setState(() => _personal = false),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'Personal',
                          selected: _personal,
                          onTap: () => setState(() => _personal = true),
                        ),
                      ],
                    ),
                    if (_runtimeObservedAt != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Runtime verified ${_relativeTime(_runtimeObservedAt!)}',
                        style: const TextStyle(
                          color: PandoraV2Colors.muted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    if (!_personal && needsYou.isNotEmpty) ...[
                      const Text(
                        'Needs You',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Only plugins that genuinely need authorization appear here.',
                        style: TextStyle(
                          color: PandoraV2Colors.muted,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final item in needsYou.where((item) {
                        if (_query.isEmpty) return true;
                        final haystack =
                            '${item.name} ${item.purpose}'.toLowerCase();
                        return haystack.contains(_query.toLowerCase());
                      }))
                        _PluginRow(
                          plugin: item,
                          onTap: () => _showPlugin(item),
                        ),
                      const SizedBox(height: 18),
                    ],
                    Text(
                      _personal ? 'Personal plugins' : 'Available plugins',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _personal
                          ? 'Personal plugins appear only when Pandora has verified user-scoped account identity.'
                          : 'Availability comes from Pandora runtime truth, not a hard-coded connected list.',
                      style: const TextStyle(
                        color: PandoraV2Colors.muted,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (controller.error != null &&
                        controller.data == null &&
                        _runtimeProviders == null)
                      _InlineState(
                        icon: Icons.warning_amber_rounded,
                        title: 'Plugin state could not load',
                        message: controller.error!.message,
                        actionLabel: 'Retry',
                        onAction: controller.load,
                      )
                    else if (_personal && available.isEmpty)
                      const _InlineState(
                        icon: Icons.person_outline_rounded,
                        title: 'No verified personal plugins',
                        message:
                            'Pandora has not verified user-scoped account identity for any plugin yet.',
                      )
                    else if (available.isEmpty)
                      const _InlineState(
                        icon: Icons.extension_off_outlined,
                        title: 'No matching plugins',
                        message: 'Try a different search term.',
                      )
                    else
                      for (final item in available)
                        _PluginRow(
                          plugin: item,
                          onTap: () => _showPlugin(item),
                        ),
                  ],
                ),
              );
            },
          ),
        ),
      );

  Future<void> _showPlugin(_PluginViewModel plugin) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: PandoraV2Colors.soft,
                  child: Icon(providerIconFor(plugin.name)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plugin.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        plugin.state,
                        style: const TextStyle(
                          color: PandoraV2Colors.muted,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(plugin.purpose),
            const SizedBox(height: 18),
            _DetailRow(
              label: 'Account',
              value: plugin.accountVerified
                  ? plugin.accountLabel ?? 'Verified account'
                  : 'Not verified',
            ),
            _DetailRow(
              label: 'Health',
              value: plugin.rawStatus,
            ),
            _DetailRow(
              label: 'Last verification',
              value: plugin.lastVerifiedAt == null
                  ? 'Not verified'
                  : _relativeTime(plugin.lastVerifiedAt!),
            ),
            _DetailRow(
              label: 'Scopes',
              value: plugin.scopesVerified
                  ? 'Verified by provider evidence'
                  : 'Not exposed by current verified runtime evidence',
            ),
            const SizedBox(height: 14),
            const Text(
              'Capabilities',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (plugin.actions.isEmpty)
              const Text(
                'No verified actions are exposed.',
                style: TextStyle(color: PandoraV2Colors.muted),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in plugin.actions)
                    _CapabilityChip(action: action),
                ],
              ),
            const SizedBox(height: 14),
            Text(
              plugin.authorization,
              style: const TextStyle(
                color: PandoraV2Colors.muted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            if (plugin.failureMessage != null) ...[
              const SizedBox(height: 12),
              _FailureNotice(message: plugin.failureMessage!),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _openGovernedPluginAction(
                    plugin,
                    plugin.installed
                        ? _PluginAction.manage
                        : plugin.state == 'Problem'
                            ? _PluginAction.reconnect
                            : _PluginAction.connect,
                  );
                },
                icon: Icon(
                  plugin.installed
                      ? Icons.tune_rounded
                      : plugin.state == 'Problem'
                          ? Icons.sync_rounded
                          : Icons.add_link_rounded,
                ),
                label: Text(
                  plugin.installed
                      ? 'Manage in Pandora'
                      : plugin.state == 'Problem'
                          ? 'Reconnect'
                          : 'Connect',
                ),
              ),
            ),
            if (plugin.installed) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _openGovernedPluginAction(
                      plugin,
                      _PluginAction.disconnect,
                    );
                  },
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('Disconnect'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openGovernedPluginAction(
    _PluginViewModel plugin,
    _PluginAction action,
  ) {
    final prompt = switch (action) {
      _PluginAction.manage =>
        'Manage ${plugin.name}. First verify the live connection, account identity, current scopes and capabilities. Use bounded reads when authorized. Route every consequential change through ProjectOS and show me only the approval or blocker that actually needs me.',
      _PluginAction.connect =>
        'Connect ${plugin.name}. Check the live authorization state, exact account and scopes required. If owner authorization is required, show the secure Needs You step. Do not claim this plugin is connected until provider readback verifies it.',
      _PluginAction.reconnect =>
        'Reconnect ${plugin.name}. Verify the current failure first, preserve existing safe state, request only the authorization actually required, then read back provider health. Do not claim recovery until the provider is verified usable.',
      _PluginAction.disconnect =>
        'Disconnect ${plugin.name}. Treat this as a consequential governed action. Show the exact account and capabilities that would be removed, require the appropriate ProjectOS authorization, then verify provider state after the change. Do not disconnect anything else.',
    };
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AskPandoraScreen(initialPrompt: prompt),
      ),
    );
  }
}

enum _PluginAction { manage, connect, reconnect, disconnect }

class _PluginViewModel {
  const _PluginViewModel({
    required this.id,
    required this.name,
    required this.purpose,
    required this.state,
    required this.rawStatus,
    required this.installed,
    required this.accountVerified,
    required this.scopesVerified,
    required this.authorization,
    required this.actions,
    this.accountLabel,
    this.lastVerifiedAt,
    this.failureMessage,
  });

  final String id;
  final String name;
  final String purpose;
  final String state;
  final String rawStatus;
  final bool installed;
  final bool accountVerified;
  final bool scopesVerified;
  final String authorization;
  final List<PandoraCapabilityAction> actions;
  final String? accountLabel;
  final DateTime? lastVerifiedAt;
  final String? failureMessage;

  factory _PluginViewModel.fromRuntime(PandoraCapabilityProvider provider) =>
      _PluginViewModel(
        id: provider.provider,
        name: provider.label,
        purpose: _providerPurpose(provider.provider),
        state: provider.state,
        rawStatus: provider.rawStatus,
        installed: provider.installed,
        accountVerified: provider.accountVerified,
        accountLabel: provider.accountLabel,
        scopesVerified: provider.scopesVerified,
        authorization: provider.authorization,
        actions: provider.actions,
        lastVerifiedAt: provider.lastVerifiedAt,
        failureMessage: provider.failureMessage,
      );

  factory _PluginViewModel.fromConnection(ConnectionSummary connection) {
    final state = resolveOwnerConnectionState(connection);
    final installed = state == OwnerConnectionState.verified &&
        (connection.canRead || connection.canChange);
    return _PluginViewModel(
      id: connection.id,
      name: connection.name,
      purpose: connection.purpose,
      state: state.label,
      rawStatus: connection.status,
      installed: installed,
      accountVerified: false,
      scopesVerified: false,
      authorization: installed
          ? 'Legacy connection summary only. Refresh runtime details before consequential work.'
          : 'Verified authorization is required before Pandora can use this plugin.',
      actions: <PandoraCapabilityAction>[
        if (connection.canRead)
          const PandoraCapabilityAction(
            name: 'read',
            mode: 'read',
            available: true,
          ),
        if (connection.canChange)
          const PandoraCapabilityAction(
            name: 'change',
            mode: 'write',
            available: true,
            approval: 'projectos',
          ),
      ],
      lastVerifiedAt: connection.freshness.lastVerifiedAt,
      failureMessage: installed ? null : 'Live plugin runtime detail is not verified.',
    );
  }
}

class _InstalledPlugin extends StatelessWidget {
  const _InstalledPlugin({required this.plugin, required this.onTap});

  final _PluginViewModel plugin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 62,
          child: Column(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: PandoraV2Colors.soft,
                child: Icon(providerIconFor(plugin.name), size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                plugin.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5),
              ),
            ],
          ),
        ),
      );
}

class _PluginRow extends StatelessWidget {
  const _PluginRow({required this.plugin, required this.onTap});

  final _PluginViewModel plugin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        leading: CircleAvatar(
          backgroundColor: PandoraV2Colors.soft,
          child: Icon(providerIconFor(plugin.name), size: 21),
        ),
        title: Text(
          plugin.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${plugin.purpose}\n${plugin.state}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: plugin.installed
            ? const Icon(Icons.check_circle_rounded, size: 20)
            : plugin.state == 'Needs authorization'
                ? const Icon(Icons.lock_outline_rounded, size: 21)
                : plugin.state == 'Problem'
                    ? const Icon(Icons.warning_amber_rounded, size: 21)
                    : const Icon(Icons.add_circle_outline_rounded, size: 22),
        onTap: onTap,
      );
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({required this.action});

  final PandoraCapabilityAction action;

  @override
  Widget build(BuildContext context) {
    final label = action.name.replaceAll('.', ' · ');
    return Chip(
      avatar: Icon(
        action.available ? Icons.check_rounded : Icons.block_rounded,
        size: 16,
      ),
      label: Text(
        action.approval == null ? label : '$label · approval',
        style: const TextStyle(fontSize: 11.5),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: Text(
                label,
                style: const TextStyle(
                  color: PandoraV2Colors.muted,
                  fontSize: 12.5,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      );
}

class _FailureNotice extends StatelessWidget {
  const _FailureNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
            fontSize: 12.5,
          ),
        ),
      );
}

class _RuntimeNotice extends StatelessWidget {
  const _RuntimeNotice({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: PandoraV2Colors.soft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
            TextButton(
              onPressed: () => unawaited(onRetry()),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? PandoraV2Colors.ink : PandoraV2Colors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: PandoraV2Colors.line),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : PandoraV2Colors.ink,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ),
      );
}

class _InlineState extends StatelessWidget {
  const _InlineState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(icon, size: 30, color: PandoraV2Colors.muted),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: PandoraV2Colors.muted,
                fontSize: 12.5,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 10),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      );
}

String _providerPurpose(String provider) => switch (provider) {
      'github' => 'Repositories, pull requests, source and governed code actions.',
      'supabase' => 'Database and project state through governed Supabase access.',
      'vercel' => 'Deployment state and governed publishing actions.',
      'posthog' => 'Product analytics when query authority is verified.',
      'google_drive' => 'Files and documents through Google Workspace authorization.',
      'google_sheets' => 'Spreadsheets through Google Workspace authorization.',
      _ => 'Provider capability exposed by Pandora runtime truth.',
    };

String _relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value.toLocal());
  if (difference.isNegative) return 'just now';
  if (difference.inMinutes < 1) return 'just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  return '${difference.inDays}d ago';
}
