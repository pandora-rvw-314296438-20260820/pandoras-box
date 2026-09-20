import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/widgets/pandora_mark.dart';

class PlpRecentChatItem {
  const PlpRecentChatItem({
    required this.id,
    required this.title,
  });

  final String id;
  final String title;
}

class PlpNavigationDrawer extends StatefulWidget {
  const PlpNavigationDrawer({
    super.key,
    required this.selectedDestination,
    required this.recentChats,
    required this.recentChatsLoading,
    required this.recentChatsError,
    required this.onRetryRecentChats,
    required this.onSelectDestination,
    required this.onSelectThread,
  });

  final String? selectedDestination;
  final List<PlpRecentChatItem> recentChats;
  final bool recentChatsLoading;
  final String? recentChatsError;
  final VoidCallback onRetryRecentChats;
  final ValueChanged<String> onSelectDestination;
  final ValueChanged<PlpRecentChatItem> onSelectThread;

  @override
  State<PlpNavigationDrawer> createState() => _PlpNavigationDrawerState();
}

class _PlpNavigationDrawerState extends State<PlpNavigationDrawer> {
  static const _businessItems = <_PlpDrawerDestination>[
    _PlpDrawerDestination('home', 'Home', Icons.home_outlined),
    _PlpDrawerDestination('overview', 'Overview', Icons.dashboard_outlined),
    _PlpDrawerDestination('operations', 'Operations', Icons.hub_outlined),
    _PlpDrawerDestination('guests', 'Guests', Icons.people_alt_outlined),
    _PlpDrawerDestination('team-access', 'Team & Access', Icons.group_outlined),
    _PlpDrawerDestination('revenue', 'Revenue', Icons.payments_outlined),
    _PlpDrawerDestination('needs-you', 'Needs You', Icons.priority_high_rounded),
    _PlpDrawerDestination('activity', 'Activity', Icons.history_rounded),
    _PlpDrawerDestination('settings', 'Settings', Icons.settings_outlined),
  ];

  static const _systemItems = <_PlpDrawerDestination>[
    _PlpDrawerDestination('local-ai', 'Local AI', Icons.memory_outlined),
    _PlpDrawerDestination(
      'developer',
      'Developer diagnostics',
      Icons.developer_mode_outlined,
    ),
  ];

  final TextEditingController _searchController = TextEditingController();
  bool _workspaceExpanded = false;
  bool _recentExpanded = true;
  bool _systemExpanded = false;
  bool _searchOpen = false;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchController.clear();
        _query = '';
      }
    });
  }

  bool _matches(String value) =>
      _query.isEmpty || value.toLowerCase().contains(_query.toLowerCase());

  Widget _divider() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10),
        child: Divider(
          height: 24,
          thickness: 1,
          color: Color(0x18FFFFFF),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final drawerWidth = math.min(360.0, viewportWidth * .76);
    final visibleBusiness =
        _businessItems.where((item) => _matches(item.label)).toList();
    final visibleSystem =
        _systemItems.where((item) => _matches(item.label)).toList();
    final visibleChats =
        widget.recentChats.where((item) => _matches(item.title)).toList();

    return Drawer(
      key: const ValueKey<String>('plp-navigation-drawer'),
      width: drawerWidth,
      elevation: 0,
      shadowColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Color(0xE50A0F16),
              border: Border(
                right: BorderSide(color: Color(0x1FFFFFFF)),
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
                    child: Row(
                      children: [
                        const PandoraMark(size: 42),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Pandora',
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            style: TextStyle(
                              color: Color(0xFFF8F8F6),
                              fontSize: 29,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.6,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey<String>('plp-drawer-search'),
                          tooltip: _searchOpen
                              ? 'Close navigation search'
                              : 'Search navigation and chats',
                          onPressed: _toggleSearch,
                          icon: Icon(
                            _searchOpen
                                ? Icons.close_rounded
                                : Icons.search_rounded,
                            size: 24,
                            color: const Color(0xFFD9DEE5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_searchOpen)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                      child: TextField(
                        key: const ValueKey<String>('plp-drawer-search-field'),
                        controller: _searchController,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        onChanged: (value) => setState(() => _query = value.trim()),
                        style: const TextStyle(
                          color: Color(0xFFF5F6F7),
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search navigation and chats',
                          hintStyle: const TextStyle(color: Color(0xFF858E9A)),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: Color(0xFFAAB1BA),
                            size: 21,
                          ),
                          filled: true,
                          fillColor: const Color(0x7318202A),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0x1FFFFFFF),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0x1FFFFFFF),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0x38FFFFFF),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      key: const ValueKey<String>('plp-drawer-scroll'),
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_query.isEmpty) ...[
                            _expandableRow(
                              semanticTitle: 'PLP Boracay',
                              title: 'PLP Boracay',
                              subtitle: 'Owner workspace',
                              expanded: _workspaceExpanded,
                              leading: _plpLogo(),
                              onTap: () => setState(
                                () => _workspaceExpanded = !_workspaceExpanded,
                              ),
                            ),
                            AnimatedCrossFade(
                              duration: const Duration(milliseconds: 150),
                              crossFadeState: _workspaceExpanded
                                  ? CrossFadeState.showSecond
                                  : CrossFadeState.showFirst,
                              firstChild: const SizedBox.shrink(),
                              secondChild: Padding(
                                padding: const EdgeInsets.fromLTRB(50, 2, 8, 8),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      size: 18,
                                      color: Color(0xFF76E6B2),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Current workspace · PLP Boracay',
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: .62,
                                          ),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _expandableRow(
                              semanticTitle: 'Recent chats',
                              title: 'Recent chats',
                              expanded: _recentExpanded,
                              leading: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 23,
                                color: Color(0xFFC7CDD5),
                              ),
                              onTap: () => setState(
                                () => _recentExpanded = !_recentExpanded,
                              ),
                            ),
                          ],
                          if ((_recentExpanded || _query.isNotEmpty) &&
                              widget.recentChatsLoading)
                            const Padding(
                              padding: EdgeInsets.fromLTRB(50, 8, 12, 12),
                              child: Row(
                                children: [
                                  SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'Loading recent chats…',
                                    style: TextStyle(
                                      color: Color(0xFF929AA5),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if ((_recentExpanded || _query.isNotEmpty) &&
                              widget.recentChatsError != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(50, 4, 8, 8),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Recent chats unavailable',
                                      style: TextStyle(
                                        color: Color(0xFF929AA5),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: widget.onRetryRecentChats,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            )
                          else if ((_recentExpanded || _query.isNotEmpty) &&
                              visibleChats.isEmpty)
                            const Padding(
                              padding: EdgeInsets.fromLTRB(50, 4, 8, 10),
                              child: Text(
                                'No recent chats',
                                style: TextStyle(
                                  color: Color(0xFF818A96),
                                  fontSize: 13,
                                ),
                              ),
                            )
                          else if (_recentExpanded || _query.isNotEmpty)
                            for (final chat in visibleChats)
                              _chatRow(chat),
                          _divider(),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                            child: Text(
                              _query.isEmpty ? 'BUSINESS' : 'MATCHING BUSINESS',
                              style: const TextStyle(
                                color: Color(0xFF747E8A),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          for (final item in visibleBusiness)
                            _navigationRow(item),
                          _divider(),
                          if (_query.isEmpty || _matches('System / Developer') ||
                              visibleSystem.isNotEmpty) ...[
                            _expandableRow(
                              semanticTitle: 'System / Developer',
                              title: 'System / Developer',
                              subtitle: 'Privileged technical surfaces',
                              expanded: _systemExpanded,
                              leading: const Icon(
                                Icons.code_rounded,
                                size: 23,
                                color: Color(0xFFB8C0CA),
                              ),
                              onTap: () => setState(
                                () => _systemExpanded = !_systemExpanded,
                              ),
                            ),
                            if (_systemExpanded || _query.isNotEmpty)
                              for (final item in visibleSystem)
                                _navigationRow(item, nested: true),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _plpLogo() => ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: SizedBox.square(
          dimension: 34,
          child: Image.asset(
            'assets/workspaces/plp.webp',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const DecoratedBox(
              decoration: BoxDecoration(color: Color(0xFF1B2734)),
              child: Center(
                child: Text(
                  'PLP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _expandableRow({
    required String semanticTitle,
    required String title,
    required bool expanded,
    required Widget leading,
    required VoidCallback onTap,
    String? subtitle,
  }) {
    return Semantics(
      button: true,
      label: '$semanticTitle, ${expanded ? 'expanded' : 'collapsed'}',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 58),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  SizedBox(width: 34, child: Center(child: leading)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFF2F4F6),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF858E99),
                              fontSize: 12,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: expanded ? .5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF9099A5),
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navigationRow(
    _PlpDrawerDestination item, {
    bool nested = false,
  }) {
    final selected = widget.selectedDestination == item.id;
    return Padding(
      padding: EdgeInsets.only(left: nested ? 36 : 0, bottom: 2),
      child: Semantics(
        button: true,
        selected: selected,
        label: selected ? '${item.label}, selected' : item.label,
        child: Material(
          color: selected ? const Color(0xC52A313B) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            key: ValueKey<String>('plp-drawer-${item.id}'),
            onTap: () => widget.onSelectDestination(item.id),
            borderRadius: BorderRadius.circular(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 30,
                      child: Icon(
                        item.icon,
                        size: 23,
                        color: selected
                            ? const Color(0xFFF7F8F9)
                            : const Color(0xFFAFB7C1),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? const Color(0xFFFFFFFF)
                              : const Color(0xFFD5DAE0),
                          fontSize: 16,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chatRow(PlpRecentChatItem chat) => Padding(
        padding: const EdgeInsets.only(left: 42),
        child: Semantics(
          button: true,
          label: 'Recent chat, ${chat.title}',
          child: InkWell(
            key: ValueKey<String>('plp-recent-chat-${chat.id}'),
            onTap: () => widget.onSelectThread(chat),
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    chat.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFB0B8C2),
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _PlpDrawerDestination {
  const _PlpDrawerDestination(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}
