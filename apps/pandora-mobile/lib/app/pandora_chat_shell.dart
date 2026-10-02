import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/analytics/owner_analytics.dart';
import '../core/data/pandora_intelligence_api.dart';
import '../core/design/pandora_tokens.dart';
import '../core/widgets/pandora_mark.dart';
import '../core/widgets/pandora_navigation_layout.dart';
import '../core/widgets/pandora_navigation.dart';
import '../features/activity/activity_screen.dart';
import '../features/approvals/approvals_screen.dart';
import '../features/enterprise/batalla_workspace_screen.dart';
import '../features/enterprise/enterprise_vision_screen.dart';
import '../features/enterprise/enterprise_workspace_home.dart';
import '../features/enterprise/marketing_growth_workspace_screen.dart';
import '../features/enterprise/provider_ecosystem_screen.dart';
import '../features/enterprise/tax_compliance_screen.dart';
import '../features/operations/operations_room_screen.dart';
import '../features/plugins/plugins_screen.dart';
import '../features/simple/ask_pandora_screen.dart';
import '../features/simple/more_screen.dart';
import '../features/simple/offline_evidence_screen.dart';
import '../features/simple/pandora_v2_ui.dart';
import '../features/simple/projects_screen.dart';
import '../features/simple/simple_safety_screen.dart';
import 'pandora_conversation_layer.dart';
import 'pandora_shared_conversation_scope.dart';
import 'pandora_dependencies.dart';

class PandoraChatShell extends StatefulWidget {
  const PandoraChatShell({super.key});

  @override
  State<PandoraChatShell> createState() => _PandoraChatShellState();
}

class _PandoraChatShellState extends State<PandoraChatShell> {
  static const _destinations = <_ChatDestination>[
    _ChatDestination('Pandora', Icons.chat_bubble_outline_rounded,
        Icons.chat_bubble_rounded),
    _ChatDestination('Projects', Icons.folder_outlined, Icons.folder_rounded),
    _ChatDestination('Needs You', Icons.check_circle_outline_rounded,
        Icons.check_circle_rounded),
    _ChatDestination('Settings & More', Icons.tune_rounded, Icons.tune_rounded),
    _ChatDestination('Activity', Icons.history_rounded, Icons.history_rounded),
    _ChatDestination(
        'Live Connections', Icons.extension_outlined, Icons.extension_rounded),
    _ChatDestination('Saved evidence', Icons.offline_pin_outlined,
        Icons.offline_pin_rounded),
    _ChatDestination(
        'Verify & Safety', Icons.shield_outlined, Icons.shield_rounded),
    _ChatDestination(
        'Operations Room', Icons.groups_2_outlined, Icons.groups_2_rounded),
    _ChatDestination('Home', Icons.home_outlined, Icons.home_rounded),
    _ChatDestination(
      'Vision Intelligence',
      Icons.videocam_outlined,
      Icons.videocam_rounded,
    ),
    _ChatDestination(
      'Capabilities & Providers',
      Icons.account_tree_outlined,
      Icons.account_tree_rounded,
    ),
  ];

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<AskPandoraScreenState> _chatKey =
      GlobalKey<AskPandoraScreenState>();
  final Map<int, Widget> _roots = <int, Widget>{};
  Map<String, Object?>? _activeEnterpriseContext;
  EnterpriseWorkspaceSelection? _activeWorkspaceSelection;
  Map<String, String> _surfaceSelectedObject = const <String, String>{};
  final Set<int> _visited = <int>{9};
  List<PandoraIntelligenceThread> _threads =
      const <PandoraIntelligenceThread>[];
  bool _historyLoading = false;
  bool _historyLoaded = false;
  int _index = 9;
  final _drawerScrollController = ScrollController();
  final _recentChatsScrollController = ScrollController();
  bool _drawerOpenScheduled = false;
  bool _recentChatsOpenScheduled = false;

  @override
  void dispose() {
    _drawerScrollController.dispose();
    _recentChatsScrollController.dispose();
    super.dispose();
  }

  void _resetDrawerScroll() {
    if (_drawerScrollController.hasClients) _drawerScrollController.jumpTo(0);
  }

  void _openDrawer() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_drawerOpenScheduled) return;
    _drawerOpenScheduled = true;
    final scaffold = _scaffoldKey.currentState;
    if (scaffold?.isEndDrawerOpen ?? false) scaffold?.closeEndDrawer();
    _resetDrawerScroll();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _drawerOpenScheduled = false;
      _resetDrawerScroll();
      final next = _scaffoldKey.currentState;
      if (!(next?.isEndDrawerOpen ?? false)) next?.openDrawer();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _openRecentChats() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_recentChatsOpenScheduled) return;
    _recentChatsOpenScheduled = true;
    final scaffold = _scaffoldKey.currentState;
    if (scaffold?.isDrawerOpen ?? false) scaffold?.closeDrawer();
    if (!_historyLoaded) _historyLoaded = true;
    unawaited(_refreshHistory());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _recentChatsOpenScheduled = false;
      if (_recentChatsScrollController.hasClients) {
        _recentChatsScrollController.jumpTo(0);
      }
      final next = _scaffoldKey.currentState;
      if (!(next?.isDrawerOpen ?? false)) next?.openEndDrawer();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void initState() {
    super.initState();
    unawaited(OwnerAnalytics.shared.capture(OwnerAnalyticsEvent.appOpened));
    unawaited(
      OwnerAnalytics.shared.capture(
        OwnerAnalyticsEvent.screenViewed,
        resultClass: 'enterprise_home',
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_historyLoaded) {
      _historyLoaded = true;
      unawaited(_refreshHistory());
    }
  }

  Future<void> _refreshHistory() async {
    if (_historyLoading) return;
    final intelligence = PandoraDependencies.of(context).intelligence;
    if (intelligence == null) return;
    setState(() => _historyLoading = true);
    try {
      final threads = await intelligence.recentThreads();
      if (!mounted) return;
      setState(() => _threads = threads);
    } on PandoraIntelligenceException {
      // Chat remains usable when history is temporarily unavailable.
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  void _select(int value) {
    if (value < 0 || value >= _destinations.length) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final scaffold = _scaffoldKey.currentState;
    if (scaffold?.isDrawerOpen ?? false) scaffold?.closeDrawer();
    if (scaffold?.isEndDrawerOpen ?? false) scaffold?.closeEndDrawer();
    if (value == _index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _index = value;
      _visited.add(value);
      _surfaceSelectedObject = const <String, String>{};
    });
    final screen = switch (value) {
      0 => 'pandora_chat',
      1 => 'projects',
      2 => 'needs_you',
      3 => 'more',
      4 => 'activity',
      5 => 'live_connections',
      6 => 'saved_evidence',
      7 => 'verify_safety',
      8 => 'operations_room',
      9 => 'enterprise_home',
      10 => 'vision_intelligence',
      11 => 'provider_ecosystem',
      _ => 'pandora_chat',
    };
    unawaited(
      OwnerAnalytics.shared.capture(
        OwnerAnalyticsEvent.screenViewed,
        resultClass: screen,
      ),
    );
  }

  void _openConversationHistory() {
    FocusManager.instance.primaryFocus?.unfocus();
    final scaffold = _scaffoldKey.currentState;
    if (scaffold?.isDrawerOpen ?? false) scaffold?.closeDrawer();
    if (scaffold?.isEndDrawerOpen ?? false) scaffold?.closeEndDrawer();
    _chatKey.currentState?.showHistory();
  }

  void _newChat() {
    final chat = _chatKey.currentState;
    if (chat == null) return;
    chat.newChat();
    chat.showHistory();
    unawaited(_refreshHistory());
  }

  Future<void> _openThread(PandoraIntelligenceThread thread) async {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold?.isDrawerOpen ?? false) scaffold?.closeDrawer();
    if (scaffold?.isEndDrawerOpen ?? false) scaffold?.closeEndDrawer();
    final chat = _chatKey.currentState;
    if (chat == null) return;
    chat.showHistory();
    await chat.loadThread(thread.id);
  }

  Future<void> _manageThread(PandoraIntelligenceThread thread) async {
    final action = await showModalBottomSheet<_ThreadAction>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () => Navigator.of(sheetContext).pop(_ThreadAction.rename),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Move to project'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ThreadAction.project),
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('Archive'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ThreadAction.archive),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete'),
              textColor: PandoraV2Colors.danger,
              iconColor: PandoraV2Colors.danger,
              onTap: () => Navigator.of(sheetContext).pop(_ThreadAction.delete),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _ThreadAction.rename:
        await _renameThread(thread);
        break;
      case _ThreadAction.project:
        await _moveThreadToProject(thread);
        break;
      case _ThreadAction.archive:
        await _archiveThread(thread);
        break;
      case _ThreadAction.delete:
        await _deleteThread(thread);
        break;
    }
  }

  Future<void> _renameThread(PandoraIntelligenceThread thread) async {
    final controller = TextEditingController(text: thread.title);
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename conversation'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          decoration: const InputDecoration(hintText: 'Conversation name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || title == null || title.isEmpty || title == thread.title) {
      return;
    }
    await _runThreadMutation(
      () => PandoraDependencies.of(context)
          .intelligence!
          .renameThread(thread.id, title),
      success: 'Conversation renamed.',
    );
  }

  Future<void> _archiveThread(PandoraIntelligenceThread thread) async {
    await _runThreadMutation(
      () => PandoraDependencies.of(context)
          .intelligence!
          .archiveThread(thread.id),
      success: 'Conversation archived.',
    );
  }

  Future<void> _deleteThread(PandoraIntelligenceThread thread) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete conversation?'),
            content: Text(
                'Delete “${thread.title}” and its saved messages? This cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted || !confirmed) return;
    await _runThreadMutation(
      () =>
          PandoraDependencies.of(context).intelligence!.deleteThread(thread.id),
      success: 'Conversation deleted.',
    );
  }

  Future<void> _moveThreadToProject(PandoraIntelligenceThread thread) async {
    final intelligence = PandoraDependencies.of(context).intelligence;
    if (intelligence == null) return;
    try {
      final projectSnapshot = await PandoraDependencies.of(context)
          .repository
          .projects(allowCached: true);
      if (!mounted) return;
      final selected = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
            children: [
              const ListTile(
                title: Text('Move conversation to project'),
                subtitle: Text(
                    'Choose a persistent project context or remove the association.'),
              ),
              ListTile(
                leading: const Icon(Icons.link_off_rounded),
                title: const Text('No project'),
                onTap: () => Navigator.of(sheetContext).pop(''),
              ),
              for (final project in projectSnapshot.data)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(project.name),
                  trailing: thread.projectId == project.id
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(project.id),
                ),
            ],
          ),
        ),
      );
      if (!mounted || selected == null) return;
      await _runThreadMutation(
        () => intelligence.associateThreadWithProject(
          thread.id,
          selected.isEmpty ? null : selected,
        ),
        success: selected.isEmpty
            ? 'Project association removed.'
            : 'Conversation moved to project.',
      );
    } on PandoraIntelligenceException catch (error) {
      _showThreadMessage(error.message);
    } on Exception {
      _showThreadMessage(
          'Pandora could not load projects for this conversation.');
    }
  }

  Future<void> _runThreadMutation(
    Future<void> Function() mutation, {
    required String success,
  }) async {
    final intelligence = PandoraDependencies.of(context).intelligence;
    if (intelligence == null) return;
    try {
      await mutation();
      if (!mounted) return;
      await _refreshHistory();
      if (mounted) _showThreadMessage(success);
    } on PandoraIntelligenceException catch (error) {
      if (mounted) _showThreadMessage(error.message);
    }
  }

  void _showThreadMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }



  String _sessionWorkspaceProfileKey() {
    final value =
        PandoraDependencies.of(context).auth.currentSession?.workspaceProfile;
    return switch (value) {
      'dan' => 'dan',
      'secretary' => 'secretary',
      'atty_batalla' => 'atty_batalla',
      _ => 'atty_batalla',
    };
  }

  String _activeWorkspaceProfileKey() {
    final selected = _activeEnterpriseContext?['selectedObject'];
    if (selected is Map) {
      final value = selected['workspaceProfile'];
      if (value == 'dan' || value == 'secretary' || value == 'atty_batalla') {
        return value as String;
      }
    }
    return _sessionWorkspaceProfileKey();
  }


  void _openWorkspace(EnterpriseWorkspaceSelection selection) {
    final nextContext = selection.enterpriseContext;
    if (selection.workspace.key == 'batalla-associates') {
      final selected = Map<String, Object?>.from(
        nextContext['selectedObject']! as Map,
      );
      selected['workspaceProfile'] = _sessionWorkspaceProfileKey();
      nextContext['selectedObject'] = selected;
    }
    setState(() {
      _activeEnterpriseContext = nextContext;
      _activeWorkspaceSelection = selection;
      _surfaceSelectedObject = const <String, String>{};
      _roots.remove(0);
      _visited.add(0);
    });
    _select(0);
    unawaited(
      OwnerAnalytics.shared.capture(
        OwnerAnalyticsEvent.screenViewed,
        resultClass: 'enterprise_workspace_' +
            selection.workspace.key +
            '_' +
            selection.section.routeSlug,
      ),
    );
  }


  void _bindEnterpriseContext(Map<String, Object?> context) {
    if (!mounted) return;
    setState(() {
      _activeEnterpriseContext = Map<String, Object?>.from(context);
      _surfaceSelectedObject = const <String, String>{};
    });
  }

  void _bindSelectedObject(Map<String, String> selected) {
    if (!mounted) return;
    setState(() => _surfaceSelectedObject = Map<String, String>.from(selected));
  }

  Future<String?> _submitSharedPrompt(
    String prompt, {
    Map<String, String>? selectedObject,
  }) async {
    if (selectedObject != null) _bindSelectedObject(selectedObject);
    await WidgetsBinding.instance.endOfFrame;
    final chat = _chatKey.currentState;
    if (chat == null) return null;
    chat.showHistory();
    return chat.submitExternalPrompt(prompt, requestFocus: false);
  }

  Future<void> _openSharedThread(String threadId) async {
    final chat = _chatKey.currentState;
    if (chat == null) return;
    chat.showHistory();
    await chat.loadThread(threadId);
  }

  void _reportSharedFailure(
    String code, {
    Map<String, String>? selectedObject,
  }) {
    if (selectedObject != null) _bindSelectedObject(selectedObject);
    _chatKey.currentState?.showExternalFailureMessage(
      pandoraNaturalFailureMessage(code),
    );
  }

  Map<String, Object?> _conversationContextForCurrentSurface() {
    if (_index == 0 && _activeEnterpriseContext != null) {
      final context = Map<String, Object?>.from(_activeEnterpriseContext!);
      final selected = context['selectedObject'];
      context['selectedObject'] = <String, String>{
        if (selected is Map)
          for (final entry in selected.entries)
            entry.key.toString(): entry.value.toString(),
        ..._surfaceSelectedObject,
      };
      return context;
    }
    final route = switch (_index) {
      1 => '/projects',
      2 => '/needs-you',
      3 => '/settings-more',
      4 => '/activity',
      5 => '/connections',
      6 => '/saved-evidence',
      7 => '/verify-safety',
      8 => '/operations-room',
      9 => '/home',
      10 => '/enterprise/vision-intelligence',
      11 => '/capabilities-providers',
      _ => '/home',
    };
    return <String, Object?>{
      'surface': 'pandora_business_os',
      'route': route,
      'capabilities': const <String>[],
      'identityScope': 'owner_workspace',
      'selectedObject': <String, String>{
        'screen': _destinations[_index].label,
        'destinationIndex': _index.toString(),
        ..._surfaceSelectedObject,
      },
    };
  }

  Widget _root(int index) => _roots.putIfAbsent(

        index,
        () => switch (index) {
          0 => _activeWorkspaceSelection?.section.routeSlug ==
                  'tax-compliance'
              ? TaxComplianceScreen(
                  workspaceKey: _activeWorkspaceSelection!.workspace.key,
                  workspaceName: _activeWorkspaceSelection!.workspace.name,
                  enterpriseContext:
                      _activeEnterpriseContext ?? _activeWorkspaceSelection!.enterpriseContext,
                  onHome: () => _select(9),
                )
              : _activeWorkspaceSelection?.workspace.key ==
                      'pandora-marketing-growth'
                  ? MarketingGrowthWorkspaceScreen(
                      initialRouteSlug:
                          _activeWorkspaceSelection!.section.routeSlug,
                      enterpriseContext:
                          _activeEnterpriseContext ?? _activeWorkspaceSelection!.enterpriseContext,
                      onHome: () => _select(9),
                      onApprovals: () => _select(2),
                    )
                  : _activeWorkspaceSelection?.workspace.key ==
                      'batalla-associates'
                  ? BatallaWorkspaceScreen(
                      initialRouteSlug:
                          _activeWorkspaceSelection!.section.routeSlug,
                      profileKey: _activeWorkspaceProfileKey(),
                      onBackToWorkspaces: () => _select(9),
                    )
                  : const SizedBox.expand(),
          1 => const ProjectsScreen(),
          2 => const ApprovalsScreen(),
          3 => const MoreScreen(),
          4 => const ActivityScreen(),
          5 => PluginsScreen(onOpenProviderCatalog: () => _select(11)),
          6 => const OfflineEvidenceScreen(),
          7 => const SimpleSafetyScreen(),
          8 => PandoraOperationsRoomScreen(
              onHome: () => _select(9),
              globalConversation: true,
            ),
          9 => EnterpriseWorkspaceHome(
              onOpen: _openWorkspace,
              onSearchChats: _openRecentChats,
              onActivity: () => _select(4),
              onMore: () => _select(3),
            ),
          10 => const EnterpriseVisionScreen(),
          11 => ProviderEcosystemScreen(
              onOpenConnections: () => _select(5),
            ),
          _ => const SizedBox.expand(),
        },
      );

  ThemeData _theme(ThemeData base) {
    const scheme = ColorScheme.dark(
      primary: PandoraV2Colors.ink,
      onPrimary: Colors.black,
      primaryContainer: PandoraV2Colors.soft,
      onPrimaryContainer: PandoraV2Colors.ink,
      secondary: PandoraV2Colors.ink,
      onSecondary: Colors.black,
      surface: PandoraV2Colors.surface,
      onSurface: PandoraV2Colors.ink,
      error: PandoraV2Colors.danger,
      onError: Colors.black,
      outline: PandoraV2Colors.line,
      outlineVariant: PandoraV2Colors.line,
    );
    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: PandoraV2Colors.canvas,
      canvasColor: PandoraV2Colors.canvas,
      extensions: const <ThemeExtension<dynamic>>[PandoraPalette.graphite],
      appBarTheme: const AppBarTheme(
        backgroundColor: PandoraV2Colors.canvas,
        foregroundColor: PandoraV2Colors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: PandoraV2Colors.line,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PandoraV2Colors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: PandoraV2Colors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: PandoraV2Colors.ink, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: PandoraV2Colors.danger),
        ),
      ),
    );
  }

  Widget _sidePanel() => _PandoraSidePanel(
        scrollController: _drawerScrollController,
        destinations: _destinations,
        selectedIndex: _index,
        onSelected: (value) {
          if (value == 0) {
            _openConversationHistory();
            return;
          }
          _select(value);
        },
      );

  Widget _recentChatsPanel() => _PandoraRecentChatsPanel(
        scrollController: _recentChatsScrollController,
        threads: _threads,
        historyLoading: _historyLoading,
        onNewChat: _newChat,
        onOpenThread: _openThread,
        onManageThread: _manageThread,
      );

  @override
  Widget build(BuildContext context) => Theme(
        data: _theme(Theme.of(context)),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final body = IndexedStack(
              index: _index,
              children: [
                for (var i = 0; i < _destinations.length; i++)
                  _visited.contains(i) || i == _index
                      ? _root(i)
                      : const SizedBox.shrink(),
              ],
            );

            final activeChat = PandoraConversationLayer(
              key: const ValueKey<String>('pandora-global-active-chat-shell'),
              businessWorkspace: PandoraSharedConversationScope(
                submitPrompt: _submitSharedPrompt,
                openThread: _openSharedThread,
                bindEnterpriseContext: _bindEnterpriseContext,
                bindSelectedObject: _bindSelectedObject,
                reportFailure: _reportSharedFailure,
                child: body,
              ),
              conversation: AskPandoraScreen(
                key: _chatKey,
                onSearchChats: _openRecentChats,
                onMore: () => _select(3),
                onHome: () => _select(9),
                enterpriseContext: _conversationContextForCurrentSurface(),
                shellOverlay: true,
              ),
            );

            if (constraints.maxWidth >= 900) {
              return Scaffold(
                key: _scaffoldKey,
                backgroundColor: PandoraV2Colors.canvas,
                drawerScrimColor: const Color(0xD9000000),
                endDrawer: Drawer(
                  key: const ValueKey<String>('pandora-recent-chats-drawer'),
                  width: 340,
                  backgroundColor: const Color(0xFA000000),
                  surfaceTintColor: Colors.transparent,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      bottomLeft: Radius.circular(24),
                    ),
                  ),
                  child: SafeArea(child: _recentChatsPanel()),
                ),
                body: Row(
                  children: [
                    SizedBox(width: 264, child: SafeArea(child: _sidePanel())),
                    const VerticalDivider(
                        width: 1, color: PandoraV2Colors.line),
                    Expanded(
                      child: PandoraNavigationScope(
                        openDrawer: null,
                        child: activeChat,
                      ),
                    ),
                  ],
                ),
              );
            }

            return Scaffold(
              key: _scaffoldKey,
              backgroundColor: PandoraV2Colors.canvas,
              onDrawerChanged: (open) {
                if (open) {
                  FocusManager.instance.primaryFocus?.unfocus();
                  _resetDrawerScroll();
                }
              },
              onEndDrawerChanged: (open) {
                if (open) {
                  FocusManager.instance.primaryFocus?.unfocus();
                  if (_recentChatsScrollController.hasClients) {
                    _recentChatsScrollController.jumpTo(0);
                  }
                  unawaited(_refreshHistory());
                }
              },
              drawerEnableOpenDragGesture: true,
              endDrawerEnableOpenDragGesture: false,
              drawerEdgeDragWidth: 32,
              drawerScrimColor: const Color(0xD9000000),
              drawer: Drawer(
                key: const ValueKey<String>('pandora-primary-navigation-drawer'),
                width: 304,
                backgroundColor: const Color(0xFA000000),
                surfaceTintColor: Colors.transparent,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: SafeArea(child: _sidePanel()),
              ),
              endDrawer: Drawer(
                key: const ValueKey<String>('pandora-recent-chats-drawer'),
                width: 340,
                backgroundColor: const Color(0xFA000000),
                surfaceTintColor: Colors.transparent,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    bottomLeft: Radius.circular(24),
                  ),
                ),
                child: SafeArea(child: _recentChatsPanel()),
              ),
              body: PandoraNavigationScope(
                openDrawer: _openDrawer,
                child: activeChat,
              ),
            );
          },
        ),
      );
}

class _PandoraSidePanel extends StatelessWidget {
  const _PandoraSidePanel({
    required this.destinations,
    required this.scrollController,
    required this.selectedIndex,
    required this.onSelected,
  });

  final ScrollController scrollController;
  final List<_ChatDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFA000000),
        child: PandoraNavigationLayout(
          controller: scrollController,
          scrollKey: const ValueKey<String>('pandora-side-panel-scroll'),
          bodyPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          header: const Padding(
            key: ValueKey<String>('pandora-side-panel-top-overlay'),
            padding: EdgeInsets.fromLTRB(20, 18, 12, 12),
            child: Row(
              children: [
                PandoraMark(size: 28),
                SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'Pandora',
                    style: TextStyle(
                      color: PandoraV2Colors.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DrawerSection(
                label: 'Core systems',
                indices: const <int>[9, 10, 0, 8],
                destinations: destinations,
                selectedIndex: selectedIndex,
                onSelected: onSelected,
              ),
              _DrawerSection(
                label: 'Work',
                indices: const <int>[1, 2, 4],
                destinations: destinations,
                selectedIndex: selectedIndex,
                onSelected: onSelected,
              ),
              _DrawerSection(
                label: 'Capabilities',
                indices: const <int>[11, 5, 6],
                destinations: destinations,
                selectedIndex: selectedIndex,
                onSelected: onSelected,
              ),
              _DrawerSection(
                label: 'Security',
                indices: const <int>[7],
                destinations: destinations,
                selectedIndex: selectedIndex,
                onSelected: onSelected,
              ),
              _DrawerSection(
                label: 'Account',
                indices: const <int>[3],
                destinations: destinations,
                selectedIndex: selectedIndex,
                onSelected: onSelected,
                showDivider: false,
              ),
            ],
          ),
          footer: const SizedBox.shrink(),
        ),
      );
}

class _DrawerSection extends StatelessWidget {
  const _DrawerSection({
    required this.label,
    required this.indices,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.showDivider = true,
  });

  final String label;
  final List<int> indices;
  final List<_ChatDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool showDivider;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 7),
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: PandoraV2Colors.muted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .8,
              ),
            ),
          ),
          for (final index in indices)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                selected: index == selectedIndex,
                selectedColor: PandoraV2Colors.ink,
                iconColor: PandoraV2Colors.muted,
                textColor: PandoraV2Colors.ink,
                selectedTileColor: PandoraV2Colors.soft,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: Icon(
                  index == selectedIndex
                      ? destinations[index].selectedIcon
                      : destinations[index].icon,
                  size: 22,
                ),
                title: Text(
                  destinations[index].label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: index == selectedIndex
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                onTap: () => onSelected(index),
              ),
            ),
          if (showDivider)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(height: 1, color: PandoraV2Colors.line),
            ),
        ],
      );
}

class _PandoraRecentChatsPanel extends StatefulWidget {
  const _PandoraRecentChatsPanel({
    required this.scrollController,
    required this.threads,
    required this.historyLoading,
    required this.onNewChat,
    required this.onOpenThread,
    required this.onManageThread,
  });

  final ScrollController scrollController;
  final List<PandoraIntelligenceThread> threads;
  final bool historyLoading;
  final VoidCallback onNewChat;
  final ValueChanged<PandoraIntelligenceThread> onOpenThread;
  final ValueChanged<PandoraIntelligenceThread> onManageThread;

  @override
  State<_PandoraRecentChatsPanel> createState() =>
      _PandoraRecentChatsPanelState();
}

class _PandoraRecentChatsPanelState extends State<_PandoraRecentChatsPanel> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.toLowerCase();
    final threads = widget.threads
        .where(
          (thread) =>
              needle.isEmpty || thread.title.toLowerCase().contains(needle),
        )
        .take(30)
        .toList(growable: false);
    return Material(
      key: const ValueKey<String>('pandora-recent-chats-panel'),
      color: const Color(0xFA000000),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Recent chats',
                    style: TextStyle(
                      color: PandoraV2Colors.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.3,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'New chat',
                  onPressed: widget.onNewChat,
                  icon: const Icon(Icons.edit_square, size: 21),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: InputDecoration(
                hintText: 'Search conversations',
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
          ),
          const Divider(height: 1, color: PandoraV2Colors.line),
          Expanded(
            child: widget.historyLoading && widget.threads.isEmpty
                ? const Center(
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : threads.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No conversations found.',
                            style: TextStyle(
                              color: PandoraV2Colors.muted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: widget.scrollController,
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 18),
                        itemCount: threads.length,
                        itemBuilder: (context, index) {
                          final thread = threads[index];
                          return ListTile(
                            key: ValueKey<String>(
                              'pandora-thread-${thread.id}',
                            ),
                            contentPadding:
                                const EdgeInsets.fromLTRB(10, 4, 4, 4),
                            title: Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: Text(
                                thread.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: PandoraV2Colors.ink,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4, right: 10),
                              child: Text(
                                '${_chatRelativeTime(thread.lastMessageAt)} · ${_chatStatusLabel(thread.status)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: PandoraV2Colors.muted,
                                  fontSize: 11,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            trailing: SizedBox.square(
                              dimension: 48,
                              child: IconButton(
                                tooltip: 'Conversation options',
                                padding: EdgeInsets.zero,
                                onPressed: () =>
                                    widget.onManageThread(thread),
                                icon: const Icon(
                                  Icons.more_horiz_rounded,
                                  size: 20,
                                ),
                              ),
                            ),
                            onTap: () => widget.onOpenThread(thread),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

String _chatRelativeTime(DateTime value) {
  final difference = DateTime.now().difference(value.toLocal());
  if (difference.isNegative || difference.inMinutes < 1) return 'just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  return '${difference.inDays}d ago';
}

String _chatStatusLabel(String status) {
  final normalized = status.trim().toLowerCase();
  if (normalized.isEmpty || normalized == 'active') return 'Active';
  return normalized
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}

enum _ThreadAction { rename, project, archive, delete }

class _ChatDestination {
  const _ChatDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
