import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/owner_projection.dart';
import '../../core/data/pandora_intelligence_api.dart';
import '../simple/ask_pandora_screen.dart';
import '../simple/pandora_v2_ui.dart';

class ProviderCatalogScreen extends StatefulWidget {
  const ProviderCatalogScreen({super.key});

  @override
  State<ProviderCatalogScreen> createState() => _ProviderCatalogScreenState();
}

class _ProviderCatalogScreenState extends State<ProviderCatalogScreen> {
  final TextEditingController _search = TextEditingController();
  Future<List<PandoraProviderCatalogEntry>>? _catalog;
  String _query = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _catalog ??= _loadCatalog();
  }

  Future<List<PandoraProviderCatalogEntry>> _loadCatalog() async {
    final intelligence = PandoraDependencies.of(context).intelligence;
    if (intelligence == null) {
      throw const PandoraIntelligenceException(
        'Pandora provider discovery is not available in this session.',
      );
    }
    return intelligence.providerCatalog();
  }

  void _refresh() {
    setState(() {
      _catalog = _loadCatalog();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: PandoraV2Colors.canvas,
        appBar: AppBar(
          backgroundColor: PandoraV2Colors.canvas,
          surfaceTintColor: Colors.transparent,
          title: const Text('Provider Catalog'),
          actions: [
            IconButton(
              tooltip: 'Refresh provider catalog',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: FutureBuilder<List<PandoraProviderCatalogEntry>>(
            future: _catalog,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _CatalogState(
                  icon: Icons.warning_amber_rounded,
                  title: 'Provider catalog could not load',
                  message:
                      'Pandora could not verify the live provider catalog.',
                  actionLabel: 'Retry',
                  onAction: _refresh,
                );
              }

              final source = (snapshot.data ??
                      const <PandoraProviderCatalogEntry>[])
                  .where((entry) => entry.isDiscoverable)
                  .toList(growable: false);
              final items = source.where((entry) {
                if (_query.isEmpty) return true;
                final haystack = [
                  entry.displayName,
                  entry.providerKey,
                  entry.lifecycleState,
                  entry.activationState ?? '',
                  ...entry.capabilities.map((item) => item.capabilityKey),
                ].join(' ').toLowerCase();
                return haystack.contains(_query.toLowerCase());
              }).toList(growable: false);

              return RefreshIndicator(
                onRefresh: () async {
                  _refresh();
                  await _catalog;
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                  children: [
                    const Text(
                      'Universal provider marketplace',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${source.length} provider${source.length == 1 ? '' : 's'} are discoverable. Availability never means connected: Pandora still requires authorization, consent, live health and provider-backed readback before use.',
                      style: const TextStyle(
                        color: PandoraV2Colors.muted,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _search,
                      onChanged: (value) =>
                          setState(() => _query = value.trim()),
                      decoration: InputDecoration(
                        hintText: 'Search providers or capabilities',
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
                    const SizedBox(height: 18),
                    if (items.isEmpty)
                      const _CatalogState(
                        icon: Icons.extension_off_outlined,
                        title: 'No matching providers',
                        message:
                            'Try a provider name or capability such as repository, database, deployment, drive, ads, delivery or AI.',
                      )
                    else
                      for (final entry in items)
                        _ProviderCatalogRow(
                          entry: entry,
                          onTap: () => _showProvider(entry),
                        ),
                  ],
                ),
              );
            },
          ),
        ),
      );

  Future<void> _showProvider(PandoraProviderCatalogEntry entry) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: PandoraV2Colors.soft,
                  child: Icon(providerIconFor(entry.displayName)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.displayName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        _providerState(entry),
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
            const SizedBox(height: 18),
            _CatalogDetail(label: 'Authentication', value: entry.authScheme),
            _CatalogDetail(
              label: 'Regions',
              value: entry.regions.isEmpty ? 'Not declared' : entry.regions.join(', '),
            ),
            _CatalogDetail(
              label: 'Data residency',
              value: entry.dataResidency.isEmpty
                  ? 'Not declared'
                  : entry.dataResidency.join(', '),
            ),
            _CatalogDetail(
              label: 'Verification',
              value: entry.lastVerifiedAt == null
                  ? 'Not currently verified'
                  : _relativeTime(entry.lastVerifiedAt!),
            ),
            const SizedBox(height: 12),
            const Text(
              'Capabilities',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (entry.capabilities.isEmpty)
              const Text(
                'No current capabilities are published.',
                style: TextStyle(color: PandoraV2Colors.muted),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final capability in entry.capabilities)
                    Chip(
                      avatar: Icon(
                        capability.operationMode == 'write'
                            ? Icons.edit_note_rounded
                            : Icons.visibility_outlined,
                        size: 16,
                      ),
                      label: Text(
                        capability.capabilityKey,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  _openGovernedProviderAction(entry);
                },
                icon: Icon(
                  entry.isAuthorized && entry.isHealthy
                      ? Icons.fact_check_outlined
                      : Icons.add_link_rounded,
                ),
                label: Text(
                  entry.isAuthorized && entry.isHealthy
                      ? 'Verify current access'
                      : 'Connect through Pandora',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openGovernedProviderAction(PandoraProviderCatalogEntry entry) {
    final prompt = entry.isAuthorized && entry.isHealthy
        ? 'Verify ${entry.displayName} from Pandora\'s Universal provider catalog. Confirm the current provider account, scopes, consent, capability grants and live health through provider-backed readback. Do not claim connected or usable from catalog metadata alone.'
        : 'Connect ${entry.displayName} from Pandora\'s Universal provider catalog. Verify the exact account, authorization scopes, consent requirements, capability grants and live provider health. Use Pandora\'s governed credential boundary and do not claim connected until provider-backed readback succeeds.';
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AskPandoraScreen(initialPrompt: prompt),
      ),
    );
  }
}

class _ProviderCatalogRow extends StatelessWidget {
  const _ProviderCatalogRow({
    required this.entry,
    required this.onTap,
  });

  final PandoraProviderCatalogEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: PandoraV2Colors.soft,
          child: Icon(providerIconFor(entry.displayName), size: 21),
        ),
        title: Text(
          entry.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${_providerState(entry)} · ${entry.capabilities.length} capabilit${entry.capabilities.length == 1 ? 'y' : 'ies'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );
}

class _CatalogDetail extends StatelessWidget {
  const _CatalogDetail({required this.label, required this.value});

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

class _CatalogState extends StatelessWidget {
  const _CatalogState({
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
        padding: const EdgeInsets.symmetric(vertical: 42),
        child: Column(
          children: [
            Icon(icon, size: 30, color: PandoraV2Colors.muted),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: PandoraV2Colors.muted,
                fontSize: 12.5,
                height: 1.4,
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

String _providerState(PandoraProviderCatalogEntry entry) {
  if (entry.isAuthorized && entry.isHealthy) return 'Authorized · healthy';
  if (entry.isAuthorized) {
    return 'Authorized · ${entry.healthState ?? 'verification required'}';
  }
  if (entry.lifecycleState == 'deprecated') return 'Deprecated';
  return 'Available · authorization required';
}

String _relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value.toLocal());
  if (difference.isNegative || difference.inMinutes < 1) return 'just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  return '${difference.inDays}d ago';
}
