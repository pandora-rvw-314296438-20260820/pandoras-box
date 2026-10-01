import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/data/pandora_intelligence_api.dart';
import '../core/local/pandora_local_state_cache.dart';
import '../core/widgets/pandora_navigation.dart';
import '../features/approvals/approvals_screen.dart';
import '../features/diagnostics/developer_diagnostics_screen.dart';
import '../features/enterprise/plp_activity_screen.dart';
import '../features/enterprise/plp_connectivity_infrastructure_screen.dart';
import '../features/enterprise/plp_editorial_surfaces.dart';
import '../features/enterprise/plp_enterprise_home.dart';
import '../features/enterprise/plp_resort_workspace.dart';
import '../features/enterprise/plp_resort_operational_screens.dart';
import '../features/enterprise/plp_guests_screen.dart';
import '../features/enterprise/plp_team_management_screen.dart';
import '../features/enterprise/tax_compliance_screen.dart';
import '../features/operations/operations_room_screen.dart';
import '../features/settings/local_ai_settings_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/simple/ask_pandora_screen.dart';
import 'pandora_dependencies.dart';
import 'plp_navigation_drawer.dart';

class PlpEnterpriseShell extends StatefulWidget {
  const PlpEnterpriseShell({
    super.key,
    this.bootstrapOverride,
  });

  /// Acceptance tests may provide a verified bootstrap fixture. Production
  /// does not pass this and still loads from the authenticated PLP RPCs.
  final Map<String, Object?>? bootstrapOverride;

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
    'connectivity': 14,
    'tax-compliance': 13,
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
  final _drawerScrollController = ScrollController();
  bool _drawerOpen = false;

  Future<Map<String, Object?>>? _bootstrapFuture;
  Map<String, Object?>? _lastBootstrap;
  bool _bootstrapInitialized = false;
  int _index = 0;
  final List<int> _surfaceHistory = <int>[];
  Widget? _routedTool;
  String? _routedToolKey;
  final List<({String key, Widget tool})> _routedToolHistory =
      <({String key, Widget tool})>[];
  bool _commandBusy = false;
  String? _commandReply;
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
    _drawerScrollController.dispose();
    super.dispose();
  }

  Future<Map<String, Object?>> _loadBootstrap() async {
    final override = widget.bootstrapOverride;
    if (override != null) {
      return Map<String, Object?>.from(override);
    }
    final localStore = PandoraDependencies.of(context).localStore;
    final cache =
        localStore == null ? null : PandoraLocalStateCache(localStore);
    try {
      final value = await Supabase.instance.client.rpc(
        'plp_enterprise_mobile_bootstrap_v1',
      );
      final normalized =
          Map<String, Object?>.from(_normalizeBootstrap(value));
      try {
        final resort = await Supabase.instance.client.rpc(
          'plp_resort_command_center_v1',
        );
        normalized['resortCommandCenter'] = _normalizeBootstrap(resort);
      } catch (_) {
        // The verified PLP core remains authoritative if the additive resort
        // command-center projection is rolling out or temporarily unavailable.
      }
      try {
        final operations = await Supabase.instance.client.rpc(
          'plp_resort_operations_v1',
        );
        normalized['resortOperations'] = _normalizeBootstrap(operations);
      } catch (_) {
        // Operational detail is additive; core resort truth remains usable.
      }
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

  void _open(
    int index, {
    bool remember = true,
    bool clearHistory = false,
  }) {
    if (_index == index && _routedTool == null) return;
    setState(() {
      if (clearHistory) {
        _surfaceHistory.clear();
      } else if (remember && index != _index) {
        if (_surfaceHistory.isEmpty || _surfaceHistory.last != _index) {
          _surfaceHistory.add(_index);
        }
      }
      _index = index;
      _routedTool = null;
      _routedToolKey = null;
      _routedToolHistory.clear();
      _commandReply = null;
    });
  }

  void _openHome() => _open(
        0,
        remember: false,
        clearHistory: true,
      );

  bool _handleWorkspaceBack() {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _closeDrawer();
      return true;
    }
    if (_routedTool != null) {
      _closeTool();
      return true;
    }
    if (_surfaceHistory.isNotEmpty) {
      final target = _surfaceHistory.removeLast();
      setState(() {
        _index = target;
        _commandReply = null;
      });
      return true;
    }
    if (_index != 0) {
      setState(() {
        _index = 0;
        _commandReply = null;
      });
      return true;
    }
    return false;
  }

  void _openTool(
    String key,
    Widget tool, {
    bool replaceHistory = false,
  }) {
    setState(() {
      if (replaceHistory) {
        _routedToolHistory.clear();
      } else if (_routedTool != null && _routedToolKey != null) {
        _routedToolHistory.add((
          key: _routedToolKey!,
          tool: _routedTool!,
        ));
      }
      _routedToolKey = key;
      _routedTool = tool;
    });
  }

  void _closeTool() {
    if (_routedTool == null) return;
    final closedKey = _routedToolKey;
    setState(() {
      if (_routedToolHistory.isNotEmpty) {
        final previous = _routedToolHistory.removeLast();
        _routedToolKey = previous.key;
        _routedTool = previous.tool;
      } else {
        _routedTool = null;
        _routedToolKey = null;
      }
    });
    if (closedKey == 'team-management') {
      _refresh();
    }
  }

  void _dismissWorkspaceKeyboard() {
    _commandFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _resetDrawerScroll() {
    if (_drawerScrollController.hasClients) {
      _drawerScrollController.jumpTo(0);
    }
  }

  void _closeDrawer() {
    _dismissWorkspaceKeyboard();
    _scaffoldKey.currentState?.closeDrawer();
  }

  void _openDrawer() {
    _dismissWorkspaceKeyboard();
    _resetDrawerScroll();
    _scaffoldKey.currentState?.openDrawer();
  }

  Future<void> _submitCommand([String? preset]) async {
    if (_commandBusy) return;
    final command = (preset ?? _commandController.text).trim();
    if (command.isEmpty) {
      _open(1);
      return;
    }
    _commandController.clear();
    _commandFocus.unfocus();
    setState(() {
      _commandBusy = true;
      _commandReply = null;
    });
    await WidgetsBinding.instance.endOfFrame;
    String? reply;
    try {
      reply = await _alfredKey.currentState?.submitExternalPrompt(
        command,
        requestFocus: false,
      );
    } finally {
      if (mounted) {
        setState(() {
          _commandBusy = false;
          _commandReply = reply;
        });
        _refresh();
      }
    }
  }

  Future<void> _submitPersistentCommand() => _submitCommand();

  String get _commandHint {
    final toolKey = _routedToolKey;
    if (toolKey != null && toolKey.startsWith('resort:')) {
      final section =
          plpResortSectionById(toolKey.substring('resort:'.length));
      if (section != null) return section.commandHint;
    }
    if (toolKey != null && toolKey.startsWith('resort-module:')) {
      final module = toolKey.substring('resort-module:'.length);
      return 'Ask about ' + module.replaceAll('-', ' ') + '…';
    }
    if (toolKey != null && toolKey.startsWith('resort-record:')) {
      return 'Ask about this resort record…';
    }
    return switch (_index) {
      0 => 'Ask what matters today…',
      2 => 'Ask about operations…',
      3 => 'Ask about what you see…',
      4 => 'Ask about local AI…',
      5 => 'Ask about today’s overview…',
      6 => 'Ask about a guest or stay…',
      7 => 'Ask about team or access…',
      8 => 'Ask about revenue…',
      9 => 'Ask what needs your attention…',
      10 => 'Ask about recent activity…',
      11 => 'Ask about settings…',
      12 => 'Ask about diagnostics…',
      13 => 'Ask about tax readiness…',
      14 => 'Ask about resort infrastructure…',
      _ => 'Message Pandora',
    };
  }

  Map<String, Object?> _alfredContext(Map<String, Object?> bootstrap) => {
        ...bootstrap,
        'assistantIdentity': const <String, Object?>{
          'name': 'Alfred',
          'role': 'PLP executive intelligence',
          'routing': 'local-first governed execution',
        },
        'uiContext': <String, Object?>{
          'surface': _drawerSelection ?? 'home',
          'interaction': 'contextual luxury resort workspace',
        },
        'enterpriseInfrastructure': const <String, Object?>{
          'presentation': 'outcome-first',
          'providerStrategy': 'provider-neutral',
          'pldtEnterpriseEligible': true,
          'providerMentionPolicy':
              'Mention PLDT Enterprise only when a verified business need makes the provider relevant or the owner asks about it.',
          'truthContract':
              'Never claim a PLDT, Smart, or other provider service is active without external provider evidence.',
          'opportunityFlow':
              'verified need -> owner approval -> assigned provider relationship manager when partner routing is connected',
        },
      };

  String? get _drawerSelection {
    final activeKeys = <String?>[
      _routedToolKey,
      for (final route in _routedToolHistory.reversed) route.key,
    ];
    for (final toolKey in activeKeys) {
      if (toolKey != null && toolKey.startsWith('resort:')) {
        return toolKey.substring('resort:'.length);
      }
    }
    for (final entry in _surfaceByDestination.entries) {
      if (entry.value == _index) return entry.key;
    }
    return null;
  }

  void _openResortRecord(
    String kind,
    Map<String, Object?> record,
  ) {
    final id = record['id']?.toString() ??
        record['bookingReference']?.toString() ??
        record['name']?.toString() ??
        kind;
    _openTool(
      'resort-record:' + kind + ':' + id,
      PlpResortRecordScreen(
        kind: kind,
        record: record,
        onBack: _closeTool,
      ),
    );
  }

  void _openResortModule(String moduleId) {
    final bootstrap = _lastBootstrap ?? const <String, Object?>{};
    _openTool(
      'resort-module:' + moduleId,
      PlpResortOperationalScreen(
        moduleId: moduleId,
        bootstrap: bootstrap,
        onBack: _closeTool,
        onRefresh: _refresh,
        onOpenRecord: (kind, record) => _openResortRecord(kind, record),
      ),
    );
  }

  void _openResortSection(
    String destination, {
    bool replaceHistory = false,
  }) {
    if (destination == 'today' || destination == 'home') {
      _openHome();
      return;
    }
    final section = plpResortSectionById(destination);
    if (section == null) return;
    final bootstrap = _lastBootstrap ?? const <String, Object?>{};
    _openTool(
      'resort:' + destination,
      PlpResortWorkspaceScreen(
        section: section,
        bootstrap: bootstrap,
        onOpenNavigation: _openDrawer,
        onRefresh: _refresh,
        onOpenSection: _openResortSection,
        onOpenModule: _openResortModule,
        onOpenRecord: (kind, record) => _openResortRecord(kind, record),
        onOpenOperationsRoom: () {
          _openTool(
            'operations-room',
            PandoraOperationsRoomScreen(onHome: _closeTool),
          );
        },
        onOpenGuestExperience: () => _open(6),
        onOpenTeam: () => _openTeamManagement(bootstrap),
        onOpenActivity: () => _open(10),
      ),
      replaceHistory: replaceHistory,
    );
  }

  void _openTeamManagement(
    Map<String, Object?> bootstrap, {
    bool invite = false,
  }) {
    final organizationId = _organizationId(bootstrap);
    if (organizationId == null || organizationId.isEmpty) return;
    _openTool(
      'team-management',
      PlpTeamManagementScreen(
        organizationId: organizationId,
        openInviteOnLoad: invite,
        onBack: _closeTool,
        onChanged: _refresh,
      ),
    );
  }

  void _selectDrawerDestination(String destination) {
    if (plpResortSectionById(destination) != null) {
      _closeDrawer();
      _openResortSection(destination, replaceHistory: true);
      return;
    }
    final target = _surfaceByDestination[destination];
    if (target == null) return;
    _closeDrawer();
    if (target == 0) {
      _openHome();
    } else {
      _open(target);
    }
  }

  Future<void> _openRecentThread(PlpRecentChatItem item) async {
    _closeDrawer();
    _open(1);
    await WidgetsBinding.instance.endOfFrame;
    await _alfredKey.currentState?.loadThread(item.id);
  }

  Future<void> _startNewChat() async {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _closeDrawer();
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
              onOpenSection: _openResortSection,
              onOpenModule: _openResortModule,
              onOpenRecord: (kind, record) => _openResortRecord(kind, record),
            ),
            AskPandoraScreen(
              key: _alfredKey,
              onHome: _openHome,
              onMore: () => _open(4),
              enterpriseContext: alfredContext,
              allowCharacterContext: false,
              allowProjectContext: false,
            ),
            PlpOperationsScreen(
              key: const ValueKey('plp-operations-room'),
              bootstrap: bootstrap,
              onOpenNavigation: _openDrawer,
              onOpenInfrastructure: () => _open(14),
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
              onOpenInfrastructure: () => _open(14),
            ),
            const LocalAiSettingsScreen(
              key: ValueKey('plp-local-ai-settings'),
            ),
            PlpOverviewScreen(
              key: const ValueKey('plp-overview'),
              bootstrap: bootstrap,
              onOpenNavigation: _openDrawer,
            ),
            PlpGuestsScreen(
              key: const ValueKey('plp-guests'),
              bootstrap: bootstrap,
              onOpenNavigation: _openDrawer,
            ),
            PlpResortWorkspaceScreen(
              key: ValueKey<String>(
                'plp-team-unified-${bootstrap['generatedAt'] ?? ''}',
              ),
              section: plpResortSectionById('team')!,
              bootstrap: bootstrap,
              onOpenNavigation: _openDrawer,
              onRefresh: _refresh,
              onOpenSection: _openResortSection,
              onOpenOperationsRoom: () {
                _openTool(
                  'operations-room',
                  PandoraOperationsRoomScreen(onHome: _closeTool),
                );
              },
              onOpenGuestExperience: () => _open(6),
              onOpenTeam: () => _openTeamManagement(bootstrap),
              onOpenActivity: () => _open(10),
            ),
            PlpRevenueScreen(
              key: const ValueKey('plp-revenue'),
              bootstrap: bootstrap,
              onOpenNavigation: _openDrawer,
            ),
            PlpNeedsYouScreen(
              key: const ValueKey('plp-needs-you'),
              bootstrap: bootstrap,
              onOpenNavigation: _openDrawer,
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
            TaxComplianceScreen(
              key: const ValueKey('plp-tax-compliance'),
              workspaceKey: 'plp-boracay',
              workspaceName: 'PLP Boracay',
              enterpriseContext: const <String, Object?>{
                'surface': 'enterprise_tax',
                'route': '/enterprise/workspaces/plp-boracay/tax-compliance',
                'capabilities': <String>[],
                'identityScope': 'enterprise_workspace',
                'selectedObject': <String, String>{
                  'workspaceKey': 'plp-boracay',
                  'workspaceName': 'PLP Boracay',
                  'workspaceType': 'Luxury Resort',
                  'section': 'Tax & Compliance',
                },
              },
              onHome: _openHome,
            ),
            PlpConnectivityInfrastructureScreen(
              key: const ValueKey('plp-connectivity-infrastructure-screen'),
              bootstrap: bootstrap,
              onOpenNavigation: _openDrawer,
              onAskPandora: (prompt) {
                unawaited(_submitCommand(prompt));
              },
            ),
          ];

          return KeyedSubtree(
            key: const ValueKey('plp-enterprise-shell'),
            child: PopScope<void>(
              canPop: !_drawerOpen &&
                  _index == 0 &&
                  _surfaceHistory.isEmpty &&
                  _routedTool == null,
              onPopInvokedWithResult: (didPop, result) {
                if (!didPop) _handleWorkspaceBack();
              },
              child: Scaffold(
                key: _scaffoldKey,
                backgroundColor: _canvas,
                drawerEnableOpenDragGesture: true,
                drawerEdgeDragWidth: 32,
                drawerScrimColor: const Color(0x99000000),
                onDrawerChanged: (open) {
                  if (_drawerOpen != open && mounted) {
                    setState(() => _drawerOpen = open);
                  }
                  if (open) {
                    _dismissWorkspaceKeyboard();
                    _resetDrawerScroll();
                    unawaited(_loadRecentChats(force: true));
                  }
                },
                drawer: PlpNavigationDrawer(
                  selectedDestination: _drawerSelection,
                  scrollController: _drawerScrollController,
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
                  openDrawer: null,
                  child: Stack(
                    children: [
                      Navigator(
                        key: _contentNavigatorKey,
                        pages: <Page<void>>[
                          MaterialPage<void>(
                            key: const ValueKey<String>('plp-shell-base-route'),
                            child: _PlpLazyIndexedStack(
                              index: _index,
                              cacheEpoch: bootstrap['generatedAt']?.toString(),
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
                      Positioned(
                        top: 0,
                        left: 0,
                        child: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 0, 0),
                            child: PandoraMenuButton(
                              key: const ValueKey<String>(
                                'plp-floating-navigation',
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
                        hintText: _commandHint,
                        busy: _commandBusy,
                        reply: _commandReply,
                        onDismissReply: () {
                          if (_commandReply != null) {
                            setState(() => _commandReply = null);
                          }
                        },
                        onOpenChat: () => _open(1),
                      ),
              ),
            ),
          );
        },
      );
}

class _PlpLazyIndexedStack extends StatefulWidget {
  const _PlpLazyIndexedStack({
    required this.index,
    required this.children,
    this.cacheEpoch,
  });

  final int index;
  final List<Widget> children;
  final String? cacheEpoch;

  @override
  State<_PlpLazyIndexedStack> createState() => _PlpLazyIndexedStackState();
}

class _PlpLazyIndexedStackState extends State<_PlpLazyIndexedStack> {
  final Map<int, Widget> _cache = <int, Widget>{};

  @override
  void initState() {
    super.initState();
    _cache[widget.index] = widget.children[widget.index];
  }

  @override
  void didUpdateWidget(covariant _PlpLazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheEpoch != widget.cacheEpoch ||
        oldWidget.children.length != widget.children.length) {
      _cache.clear();
    }
    _cache[widget.index] = widget.children[widget.index];
  }

  @override
  Widget build(BuildContext context) {
    _cache[widget.index] ??= widget.children[widget.index];
    return IndexedStack(
      index: widget.index,
      children: List<Widget>.generate(
        widget.children.length,
        (index) => _cache[index] ??
            KeyedSubtree(
              key: ValueKey<String>('plp-lazy-placeholder-$index'),
              child: const SizedBox.shrink(),
            ),
      ),
    );
  }
}

class PlpCommandDock extends StatelessWidget {
  const PlpCommandDock({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    this.hintText = 'Message Pandora',
    this.busy = false,
    this.reply,
    this.onDismissReply,
    this.onOpenChat,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onSubmit;
  final String hintText;
  final bool busy;
  final String? reply;
  final VoidCallback? onDismissReply;
  final VoidCallback? onOpenChat;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: focusNode,
        builder: (context, _) {
          final keyboardInset = focusNode.hasFocus
              ? MediaQuery.viewInsetsOf(context).bottom
              : 0.0;
          return AnimatedPadding(
            key: const ValueKey<String>('plp-command-keyboard-offset'),
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(bottom: keyboardInset),
            child: SafeArea(
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (busy || (reply?.trim().isNotEmpty ?? false))
                      _PlpCommandResult(
                        busy: busy,
                        reply: reply,
                        onDismiss: onDismissReply ?? () {},
                        onOpenChat: onOpenChat ?? () {},
                      ),
                    DecoratedBox(
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
                              decoration: InputDecoration(
                                hintText: hintText,
                                hintStyle: const TextStyle(
                                  color: Color(0xFFB6B0A7),
                                  fontSize: 15.5,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isDense: true,
                                contentPadding:
                                    const EdgeInsets.fromLTRB(2, 15, 6, 14),
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
                              onPressed: busy ? null : onSubmit,
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
                  ],
                ),
              ),
            ),
          );
        },
      );
}

class _PlpCommandResult extends StatelessWidget {
  const _PlpCommandResult({
    required this.busy,
    required this.reply,
    required this.onDismiss,
    required this.onOpenChat,
  });

  final bool busy;
  final String? reply;
  final VoidCallback onDismiss;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    final text = busy
        ? 'Pandora is working on this request…'
        : (reply?.trim().isNotEmpty ?? false)
            ? reply!.trim()
            : '';
    return Container(
      key: const ValueKey<String>('plp-command-result'),
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFFFFDFC),
        border: Border(
          left: BorderSide(color: Color(0xFFE1DBD1)),
          right: BorderSide(color: Color(0xFFE1DBD1)),
          top: BorderSide(color: Color(0xFFE1DBD1)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.auto_awesome_outlined,
              color: Color(0xFF70643F),
              size: 18,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              key: const ValueKey<String>('plp-command-result-text'),
              maxLines: busy ? 1 : 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF35312C),
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
          if (!busy) ...[
            TextButton(
              key: const ValueKey<String>('plp-command-open-chat'),
              onPressed: onOpenChat,
              child: const Text('Open chat'),
            ),
            IconButton(
              key: const ValueKey<String>('plp-command-dismiss-result'),
              tooltip: 'Dismiss',
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ],
      ),
    );
  }
}
