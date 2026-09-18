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
import '../features/enterprise/eurofish_overview_screen.dart';
import '../features/enterprise/eurofish_section_screen.dart';
import '../features/plugins/plugins_screen.dart';
import '../features/simple/ask_pandora_screen.dart';
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
    _ChatDestination(
      'Orders & Quotes',
      Icons.request_quote_outlined,
      Icons.request_quote_rounded,
    ),
    _ChatDestination(
      'Shipments',
      Icons.flight_land_outlined,
      Icons.flight_land_rounded,
    ),
    _ChatDestination(
      'Inventory',
      Icons.inventory_2_outlined,
      Icons.inventory_2_rounded,
    ),
    _ChatDestination('Customers', Icons.groups_outlined, Icons.groups_rounded),
    _ChatDestination('Aquaculture', Icons.water_outlined, Icons.water_rounded),
    _ChatDestination(
      'Flowers',
      Icons.local_florist_outlined,
      Icons.local_florist_rounded,
    ),
    _ChatDestination(
      'Compliance',
      Icons.fact_check_outlined,
      Icons.fact_check_rounded,
    ),
    _ChatDestination(
      'Finance',
      Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet_rounded,
    ),
    _ChatDestination(
      'Documents',
      Icons.description_outlined,
      Icons.description_rounded,
    ),
    _ChatDestination(
      'App Users',
      Icons.manage_accounts_outlined,
      Icons.manage_accounts_rounded,
    ),
    _ChatDestination('Integrations', Icons.hub_outlined, Icons.hub_rounded),
    _ChatDestination(
      'Security',
      Icons.admin_panel_settings_outlined,
      Icons.admin_panel_settings_rounded,
    ),
    _ChatDestination(
      'Settings',
      Icons.settings_outlined,
      Icons.settings_rounded,
    ),
  ];

  static const _enterpriseDescriptions = <int, String>{
    9: 'Bulk fry and flower inquiries, quotes, orders and customer follow-up.',
    10: 'Inbound arrivals, quarantine clearance, release, cold-chain and delivery.',
    11: 'Live fry batches, flower lots, availability and expected arrivals.',
    12: 'Farm, nursery, florist and wholesale customer relationships.',
    13: 'Milkfish fry sourcing, batch status, biosecurity and destination handling.',
    14: 'Imported roses, orchids, exotics, weekly availability and cold-chain.',
    15: 'BFAR, BPI/NPQSD, permits, accreditation evidence and expiry watch.',
    16: 'Landed cost, receivables, collections, margin and cash visibility.',
    17: 'Permits, certificates, airway bills, invoices and shipment evidence.',
    18: 'Application users, roles, invitations and owner-controlled access.',
    19: 'Connected providers, business sources and connector health.',
    20: 'Authentication, permissions, data protection and audit controls.',
    21: 'Euro-Fish enterprise preferences and operating defaults.',
  };

  static const _enterpriseItems = <int, List<String>>{
    9: [
      'New inquiries',
      'Quote pipeline',
      'Confirmed orders',
      'Follow-up queue',
    ],
    10: [
      'Expected arrivals',
      'Airport / quarantine status',
      'Release & handoff',
      'Delivery exceptions',
    ],
    11: [
      'Fry batch availability',
      'Flower lot availability',
      'Reserved stock',
      'Expected replenishment',
    ],
    12: [
      'Customer accounts',
      'Contacts',
      'Order history',
      'Reorder opportunities',
    ],
    13: [
      'Origin & supplier',
      'Batch / health documents',
      'Biosecurity checks',
      'Farm destination',
    ],
    14: [
      'Variety & origin',
      'Weekly arrivals',
      'Cold-chain status',
      'Customer allocation',
    ],
    15: [
      'Accreditation register',
      'Permit deadlines',
      'Shipment clearances',
      'Compliance evidence',
    ],
    16: [
      'Landed cost',
      'Invoices & receivables',
      'Collections',
      'Margin visibility',
    ],
    17: [
      'Import permits',
      'Health / phytosanitary certificates',
      'Airway bills',
      'Invoices & receipts',
    ],
    18: ['Users & roles', 'Invitations', 'Account status', 'Access review'],
    19: [
      'Connected sources',
      'Provider health',
      'Permissions',
      'Last successful sync',
    ],
    20: [
      'Authentication',
      'Roles & permissions',
      'Audit evidence',
      'Security controls',
    ],
    21: [
      'Workspace defaults',
      'Notifications',
      'Business preferences',
      'Pandora behavior',
    ],
  };

  static const _enterprisePrompts = <int, String>{
    9: 'Which orders or quotes need follow-up today?',
    10: 'Show shipment status, clearance blockers and delivery risks.',
    11: 'Show current fry and flower availability from verified inventory data.',
    12: 'Which customers need follow-up or are due for a reorder?',
    13: 'Summarize current milkfish fry operations and any batch risks.',
    14: 'Summarize flower availability, arrivals and cold-chain exceptions.',
    15: 'What permits, accreditations or compliance documents need attention?',
    16: 'Summarize collections, receivables, costs and margin issues.',
    17: 'Find missing or expiring import and shipment documents.',
    18: 'Show application access changes or users that need attention.',
    19: 'Which Euro-Fish data connections are healthy or failing?',
    20: 'Show security or permission issues that need owner action.',
    21: 'What Euro-Fish workspace settings should I review?',
  };

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<AskPandoraScreenState> _chatKey =
      GlobalKey<AskPandoraScreenState>();
  final Map<int, Widget> _roots = <int, Widget>{};
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
      8 => 'eurofish_overview',
      9 => 'eurofish_orders',
      10 => 'eurofish_shipments',
      11 => 'eurofish_inventory',
      12 => 'eurofish_customers',
      13 => 'eurofish_aquaculture',
      14 => 'eurofish_flowers',
      15 => 'eurofish_compliance',
      16 => 'eurofish_finance',
      17 => 'eurofish_documents',
      18 => 'eurofish_app_users',
      19 => 'eurofish_integrations',
      20 => 'eurofish_security',
      21 => 'eurofish_settings',
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
      () =>
          PandoraDependencies.of(context).intelligence!
              .renameThread(thread.id, title),
      success: 'Conversation renamed.',
    );
  }

  Future<void> _archiveThread(PandoraIntelligenceThread thread) async {
    await _runThreadMutation(
      () =>
          PandoraDependencies.of(context).intelligence!
              .archiveThread(thread.id),
      success: 'Conversation archived.',
    );
  }

  Future<void> _deleteThread(PandoraIntelligenceThread thread) async {
    final confirmed =
        await showDialog<bool>(
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
      final projectSnapshot = await PandoraDependencies.of(context).repository
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
    if (index == 8) return const EurofishOverviewScreen();
    if (index >= 9 && index <= 21) {
      return EurofishSectionScreen(
        title: _destinations[index].label,
        description:
            _enterpriseDescriptions[index] ?? 'Euro-Fish enterprise workspace.',
        icon: _destinations[index].selectedIcon,
        items: _enterpriseItems[index] ?? const <String>[],
        suggestedPrompt:
            _enterprisePrompts[index] ?? 'What needs my attention here?',
      );
    }
    return switch (index) {
      0 => AskPandoraScreen(
        key: _chatKey,
        onSearchChats: _searchChats,
        onMore: () => _select(3),
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

  Widget _sidePanel() => _PandoraSidePanel(
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

        if (constraints.maxWidth >= 900) {
          return Scaffold(
            backgroundColor: PandoraV2Colors.canvas,
            body: Row(
              children: [
                SizedBox(width: 264, child: SafeArea(child: _sidePanel())),
                const VerticalDivider(width: 1, color: PandoraV2Colors.line),
                Expanded(
                  child: PandoraNavigationScope(openDrawer: null, child: body),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: PandoraV2Colors.canvas,
          onDrawerChanged: (open) {
            if (open) unawaited(_refreshHistory());
          },
          drawer: Drawer(
            width: 304,
            backgroundColor: PandoraV2Colors.surface,
            surfaceTintColor: Colors.transparent,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: SafeArea(child: _sidePanel()),
          ),
          body: PandoraNavigationScope(
            openDrawer: () => _scaffoldKey.currentState?.openDrawer(),
            child: body,
          ),
        );
      },
    ),
  );
}

class _PandoraSidePanel extends StatelessWidget {
  const _PandoraSidePanel({
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

  final List<_ChatDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<PandoraIntelligenceThread> threads;
  final bool historyLoading;
  final VoidCallback onNewChat;
  final VoidCallback onSearchChats;
  final ValueChanged<PandoraIntelligenceThread> onOpenThread;
  final ValueChanged<PandoraIntelligenceThread> onManageThread;

  @override
  Widget build(BuildContext context) => Material(
    color: PandoraV2Colors.surface,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 22, 18, 16),
          child: Row(
            children: [
              PandoraMark(size: 28),
              SizedBox(width: 11),
              Text(
                'Pandora',
                style: TextStyle(
                  color: PandoraV2Colors.ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.35,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
          child: ListTile(
            key: const ValueKey<String>('pandora-new-chat'),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            leading: const Icon(Icons.edit_square, size: 21),
            title: const Text(
              'New chat',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            onTap: onNewChat,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: ListTile(
            key: const ValueKey<String>('pandora-search-chats'),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            leading: const Icon(Icons.search_rounded, size: 21),
            title: const Text(
              'Search chats',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            onTap: onSearchChats,
          ),
        ),
        const Divider(height: 1, color: PandoraV2Colors.line),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
            children: [
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1, color: PandoraV2Colors.line),
              ),
              for (final index in const <int>[0, 1, 2, 4, 5, 6, 7, 3])
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
              const Padding(
                padding: EdgeInsets.fromLTRB(10, 16, 10, 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Color(0xFFEAB308),
                      child: Icon(
                        Icons.set_meal_rounded,
                        size: 16,
                        color: Color(0xFF0A192F),
                      ),
                    ),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '1064 Euro-Fish Trading',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              for (var index = 8; index < destinations.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: ListTile(
                    dense: true,
                    selected: index == selectedIndex,
                    selectedColor: PandoraV2Colors.ink,
                    iconColor: PandoraV2Colors.muted,
                    textColor: PandoraV2Colors.ink,
                    selectedTileColor: const Color(0x221E40AF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    leading: Icon(
                      index == selectedIndex
                          ? destinations[index].selectedIcon
                          : destinations[index].icon,
                      size: 20,
                    ),
                    title: Text(
                      destinations[index].label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: index == selectedIndex
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    onTap: () => onSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ],
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
