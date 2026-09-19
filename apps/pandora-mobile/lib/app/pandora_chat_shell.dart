import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/analytics/owner_analytics.dart';
import '../core/data/pandora_intelligence_api.dart';
import '../core/design/pandora_tokens.dart';
import '../core/widgets/pandora_mark.dart';
import '../core/widgets/pandora_navigation.dart';
import '../features/activity/activity_screen.dart';
import '../features/approvals/approvals_screen.dart';
import '../features/enterprise/enterprise_code_screen.dart';
import '../features/enterprise/enterprise_command_stack.dart';
import '../features/enterprise/enterprise_page_context.dart';
import '../features/enterprise/plp_alfred_profile.dart';
import '../features/plugins/plugins_screen.dart';
import '../features/simple/ask_pandora_screen.dart';
import '../features/simple/enterprise_section_screen.dart';
import '../features/simple/more_screen.dart';
import '../features/simple/offline_evidence_screen.dart';
import '../features/simple/pandora_v2_ui.dart';
import '../features/simple/projects_screen.dart';
import '../features/simple/simple_safety_screen.dart';
import 'pandora_dependencies.dart';

class PandoraChatShell extends StatefulWidget {
  const PandoraChatShell({super.key});

  @override
  State<PandoraChatShell> createState() => _PandoraChatShellState();
}

class _PandoraChatShellState extends State<PandoraChatShell> {
  static const _destinations = <_ChatDestination>[
    _ChatDestination(
      'Pandora',
      Icons.chat_bubble_outline_rounded,
      Icons.chat_bubble_rounded,
    ),
    _ChatDestination('Projects', Icons.folder_outlined, Icons.folder_rounded),
    _ChatDestination(
      'Needs You',
      Icons.check_circle_outline_rounded,
      Icons.check_circle_rounded,
    ),
    _ChatDestination('Settings & More', Icons.tune_rounded, Icons.tune_rounded),
    _ChatDestination('Activity', Icons.history_rounded, Icons.history_rounded),
    _ChatDestination(
      'Connections',
      Icons.extension_outlined,
      Icons.extension_rounded,
    ),
    _ChatDestination(
      'Saved evidence',
      Icons.offline_pin_outlined,
      Icons.offline_pin_rounded,
    ),
    _ChatDestination(
      'Verify & Safety',
      Icons.shield_outlined,
      Icons.shield_rounded,
    ),
    _ChatDestination(
      'Overview',
      Icons.dashboard_outlined,
      Icons.dashboard_rounded,
    ),
    _ChatDestination('Team & Access', Icons.group_outlined, Icons.group_rounded),
    _ChatDestination('Data', Icons.storage_outlined, Icons.storage_rounded),
    _ChatDestination(
      'Analytics',
      Icons.query_stats_outlined,
      Icons.query_stats_rounded,
    ),
    _ChatDestination(
      'Marketing',
      Icons.campaign_outlined,
      Icons.campaign_rounded,
    ),
    _ChatDestination(
      'Domains',
      Icons.language_outlined,
      Icons.language_rounded,
    ),
    _ChatDestination('Integrations', Icons.hub_outlined, Icons.hub_rounded),
    _ChatDestination(
      'Security',
      Icons.admin_panel_settings_outlined,
      Icons.admin_panel_settings_rounded,
    ),
    _ChatDestination('Code', Icons.code_outlined, Icons.code_rounded),
    _ChatDestination(
      'Agents',
      Icons.smart_toy_outlined,
      Icons.smart_toy_rounded,
    ),
    _ChatDestination(
      'Workflows',
      Icons.account_tree_outlined,
      Icons.account_tree_rounded,
    ),
    _ChatDestination(
      'Logs',
      Icons.receipt_long_outlined,
      Icons.receipt_long_rounded,
    ),
    _ChatDestination('API', Icons.api_outlined, Icons.api_rounded),
    _ChatDestination(
      'Settings',
      Icons.settings_outlined,
      Icons.settings_rounded,
    ),
    _ChatDestination(
      'MCP',
      Icons.device_hub_outlined,
      Icons.device_hub_rounded,
    ),
    _ChatDestination(
      'Operations',
      Icons.event_note_outlined,
      Icons.event_note_rounded,
    ),
    _ChatDestination(
      'Guests',
      Icons.people_alt_outlined,
      Icons.people_alt_rounded,
    ),
    _ChatDestination(
      'Revenue',
      Icons.payments_outlined,
      Icons.payments_rounded,
    ),
    _ChatDestination(
      'Needs You',
      Icons.priority_high_rounded,
      Icons.priority_high_rounded,
    ),
    _ChatDestination(
      'Activity',
      Icons.history_outlined,
      Icons.history_rounded,
    ),
    _ChatDestination(
      'Vision Intelligence',
      Icons.videocam_outlined,
      Icons.videocam_rounded,
    ),
  ];

  static const _enterpriseDescriptions = <int, String>{
    8: 'System, account and environment summary for Pandora Enterprise.',
    9: 'Manage application users, access state and account administration.',
    10: 'Databases, tables, storage and enterprise data resources.',
    11: 'Usage, product and operational metrics for the enterprise workspace.',
    12: 'Growth, audiences, campaigns and customer engagement tools.',
    13: 'Domain configuration, routing and verification.',
    14: 'External services, connectors and provider integrations.',
    15: 'Authentication, permissions, policies and security controls.',
    16: 'Application source, builds and source-related controls.',
    17: 'AI agents, capabilities, assignments and operating state.',
    18: 'Automations, orchestration and governed workflow execution.',
    19: 'System, activity and runtime logs with operational evidence.',
    20: 'API configuration, credentials governance and developer access.',
    21: 'General Enterprise workspace and application configuration.',
    22: 'MCP servers, tools, resources and connection management.',
    23: 'Today’s operations, booking movement and verified operational exceptions.',
    24: 'Guest and customer records, requests and service context.',
    25: 'Verified business reporting, comparisons and revenue evidence.',
    26: 'Only decisions, approvals or missing input that genuinely require you.',
    27: 'Business-readable verified activity and execution evidence.',
    28: 'Live camera awareness, visual monitoring and incident review for authorized enterprise environments.',
  };

  static const _enterpriseItems = <int, List<String>>{
    8: ['Environment health', 'Usage summary', 'Recent operational activity'],
    9: ['Users and roles', 'Invitations and access', 'Account status'],
    10: ['Databases and tables', 'Storage resources', 'Data access policies'],
    11: ['Product usage', 'Runtime metrics', 'Event and funnel reporting'],
    12: ['Audiences', 'Campaigns', 'Customer engagement'],
    13: ['Configured domains', 'DNS and verification', 'Routing status'],
    14: ['Connected providers', 'Connector health', 'Integration permissions'],
    15: ['Authentication', 'Permissions', 'Security policies and evidence'],
    16: ['Repositories and source', 'Builds', 'Release controls'],
    17: ['Agent registry', 'Capabilities', 'Assignments and status'],
    18: ['Workflow registry', 'Runs and approvals', 'Automation evidence'],
    19: ['Runtime logs', 'Activity events', 'Audit evidence'],
    20: ['API access', 'Keys and scopes', 'Developer configuration'],
    21: [
      'Workspace settings',
      'Application defaults',
      'Enterprise preferences',
    ],
    22: ['MCP servers', 'Available tools', 'Resources and connection state'],
    23: ['Today’s movement', 'Bookings and operations', 'Exceptions and handoffs'],
    24: ['Guests and customers', 'Requests and service context', 'Selected guest record'],
    25: ['Verified KPIs', 'Period comparisons', 'Reports and evidence'],
    26: ['Approvals', 'Consequential decisions', 'Missing access or input'],
    27: ['Verified business activity', 'Provider receipts', 'Execution evidence'],
    28: ['Live public demo', 'Vision capabilities', 'Authorized camera path'],
  };

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<AskPandoraScreenState> _chatKey =
      GlobalKey<AskPandoraScreenState>();
  final Map<int, Widget> _roots = <int, Widget>{};
  final Map<int, Map<String, String>?> _enterpriseSelections =
      <int, Map<String, String>?>{};
  final Set<int> _visited = <int>{0};
  List<PandoraIntelligenceThread> _threads =
      const <PandoraIntelligenceThread>[];
  bool _historyLoading = false;
  bool _historyLoaded = false;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    unawaited(OwnerAnalytics.shared.capture(OwnerAnalyticsEvent.appOpened));
    unawaited(
      OwnerAnalytics.shared.capture(
        OwnerAnalyticsEvent.screenViewed,
        resultClass: 'pandora_chat',
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
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
    if (value == _index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _index = value;
      _visited.add(value);
    });
    final screen = switch (value) {
      0 => 'pandora_chat',
      1 => 'projects',
      2 => 'needs_you',
      3 => 'more',
      4 => 'activity',
      5 => 'plugins',
      6 => 'saved_evidence',
      7 => 'verify_safety',
      8 => 'enterprise_overview',
      9 => 'enterprise_app_users',
      10 => 'enterprise_data',
      11 => 'enterprise_analytics',
      12 => 'enterprise_marketing',
      13 => 'enterprise_domains',
      14 => 'enterprise_integrations',
      15 => 'enterprise_security',
      16 => 'enterprise_code',
      17 => 'enterprise_agents',
      18 => 'enterprise_workflows',
      19 => 'enterprise_logs',
      20 => 'enterprise_api',
      21 => 'enterprise_settings',
      22 => 'enterprise_mcp',
      23 => 'enterprise_operations',
      24 => 'enterprise_guests',
      25 => 'enterprise_revenue',
      26 => 'enterprise_needs_you',
      27 => 'enterprise_activity',
      28 => 'enterprise_vision',
      _ => 'pandora_chat',
    };
    unawaited(
      OwnerAnalytics.shared.capture(
        OwnerAnalyticsEvent.screenViewed,
        resultClass: screen,
      ),
    );
  }

  void _newChat() {
    _select(0);
    _chatKey.currentState?.newChat();
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
  }

  Future<void> _searchChats() async {
    if (!_historyLoaded) await _refreshHistory();
    if (!mounted) return;
    final selected = await showModalBottomSheet<PandoraIntelligenceThread>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _SearchChatsSheet(threads: _threads),
    );
    if (!mounted || selected == null) return;
    await _openThread(selected);
  }

  Future<void> _openThread(PandoraIntelligenceThread thread) async {
    _select(0);
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
    await _chatKey.currentState?.loadThread(thread.id);
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
              'Delete “${thread.title}” and its saved messages? This cannot be undone.',
            ),
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
                  'Choose a persistent project context or remove the association.',
                ),
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
        'Pandora could not load projects for this conversation.',
      );
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

  Widget _root(int index) => _roots.putIfAbsent(index, () {
        if (index == 16) {
          return const EnterpriseCodeScreen();
        }
        if (index >= 8 && index < _destinations.length) {
          return EnterpriseSectionScreen(
            surface: _enterpriseContext(index).surface,
            title: _destinations[index].label,
            description: _enterpriseDescriptions[index] ??
                'Enterprise configuration and operational controls.',
            icon: _destinations[index].selectedIcon,
            items: _enterpriseItems[index] ?? const <String>[],
            onSelectionChanged: (selection) {
              if (!mounted) return;
              setState(() => _enterpriseSelections[index] = selection);
            },
          );
        }
        return switch (index) {
          0 => AskPandoraScreen(
              key: _chatKey,
              onSearchChats: _searchChats,
              onMore: () => _select(3),
              assistantLabel: PlpAlfredProfile.assistantLabel,
              enterpriseContext: PlpAlfredProfile.enterpriseContext(
                surface: 'enterprise_overview',
                route: '/enterprise/assistant',
                capabilities: const <String>[],
                identityScope: 'enterprise_workspace',
              ),
            ),
          1 => const ProjectsScreen(),
          2 => const ApprovalsScreen(),
          3 => const MoreScreen(),
          4 => const ActivityScreen(),
          5 => const PluginsScreen(),
          6 => const OfflineEvidenceScreen(),
          7 => const SimpleSafetyScreen(),
          _ => AskPandoraScreen(key: _chatKey),
        };
      });

  EnterprisePageContext _enterpriseContext(int index) {
    final surface = switch (index) {
      8 => 'enterprise_overview',
      9 => 'enterprise_app_users',
      10 => 'enterprise_data',
      11 => 'enterprise_analytics',
      12 => 'enterprise_marketing',
      13 => 'enterprise_domains',
      14 => 'enterprise_integrations',
      15 => 'enterprise_security',
      16 => 'enterprise_code',
      17 => 'enterprise_agents',
      18 => 'enterprise_workflows',
      19 => 'enterprise_logs',
      20 => 'enterprise_api',
      21 => 'enterprise_settings',
      22 => 'enterprise_mcp',
      23 => 'enterprise_workflows',
      24 => 'enterprise_data',
      25 => 'enterprise_analytics',
      26 => 'enterprise_workflows',
      27 => 'enterprise_logs',
      28 => 'enterprise_vision',
      _ => throw StateError('Not an Enterprise destination.'),
    };
    final route = switch (index) {
      8 => '/enterprise/overview',
      9 => '/enterprise/app-users',
      10 => '/enterprise/data',
      11 => '/enterprise/analytics',
      12 => '/enterprise/marketing',
      13 => '/enterprise/domains',
      14 => '/enterprise/integrations',
      15 => '/enterprise/security',
      16 => '/enterprise/code',
      17 => '/enterprise/agents',
      18 => '/enterprise/workflows',
      19 => '/enterprise/logs',
      20 => '/enterprise/api',
      21 => '/enterprise/settings',
      22 => '/enterprise/mcp',
      23 => '/enterprise/operations',
      24 => '/enterprise/guests',
      25 => '/enterprise/revenue',
      26 => '/enterprise/needs-you',
      27 => '/enterprise/activity',
      28 => '/enterprise/vision',
      _ => throw StateError('Not an Enterprise destination.'),
    };
    final capabilities = switch (index) {
      9 => const <String>[
          'organization.users.read',
          'organization.users.manage',
        ],
      15 => const <String>[
          'enterprise.security.read',
          'enterprise.security.manage',
        ],
      16 => const <String>['source.read', 'build.request'],
      20 => const <String>['enterprise.api.read', 'enterprise.api.manage'],
      _ => <String>['$surface.read'],
    };
    return EnterprisePageContext(
      surface: surface,
      route: route,
      capabilities: capabilities,
      selectedObject: _enterpriseSelections[index],
      identityScope:
          index == 9 ? 'pandora_organization' : 'enterprise_workspace',
      tenantSlug: PlpAlfredProfile.tenantSlug,
      personaId: PlpAlfredProfile.personaId,
      personaLabel: PlpAlfredProfile.assistantLabel,
      assistantRole: PlpAlfredProfile.assistantRole,
    );
  }

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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
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

  Widget _sidePanel({bool glass = false}) => _PandoraSidePanel(
        glass: glass,
        destinations: _destinations,
        selectedIndex: _index,
        onSelected: _select,
        threads: _threads,
        historyLoading: _historyLoading,
        onNewChat: _newChat,
        onSearchChats: _searchChats,
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

            final workspace = _index >= 8
                ? EnterprisePageContextScope(
                    pageContext: _enterpriseContext(_index),
                    child: EnterpriseCommandStack(
                      onVerifiedResult: (_) {
                        if (!mounted) return;
                        setState(() => _roots.remove(_index));
                      },
                      child: body,
                    ),
                  )
                : body;

            if (constraints.maxWidth >= 900) {
              return Scaffold(
                backgroundColor: PandoraV2Colors.canvas,
                body: Row(
                  children: [
                    SizedBox(
                      width: _index >= 8 ? 248 : 264,
                      child: SafeArea(child: _sidePanel()),
                    ),
                    VerticalDivider(
                      width: 1,
                      color: _index >= 8
                          ? const Color(0x2ED0A16F)
                          : PandoraV2Colors.line,
                    ),
                    Expanded(
                      child: PandoraNavigationScope(
                        openDrawer: null,
                        child: workspace,
                      ),
                    ),
                  ],
                ),
              );
            }

            return Scaffold(
              key: _scaffoldKey,
              backgroundColor: PandoraV2Colors.canvas,
              drawerScrimColor: Colors.black.withValues(alpha: .62),
              onDrawerChanged: (open) {
                if (open) unawaited(_refreshHistory());
              },
              drawer: Drawer(
                width: constraints.maxWidth * .82 > 320
                    ? 320
                    : constraints.maxWidth * .82,
                elevation: 0,
                shadowColor: Colors.transparent,
                backgroundColor: _index >= 8
                    ? const Color(0xFF0D0C0B)
                    : Colors.transparent,
                surfaceTintColor: Colors.transparent,
                shape: const RoundedRectangleBorder(),
                child: SafeArea(
                  child: _sidePanel(glass: _index < 8),
                ),
              ),
              body: PandoraNavigationScope(
                openDrawer: () => _scaffoldKey.currentState?.openDrawer(),
                child: workspace,
              ),
            );
          },
        ),
      );
}

class _PandoraSidePanel extends StatelessWidget {
  const _PandoraSidePanel({
    this.glass = false,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.threads,
    required this.historyLoading,
    required this.onNewChat,
    required this.onSearchChats,
    required this.onOpenThread,
    required this.onManageThread,
  });

  final bool glass;
  final List<_ChatDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<PandoraIntelligenceThread> threads;
  final bool historyLoading;
  final VoidCallback onNewChat;
  final VoidCallback onSearchChats;
  final ValueChanged<PandoraIntelligenceThread> onOpenThread;
  final ValueChanged<PandoraIntelligenceThread> onManageThread;

  Widget _glassChrome(Widget child) => child;

  @override
  Widget build(BuildContext context) {
    final enterpriseActive = selectedIndex >= 8;
    return Material(
      color: glass
          ? Colors.transparent
          : enterpriseActive
              ? const Color(0xFF0D0C0B)
              : PandoraV2Colors.surface,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ListView(
            key: const ValueKey<String>('pandora-side-panel-scroll'),
            padding: EdgeInsets.fromLTRB(
              10,
              82,
              10,
              enterpriseActive ? 18 : 86,
            ),
            children: [
              _EnterpriseMenu(
                destinations: destinations,
                selectedIndex: selectedIndex,
                onSelected: onSelected,
              ),
              if (!enterpriseActive) ...[
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.fromLTRB(10, 0, 10, 7),
                  child: Text(
                    'Recent chats',
                    style: TextStyle(
                      color: PandoraV2Colors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (historyLoading && threads.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 1.8),
                      ),
                    ),
                  )
                else if (threads.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(10, 4, 10, 14),
                    child: Text(
                      'Your conversations will appear here.',
                      style: TextStyle(
                        color: PandoraV2Colors.muted,
                        fontSize: 12.5,
                      ),
                    ),
                  )
                else
                  for (final thread in threads.take(12))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: ListTile(
                        dense: true,
                        visualDensity: const VisualDensity(vertical: -2),
                        key: ValueKey<String>('pandora-thread-${thread.id}'),
                        title: Text(
                          thread.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Conversation options',
                          icon: const Icon(Icons.more_horiz_rounded, size: 19),
                          onPressed: () => onManageThread(thread),
                        ),
                        onTap: () => onOpenThread(thread),
                      ),
                    ),
                const SizedBox(height: 16),
                for (final index in const <int>[0, 1, 2, 4, 5, 6, 7, 3])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      selected: index == selectedIndex,
                      selectedColor: PandoraV2Colors.ink,
                      iconColor: PandoraV2Colors.muted,
                      textColor: PandoraV2Colors.ink,
                      selectedTileColor: Colors.white.withValues(alpha: .06),
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
              ],
            ],
          ),
          Align(
            alignment: Alignment.topCenter,
            child: _glassChrome(
              SizedBox(
                key: const ValueKey<String>('pandora-side-panel-glass-header'),
                height: 72,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 10, 6),
                  child: enterpriseActive
                      ? Row(
                          children: [
                            Container(
                              width: 36,
                              height: 44,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF11100F),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0x66D0A16F),
                                ),
                              ),
                              child: Image.asset(
                                'assets/enterprise/plp_logo.webp',
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(width: 11),
                            const Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'PLP Boracay',
                                    style: TextStyle(
                                      color: Color(0xFFF4EFE6),
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -.2,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'POWERED BY PANDORA',
                                    style: TextStyle(
                                      color: Color(0xFFD0A16F),
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            const PandoraMark(size: 28),
                            const SizedBox(width: 11),
                            const Text(
                              'Pandora',
                              style: TextStyle(
                                color: PandoraV2Colors.ink,
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.35,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              key: const ValueKey<String>('pandora-search-chats'),
                              tooltip: 'Search chats',
                              onPressed: onSearchChats,
                              icon: const Icon(Icons.search_rounded, size: 22),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
          if (!enterpriseActive)
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 0, 10),
                child: Material(
                  key:
                      const ValueKey<String>('pandora-side-panel-glass-footer'),
                  color: Colors.white.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(28),
                  child: SizedBox(
                    width: 166,
                    height: 54,
                    child: ListTile(
                      key: const ValueKey<String>('pandora-new-chat'),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      leading: const Icon(Icons.edit_square, size: 21),
                      title: const Text(
                        'New chat',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onTap: onNewChat,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EnterpriseMenu extends StatelessWidget {
  const _EnterpriseMenu({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_ChatDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const ownerIndexes = <int>[8, 23, 28, 24, 9, 25, 26, 27, 21];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 5, 12, 11),
          child: Text(
            'PROPERTY OPERATIONS',
            style: TextStyle(
              color: Color(0xFF8E857C),
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.25,
            ),
          ),
        ),
        for (final index in ownerIndexes)
          _EnterpriseNavTile(
            destination: destinations[index],
            selected: index == selectedIndex,
            onTap: () => onSelected(index),
          ),
      ],
    );
  }
}

class _EnterpriseNavTile extends StatelessWidget {
  const _EnterpriseNavTile({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _ChatDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Semantics(
          button: true,
          selected: selected,
          label: destination.label,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0x14D0A16F)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border(
                  left: BorderSide(
                    color: selected
                        ? const Color(0xFFD0A16F)
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 20,
                    color: selected
                        ? const Color(0xFFD0A16F)
                        : const Color(0xFF9E978E),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      destination.label,
                      style: TextStyle(
                        color: selected
                            ? const Color(0xFFF4EFE6)
                            : const Color(0xFFC9C1B7),
                        fontSize: 14.5,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        letterSpacing: selected ? -.1 : 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _SearchChatsSheet extends StatefulWidget {
  const _SearchChatsSheet({required this.threads});

  final List<PandoraIntelligenceThread> threads;

  @override
  State<_SearchChatsSheet> createState() => _SearchChatsSheetState();
}

class _SearchChatsSheetState extends State<_SearchChatsSheet> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = widget.threads
        .where(
          (thread) =>
              _query.isEmpty ||
              thread.title.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList(growable: false);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        4,
        18,
        MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      child: SizedBox(
        key: const ValueKey<String>('pandora-search-chats-sheet'),
        height: MediaQuery.sizeOf(context).height * .68,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Search chats',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search conversations',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: matches.isEmpty
                  ? const Center(
                      child: Text(
                        'No matching chats.',
                        style: TextStyle(color: PandoraV2Colors.muted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final thread = matches[index];
                        return ListTile(
                          title: Text(
                            thread.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.of(context).pop(thread),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ThreadAction { rename, project, archive, delete }

class _ChatDestination {
  const _ChatDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}