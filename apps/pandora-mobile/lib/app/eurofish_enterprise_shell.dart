import 'dart:async';

import 'package:flutter/material.dart';

import '../core/data/eurofish_workspace_api.dart';
import '../core/data/pandora_intelligence_api.dart';
import '../core/widgets/pandora_navigation.dart';
import '../features/enterprise/enterprise_workspace_home.dart';
import '../features/enterprise/tax_compliance_screen.dart';
import '../features/simple/ask_pandora_screen.dart';
import 'pandora_dependencies.dart';

class EurofishEnterpriseShell extends StatefulWidget {
  const EurofishEnterpriseShell({super.key});

  @override
  State<EurofishEnterpriseShell> createState() =>
      _EurofishEnterpriseShellState();
}

class _EurofishEnterpriseShellState extends State<EurofishEnterpriseShell> {
  static const _workspaceKey = '1064-euro-fish-traders';
  static const _canvas = Color(0xFF07111B);
  static const _panel = Color(0xFF0C1728);
  static const _line = Color(0xFF263750);
  static const _ink = Color(0xFFF6F2E9);
  static const _muted = Color(0xFF9FB0C5);
  static const _blue = Color(0xFF6AA9FF);

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<AskPandoraScreenState> _chatKey =
      GlobalKey<AskPandoraScreenState>();
  final EurofishWorkspaceApi _workspaceApi = EurofishWorkspaceApi();

  String _routeSlug = 'home';
  List<PandoraIntelligenceThread> _threads = const <PandoraIntelligenceThread>[];
  bool _historyLoaded = false;
  bool _historyLoading = false;

  EnterpriseWorkspaceProfile get _workspace => enterpriseWorkspaces.firstWhere(
        (item) => item.key == _workspaceKey,
      );

  EnterpriseWorkspaceSection get _section => _workspace.sections.firstWhere(
        (item) => item.routeSlug == _routeSlug,
        orElse: () => _workspace.sections.first,
      );

  Map<String, Object?> get _enterpriseContext =>
      EnterpriseWorkspaceSelection(
        workspace: _workspace,
        section: _section,
      ).enterpriseContext;

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
      // Navigation remains usable while history is unavailable.
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  void _openDrawer() {
    FocusManager.instance.primaryFocus?.unfocus();
    _scaffoldKey.currentState?.openDrawer();
    unawaited(_refreshHistory());
  }

  void _selectSection(String routeSlug) {
    if (!_workspace.sections.any((item) => item.routeSlug == routeSlug)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
    setState(() => _routeSlug = routeSlug);
  }

  Future<void> _openThread(PandoraIntelligenceThread thread) async {
    _selectSection('overview');
    await WidgetsBinding.instance.endOfFrame;
    await _chatKey.currentState?.loadThread(thread.id);
  }

  Future<void> _newChat() async {
    _selectSection('overview');
    await WidgetsBinding.instance.endOfFrame;
    _chatKey.currentState?.newChat();
  }

  Widget _body() {
    if (_routeSlug == 'home') {
      return _EurofishHome(
        workspace: _workspace,
        api: _workspaceApi,
        openDrawer: _openDrawer,
        onOpen: _selectSection,
        onAskPandora: () => _selectSection('overview'),
      );
    }
    if (_routeSlug == 'tax-compliance') {
      return TaxComplianceScreen(
        workspaceKey: _workspace.key,
        workspaceName: _workspace.name,
        enterpriseContext: _enterpriseContext,
        onHome: () => _selectSection('home'),
      );
    }
    return AskPandoraScreen(
      key: _chatKey,
      onHome: () => _selectSection('home'),
      onSearchChats: _showSearchChats,
      onMore: _openDrawer,
      enterpriseContext: _enterpriseContext,
      allowCharacterContext: false,
      allowProjectContext: false,
    );
  }

  Future<void> _showSearchChats() async {
    if (!_historyLoaded) await _refreshHistory();
    if (!mounted) return;
    final selected = await showModalBottomSheet<PandoraIntelligenceThread>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: _panel,
      builder: (sheetContext) => _EurofishChatSearch(threads: _threads),
    );
    if (selected != null && mounted) await _openThread(selected);
  }

  @override
  Widget build(BuildContext context) {
    final drawer = _EurofishNavigationDrawer(
      workspace: _workspace,
      selectedRoute: _routeSlug,
      recentChats: _threads,
      recentChatsLoading: _historyLoading,
      onSelectRoute: _selectSection,
      onSelectThread: (thread) => unawaited(_openThread(thread)),
      onRefreshChats: () => unawaited(_refreshHistory()),
      onNewChat: () => unawaited(_newChat()),
    );

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: _canvas,
        canvasColor: _canvas,
      ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: _canvas,
        drawer: drawer,
        drawerScrimColor: const Color(0xB3000000),
        onDrawerChanged: (open) {
          if (open) unawaited(_refreshHistory());
        },
        body: PandoraNavigationScope(
          openDrawer: _openDrawer,
          child: _body(),
        ),
      ),
    );
  }
}

class _EurofishHome extends StatefulWidget {
  const _EurofishHome({
    required this.workspace,
    required this.api,
    required this.openDrawer,
    required this.onOpen,
    required this.onAskPandora,
  });

  final EnterpriseWorkspaceProfile workspace;
  final EurofishWorkspaceApi api;
  final VoidCallback openDrawer;
  final ValueChanged<String> onOpen;
  final VoidCallback onAskPandora;

  @override
  State<_EurofishHome> createState() => _EurofishHomeState();
}

class _EurofishHomeState extends State<_EurofishHome> {
  static const _canvas = Color(0xFF07111B);
  static const _panel = Color(0xFF0C1728);
  static const _line = Color(0xFF263750);
  static const _ink = Color(0xFFF6F2E9);
  static const _muted = Color(0xFF9FB0C5);
  static const _blue = Color(0xFF6AA9FF);

  late Future<EurofishWorkspaceSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.api.loadOverview();
  }

  Future<void> _refresh() async {
    setState(() => _snapshot = widget.api.loadOverview());
    try {
      await _snapshot;
    } catch (_) {
      // The visible provider status explains the unavailable state.
    }
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: _canvas,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
              children: [
                _header(),
                const SizedBox(height: 20),
                const Text(
                  'IMPORT / EXPORT CONTROL CENTER',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Orders, inventory, logistics and business decisions in one workspace.',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 27,
                    height: 1.12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.6,
                  ),
                ),
                const SizedBox(height: 18),
                FutureBuilder<EurofishWorkspaceSnapshot>(
                  future: _snapshot,
                  builder: (context, value) => _providerCard(value),
                ),
                const SizedBox(height: 18),
                const Text(
                  'WORKSPACES',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                for (final section in widget.workspace.sections)
                  if (section.routeSlug != 'home')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: _panel,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          key: ValueKey<String>(
                            'eurofish-home-' + section.routeSlug,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => widget.onOpen(section.routeSlug),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Icon(section.icon, color: _blue, size: 22),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    section.label,
                                    style: const TextStyle(
                                      color: _ink,
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  color: _muted,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const ValueKey<String>('eurofish-home-ask-pandora'),
                  onPressed: widget.onAskPandora,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Message Pandora'),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _header() => Row(
        children: [
          IconButton(
            key: const ValueKey<String>('eurofish-navigation'),
            tooltip: 'Navigation',
            onPressed: widget.openDrawer,
            color: _ink,
            icon: const Icon(Icons.menu_rounded),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              widget.workspace.logoAsset,
              width: 42,
              height: 42,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.square(
                dimension: 42,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: _panel),
                  child: Center(
                    child: Text(
                      '1064',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1064 euro-fish traders',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Import/Export',
                  style: TextStyle(color: _muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _providerCard(AsyncSnapshot<EurofishWorkspaceSnapshot> value) {
    if (value.connectionState == ConnectionState.waiting) {
      return const _EurofishPanel(
        child: Row(
          children: [
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Reading provider-backed business state…',
                style: TextStyle(color: _muted),
              ),
            ),
          ],
        ),
      );
    }
    if (value.hasError || value.data == null) {
      return _EurofishPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PROVIDER STATE',
              style: TextStyle(
                color: _muted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'No authorized provider snapshot is available in this session.',
              style: TextStyle(color: _ink, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            Text(
              value.error.toString(),
              style: const TextStyle(color: _muted, fontSize: 12.5),
            ),
          ],
        ),
      );
    }

    final snapshot = value.data!;
    final displayName =
        snapshot.profile['displayName']?.toString().trim() ?? '';
    return _EurofishPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'PROVIDER STATE',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const Icon(Icons.verified_rounded, color: _blue, size: 18),
            ],
          ),
          if (displayName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              displayName,
              style: const TextStyle(
                color: _ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metric('Verified evidence', snapshot.verifiedEvidenceCount),
              _metric('Needs verification', snapshot.needsVerificationCount),
              _metric('Connected sources', snapshot.connectedSourceCount),
              _metric('Not connected', snapshot.notConnectedSourceCount),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Unknown operational values stay unknown. Pandora does not substitute zero for missing business data.',
            style: TextStyle(color: _muted, fontSize: 12.5, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, int value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _canvas,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _line),
        ),
        child: Text(
          label + ': ' + value.toString(),
          style: const TextStyle(
            color: _ink,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _EurofishPanel extends StatelessWidget {
  const _EurofishPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0C1728),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF263750)),
        ),
        padding: const EdgeInsets.all(15),
        child: child,
      );
}

class _EurofishNavigationDrawer extends StatefulWidget {
  const _EurofishNavigationDrawer({
    required this.workspace,
    required this.selectedRoute,
    required this.recentChats,
    required this.recentChatsLoading,
    required this.onSelectRoute,
    required this.onSelectThread,
    required this.onRefreshChats,
    required this.onNewChat,
  });

  final EnterpriseWorkspaceProfile workspace;
  final String selectedRoute;
  final List<PandoraIntelligenceThread> recentChats;
  final bool recentChatsLoading;
  final ValueChanged<String> onSelectRoute;
  final ValueChanged<PandoraIntelligenceThread> onSelectThread;
  final VoidCallback onRefreshChats;
  final VoidCallback onNewChat;

  @override
  State<_EurofishNavigationDrawer> createState() =>
      _EurofishNavigationDrawerState();
}

class _EurofishNavigationDrawerState
    extends State<_EurofishNavigationDrawer> {
  static const _canvas = Color(0xFF050B12);
  static const _panel = Color(0xFF0C1728);
  static const _ink = Color(0xFFF6F2E9);
  static const _muted = Color(0xFF9FB0C5);
  static const _blue = Color(0xFF6AA9FF);

  bool _recentExpanded = true;

  @override
  Widget build(BuildContext context) => Drawer(
        width: MediaQuery.sizeOf(context).width.clamp(280.0, 360.0) * .88,
        backgroundColor: _canvas,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        widget.workspace.logoAsset,
                        width: 38,
                        height: 38,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const DecoratedBox(
                          decoration: BoxDecoration(color: _panel),
                          child: SizedBox.square(dimension: 38),
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '1064 euro-fish traders',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Import/Export',
                            style: TextStyle(color: _muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFF263750)),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
                  children: [
                    for (final section in widget.workspace.sections)
                      _navRow(section),
                    const Divider(
                      height: 24,
                      color: Color(0xFF263750),
                    ),
                    ListTile(
                      key: const ValueKey<String>('eurofish-recent-toggle'),
                      title: const Text(
                        'Recent chats',
                        style: TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      leading: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: _muted,
                      ),
                      trailing: Icon(
                        _recentExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: _muted,
                      ),
                      onTap: () => setState(
                        () => _recentExpanded = !_recentExpanded,
                      ),
                    ),
                    if (_recentExpanded)
                      if (widget.recentChatsLoading &&
                          widget.recentChats.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else if (widget.recentChats.isEmpty)
                        ListTile(
                          title: const Text(
                            'No recent chats',
                            style: TextStyle(color: _muted, fontSize: 13),
                          ),
                          trailing: IconButton(
                            tooltip: 'Refresh',
                            onPressed: widget.onRefreshChats,
                            icon: const Icon(
                              Icons.refresh_rounded,
                              color: _muted,
                            ),
                          ),
                        )
                      else
                        for (final thread in widget.recentChats.take(10))
                          ListTile(
                            dense: true,
                            title: Text(
                              thread.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 13.5,
                              ),
                            ),
                            onTap: () => widget.onSelectThread(thread),
                          ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey<String>('eurofish-new-chat'),
                    onPressed: widget.onNewChat,
                    icon: const Icon(Icons.edit_square),
                    label: const Text('New chat'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _navRow(EnterpriseWorkspaceSection section) {
    final selected = widget.selectedRoute == section.routeSlug;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: ListTile(
        key: ValueKey<String>('eurofish-nav-' + section.routeSlug),
        selected: selected,
        selectedTileColor: _blue.withValues(alpha: .12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(
          section.icon,
          color: selected ? _blue : _muted,
          size: 21,
        ),
        title: Text(
          section.label,
          style: TextStyle(
            color: _ink,
            fontSize: 14.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        onTap: () => widget.onSelectRoute(section.routeSlug),
      ),
    );
  }
}

class _EurofishChatSearch extends StatefulWidget {
  const _EurofishChatSearch({required this.threads});

  final List<PandoraIntelligenceThread> threads;

  @override
  State<_EurofishChatSearch> createState() => _EurofishChatSearchState();
}

class _EurofishChatSearchState extends State<_EurofishChatSearch> {
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
        .where((thread) =>
            _query.isEmpty ||
            thread.title.toLowerCase().contains(_query.toLowerCase()))
        .toList(growable: false);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        6,
        18,
        MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Search Euro-Fish chats',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
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
            const SizedBox(height: 10),
            Expanded(
              child: matches.isEmpty
                  ? const Center(child: Text('No matching chats.'))
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
