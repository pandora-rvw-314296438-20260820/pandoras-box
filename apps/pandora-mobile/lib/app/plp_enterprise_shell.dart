import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/data/pandora_intelligence_api.dart';
import '../core/local/pandora_local_state_cache.dart';
import '../core/widgets/pandora_navigation.dart';
import '../features/approvals/approvals_screen.dart';
import '../features/diagnostics/developer_diagnostics_screen.dart';
import '../features/enterprise/plp_activity_screen.dart';
import '../features/enterprise/plp_editorial_surfaces.dart';
import '../features/enterprise/plp_enterprise_home.dart';
import '../features/enterprise/plp_guests_screen.dart';
import '../features/enterprise/plp_team_access_screen.dart';
import '../features/operations/operations_room_screen.dart';
import '../features/settings/local_ai_settings_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/simple/ask_pandora_screen.dart';
import '../features/team/team_screen.dart';
import 'pandora_dependencies.dart';
import 'plp_navigation_drawer.dart';

class PlpEnterpriseShell extends StatefulWidget {
  const PlpEnterpriseShell({super.key});

  @override
  State<PlpEnterpriseShell> createState() => _PlpEnterpriseShellState();
}

class _PlpEnterpriseShellState extends State<PlpEnterpriseShell> {
  static const _canvas = Color(0xFFFAF8F3);
  static const _muted = Color(0xFF746F67);
  static const _text = Color(0xFF171512);
  static const _accent = Color(0xFF82764F);

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
  final GlobalKey<NavigatorState> _contentNavigatorKey =
      GlobalKey<NavigatorState>();
  final _alfredKey = GlobalKey<AskPandoraScreenState>();
  final _commandController = TextEditingController();
  final _commandFocus = FocusNode();

  Future<Map<String, Object?>>? _bootstrapFuture;
  Map<String, Object?>? _lastBootstrap;
  bool _bootstrapInitialized = false;
  int _index = 0;
  Widget? _routedTool;
  String? _routedToolKey;
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
    _bootstrapFuture = _loadBootstrapAndRemember();
  }

  Future<Map<String, Object?>> _loadBootstrapAndRemember() async {
    final value = await _loadBootstrap();
    _lastBootstrap = value;
    return value;
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
    final rawSource = cached['sourceHealth'];
    final source = rawSource is Map
        ? rawSource.map((key, item) => MapEntry(key.toString(), item))
        : <String, Object?>{};
    return <String, Object?>{
      ...cached,
      'sourceHealth': <String, Object?>{
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
            final topic = payload.newRecord['topic']?.toString();
            if (eventOrganizationId == organizationId &&
                topic != 'pandora_activity') {
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
        setState(() => _bootstrapFuture = _loadBootstrapAndRemember());
      },
    );
  }

  void _refresh() {
    setState(() => _bootstrapFuture = _loadBootstrapAndRemember());
  }

  void _open(int index) {
    if (_index == index && _routedTool == null) return;
    setState(() {
      _index = index;
      _routedTool = null;
      _routedToolKey = null;
    });
  }

  void _openTool(String key, Widget tool) {
    setState(() {
      _routedToolKey = key;
      _routedTool = tool;
    });
  }

  void _closeTool() {
    if (_routedTool == null) return;
    final closedKey = _routedToolKey;
    setState(() {
      _routedTool = null;
      _routedToolKey = null;
    });
    if (closedKey == 'team-management') {
      _refresh();
    }
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
    setState(() {
      _index = 1;
      _routedTool = null;
      _routedToolKey = null;
    });
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

  Future<void> _startNewChat() async {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
    _open(1);
    await WidgetsBinding.instance.endOfFrame;
    _alfredKey.currentState?.newChat();
    if (!mounted) return;
    setState(() {
      _recentChatsLoaded = false;
      _recentChatsError = null;
    });
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
          final bootstrap = snapshot.data ?? _lastBootstrap;
          if (bootstrap == null &&
              snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              backgroundColor: _canvas,
              body: Center(
                child: CircularProgressIndicator(
                  key: ValueKey('plp-bootstrap-loading'),
                ),
              ),
            );
          }

          if (bootstrap == null) {
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
            PlpOperationsScreen(
              key: const ValueKey('plp-operations-room'),
              bootstrap: bootstrap,
              onOpenNavigation: _openDrawer,
              onAskPandora: () => _open(1),
              onOpenRoom: () {
                _openTool(
                  'operations-room',
                  PandoraOperationsRoomScreen(onHome: _closeTool),
                );
              },
            ),
            PlpVisionScreen(
              key: const ValueKey('plp-vision-intelligence'),
              onOpenNavigation: _openDrawer,
              onAskPandora: () => _open(1),
            ),
            const LocalAiSettingsScreen(
              key: ValueKey('plp-local-ai-settings'),
            ),
            PlpOverviewScreen(
              key: const ValueKey('plp-overview'),
              bootstrap: bootstrap,
              onOpenNavigation: _openDrawer,
              onAskPandora: () => _open(1),
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
                _openTool(
                  'team-management',
                  const TeamScreen(openInviteOnLoad: true),
                );
              },
              onManageTeam: () {
                _openTool('team-management', const TeamScreen());
              },
            ),
            PlpRevenueScreen(
              key: const ValueKey('plp-revenue'),
              bootstrap: bootstrap,
              onOpenNavigation: _openDrawer,
              onAskPandora: () => _open(1),
            ),
            PlpNeedsYouScreen(
              key: const ValueKey('plp-needs-you'),
              bootstrap: bootstrap,
              onOpenNavigation: _openDrawer,
              onAskPandora: () => _open(1),
              onOpenApprovals: () {
                _openTool('approvals', const ApprovalsScreen());
              },
            ),
            PlpActivityScreen(
              key: const ValueKey('plp-activity'),
              organizationId: _organizationId(bootstrap),
              onOpenNavigation: _openDrawer,
            ),
            PlpSettingsScreen(
              key: const ValueKey('plp-settings'),
              bootstrap: bootstrap,
              onOpenNavigation: _openDrawer,
              onOpenLocalAi: () => _open(4),
              onOpenDeveloper: () => _open(12),
              onOpenFullSettings: () {
                _openTool('full-settings', const SettingsScreen());
              },
            ),
            const DeveloperDiagnosticsScreen(key: ValueKey('plp-developer')),
          ];

          return KeyedSubtree(
            key: const ValueKey('plp-enterprise-shell'),
            child: Scaffold(
              key: _scaffoldKey,
              backgroundColor: _canvas,
              drawerEnableOpenDragGesture: true,
              drawerEdgeDragWidth: 32,
              drawerScrimColor: const Color(0x99000000),
              onDrawerChanged: (open) {
                if (open) unawaited(_loadRecentChats(force: true));
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
                onNewChat: () {
                  unawaited(_startNewChat());
                },
              ),
              body: PandoraNavigationScope(
                openDrawer: _index == 1 ? _openDrawer : null,
                child: Stack(
                  children: [
                    Navigator(
                      key: _contentNavigatorKey,
                      pages: <Page<void>>[
                        MaterialPage<void>(
                          key: const ValueKey<String>('plp-shell-base-route'),
                          child: IndexedStack(
                            index: _index,
                            children: screens,
                          ),
                        ),
                        if (_routedTool != null)
                          MaterialPage<void>(
                            key: ValueKey<String>(
                              'plp-shell-tool-${_routedToolKey!}',
                            ),
                            child: _routedTool!,
                          ),
                      ],
                      onDidRemovePage: (page) {
                        final routeKey = page.key;
                        if (_routedTool == null ||
                            routeKey is! ValueKey<String> ||
                            !routeKey.value.startsWith('plp-shell-tool-')) {
                          return;
                        }
                        _closeTool();
                      },
                    ),
                    if (_index != 1)
                      Positioned(
                        top: 0,
                        left: 0,
                        child: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 0, 0),
                            child: PandoraMenuButton(
                              key: const ValueKey<String>(
                                'pandora-side-panel-open',
                              ),
                              onPressed: _openDrawer,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              bottomNavigationBar: _index == 1
                  ? null
                  : PlpCommandDock(
                      controller: _commandController,
                      focusNode: _commandFocus,
                      onSubmit: _submitPersistentCommand,
                    ),
            ),
          );
        },
      );
}


class PlpCommandDock extends StatelessWidget {
  const PlpCommandDock({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          key: const ValueKey<String>('plp-command-dock'),
          decoration: const BoxDecoration(
            color: _PlpEnterpriseShellState._canvas,
            border: Border(
              top: BorderSide(color: Color(0xFFE1DBD1)),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: DecoratedBox(
            key: const ValueKey<String>('plp-persistent-command-bar'),
            decoration: const BoxDecoration(
              color: Color(0xFF171512),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox.square(
                  dimension: 50,
                  child: Icon(
                    Icons.view_in_ar_outlined,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('plp-command-field'),
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSubmit(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      height: 1.35,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Message Pandora',
                      hintStyle: TextStyle(
                        color: Color(0xFFB6B0A7),
                        fontSize: 15.5,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.fromLTRB(2, 15, 6, 14),
                    ),
                  ),
                ),
                const SizedBox.square(
                  dimension: 46,
                  child: Icon(
                    Icons.mic_none_rounded,
                    color: Color(0xFFD6D0C7),
                    size: 25,
                  ),
                ),
                Container(
                  width: 1,
                  height: 34,
                  color: const Color(0xFF3D3934),
                ),
                SizedBox.square(
                  dimension: 50,
                  child: IconButton(
                    key: const ValueKey<String>('plp-command-submit'),
                    onPressed: onSubmit,
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                    icon: const Icon(
                      Icons.arrow_upward_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
