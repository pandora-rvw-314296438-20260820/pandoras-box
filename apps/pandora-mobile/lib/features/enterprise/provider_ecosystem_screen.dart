import 'package:flutter/material.dart';

import '../../app/pandora_shared_conversation_scope.dart';
import '../../core/widgets/pandora_editorial_scope.dart';
import '../../core/widgets/pandora_navigation.dart';
import '../simple/pandora_v2_ui.dart';

part 'provider_ecosystem_widgets.dart';
part 'provider_ecosystem_catalog.dart';

class ProviderEcosystemScreen extends StatefulWidget {
  const ProviderEcosystemScreen({
    super.key,
    required this.onOpenConnections,
  });

  final VoidCallback onOpenConnections;

  @override
  State<ProviderEcosystemScreen> createState() =>
      _ProviderEcosystemScreenState();
}

class _ProviderEcosystemScreenState extends State<ProviderEcosystemScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<_CapabilityFamily> get _filteredFamilies {
    final query = _query.toLowerCase();
    if (query.isEmpty) return _capabilityFamilies;
    return _capabilityFamilies.where((family) {
      final haystack =
          '${family.name} ${family.providers.join(' ')}'.toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final families = _filteredFamilies;
    return Scaffold(
      backgroundColor: pandoraOwnerColor(context, PandoraV2Colors.canvas),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
          children: [
            Row(
              children: [
                Builder(
                  builder: (context) {
                    final navigation = PandoraNavigationScope.maybeOf(context);
                    if (navigation?.openDrawer == null) {
                      return const SizedBox(width: 48);
                    }
                    return PandoraMenuButton(
                      key: const ValueKey<String>(
                        'provider-ecosystem-side-panel-open',
                      ),
                      onPressed: navigation!.openDrawer!,
                    );
                  },
                ),
                const Expanded(
                  child: Text(
                    'Capabilities & Providers',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.35,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Open live connections',
                  onPressed: widget.onOpenConnections,
                  icon: const Icon(Icons.link_rounded),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: pandoraOwnerColor(context, PandoraV2Colors.surface),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: pandoraOwnerColor(context, PandoraV2Colors.line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'One Pandora · 15 capability families',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.25,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Providers sit underneath the capability layer. Catalog presence never means connected or executable.',
                    style: TextStyle(
                      color: pandoraOwnerColor(context, PandoraV2Colors.muted),
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Outcome examples',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: widget.onOpenConnections,
                  icon: const Icon(Icons.verified_user_outlined, size: 18),
                  label: const Text('Live connections'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 112,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _outcomes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) => _OutcomeCard(
                  outcome: _outcomes[index],
                ),
              ),
            ),
            const SizedBox(height: 22),
            TextField(
              key: const ValueKey<String>('provider-ecosystem-search'),
              controller: _search,
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: InputDecoration(
                hintText: 'Search capability or provider',
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
              'Capability map',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -.2,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Tap a capability to inspect its provider catalog.',
              style: TextStyle(
                color: pandoraOwnerColor(context, PandoraV2Colors.muted),
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 12),
            if (families.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  children: [
                    Icon(
                      Icons.search_off_rounded,
                      color: pandoraOwnerColor(context, PandoraV2Colors.muted),
                      size: 30,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'No matching capability or provider',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              )
            else
              for (final family in families)
                _CapabilityTile(
                  family: family,
                  onTap: () => _showFamily(family),
                ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: pandoraOwnerColor(context, PandoraV2Colors.soft),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.add_circle_outline_rounded, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Future providers plug into these capabilities instead of creating another Pandora interface.',
                      style: TextStyle(fontSize: 12.5, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFamily(_CapabilityFamily family) async {
    PandoraSharedConversationScope.maybeOf(context)?.bindSelectedObject(
      <String, String>{
        'recordType': 'capability_family',
        'capabilityFamily': family.name,
      },
    );
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
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: pandoraOwnerColor(context, PandoraV2Colors.soft),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(family.icon, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    family.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'These are provider candidates under this capability. Pandora verifies authorization, account scope, jurisdiction, provider health and availability before execution.',
              style: TextStyle(
                color: pandoraOwnerColor(context, PandoraV2Colors.muted),
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            for (final provider in family.providers)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.apartment_rounded, size: 19),
                title: Text(provider),
                trailing: Text(
                  'Catalog',
                  style: TextStyle(
                    color: pandoraOwnerColor(context, PandoraV2Colors.muted),
                    fontSize: 11.5,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  widget.onOpenConnections();
                },
                icon: const Icon(Icons.link_rounded),
                label: const Text('Open live connections'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
