import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/owner_projection.dart';
import '../../core/models/pandora_models.dart';
import '../../core/state/screen_controller.dart';
import '../../core/widgets/owner_experience.dart';
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final repository = PandoraDependencies.of(context).repository;
    _controller = ScreenController<List<ConnectionSummary>>(
      () => repository.connections(allowCached: true),
    )..load();
  }

  @override
  void dispose() {
    _search.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: PandoraV2Colors.canvas,
        body: SafeArea(
          child: AnimatedBuilder(
            animation: _controller!,
            builder: (context, _) {
              final controller = _controller!;
              final raw = controller.data ?? const <ConnectionSummary>[];
              final items = deduplicateConnections(raw);
              final installed = items
                  .where((item) =>
                      resolveOwnerConnectionState(item) ==
                          OwnerConnectionState.verified &&
                      (item.canRead || item.canChange))
                  .toList(growable: false);
              final visible = items.where((item) {
                if (_query.isEmpty) return true;
                final haystack = '${item.name} ${item.purpose}'.toLowerCase();
                return haystack.contains(_query.toLowerCase());
              }).toList(growable: false);

              return RefreshIndicator(
                onRefresh: () => controller.refresh(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Back to Pandora',
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back_rounded),
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
                          onPressed: controller.refresh,
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
                    const SizedBox(height: 22),
                    const Text(
                      'Installed',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    if (controller.isLoading && controller.data == null)
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
                            connection: installed[index],
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
                    const SizedBox(height: 22),
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
                          ? 'Personal plugins appear here only when Pandora returns verified user-scoped access.'
                          : 'Availability and connection state come from Pandora runtime truth, not a hard-coded catalog.',
                      style: const TextStyle(
                        color: PandoraV2Colors.muted,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (controller.error != null && controller.data == null)
                      _InlineState(
                        icon: Icons.warning_amber_rounded,
                        title: 'Plugin state could not load',
                        message: controller.error!.message,
                        actionLabel: 'Retry',
                        onAction: controller.load,
                      )
                    else if (_personal)
                      const _InlineState(
                        icon: Icons.person_outline_rounded,
                        title: 'No personal plugins returned',
                        message:
                            'This plugin needs verified authorization before Pandora can use it. Personal plugins appear here only after user-scoped access is verified.',
                      )
                    else if (visible.isEmpty)
                      const _InlineState(
                        icon: Icons.extension_off_outlined,
                        title: 'No matching plugins',
                        message: 'Try a different search term.',
                      )
                    else
                      for (final item in visible)
                        _PluginRow(
                          connection: item,
                          onTap: () => _showPlugin(item),
                        ),
                  ],
                ),
              );
            },
          ),
        ),
      );

  Future<void> _showPlugin(ConnectionSummary connection) async {
    final state = resolveOwnerConnectionState(connection);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: PandoraV2Colors.soft,
                  child: Icon(providerIconFor(connection.name)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connection.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        state.label,
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
            Text(connection.purpose),
            const SizedBox(height: 14),
            Text(
              connection.canChange
                  ? 'Verified access: read and change'
                  : connection.canRead
                      ? 'Verified access: read only'
                      : 'Verified access is not currently available',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _openGovernedPluginAction(connection);
                },
                icon: Icon(connection.canRead
                    ? Icons.tune_rounded
                    : Icons.add_link_rounded),
                label:
                    Text(connection.canRead ? 'Manage in Pandora' : 'Connect'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openGovernedPluginAction(ConnectionSummary connection) {
    final state = resolveOwnerConnectionState(connection);
    final prompt = state == OwnerConnectionState.verified
        ? 'Manage ${connection.name}. First verify the live connection and current capabilities. Use the plugin for bounded reads when authorized. Route any consequential change through ProjectOS and show me only the approval or blocker that actually needs me.'
        : 'Connect ${connection.name}. Check the live authorization state and exact scopes required. If owner authorization is required, show me the secure Needs You step. Do not claim this plugin is connected until provider readback verifies it.';
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AskPandoraScreen(initialPrompt: prompt),
      ),
    );
  }
}

class _InstalledPlugin extends StatelessWidget {
  const _InstalledPlugin({required this.connection, required this.onTap});

  final ConnectionSummary connection;
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
                child: Icon(providerIconFor(connection.name), size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                connection.name,
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
  const _PluginRow({required this.connection, required this.onTap});

  final ConnectionSummary connection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = resolveOwnerConnectionState(connection);
    final connected = state == OwnerConnectionState.verified &&
        (connection.canRead || connection.canChange);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      leading: CircleAvatar(
        backgroundColor: PandoraV2Colors.soft,
        child: Icon(providerIconFor(connection.name), size: 21),
      ),
      title: Text(
        connection.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        connection.purpose,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: connected
          ? const Icon(Icons.check_circle_rounded, size: 20)
          : const Icon(Icons.add_circle_outline_rounded, size: 22),
      onTap: onTap,
    );
  }
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
