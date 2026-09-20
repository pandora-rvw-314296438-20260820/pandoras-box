import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/data/pandora_intelligence_api.dart';
import '../core/local/pandora_local_state_cache.dart';
import '../core/widgets/pandora_navigation.dart';
import '../features/enterprise/plp_activity_screen.dart';
import '../features/approvals/approvals_screen.dart';
import '../features/diagnostics/developer_diagnostics_screen.dart';
import '../features/enterprise/enterprise_vision_screen.dart';
import '../features/enterprise/plp_enterprise_home.dart';
import '../features/enterprise/plp_guests_screen.dart';
import '../features/enterprise/plp_team_access_screen.dart';
import '../features/operations/operations_room_screen.dart';
import '../features/settings/local_ai_settings_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/simple/ask_pandora_screen.dart';
import 'pandora_dependencies.dart';
import 'plp_navigation_drawer.dart';

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

  static const _surfaceByDestination = <String, int>{
    'home': 0,
    'operations': 2,
    'vision': 3,
    'local-ai': 4,
    'overview': 5,
    'guests': 6,
    'team-access': 7,
    'revenue': 8,
    'needs-you': 9,
    'activity': 10,
    'settings': 11,
    'developer': 12,
  };

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final _alfredKey = GlobalKey<AskPandoraScreenState>();
  final _commandController = TextEditingController();
  final _commandFocus = FocusNode();

  Future<Map<String, Object?>>? _bootstrapFuture;
  bool _bootstrapInitialized = false;
  int _index = 0;
  List<PlpRecentChatItem> _recentChats = const <PlpRecentChatItem>[];
  bool _recentChatsLoading = false;
  bool _recentChatsLoaded = false;
  String? _recentChatsError;
  RealtimeChannel? _plpRealtimeChannel;
  Timer? _plpRealtimeRefreshDebounce;
  String? _plpRealtimeOrganizationId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapInitialized) return;
    _bootstrapInitialized = true;
    _bootstrapFuture = _loadBootstrap();
  }

  @override
  void dispose() {
    _plpRealtimeRefreshDebounce?.cancel();
    final channel = _plpRealtimeChannel;
    if (channel != null) {
      unawaited(channel.unsubscribe().then<void>((_) {}));
    }
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
      _ensureRealtime(normalized);
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

  String? _organizationId(Map<String, Object?> bootstrap) {
    final raw = bootstrap['organization'];
    if (raw is! Map) return null;
    final value = raw['id']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  void _ensureRealtime(Map<String, Object?> bootstrap) {
    final organizationId = _organizationId(bootstrap);
    if (organizationId == null ||
        organizationId == _plpRealtimeOrganizationId) {
      return;
    }

    final previous = _plpRealtimeChannel;
    if (previous != null) {
      unawaited(previous.unsubscribe().then<void>((_) {}));
    }

    _plpRealtimeOrganizationId = organizationId;
    _plpRealtimeChannel = Supabase.instance.client
        .channel('plp-enterprise-live-$organizationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'enterprise_realtime_signals',
          callback: (payload) {
            final eventOrganizationId =
                payload.newRecord['organization_id']?.toString();
            if (eventOrganizationId == organizationId) {
              _scheduleRealtimeRefresh();
            }
          },
        )
        .subscribe();
  }

  void _scheduleRealtimeRefresh() {
    _plpRealtimeRefreshDebounce?.cancel();
    _plpRealtimeRefreshDebounce = Timer(
      const Duration(milliseconds: 250),
      () {
        if (!mounted) return;
        setState(() => _bootstrapFuture = _loadBootstrap());
      },
    );
  }

  void _refresh() {
    setState(() => _bootstrapFuture = _loadBootstrap());
  }

  void _open(int index) {
    if (_index == index) return;
    setState(() => _index = index);
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  Future<void> _submitCommand([String? preset]) async {
    final command = (preset ?? _commandController.text).trim();
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

  Future<void> _submitPersistentCommand() => _submitCommand();

  Map<String, Object?> _alfredContext(Map<String, Object?> bootstrap) => {
        ...bootstrap,
        'assistantIdentity': const <String, Object?>{
          'name': 'Alfred',
          'role': 'PLP executive intelligence',
          'routing': 'local-first governed execution',
        },
      };

  String? get _drawerSelection {
    for (final entry in _surfaceByDestination.entries) {
      if (entry.value == _index) return entry.key;
    }
    return null;
  }

  void _selectDrawerDestination(String destination) {
    final target = _surfaceByDestination[destination];
    if (target == null) return;
    _scaffoldKey.currentState?.closeDrawer();
    _open(target);
  }

  Future<void> _openRecentThread(PlpRecentChatItem item) async {
    _scaffoldKey.currentState?.closeDrawer();
    _open(1);
    await WidgetsBinding.instance.endOfFrame;
    await _alfredKey.currentState?.loadThread(item.id);
  }

  Future<void> _loadRecentChats({bool force = false}) async {
    if (_recentChatsLoading || (_recentChatsLoaded && !force)) return;
    final intelligence = PandoraDependencies.of(context).intelligence;
    if (intelligence == null) {
      setState(() {
        _recentChatsLoaded = true;
        _recentChatsError = 'Recent chats are unavailable.';
      });
      return;
    }

    setState(() {
      _recentChatsLoading = true;
      _recentChatsError = null;
    });

    try {
      final threads = await intelligence.recentThreadsForWorkspace(
        'plp-boracay',
        limit: 8,
      );
      if (!mounted) return;
      setState(() {
        _recentChats = threads
            .map(
              (thread) => PlpRecentChatItem(
                id: thread.id,
                title: thread.title.trim().isEmpty
                    ? 'Untitled conversation'
                    : thread.title.trim(),
              ),
            )
            .toList(growable: false);
        _recentChatsLoaded = true;
      });
    } on PandoraIntelligenceException catch (error) {
      if (!mounted) return;
      setState(() {
        _recentChatsLoaded = true;
        _recentChatsError = error.message;
      });
    } finally {
      if (mounted) setState(() => _recentChatsLoading = false);
    }
  }

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
              onOpenNavigation: _openDrawer,
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
            _PlpBusinessSurface(
              key: const ValueKey('plp-overview'),
              destination: 'overview',
              title: 'Overview',
              icon: Icons.dashboard_outlined,
              bootstrap: bootstrap,
              onOpenNavigation: _openDrawer,
            ),
            PlpGuestsScreen(
              key: const ValueKey('plp-guests'),
              bootstrap: bootstrap,
              onOpenNavigation: _openDrawer,
            ),
            PlpTeamAccessScreen(
              key: const ValueKey('plp-team-access'),
              bootstrap: bootstrap,
              onOpenNavigation: _openDrawer,
              onAddPeople: () {
                unawaited(_submitCommand('Add a person to the PLP team'));
              },
            ),
            _PlpBusinessSurface(
              key: const ValueKey('plp-revenue'),
              destination: 'revenue',
              title: 'Revenue',
              icon: Icons.payments_outlined,
              bootstrap: bootstrap,
              onOpenNavigation: _openDrawer,
            ),
            const ApprovalsScreen(key: ValueKey('plp-needs-you')),
            PlpActivityScreen(
              key: const ValueKey('plp-activity'),
              organizationId: _organizationId(bootstrap),
              onOpenNavigation: _openDrawer,
            ),
            const SettingsScreen(key: ValueKey('plp-settings')),
            const DeveloperDiagnosticsScreen(key: ValueKey('plp-developer')),
          ];

          return KeyedSubtree(
            key: const ValueKey('plp-enterprise-shell'),
            child: Scaffold(
              key: _scaffoldKey,
              backgroundColor: _canvas,
              drawerEnableOpenDragGesture: true,
              drawerEdgeDragWidth: 28,
              drawerScrimColor: const Color(0x99000000),
              onDrawerChanged: (open) {
                if (open) unawaited(_loadRecentChats());
              },
              drawer: PlpNavigationDrawer(
                selectedDestination: _drawerSelection,
                recentChats: _recentChats,
                recentChatsLoading: _recentChatsLoading,
                recentChatsError: _recentChatsError,
                onRetryRecentChats: () {
                  unawaited(_loadRecentChats(force: true));
                },
                onSelectDestination: _selectDrawerDestination,
                onSelectThread: (item) {
                  unawaited(_openRecentThread(item));
                },
              ),
              body: PandoraNavigationScope(
                openDrawer: _openDrawer,
                child: IndexedStack(
                  index: _index,
                  children: screens,
                ),
              ),
              bottomNavigationBar: _index == 6
                  ? _PlpGuestCommandDock(
                      controller: _commandController,
                      focusNode: _commandFocus,
                      onSubmit: _submitPersistentCommand,
                      onSuggestion: (prompt) {
                        unawaited(_submitCommand(prompt));
                      },
                    )
                  : _index == 7
                      ? _PlpTeamCommandDock(
                          controller: _commandController,
                          focusNode: _commandFocus,
                          onSubmit: _submitPersistentCommand,
                          onSuggestion: (prompt) {
                            unawaited(_submitCommand(prompt));
                          },
                        )
                      : _index == 10
                          ? _PlpActivityCommandDock(
                              controller: _commandController,
                              focusNode: _commandFocus,
                              onSubmit: _submitPersistentCommand,
                              onSuggestion: (prompt) {
                                unawaited(_submitCommand(prompt));
                              },
                            )
                          : _PlpCommandDock(
                              selectedIndex: _index,
                              controller: _commandController,
                              focusNode: _commandFocus,
                              showPersistentComposer: _index != 1,
                              onSubmit: _submitPersistentCommand,
                              onDestinationSelected: _open,
                            ),
            ),
          );
        },
      );
}


class _PlpGuestCommandDock extends StatelessWidget {
  const _PlpGuestCommandDock({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onSuggestion,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onSubmit;
  final ValueChanged<String> onSuggestion;

  static const _canvas = Color(0xFFFAF7F1);
  static const _paper = Color(0xFFFFFDFC);
  static const _ink = Color(0xFF171512);
  static const _muted = Color(0xFF7A756E);
  static const _line = Color(0xFFE7DDD0);
  static const _gold = Color(0xFF9A692F);

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          key: const ValueKey<String>('plp-guests-command-dock'),
          decoration: const BoxDecoration(
            color: _canvas,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 20,
                offset: Offset(0, -6),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: _paper,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFFD9C6AD)),
                ),
                padding: const EdgeInsets.fromLTRB(8, 4, 5, 4),
                child: Row(
                  children: [
                    ClipOval(
                      child: Image.asset(
                        'assets/brand/pandora-product-mark-ui-1024.png',
                        width: 34,
                        height: 34,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 34,
                          height: 34,
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            color: _ink,
                            size: 21,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const ValueKey<String>(
                          'plp-guests-command-field',
                        ),
                        controller: controller,
                        focusNode: focusNode,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => onSubmit(),
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 13.5,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: 'Ask Pandora about guests…',
                          hintStyle: TextStyle(
                            color: _muted,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.mic_none_rounded,
                        color: _ink,
                        size: 23,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey<String>(
                        'plp-guests-command-submit',
                      ),
                      tooltip: 'Ask Pandora',
                      onPressed: onSubmit,
                      style: IconButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: _gold,
                      ),
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _GuestSuggestionChip(
                      icon: Icons.auto_awesome_rounded,
                      label: 'Who needs attention?',
                      onTap: () => onSuggestion('Who needs attention?'),
                    ),
                    const SizedBox(width: 7),
                    _GuestSuggestionChip(
                      icon: Icons.people_alt_rounded,
                      label: 'Show VIP guests',
                      onTap: () => onSuggestion('Show VIP guests'),
                    ),
                    const SizedBox(width: 7),
                    _GuestSuggestionChip(
                      icon: Icons.flight_land_rounded,
                      label: 'Who arrives next?',
                      onTap: () => onSuggestion('Who arrives next?'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _GuestSuggestionChip extends StatelessWidget {
  const _GuestSuggestionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFFFFFDFC),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFE7DDD0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: const Color(0xFF9A692F)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF3F3A34),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _PlpTeamCommandDock extends StatelessWidget {
  const _PlpTeamCommandDock({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onSuggestion,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onSubmit;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          key: const ValueKey<String>('plp-team-command-dock'),
          decoration: const BoxDecoration(
            color: Color(0xFFFBF8F2),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 20,
                offset: Offset(0, -6),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFDFC),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFFD9C6AD)),
                ),
                padding: const EdgeInsets.fromLTRB(8, 4, 5, 4),
                child: Row(
                  children: [
                    ClipOval(
                      child: Image.asset(
                        'assets/brand/pandora-product-mark-ui-1024.png',
                        width: 34,
                        height: 34,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 34,
                          height: 34,
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            color: Color(0xFF101B33),
                            size: 21,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const ValueKey<String>('plp-team-command-field'),
                        controller: controller,
                        focusNode: focusNode,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => onSubmit(),
                        style: const TextStyle(
                          color: Color(0xFF101B33),
                          fontSize: 13.5,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: 'Ask Pandora about team & access…',
                          hintStyle: TextStyle(
                            color: Color(0xFF77736C),
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey<String>('plp-team-command-submit'),
                      tooltip: 'Ask Pandora',
                      onPressed: onSubmit,
                      style: IconButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: const Color(0xFF9D6928),
                      ),
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _TeamSuggestionChip(
                      icon: Icons.shield_outlined,
                      label: 'Who has access?',
                      onTap: () => onSuggestion('Who has access to PLP?'),
                    ),
                    const SizedBox(width: 7),
                    _TeamSuggestionChip(
                      icon: Icons.person_add_alt_1_rounded,
                      label: 'Add team member',
                      onTap: () => onSuggestion('Add a person to the PLP team'),
                    ),
                    const SizedBox(width: 7),
                    _TeamSuggestionChip(
                      icon: Icons.history_rounded,
                      label: 'Recent activity',
                      onTap: () => onSuggestion('Show recent PLP team activity'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _TeamSuggestionChip extends StatelessWidget {
  const _TeamSuggestionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFFFFFDFC),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFE7DDD0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: const Color(0xFF9D6928)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF3F3A34),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _PlpActivityCommandDock extends StatelessWidget {
  const _PlpActivityCommandDock({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onSuggestion,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onSubmit;
  final ValueChanged<String> onSuggestion;

  static const _canvas = Color(0xFFFAF7F1);
  static const _paper = Color(0xFFFFFDFC);
  static const _ink = Color(0xFF171B29);
  static const _muted = Color(0xFF77736D);
  static const _gold = Color(0xFF99682C);
  static const _line = Color(0xFFE5DDD2);

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          key: const ValueKey<String>('plp-activity-command-dock'),
          decoration: const BoxDecoration(
            color: _canvas,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 20,
                offset: Offset(0, -6),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: _paper,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFFD9C6AD)),
                ),
                padding: const EdgeInsets.fromLTRB(8, 4, 5, 4),
                child: Row(
                  children: [
                    ClipOval(
                      child: Image.asset(
                        'assets/brand/pandora-product-mark-ui-1024.png',
                        width: 34,
                        height: 34,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 34,
                          height: 34,
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            color: _ink,
                            size: 21,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const ValueKey<String>(
                          'plp-activity-command-field',
                        ),
                        controller: controller,
                        focusNode: focusNode,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => onSubmit(),
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 13.5,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: 'Ask Pandora about activity…',
                          hintStyle: TextStyle(
                            color: _muted,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.mic_none_rounded,
                        color: _ink,
                        size: 23,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey<String>(
                        'plp-activity-command-submit',
                      ),
                      tooltip: 'Ask Pandora',
                      onPressed: onSubmit,
                      style: IconButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: _gold,
                      ),
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _ActivitySuggestionChip(
                      icon: Icons.notifications_none_rounded,
                      label: 'What needs attention?',
                      onTap: () => onSuggestion('What needs attention?'),
                    ),
                    const SizedBox(width: 7),
                    _ActivitySuggestionChip(
                      icon: Icons.groups_2_outlined,
                      label: 'Show guest activity',
                      onTap: () => onSuggestion('Show recent guest activity'),
                    ),
                    const SizedBox(width: 7),
                    _ActivitySuggestionChip(
                      icon: Icons.receipt_long_outlined,
                      label: 'Show team updates',
                      onTap: () => onSuggestion('Show recent team updates'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _ActivitySuggestionChip extends StatelessWidget {
  const _ActivitySuggestionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFFFFFDFC),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFE5DDD2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: const Color(0xFF99682C)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF3F3A34),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
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


class _PlpBusinessSurface extends StatelessWidget {
  const _PlpBusinessSurface({
    super.key,
    required this.destination,
    required this.title,
    required this.icon,
    required this.bootstrap,
    required this.onOpenNavigation,
  });

  final String destination;
  final String title;
  final IconData icon;
  final Map<String, Object?> bootstrap;
  final VoidCallback onOpenNavigation;

  Map<String, Object?> _map(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const <String, Object?>{};
  }

  String _text(Object? value, {String fallback = '—'}) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? fallback : normalized;
  }

  List<MapEntry<String, String>> _metrics() {
    final today = _map(bootstrap['today']);
    switch (destination) {
      case 'guests':
        return <MapEntry<String, String>>[
          MapEntry(
            'Arrivals today',
            _text(today['arrivals_today'], fallback: '0'),
          ),
          MapEntry(
            'Departures today',
            _text(today['departures_today'], fallback: '0'),
          ),
          MapEntry(
            'OTA conflicts',
            _text(today['open_ota_conflicts'], fallback: '0'),
          ),
        ];
      case 'team-access':
        return <MapEntry<String, String>>[
          MapEntry(
            'Open staff tasks',
            _text(today['open_staff_tasks'], fallback: '0'),
          ),
          const MapEntry('Access scope', 'PLP owner workspace'),
        ];
      case 'revenue':
        return <MapEntry<String, String>>[
          MapEntry(
            'Sales today',
            '₱${_text(today['sales_today_php'], fallback: '0')}',
          ),
          MapEntry(
            'Occupancy',
            '${_text(today['occupancy_percent'], fallback: '0')}%',
          ),
        ];
      default:
        return <MapEntry<String, String>>[
          MapEntry(
            'Occupancy',
            '${_text(today['occupancy_percent'], fallback: '0')}%',
          ),
          MapEntry(
            'Rooms available',
            _text(today['rooms_available'], fallback: '0'),
          ),
          MapEntry(
            'Open staff tasks',
            _text(today['open_staff_tasks'], fallback: '0'),
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _metrics();
    return SafeArea(
      child: ListView(
        key: ValueKey<String>('plp-business-$destination'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 180),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Open navigation',
                onPressed: onOpenNavigation,
                icon: const Icon(Icons.menu_rounded, size: 28),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 25),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'PLP Boracay',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Luxury Resort · live owner workspace',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          for (final metric in metrics) ...[
            Card(
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                title: Text(metric.key),
                trailing: Text(
                  metric.value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
