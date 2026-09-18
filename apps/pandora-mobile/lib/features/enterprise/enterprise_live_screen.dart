import 'package:flutter/material.dart';

import '../../core/data/enterprise_live_repository.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import '../simple/pandora_v2_ui.dart';

class EnterpriseLiveScreen extends StatefulWidget {
  const EnterpriseLiveScreen({
    super.key,
    required this.surface,
    required this.title,
    required this.description,
    required this.icon,
    this.onSelectionChanged,
  });

  final String surface;
  final String title;
  final String description;
  final IconData icon;
  final ValueChanged<Map<String, String>?>? onSelectionChanged;

  @override
  State<EnterpriseLiveScreen> createState() => _EnterpriseLiveScreenState();
}

class _EnterpriseLiveScreenState extends State<EnterpriseLiveScreen> {
  late Future<EnterpriseLiveSnapshot> _snapshot;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _snapshot = const EnterpriseLiveRepository().load(widget.surface);
  }

  Future<void> _refresh() async {
    final next = const EnterpriseLiveRepository().load(widget.surface);
    setState(() => _snapshot = next);
    await next;
  }

  void _select(EnterpriseLiveItem item) {
    final selected = _selectedId == item.id ? null : item;
    setState(() => _selectedId = selected?.id);
    widget.onSelectionChanged?.call(selected?.selection);
  }

  @override
  Widget build(BuildContext context) => PandoraPage(
        title: widget.title,
        subtitle: widget.description,
        onRefresh: _refresh,
        child: FutureBuilder<EnterpriseLiveSnapshot>(
          future: _snapshot,
          builder: (context, async) {
            if (async.connectionState == ConnectionState.waiting &&
                !async.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 64),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            if (async.hasError || !async.hasData) {
              return _error(async.error);
            }
            return _content(async.data!);
          },
        ),
      );

  Widget _content(EnterpriseLiveSnapshot snapshot) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PandoraSurface(
            title: snapshot.title,
            subtitle: snapshot.summary,
            leading: Icon(widget.icon),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (snapshot.partial) ...[
                  Semantics(
                    label:
                        'Partial data. Some connected provider fields are unavailable and are not estimated.',
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: PandoraV2Colors.soft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: PandoraV2Colors.warning),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 19,
                            color: PandoraV2Colors.warning,
                          ),
                          SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              'Partial provider data — unavailable values stay unavailable and are never estimated.',
                              style: TextStyle(height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (snapshot.metrics.isNotEmpty) ...[
                  _metrics(snapshot.metrics),
                  if (snapshot.items.isNotEmpty) const SizedBox(height: 14),
                ],
                if (snapshot.items.isEmpty)
                  _emptyState(snapshot.surface)
                else
                  for (final item in snapshot.items) _item(item),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PandoraSurface(
            title: 'Pandora on this page',
            subtitle: 'Context stays attached to this workspace',
            leading: const Icon(Icons.auto_awesome_rounded),
            child: Text(
              _commandHelp(widget.surface),
              style: const TextStyle(
                color: PandoraV2Colors.muted,
                height: 1.45,
              ),
            ),
          ),
        ],
      );

  Widget _metrics(Map<String, String> metrics) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 720 ? 3 : 2;
          final width = (constraints.maxWidth - ((columns - 1) * 10)) / columns;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final entry in metrics.entries)
                SizedBox(
                  width: width,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 92),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: PandoraV2Colors.soft,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: PandoraV2Colors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.key,
                          style: const TextStyle(
                            color: PandoraV2Colors.muted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          entry.value,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      );

  Widget _item(EnterpriseLiveItem item) {
    final selected = _selectedId == item.id;
    return Semantics(
      button: true,
      selected: selected,
      label: '${item.title}. ${item.subtitle}. Status ${item.status}.',
      child: InkWell(
        key: ValueKey<String>('enterprise-live-item-${item.id}'),
        onTap: () => _select(item),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          margin: const EdgeInsets.only(bottom: 7),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? PandoraV2Colors.soft : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? PandoraV2Colors.ink : PandoraV2Colors.line,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  _statusIcon(item.status),
                  size: 19,
                  color: _statusColor(item.status),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      style: const TextStyle(
                        color: PandoraV2Colors.muted,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                item.status,
                style: TextStyle(
                  color: _statusColor(item.status),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(String surface) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          switch (surface) {
            'enterprise_marketing' =>
              'No persisted marketing drafts yet. Ask Pandora to draft content; publishing remains approval-gated.',
            'enterprise_domains' =>
              'No provider-backed project domains are registered for this organization.',
            'enterprise_agents' =>
              'No independently verified active agent runtime proof is available.',
            'enterprise_workflows' =>
              'No governed workflow run is persisted yet.',
            _ => 'No provider-backed records are available for this surface.',
          },
          style: const TextStyle(
            color: PandoraV2Colors.muted,
            height: 1.4,
          ),
        ),
      );

  Widget _error(Object? error) => PandoraSurface(
        title: '${widget.title} unavailable',
        subtitle: 'No provider state was changed.',
        leading: const Icon(Icons.error_outline_rounded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              error.toString().replaceFirst('EnterpriseLiveException: ', ''),
              style: const TextStyle(color: PandoraV2Colors.muted),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      );

  String _commandHelp(String surface) => switch (surface) {
        'enterprise_data' =>
          'Ask about the selected snapshot or request a bounded comparison. Pandora receives the selected row ID and page scope; unavailable source fields remain unavailable.',
        'enterprise_analytics' =>
          'Ask for comparisons across the verified snapshots shown above. Revenue/ADR/RevPAR are not inferred when the provider has not supplied them.',
        'enterprise_marketing' =>
          'Ask Pandora to prepare a draft. Draft creation is reversible; publishing is a separate consequential action and requires its own authorization.',
        'enterprise_domains' =>
          'Ask about a selected domain, verification or routing state. Purchases and DNS mutations remain consequential provider actions.',
        'enterprise_integrations' =>
          'Ask about a selected source connection or its health. Credentials stay in governed provider storage and are never rendered on this page.',
        'enterprise_security' =>
          'Ask about membership or approval state. Client-side data never includes credential material.',
        'enterprise_agents' =>
          'Ask about verified runtime proofs and capability state. Pandora will not create a fake agent record when no runnable registry contract exists.',
        'enterprise_workflows' =>
          'Ask about a selected persisted run or request a governed workflow through the capability runtime.',
        'enterprise_logs' =>
          'Ask Pandora to summarize the selected redacted audit event or recent operational evidence.',
        'enterprise_api' =>
          'Ask about verified API/provider capabilities, scopes and availability. Secret values remain inaccessible.',
        'enterprise_settings' =>
          'Ask about the selected workspace configuration. Consequential changes require a provider-backed authorization path.',
        'enterprise_mcp' =>
          'Ask about a selected provider/tool connection from the verified runtime registry.',
        _ => 'Ask Pandora about this page.',
      };

  static IconData _statusIcon(String value) {
    final status = value.toLowerCase();
    if (status.contains('healthy') ||
        status.contains('verified') ||
        status.contains('active') ||
        status.contains('completed') ||
        status.contains('recorded')) {
      return Icons.check_circle_outline_rounded;
    }
    if (status.contains('error') ||
        status.contains('failed') ||
        status.contains('denied')) {
      return Icons.error_outline_rounded;
    }
    return Icons.info_outline_rounded;
  }

  static Color _statusColor(String value) {
    final status = value.toLowerCase();
    if (status.contains('healthy') ||
        status.contains('verified') ||
        status.contains('active') ||
        status.contains('completed') ||
        status.contains('recorded')) {
      return PandoraV2Colors.success;
    }
    if (status.contains('error') ||
        status.contains('failed') ||
        status.contains('denied')) {
      return PandoraV2Colors.danger;
    }
    return PandoraV2Colors.warning;
  }
}
