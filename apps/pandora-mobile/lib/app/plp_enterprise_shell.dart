import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/enterprise/enterprise_vision_screen.dart';
import '../features/enterprise/plp_enterprise_home.dart';
import '../features/operations/operations_room_screen.dart';
import '../features/settings/local_ai_settings_screen.dart';
import '../features/simple/ask_pandora_screen.dart';

class PlpEnterpriseShell extends StatefulWidget {
  const PlpEnterpriseShell({super.key});

  @override
  State<PlpEnterpriseShell> createState() => _PlpEnterpriseShellState();
}

class _PlpEnterpriseShellState extends State<PlpEnterpriseShell> {
  late Future<Map<String, Object?>> _bootstrapFuture;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _loadBootstrap();
  }

  Future<Map<String, Object?>> _loadBootstrap() async {
    final value = await Supabase.instance.client.rpc(
      'plp_enterprise_mobile_bootstrap_v1',
    );
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    throw StateError('PLP bootstrap returned an invalid payload.');
  }

  void _refresh() {
    setState(() => _bootstrapFuture = _loadBootstrap());
  }

  void _open(int index) {
    if (_index == index) return;
    setState(() => _index = index);
  }

  Map<String, Object?> _alfredContext(Map<String, Object?> bootstrap) => {
        ...bootstrap,
        'assistantIdentity': const <String, Object?>{
          'name': 'Alfred',
          'role': 'PLP executive intelligence',
          'routing': 'local-first governed execution',
        },
      };

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, Object?>>(
        future: _bootstrapFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(
                  key: ValueKey('plp-bootstrap-loading'),
                ),
              ),
            );
          }

          final bootstrap = snapshot.data;
          if (snapshot.hasError || bootstrap == null) {
            return Scaffold(
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_outline_rounded, size: 42),
                        const SizedBox(height: 12),
                        const Text(
                          'PLP access could not be loaded.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Pandora requires an active PLP membership and a verified resort bootstrap.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          key: const ValueKey('plp-bootstrap-retry'),
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          final alfredContext = _alfredContext(bootstrap);
          final screens = <Widget>[
            PlpEnterpriseHome(
              bootstrap: bootstrap,
              onRefresh: _refresh,
              onAskAlfred: () => _open(1),
              onOperations: () => _open(2),
              onVision: () => _open(3),
            ),
            AskPandoraScreen(
              key: const ValueKey('plp-alfred-screen'),
              onHome: () => _open(0),
              onMore: () => _open(4),
              enterpriseContext: alfredContext,
            ),
            PandoraOperationsRoomScreen(
              key: const ValueKey('plp-operations-room'),
              onHome: () => _open(0),
            ),
            EnterpriseVisionScreen(
              key: const ValueKey('plp-vision-intelligence'),
              onAskPandora: () => _open(1),
            ),
            const LocalAiSettingsScreen(
              key: ValueKey('plp-local-ai-settings'),
            ),
          ];

          return Scaffold(
            key: const ValueKey('plp-enterprise-shell'),
            body: IndexedStack(
              index: _index,
              children: screens,
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _open,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.auto_awesome_outlined),
                  selectedIcon: Icon(Icons.auto_awesome_rounded),
                  label: 'Alfred',
                ),
                NavigationDestination(
                  icon: Icon(Icons.hub_outlined),
                  selectedIcon: Icon(Icons.hub_rounded),
                  label: 'Operations',
                ),
                NavigationDestination(
                  icon: Icon(Icons.visibility_outlined),
                  selectedIcon: Icon(Icons.visibility_rounded),
                  label: 'Vision',
                ),
                NavigationDestination(
                  icon: Icon(Icons.memory_outlined),
                  selectedIcon: Icon(Icons.memory_rounded),
                  label: 'Local AI',
                ),
              ],
            ),
          );
        },
      );
}
