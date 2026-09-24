import 'package:flutter/material.dart';

import '../../core/widgets/pandora_navigation.dart';

class PlpTeamAccessScreen extends StatefulWidget {
  const PlpTeamAccessScreen({
    super.key,
    required this.bootstrap,
    required this.onOpenNavigation,
    required this.onAddPeople,
    required this.onManageTeam,
  });

  final Map<String, Object?> bootstrap;
  final VoidCallback onOpenNavigation;
  final VoidCallback onAddPeople;
  final VoidCallback onManageTeam;

  @override
  State<PlpTeamAccessScreen> createState() => _PlpTeamAccessScreenState();
}

class _PlpTeamAccessScreenState extends State<PlpTeamAccessScreen> {
  static const _canvas = Color(0xFF050505);
  static const _paper = Color(0xFF0E0E0F);
  static const _ink = Color(0xFFF2EEE7);
  static const _muted = Color(0xFFA49D93);
  static const _gold = Color(0xFFD6AD63);
  static const _goldSoft = Color(0xFF17130D);
  static const _line = Color(0xFF2C2924);
  static const _green = Color(0xFF8FA889);
  static const _grayDot = Color(0xFF8F8980);

  int _tab = 0;
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, Object?> _map(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const <String, Object?>{};
  }

  List<Map<String, Object?>> _maps(Object? value) {
    if (value is! List) return const <Map<String, Object?>>[];
    return value
        .whereType<Map>()
        .map(
          (item) => item.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        )
        .toList(growable: false);
  }

  String _text(Object? value, {String fallback = '—'}) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? fallback : normalized;
  }

  bool _bool(Object? value) {
    if (value is bool) return value;
    return const {'true', '1', 'yes'}
        .contains(value?.toString().trim().toLowerCase());
  }

  String _initials(String name) {
    final words = name
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .take(2)
        .toList(growable: false);
    if (words.isEmpty) return 'PL';
    return words.map((word) => word[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final teamAccess = _map(widget.bootstrap['teamAccess']);
    final user = _map(widget.bootstrap['user']);
    final allMembers = _maps(teamAccess['members']);
    final activity = _maps(teamAccess['recentActivity']);
    final query = _searchController.text.trim().toLowerCase();
    final members = query.isEmpty
        ? allMembers
        : allMembers
            .where(
              (member) =>
                  _text(member['displayName']).toLowerCase().contains(query) ||
                  _text(member['roleLabel']).toLowerCase().contains(query) ||
                  _text(member['accessRole']).toLowerCase().contains(query),
            )
            .toList(growable: false);

    return Material(
      color: _canvas,
      child: SafeArea(
        bottom: false,
        child: ListView(
          key: const ValueKey<String>('plp-team-access-light-page'),
          padding: const EdgeInsets.only(bottom: 26),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
              child: _Header(
                onOpenNavigation: widget.onOpenNavigation,
                onSearch: () {
                  setState(() => _searching = !_searching);
                  if (!_searching) {
                    _searchController.clear();
                  }
                },
                currentUserName: _text(
                  user['displayName'],
                  fallback: 'PLP',
                ),
              ),
            ),
            if (_searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: TextField(
                  key: const ValueKey<String>('plp-team-search-field'),
                  controller: _searchController,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: _ink),
                  decoration: InputDecoration(
                    hintText: 'Search team member or role',
                    hintStyle: const TextStyle(color: _muted),
                    prefixIcon:
                        const Icon(Icons.search_rounded, color: _gold),
                    suffixIcon: IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                    filled: true,
                    fillColor: _paper,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: const BorderSide(color: _line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: const BorderSide(color: _gold),
                    ),
                  ),
                ),
              ),
            const _PeopleHero(),
            _Tabs(
              selected: _tab,
              onSelect: (index) => setState(() => _tab = index),
            ),
            if (_tab == 0)
              _TeamTab(
                members: members,
                allMemberCount: allMembers.length,
                onAddPeople: widget.onAddPeople,
                onManageTeam: widget.onManageTeam,
                initialsFor: _initials,
                textFor: _text,
                boolFor: _bool,
              )
            else if (_tab == 1)
              _AccessTab(
                teamAccess: teamAccess,
                members: members,
                onManageTeam: widget.onManageTeam,
                textFor: _text,
                boolFor: _bool,
              )
            else
              _ActivityTab(
                activity: activity,
                textFor: _text,
                boolFor: _bool,
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onOpenNavigation,
    required this.onSearch,
    required this.currentUserName,
  });

  final VoidCallback onOpenNavigation;
  final VoidCallback onSearch;
  final String currentUserName;

  String _initials(String name) {
    final words = name
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .take(2)
        .toList(growable: false);
    if (words.isEmpty) return 'PL';
    return words.map((word) => word[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) => Row(
        children: [
          if (PandoraNavigationScope.maybeOf(context)?.openDrawer != null)
            PandoraMenuButton(
              key: const ValueKey<String>('plp-team-open-navigation'),
              onPressed: onOpenNavigation,
            )
          else
            const SizedBox.square(dimension: 44),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'PUEBLO\nLA PERLA\nBORACAY',
              maxLines: 3,
              overflow: TextOverflow.fade,
              style: TextStyle(
                color: Color(0xFFCFB27A),
                fontSize: 8.5,
                height: 1.06,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey<String>('plp-team-search'),
            tooltip: 'Search team',
            onPressed: onSearch,
            style: IconButton.styleFrom(
              foregroundColor: _PlpTeamAccessScreenState._ink,
              backgroundColor: _PlpTeamAccessScreenState._paper,
              side: const BorderSide(color: Color(0xFF2C2924)),
            ),
            icon: const Icon(Icons.search_rounded, size: 26),
          ),
          const SizedBox(width: 8),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _PlpTeamAccessScreenState._ink,
              border: Border.all(color: _PlpTeamAccessScreenState._line),
            ),
            child: Center(
              child: Text(
                _initials(currentUserName),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .5,
                ),
              ),
            ),
          ),
        ],
      );
}

class _PeopleHero extends StatelessWidget {
  const _PeopleHero();

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey<String>('plp-team-editorial-hero'),
        decoration: const BoxDecoration(
          color: _PlpTeamAccessScreenState._paper,
          border: Border(
            top: BorderSide(color: _PlpTeamAccessScreenState._line),
            bottom: BorderSide(color: _PlpTeamAccessScreenState._line),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(24, 28, 20, 26),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TEAM & ACCESS',
                    style: TextStyle(
                      color: _PlpTeamAccessScreenState._gold,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.1,
                    ),
                  ),
                  SizedBox(height: 13),
                  Text(
                    'Our People',
                    style: TextStyle(
                      color: _PlpTeamAccessScreenState._ink,
                      fontFamily: 'serif',
                      fontSize: 42,
                      height: .96,
                      fontWeight: FontWeight.w400,
                      letterSpacing: -1.1,
                    ),
                  ),
                  SizedBox(height: 13),
                  Text(
                    'The people who shape every stay, with access kept clear, deliberate and accountable.',
                    style: TextStyle(
                      color: _PlpTeamAccessScreenState._muted,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.selected,
    required this.onSelect,
  });

  final int selected;
  final ValueChanged<int> onSelect;

  static const _items = <({IconData icon, String label})>[
    (icon: Icons.people_alt_rounded, label: 'Team'),
    (icon: Icons.shield_outlined, label: 'Access'),
    (icon: Icons.schedule_rounded, label: 'Activity'),
  ];

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E0E0F),
          border: Border(
            bottom: BorderSide(color: _PlpTeamAccessScreenState._line),
          ),
        ),
        child: Row(
          children: List<Widget>.generate(_items.length, (index) {
            final item = _items[index];
            final active = selected == index;
            return Expanded(
              child: InkWell(
                key: ValueKey<String>('plp-team-tab-${item.label.toLowerCase()}'),
                onTap: () => onSelect(index),
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          item.icon,
                          size: 20,
                          color: active
                              ? _PlpTeamAccessScreenState._gold
                              : const Color(0xFF98928A),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              item.label,
                              maxLines: 1,
                              style: TextStyle(
                                color: active
                                    ? _PlpTeamAccessScreenState._ink
                                    : const Color(0xFF9F9990),
                                fontSize: 14,
                                fontWeight: active
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 13),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 34),
                      color: active
                          ? _PlpTeamAccessScreenState._gold
                          : Colors.transparent,
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      );
}

class _TeamTab extends StatelessWidget {
  const _TeamTab({
    required this.members,
    required this.allMemberCount,
    required this.onAddPeople,
    required this.onManageTeam,
    required this.initialsFor,
    required this.textFor,
    required this.boolFor,
  });

  final List<Map<String, Object?>> members;
  final int allMemberCount;
  final VoidCallback onAddPeople;
  final VoidCallback onManageTeam;
  final String Function(String) initialsFor;
  final String Function(Object?, {String fallback}) textFor;
  final bool Function(Object?) boolFor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Team members',
                    style: TextStyle(
                      color: _PlpTeamAccessScreenState._ink,
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.6,
                    ),
                  ),
                ),
                FilledButton.icon(
                  key: const ValueKey<String>('plp-team-add-people'),
                  onPressed: onAddPeople,
                  style: FilledButton.styleFrom(
                    backgroundColor: _PlpTeamAccessScreenState._gold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 21),
                  label: const Text(
                    'Add people',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (members.isEmpty)
              const _EmptyState(
                icon: Icons.groups_outlined,
                title: 'No matching team members',
                detail:
                    'Team access remains governed by active PLP memberships.',
              )
            else
              for (var index = 0; index < members.length; index++) ...[
                InkWell(
                  key: ValueKey<String>(
                    'plp-team-member-${members[index]['id']}',
                  ),
                  onTap: onManageTeam,
                  child: _TeamMemberRow(
                    member: members[index],
                    initials: initialsFor(
                      textFor(
                        members[index]['displayName'],
                        fallback: 'PLP team member',
                      ),
                    ),
                    textFor: textFor,
                    boolFor: boolFor,
                  ),
                ),
                if (index != members.length - 1)
                  const Divider(
                    height: 1,
                    indent: 72,
                    color: _PlpTeamAccessScreenState._line,
                  ),
              ],
            const SizedBox(height: 20),
            const Divider(height: 1, color: _PlpTeamAccessScreenState._line),
            const SizedBox(height: 16),
            InkWell(
              key: const ValueKey<String>('plp-team-view-all'),
              onTap: onManageTeam,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'View all team members',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFFD1A15F),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: _PlpTeamAccessScreenState._gold,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$allMemberCount',
                      style: const TextStyle(
                        color: _PlpTeamAccessScreenState._muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _TeamMemberRow extends StatelessWidget {
  const _TeamMemberRow({
    required this.member,
    required this.initials,
    required this.textFor,
    required this.boolFor,
  });

  final Map<String, Object?> member;
  final String initials;
  final String Function(Object?, {String fallback}) textFor;
  final bool Function(Object?) boolFor;

  @override
  Widget build(BuildContext context) {
    final name =
        textFor(member['displayName'], fallback: 'PLP team member');
    final role = textFor(member['roleLabel'], fallback: 'Team member');
    final active = boolFor(member['active']);
    final status = textFor(
      member['accessStatus'],
      fallback: active ? 'active' : 'inactive',
    );
    final current = boolFor(member['isCurrentUser']);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _PlpTeamAccessScreenState._goldSoft,
              border: Border.all(color: _PlpTeamAccessScreenState._line),
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  color: Color(0xFFCBC4BA),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _PlpTeamAccessScreenState._ink,
                          fontSize: 18,
                          height: 1.05,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.35,
                        ),
                      ),
                    ),
                    if (current) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _PlpTeamAccessScreenState._goldSoft,
                          borderRadius: BorderRadius.zero,
                        ),
                        child: const Text(
                          'You',
                          style: TextStyle(
                            color: Color(0xFFD0A05C),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  role,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _PlpTeamAccessScreenState._muted,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF121213),
              borderRadius: BorderRadius.zero,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 9,
                  height: 9,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active
                          ? _PlpTeamAccessScreenState._green
                          : _PlpTeamAccessScreenState._grayDot,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  status[0].toUpperCase() + status.substring(1),
                  style: const TextStyle(
                    color: Color(0xFF979189),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          const Icon(
            Icons.chevron_right_rounded,
            color: _PlpTeamAccessScreenState._gold,
            size: 23,
          ),
        ],
      ),
    );
  }
}

class _AccessTab extends StatelessWidget {
  const _AccessTab({
    required this.teamAccess,
    required this.members,
    required this.onManageTeam,
    required this.textFor,
    required this.boolFor,
  });

  final Map<String, Object?> teamAccess;
  final List<Map<String, Object?>> members;
  final VoidCallback onManageTeam;
  final String Function(Object?, {String fallback}) textFor;
  final bool Function(Object?) boolFor;

  @override
  Widget build(BuildContext context) {
    final canManage = boolFor(teamAccess['canManageTeam']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Workspace access',
            style: TextStyle(
              color: _PlpTeamAccessScreenState._ink,
              fontSize: 25,
              fontWeight: FontWeight.w700,
              letterSpacing: -.6,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Access is governed by active PLP organization memberships.',
            style: TextStyle(
              color: _PlpTeamAccessScreenState._muted,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          _AccessSummaryCard(
            label: 'Active members',
            value: textFor(teamAccess['activeMemberCount'], fallback: '0'),
            icon: Icons.groups_2_outlined,
          ),
          const SizedBox(height: 9),
          _AccessSummaryCard(
            label: 'Your role',
            value: textFor(
              teamAccess['currentUserRole'],
              fallback: 'member',
            ),
            icon: Icons.admin_panel_settings_outlined,
          ),
          const SizedBox(height: 9),
          InkWell(
            key: const ValueKey<String>('plp-access-manage-team'),
            onTap: canManage ? onManageTeam : null,
            child: _AccessSummaryCard(
              label: 'Manage team',
              value: canManage ? 'Allowed' : 'View only',
              icon: Icons.verified_user_outlined,
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'People with access',
            style: TextStyle(
              color: _PlpTeamAccessScreenState._ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (members.isEmpty)
            const _EmptyState(
              icon: Icons.shield_outlined,
              title: 'No access records shown',
              detail: 'No member matches the current search.',
            )
          else
            for (var index = 0; index < members.length; index++) ...[
              InkWell(
                key: ValueKey<String>(
                  'plp-access-member-${members[index]['id']}',
                ),
                onTap: canManage ? onManageTeam : null,
                child: _AccessMemberRow(
                  member: members[index],
                  textFor: textFor,
                ),
              ),
              if (index != members.length - 1)
                const Divider(
                  height: 1,
                  color: _PlpTeamAccessScreenState._line,
                ),
            ],
        ],
      ),
    );
  }
}

class _AccessSummaryCard extends StatelessWidget {
  const _AccessSummaryCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        decoration: BoxDecoration(
          color: _PlpTeamAccessScreenState._paper,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: _PlpTeamAccessScreenState._line),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: _PlpTeamAccessScreenState._gold,
              size: 22,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: _PlpTeamAccessScreenState._muted,
                  fontSize: 12,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: _PlpTeamAccessScreenState._ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _AccessMemberRow extends StatelessWidget {
  const _AccessMemberRow({
    required this.member,
    required this.textFor,
  });

  final Map<String, Object?> member;
  final String Function(Object?, {String fallback}) textFor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            const Icon(
              Icons.person_outline_rounded,
              color: _PlpTeamAccessScreenState._gold,
              size: 21,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                textFor(
                  member['displayName'],
                  fallback: 'PLP team member',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _PlpTeamAccessScreenState._ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              textFor(member['accessRole'], fallback: 'member'),
              style: const TextStyle(
                color: _PlpTeamAccessScreenState._muted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
}

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({
    required this.activity,
    required this.textFor,
    required this.boolFor,
  });

  final List<Map<String, Object?>> activity;
  final String Function(Object?, {String fallback}) textFor;
  final bool Function(Object?) boolFor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Team activity',
              style: TextStyle(
                color: _PlpTeamAccessScreenState._ink,
                fontSize: 25,
                fontWeight: FontWeight.w700,
                letterSpacing: -.6,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Recent synchronized staff-task activity.',
              style: TextStyle(
                color: _PlpTeamAccessScreenState._muted,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 18),
            if (activity.isEmpty)
              const _EmptyState(
                icon: Icons.history_rounded,
                title: 'No recent activity',
                detail: 'Staff-task events will appear here after sync.',
              )
            else
              for (var index = 0; index < activity.length; index++) ...[
                _ActivityRow(
                  item: activity[index],
                  textFor: textFor,
                  boolFor: boolFor,
                ),
                if (index != activity.length - 1)
                  const Divider(
                    height: 1,
                    color: _PlpTeamAccessScreenState._line,
                  ),
              ],
          ],
        ),
      );
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.item,
    required this.textFor,
    required this.boolFor,
  });

  final Map<String, Object?> item;
  final String Function(Object?, {String fallback}) textFor;
  final bool Function(Object?) boolFor;

  @override
  Widget build(BuildContext context) {
    final mock = boolFor(item['isMock']);
    final status = textFor(item['status'], fallback: 'updated');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _PlpTeamAccessScreenState._goldSoft,
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: _PlpTeamAccessScreenState._gold,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  textFor(item['title'], fallback: 'Team activity'),
                  style: const TextStyle(
                    color: _PlpTeamAccessScreenState._ink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  textFor(item['actor'], fallback: 'PLP team'),
                  style: const TextStyle(
                    color: _PlpTeamAccessScreenState._muted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          if (mock)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1C170F),
                borderRadius: BorderRadius.zero,
              ),
              child: const Text(
                'QA',
                style: TextStyle(
                  color: Color(0xFFD4A052),
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          Text(
            status.replaceAll('_', ' '),
            style: const TextStyle(
              color: _PlpTeamAccessScreenState._muted,
              fontSize: 9.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _PlpTeamAccessScreenState._paper,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: _PlpTeamAccessScreenState._line),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: _PlpTeamAccessScreenState._gold,
              size: 26,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _PlpTeamAccessScreenState._ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: _PlpTeamAccessScreenState._muted,
                      fontSize: 10.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
