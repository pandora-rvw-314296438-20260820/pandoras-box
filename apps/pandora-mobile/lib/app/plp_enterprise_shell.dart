import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/local/pandora_local_state_cache.dart';
import '../features/enterprise/enterprise_vision_screen.dart';
import 'pandora_dependencies.dart';
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
  static const _canvas = Color(0xFF070A0F);
  static const _panel = Color(0xF20D1219);
  static const _line = Color(0xFF263040);
  static const _muted = Color(0xFF8D9AAB);
  static const _text = Color(0xFFF4F7FB);
  static const _accent = Color(0xFF5ED8E6);

  Future<Map<String, Object?>>? _bootstrapFuture;
  bool _bootstrapInitialized = false;
  final _alfredKey = GlobalKey<AskPandoraScreenState>();
  final _commandController = TextEditingController();
  final _commandFocus = FocusNode();
  int _index = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapInitialized) return;
    _bootstrapInitialized = true;
    _bootstrapFuture = _loadBootstrap();
  }

  @override
  void dispose() {
    _commandController.dispose();
    _commandFocus.dispose();
    super.dispose();
  }

  Future<Map<String, Object?>> _loadBootstrap() async {
    final localStore = PandoraDependencies.of(context).localStore;
    final cache =
        localStore == null ? null : PandoraLocalStateCache(localStore);
    try {
      final value = await Supabase.instance.client.rpc(
        'plp_enterprise_mobile_bootstrap_v1',
      );
      final normalized = _normalizeBootstrap(value);
      if (cache != null) {
        try {
          await cache.cacheMemoryContext(
            contextId: 'plp-enterprise-bootstrap',
            boundedContext: normalized,
          );
        } catch (_) {
          // Live PLP access remains authoritative even if local caching fails.
        }
      }
      return normalized;
    } catch (_) {
      if (cache != null) {
        try {
          final value = await cache.loadMemoryContext(
            contextId: 'plp-enterprise-bootstrap',
          );
          if (value != null) return _offlineBootstrap(value);
        } catch (_) {
          // Fall through to the original live bootstrap error.
        }
      }
      rethrow;
    }
  }

  Map<String, Object?> _normalizeBootstrap(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    throw StateError('PLP bootstrap returned an invalid payload.');
  }

  Map<String, Object?> _offlineBootstrap(Object? value) {
    final cached = _normalizeBootstrap(value);
    final rawSource = cached['source'];
    final source = rawSource is Map
        ? rawSource.map((key, item) => MapEntry(key.toString(), item))
        : <String, Object?>{};
    return <String, Object?>{
      ...cached,
      'source': <String, Object?>{
        ...source,
        'state': 'cached_offline',
        'message':
            'Using the last verified PLP snapshot while the live provider is unavailable.',
      },
      'offlineBootstrap': true,
    };
  }

  void _refresh() {
    setState(() => _bootstrapFuture = _loadBootstrap());
  }

  void _open(int index) {
    if (_index == index) return;
    setState(() => _index = index);
  }

  Future<void> _submitPersistentCommand() async {
    final command = _commandController.text.trim();
    if (command.isEmpty) {
      _open(1);
      return;
    }
    _commandController.clear();
    _commandFocus.unfocus();
    setState(() => _index = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _alfredKey.currentState?.submitExternalPrompt(command);
    });
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
              backgroundColor: _canvas,
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
              backgroundColor: _canvas,
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.lock_outline_rounded,
                          size: 42,
                          color: _accent,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'PLP access could not be loaded.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _text,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Pandora requires an active PLP membership and a verified resort bootstrap.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _muted),
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
              key: _alfredKey,
              onHome: () => _open(0),
              onMore: () => _open(4),
              enterpriseContext: alfredContext,
              allowCharacterContext: false,
              allowProjectContext: false,
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
            backgroundColor: _canvas,
            body: IndexedStack(
              index: _index,
              children: screens,
            ),
            bottomNavigationBar: _PlpCommandDock(
              selectedIndex: _index,
              controller: _commandController,
              focusNode: _commandFocus,
              showPersistentComposer: _index != 1,
              onSubmit: _submitPersistentCommand,
              onDestinationSelected: _open,
            ),
          );
        },
      );
}

class _PlpCommandDock extends StatelessWidget {
  const _PlpCommandDock({
    required this.selectedIndex,
    required this.controller,
    required this.focusNode,
    required this.showPersistentComposer,
    required this.onSubmit,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool showPersistentComposer;
  final Future<void> Function() onSubmit;
  final ValueChanged<int> onDestinationSelected;

  static const _items = <({IconData icon, String label})>[
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.auto_awesome_rounded, label: 'Alfred'),
    (icon: Icons.hub_rounded, label: 'Operations'),
    (icon: Icons.visibility_rounded, label: 'Vision'),
    (icon: Icons.memory_rounded, label: 'Local AI'),
  ];

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: _PlpEnterpriseShellState._panel,
            border: Border(
              top: BorderSide(color: _PlpEnterpriseShellState._line),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            10,
            showPersistentComposer ? 10 : 7,
            10,
            7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showPersistentComposer) ...[
                Container(
                  key: const ValueKey('plp-persistent-command-bar'),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151B25),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _PlpEnterpriseShellState._line),
                  ),
                  padding: const EdgeInsets.fromLTRB(13, 3, 5, 3),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        color: _PlpEnterpriseShellState._accent,
                        size: 18,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          style: const TextStyle(
                            color: _PlpEnterpriseShellState._text,
                            fontSize: 14,
                          ),
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => onSubmit(),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Ask Alfred or tell Pandora what to do…',
                            hintStyle: TextStyle(
                              color: _PlpEnterpriseShellState._muted,
                            ),
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Send to Alfred',
                        onPressed: onSubmit,
                        icon: const Icon(
                          Icons.arrow_upward_rounded,
                          color: _PlpEnterpriseShellState._text,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Row(
                children: List<Widget>.generate(_items.length, (index) {
                  final item = _items[index];
                  final selected = selectedIndex == index;
                  return Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => onDestinationSelected(index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              width: 38,
                              height: 28,
                              decoration: BoxDecoration(
                                color: selected
                                    ? _PlpEnterpriseShellState._accent
                                        .withValues(alpha: 0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                item.icon,
                                size: 20,
                                color: selected
                                    ? _PlpEnterpriseShellState._accent
                                    : _PlpEnterpriseShellState._muted,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              style: TextStyle(
                                color: selected
                                    ? _PlpEnterpriseShellState._text
                                    : _PlpEnterpriseShellState._muted,
                                fontSize: 9.5,
                                fontWeight:
                                    selected ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      );
}
