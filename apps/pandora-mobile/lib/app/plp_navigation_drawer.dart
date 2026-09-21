import 'dart:math' as math;

import 'package:flutter/material.dart';

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
    required this.onNewChat,
  });

  final String? selectedDestination;
  final List<PlpRecentChatItem> recentChats;
  final bool recentChatsLoading;
  final String? recentChatsError;
  final VoidCallback onRetryRecentChats;
  final ValueChanged<String> onSelectDestination;
  final ValueChanged<PlpRecentChatItem> onSelectThread;
  final VoidCallback onNewChat;

  @override
  State<PlpNavigationDrawer> createState() => _PlpNavigationDrawerState();
}

class _PlpNavigationDrawerState extends State<PlpNavigationDrawer> {
  static const _canvas = Color(0xFFFAF8F3);
  static const _paper = Color(0xFFFFFDFC);
  static const _ink = Color(0xFF171512);
  static const _muted = Color(0xFF746F67);
  static const _line = Color(0xFFE1DBD1);
  static const _accent = Color(0xFF82764F);

  static const _businessItems = <_PlpDrawerDestination>[
    _PlpDrawerDestination('home', 'Home'),
    _PlpDrawerDestination('overview', 'Overview'),
    _PlpDrawerDestination('operations', 'Operations'),
    _PlpDrawerDestination('vision', 'Vision'),
    _PlpDrawerDestination('guests', 'Guest Experience'),
    _PlpDrawerDestination('team-access', 'Team & Access'),
    _PlpDrawerDestination('revenue', 'Revenue'),
    _PlpDrawerDestination('needs-you', 'Needs You'),
    _PlpDrawerDestination('activity', 'Activity'),
    _PlpDrawerDestination('settings', 'Settings'),
  ];

  static const _systemItems = <_PlpDrawerDestination>[
    _PlpDrawerDestination('local-ai', 'Local AI'),
    _PlpDrawerDestination('developer', 'Developer diagnostics'),
  ];

  final TextEditingController _searchController = TextEditingController();
  bool _recentExpanded = true;
  bool _systemExpanded = false;
  bool _searchOpen = false;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(String value) =>
      _query.isEmpty || value.toLowerCase().contains(_query.toLowerCase());

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchController.clear();
        _query = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final drawerWidth = math.min(430.0, viewportWidth);
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
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: _canvas,
          border: Border(right: BorderSide(color: _line)),
        ),
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              SingleChildScrollView(
                key: const ValueKey<String>('plp-drawer-scroll'),
                padding: EdgeInsets.fromLTRB(
                  26,
                  _searchOpen ? 132 : 88,
                  26,
                  108,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_query.isEmpty) ...[
                      const _DrawerEyebrow('OWNER WORKSPACE'),
                      const SizedBox(height: 18),
                    ],
                    for (final item in visibleBusiness) _navigationRow(item),
                    const SizedBox(height: 26),
                    const Divider(height: 1, color: _line),
                    const SizedBox(height: 18),
                    _sectionToggle(
                      title: 'Recent chats',
                      expanded: _recentExpanded,
                      onTap: () => setState(
                        () => _recentExpanded = !_recentExpanded,
                      ),
                    ),
                    if ((_recentExpanded || _query.isNotEmpty) &&
                        widget.recentChatsLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          children: [
                            SizedBox.square(
                              dimension: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: _ink,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Loading recent chats...',
                              style: TextStyle(
                                color: _muted,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if ((_recentExpanded || _query.isNotEmpty) &&
                        widget.recentChatsError != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Recent chats unavailable',
                                style: TextStyle(
                                  color: _muted,
                                  fontSize: 12.5,
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
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          'No recent chats',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 12.5,
                          ),
                        ),
                      )
                    else if (_recentExpanded || _query.isNotEmpty)
                      for (final chat in visibleChats) _chatRow(chat),
                    const SizedBox(height: 20),
                    const Divider(height: 1, color: _line),
                    const SizedBox(height: 18),
                    _sectionToggle(
                      title: 'System / Developer',
                      subtitle: 'Privileged technical surfaces',
                      expanded: _systemExpanded,
                      onTap: () => setState(
                        () => _systemExpanded = !_systemExpanded,
                      ),
                    ),
                    if (_systemExpanded || _query.isNotEmpty)
                      for (final item in visibleSystem)
                        _systemRow(item),
                  ],
                ),
              ),
              Positioned(
                key: const ValueKey<String>('plp-drawer-header-overlay'),
                top: 0,
                left: 0,
                right: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: _canvas,
                    border: Border(bottom: BorderSide(color: _line)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 14, 10, 13),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'PUEBLO LA PERLA',
                                    style: TextStyle(
                                      color: _ink,
                                      fontFamily: 'serif',
                                      fontSize: 19,
                                      letterSpacing: 2.6,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'BORACAY',
                                    style: TextStyle(
                                      color: _accent,
                                      fontSize: 8,
                                      letterSpacing: 3.2,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
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
                                color: _ink,
                                size: 23,
                              ),
                            ),
                            IconButton(
                              key: const ValueKey<String>('plp-drawer-close'),
                              tooltip: 'Close navigation',
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(
                                Icons.close_rounded,
                                color: _ink,
                                size: 23,
                              ),
                            ),
                          ],
                        ),
                        if (_searchOpen) ...[
                          const SizedBox(height: 10),
                          TextField(
                            key: const ValueKey<String>(
                              'plp-drawer-search-field',
                            ),
                            controller: _searchController,
                            autofocus: true,
                            onChanged: (value) =>
                                setState(() => _query = value.trim()),
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 14,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Search workspace or chats',
                              hintStyle: TextStyle(color: _muted),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: _accent,
                                size: 20,
                              ),
                              filled: true,
                              fillColor: _paper,
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.zero,
                                borderSide: BorderSide(color: _line),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.zero,
                                borderSide: BorderSide(color: _line),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.zero,
                                borderSide: BorderSide(color: _ink),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                key: const ValueKey<String>('plp-drawer-bottom-overlay'),
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: _canvas,
                    border: Border(top: BorderSide(color: _line)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                    child: Material(
                      color: _ink,
                      child: InkWell(
                        key: const ValueKey<String>('plp-drawer-new-chat'),
                        onTap: widget.onNewChat,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.edit_outlined,
                                size: 19,
                                color: Colors.white,
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'NEW CHAT',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.8,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navigationRow(_PlpDrawerDestination item) {
    final selected = widget.selectedDestination == item.id;
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: selected ? '${item.label}, selected' : item.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey<String>('plp-drawer-${item.id}'),
          onTap: () => widget.onSelectDestination(item.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Center(
              child: Text(
                item.label,
                style: TextStyle(
                  color: selected ? _accent : _ink,
                  fontSize: selected ? 16.5 : 15.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: selected ? 1.1 : 0.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _systemRow(_PlpDrawerDestination item) {
    final selected = widget.selectedDestination == item.id;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: ValueKey<String>('plp-drawer-${item.id}'),
        onTap: () => widget.onSelectDestination(item.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    color: selected ? _accent : _muted,
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 15,
                color: _muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionToggle({
    required String title,
    required bool expanded,
    required VoidCallback onTap,
    String? subtitle,
  }) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _ink,
                        fontFamily: 'serif',
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              AnimatedRotation(
                turns: expanded ? .5 : 0,
                duration: const Duration(milliseconds: 160),
                child: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: _muted,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _chatRow(PlpRecentChatItem chat) => InkWell(
        key: ValueKey<String>('plp-recent-chat-${chat.id}'),
        onTap: () => widget.onSelectThread(chat),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            chat.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _muted,
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
        ),
      );
}

class _DrawerEyebrow extends StatelessWidget {
  const _DrawerEyebrow(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _accent,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 2.1,
        ),
      );
}

class _PlpDrawerDestination {
  const _PlpDrawerDestination(this.id, this.label);
  final String id;
  final String label;
}
