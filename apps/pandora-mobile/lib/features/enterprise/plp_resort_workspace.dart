import 'package:flutter/material.dart';

import '../../core/widgets/pandora_navigation.dart';

class PlpResortSection {
  const PlpResortSection({
    required this.id,
    required this.label,
    required this.icon,
    required this.commandHint,
  });

  final String id;
  final String label;
  final IconData icon;
  final String commandHint;
}

const plpResortSections = <PlpResortSection>[
  PlpResortSection(id: 'today', label: 'Today', icon: Icons.wb_sunny_outlined, commandHint: 'Ask what matters today…'),
  PlpResortSection(id: 'stays', label: 'Stays', icon: Icons.event_available_outlined, commandHint: 'Ask about a stay or arrival…'),
  PlpResortSection(id: 'rooms', label: 'Rooms', icon: Icons.bed_outlined, commandHint: 'Ask about rooms or housekeeping…'),
  PlpResortSection(id: 'guests', label: 'Guests', icon: Icons.person_outline_rounded, commandHint: 'Ask about a guest or request…'),
  PlpResortSection(id: 'operations', label: 'Operations', icon: Icons.hub_outlined, commandHint: 'Ask about resort operations…'),
  PlpResortSection(id: 'revenue', label: 'Revenue', icon: Icons.insights_outlined, commandHint: 'Ask about revenue or availability…'),
  PlpResortSection(id: 'experiences', label: 'Experiences', icon: Icons.spa_outlined, commandHint: 'Ask about concierge or experiences…'),
  PlpResortSection(id: 'team', label: 'Team', icon: Icons.groups_outlined, commandHint: 'Ask about team or access…'),
  PlpResortSection(id: 'activity', label: 'Activity', icon: Icons.history_rounded, commandHint: 'Ask what changed recently…'),
];

PlpResortSection? plpResortSectionById(String id) {
  for (final section in plpResortSections) {
    if (section.id == id) return section;
  }
  return null;
}

class PlpResortWorkspaceScreen extends StatelessWidget {
  const PlpResortWorkspaceScreen({
    super.key,
    required this.section,
    required this.bootstrap,
    required this.onOpenNavigation,
    required this.onRefresh,
    required this.onAskPandora,
    this.onOpenSection,
    this.onOpenOperationsRoom,
    this.onOpenGuestExperience,
    this.onOpenTeam,
    this.onOpenActivity,
  });

  final PlpResortSection section;
  final Map<String, Object?> bootstrap;
  final VoidCallback onOpenNavigation;
  final VoidCallback onRefresh;
  final ValueChanged<String> onAskPandora;
  final ValueChanged<String>? onOpenSection;
  final VoidCallback? onOpenOperationsRoom;
  final VoidCallback? onOpenGuestExperience;
  final VoidCallback? onOpenTeam;
  final VoidCallback? onOpenActivity;

  static const canvas = Color(0xFFFAF7F1);
  static const paper = Color(0xFFFFFDFC);
  static const ink = Color(0xFF171512);
  static const muted = Color(0xFF756F67);
  static const line = Color(0xFFE4DCCF);
  static const accent = Color(0xFF776A43);
  static const good = Color(0xFF60745F);
  static const warn = Color(0xFFA46C31);
  static const softGold = Color(0xFFF0E8D8);

  @override
  Widget build(BuildContext context) {
    final children = switch (section.id) {
      'today' => _today(),
      'stays' => _stays(),
      'rooms' => _rooms(),
      'guests' => _guests(),
      'operations' => _operations(),
      'revenue' => _revenue(),
      'experiences' => _experiences(),
      'team' => _team(),
      'activity' => _activity(),
      _ => <Widget>[const _EmptyState('This resort workspace is not available.')],
    };

    return Material(
      color: canvas,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: ink,
          backgroundColor: paper,
          onRefresh: () async => onRefresh(),
          child: ListView(
            key: ValueKey<String>('plp-resort-' + section.id),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 190),
            children: [
              _ResortHeader(
                section: section,
                propertyName: _text(
                  _map(bootstrap['organization'])['propertyName'],
                  fallback: 'Pueblo La Perla',
                ),
                sourceState: _text(
                  _map(bootstrap['sourceHealth'])['state'],
                  fallback: 'unknown',
                ),
                onOpenNavigation: onOpenNavigation,
              ),
              const SizedBox(height: 26),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _today() {
    final today = _map(bootstrap['today']);
    final guest = _map(bootstrap['guestExperience']);
    final command = _map(bootstrap['resortCommandCenter']);
    final pulse = _map(command['roomPulse']);
    final operations = _map(command['operations']);
    final inHouse = _maps(guest['inHouse']);
    final arrivals = _maps(guest['arrivals']);
    final departing = _maps(guest['departing']);
    final attention = _maps(guest['attention']);
    final total = _number(pulse['total'], fallback: _number(today['rooms_total']));
    final occupied = _number(
      pulse['occupied'],
      fallback: _number(today['occupied_rooms']),
    );
    final available = _number(
      pulse['available'],
      fallback: _number(today['rooms_available']),
    );
    final openWork = _number(
      operations['openWork'],
      fallback: _number(today['open_staff_tasks']),
    );
    final conflicts = _number(
      operations['channelExceptions'],
      fallback: _number(today['open_ota_conflicts']),
    );

    return [
      _HeroLine(
        eyebrow: 'TODAY AT PUEBLO LA PERLA',
        title: conflicts > 0 || openWork > 0
            ? 'The resort needs a little attention.'
            : 'The resort is composed.',
        trailing: _peso(today['sales_today_php']),
      ),
      const SizedBox(height: 24),
      _MetricRail(
        items: [
          _Metric(
            'Occupancy',
            _text(today['occupancy_percent'], fallback: '0') + '%',
            _integer(occupied) + ' of ' + _integer(total),
          ),
          _Metric('Available', _integer(available), 'rooms'),
          _Metric(
            'Arrivals',
            _integer(
              _number(today['arrivals_today'], fallback: arrivals.length),
            ),
            'today',
          ),
          _Metric('Open work', _integer(openWork), 'items'),
        ],
      ),
      const SizedBox(height: 30),
      _MovementPair(
        arrivals: _integer(
          _number(today['arrivals_today'], fallback: arrivals.length),
        ),
        departures: _integer(
          _number(today['departures_today'], fallback: departing.length),
        ),
        onArrivals: () => onOpenSection?.call('stays'),
        onDepartures: () => onOpenSection?.call('stays'),
      ),
      const SizedBox(height: 28),
      _RoomPulse(
        total: total,
        occupied: occupied,
        available: available,
        arriving: _number(pulse['arriving'], fallback: arrivals.length),
        departing: _number(pulse['departing'], fallback: departing.length),
      ),
      const SizedBox(height: 30),
      _SectionHeader(
        'NEEDS ATTENTION',
        action: attention.isNotEmpty ? attention.length.toString() : null,
      ),
      const SizedBox(height: 10),
      if (attention.isEmpty && conflicts == 0)
        const _ClearState(
          'No guest or channel exception needs owner attention.',
        )
      else
        _AttentionList(
          items: attention,
          conflicts: conflicts,
          onAskPandora: onAskPandora,
        ),
      if (inHouse.isNotEmpty) ...[
        const SizedBox(height: 32),
        _SectionHeader('IN HOUSE', action: inHouse.length.toString()),
        const SizedBox(height: 12),
        _GuestStrip(items: inHouse, onTap: onOpenGuestExperience),
      ],
      const SizedBox(height: 34),
      const _SectionHeader('RESORT'),
      const SizedBox(height: 12),
      _SectionLaunchRail(onOpen: onOpenSection),
    ];
  }

  List<Widget> _stays() {
    final guest = _map(bootstrap['guestExperience']);
    final command = _map(bootstrap['resortCommandCenter']);
    final stays = _maps(command['stays']);
    final arrivals = _maps(guest['arrivals']);
    final inHouse = _maps(guest['inHouse']);
    final departing = _maps(guest['departing']);
    return [
      const _HeroLine(
        eyebrow: 'STAYS',
        title: 'Every stay in one calm view.',
      ),
      const SizedBox(height: 22),
      _MetricRail(
        items: [
          _Metric('Arriving', arrivals.length.toString(), 'today'),
          _Metric('In house', inHouse.length.toString(), 'current'),
          _Metric('Departing', departing.length.toString(), 'today'),
        ],
      ),
      const SizedBox(height: 30),
      _SectionHeader(
        'UPCOMING & ACTIVE',
        action: stays.isNotEmpty ? stays.length.toString() : null,
      ),
      const SizedBox(height: 8),
      if (stays.isEmpty)
        const _EmptyState('No connected stay records are available.')
      else
        _StayList(items: stays, onAskPandora: onAskPandora),
    ];
  }

  List<Widget> _rooms() {
    final command = _map(bootstrap['resortCommandCenter']);
    final pulse = _map(command['roomPulse']);
    final rooms = _maps(command['rooms']);
    final today = _map(bootstrap['today']);
    final total = _number(
      pulse['total'],
      fallback: _number(today['rooms_total']),
    );
    final occupied = _number(
      pulse['occupied'],
      fallback: _number(today['occupied_rooms']),
    );
    final available = _number(
      pulse['available'],
      fallback: _number(today['rooms_available']),
    );
    return [
      const _HeroLine(
        eyebrow: 'ROOMS & HOUSEKEEPING',
        title: 'The property at a glance.',
      ),
      const SizedBox(height: 24),
      _RoomPulse(
        total: total,
        occupied: occupied,
        available: available,
        arriving: _number(pulse['arriving']),
        departing: _number(pulse['departing']),
      ),
      const SizedBox(height: 28),
      _SectionHeader(
        'ROOM BOARD',
        action: rooms.isNotEmpty ? rooms.length.toString() : null,
      ),
      const SizedBox(height: 12),
      if (rooms.isEmpty)
        const _EmptyState(
          'Room-level status will appear when accommodation records are connected.',
        )
      else
        _RoomGrid(rooms: rooms, onAskPandora: onAskPandora),
      const SizedBox(height: 30),
      _CapabilityGrid(
        items: [
          _Capability(
            'Housekeeping',
            Icons.cleaning_services_outlined,
            () => onAskPandora(
              'Show housekeeping priorities and room turnover readiness.',
            ),
          ),
          _Capability(
            'Maintenance',
            Icons.build_outlined,
            () => onAskPandora(
              'Show room maintenance issues that can affect a guest stay.',
            ),
          ),
          _Capability(
            'Linen',
            Icons.local_laundry_service_outlined,
            () => onAskPandora(
              'Show linen or laundry issues that need action.',
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _guests() {
    final guest = _map(bootstrap['guestExperience']);
    final command = _map(bootstrap['resortCommandCenter']);
    final inHouse = _maps(guest['inHouse']);
    final arrivals = _maps(guest['arrivals']);
    final requests = _maps(command['experienceSignals']);
    return [
      const _HeroLine(
        eyebrow: 'GUESTS',
        title: 'Know the stay, not just the booking.',
      ),
      const SizedBox(height: 22),
      _MetricRail(
        items: [
          _Metric('In house', inHouse.length.toString(), 'guests'),
          _Metric('Arriving', arrivals.length.toString(), 'today'),
          _Metric('Requests', requests.length.toString(), 'connected'),
        ],
      ),
      if (inHouse.isNotEmpty) ...[
        const SizedBox(height: 30),
        _SectionHeader(
          'CURRENT GUESTS',
          action: inHouse.length.toString(),
        ),
        const SizedBox(height: 12),
        _GuestStrip(items: inHouse, onTap: onOpenGuestExperience),
      ],
      const SizedBox(height: 30),
      _SectionHeader(
        'REQUESTS & PREFERENCES',
        action: requests.isNotEmpty ? requests.length.toString() : null,
      ),
      const SizedBox(height: 10),
      if (requests.isEmpty)
        const _ClearState('No connected special request is waiting.')
      else
        _RequestList(items: requests, onAskPandora: onAskPandora),
      const SizedBox(height: 30),
      _CapabilityGrid(
        items: [
          _Capability(
            'Concierge',
            Icons.support_agent_outlined,
            () => onAskPandora(
              'Open the concierge view for current and arriving guests.',
            ),
          ),
          _Capability(
            'VIP',
            Icons.workspace_premium_outlined,
            () => onAskPandora(
              'Show VIP arrivals and preference-sensitive guest moments.',
            ),
          ),
          _Capability(
            'Transfers',
            Icons.airport_shuttle_outlined,
            () => onAskPandora(
              'Show guest transfer needs around arrivals and departures.',
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _operations() {
    final command = _map(bootstrap['resortCommandCenter']);
    final operations = _map(command['operations']);
    final guest = _map(bootstrap['guestExperience']);
    final attention = _maps(guest['attention']);
    return [
      const _HeroLine(
        eyebrow: 'OPERATIONS',
        title: 'Keep the resort moving quietly.',
      ),
      const SizedBox(height: 22),
      _MetricRail(
        items: [
          _Metric(
            'Open work',
            _integer(_number(operations['openWork'])),
            'items',
          ),
          _Metric(
            'Priority',
            _integer(_number(operations['priorityWork'])),
            'high',
          ),
          _Metric(
            'Channel',
            _integer(_number(operations['channelExceptions'])),
            'exceptions',
          ),
        ],
      ),
      const SizedBox(height: 30),
      _SectionHeader(
        'ACTIVE WORK',
        action: attention.isNotEmpty ? attention.length.toString() : null,
      ),
      const SizedBox(height: 10),
      if (attention.isEmpty)
        const _ClearState('No connected operational task is waiting.')
      else
        _AttentionList(
          items: attention,
          conflicts: _number(operations['channelExceptions']),
          onAskPandora: onAskPandora,
        ),
      const SizedBox(height: 30),
      _CapabilityGrid(
        items: [
          _Capability(
            'Property',
            Icons.domain_outlined,
            () => onAskPandora(
              'Show property operations and maintenance priorities.',
            ),
          ),
          _Capability(
            'Security',
            Icons.shield_outlined,
            () => onAskPandora(
              'Show verified safety or security items that need attention.',
            ),
          ),
          _Capability(
            'Transport',
            Icons.directions_car_outlined,
            () => onAskPandora(
              'Show transport and transfer operations for today.',
            ),
          ),
        ],
      ),
      if (onOpenOperationsRoom != null) ...[
        const SizedBox(height: 24),
        _ActionBar(
          label: 'Operations Room',
          icon: Icons.hub_outlined,
          onTap: onOpenOperationsRoom!,
        ),
      ],
    ];
  }

  List<Widget> _revenue() {
    final today = _map(bootstrap['today']);
    final finance = _map(
      _map(bootstrap['resortCommandCenter'])['finance'],
    );
    return [
      _HeroLine(
        eyebrow: 'REVENUE',
        title: _peso(today['sales_today_php']),
        subtitle: 'TODAY',
      ),
      const SizedBox(height: 22),
      _MetricRail(
        items: [
          _Metric(
            'Occupancy',
            _text(today['occupancy_percent'], fallback: '0') + '%',
            'today',
          ),
          _Metric(
            'Available',
            _integer(_number(today['rooms_available'])),
            'rooms',
          ),
        ],
      ),
      const SizedBox(height: 30),
      const _SectionHeader('NEXT 30 DAYS'),
      const SizedBox(height: 12),
      _MoneyBand(
        label: 'Booked value',
        value: _peso(finance['bookedValue30dPhp']),
      ),
      _MoneyBand(
        label: 'Outstanding',
        value: _peso(finance['outstandingBalancePhp']),
        tone: warn,
      ),
      _MoneyBand(
        label: 'Collected',
        value: _peso(finance['paidValue30dPhp']),
        tone: good,
      ),
      const SizedBox(height: 30),
      _CapabilityGrid(
        items: [
          _Capability(
            'Rates',
            Icons.sell_outlined,
            () => onAskPandora(
              'Review rates and availability for the next 30 days.',
            ),
          ),
          _Capability(
            'Channels',
            Icons.travel_explore_outlined,
            () => onAskPandora(
              'Show OTA channel exceptions and inventory risks.',
            ),
          ),
          _Capability(
            'Forecast',
            Icons.query_stats_outlined,
            () => onAskPandora(
              'Summarize the forward occupancy and revenue picture from connected data.',
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _experiences() {
    final requests = _maps(
      _map(bootstrap['resortCommandCenter'])['experienceSignals'],
    );
    return [
      const _HeroLine(
        eyebrow: 'EXPERIENCES',
        title: 'Hospitality beyond the room.',
      ),
      const SizedBox(height: 22),
      _CapabilityGrid(
        items: [
          _Capability(
            'Concierge',
            Icons.support_agent_outlined,
            () => onAskPandora(
              'Coordinate concierge requests for current and arriving guests.',
            ),
          ),
          _Capability(
            'Transfers',
            Icons.airport_shuttle_outlined,
            () => onAskPandora(
              'Coordinate airport and island transfers around guest movement.',
            ),
          ),
          _Capability(
            'Dining',
            Icons.restaurant_outlined,
            () => onAskPandora(
              'Show dining-related guest requests and connected hospitality context.',
            ),
          ),
          _Capability(
            'Wellness',
            Icons.spa_outlined,
            () => onAskPandora(
              'Show spa or wellness requests from connected guest context.',
            ),
          ),
          _Capability(
            'Activities',
            Icons.explore_outlined,
            () => onAskPandora(
              'Show experience and activity requests from connected guest context.',
            ),
          ),
          _Capability(
            'Events',
            Icons.celebration_outlined,
            () => onAskPandora(
              'Show event or celebration needs from connected guest context.',
            ),
          ),
        ],
      ),
      const SizedBox(height: 30),
      _SectionHeader(
        'GUEST SIGNALS',
        action: requests.isNotEmpty ? requests.length.toString() : null,
      ),
      const SizedBox(height: 10),
      if (requests.isEmpty)
        const _ClearState('No connected experience request is waiting.')
      else
        _RequestList(items: requests, onAskPandora: onAskPandora),
    ];
  }

  List<Widget> _team() {
    final team = _map(bootstrap['teamAccess']);
    final members = _maps(team['members']);
    final activity = _maps(team['recentActivity']);
    return [
      const _HeroLine(
        eyebrow: 'TEAM',
        title: 'The people running the property.',
      ),
      const SizedBox(height: 22),
      _MetricRail(
        items: [
          _Metric(
            'Active',
            _integer(_number(team['activeMemberCount'])),
            'access',
          ),
          _Metric('Visible', members.length.toString(), 'members'),
          _Metric(
            'Staff IDs',
            _integer(_number(team['staffIdentityCount'])),
            'mapped',
          ),
        ],
      ),
      if (members.isNotEmpty) ...[
        const SizedBox(height: 30),
        _SectionHeader('ACCESS', action: members.length.toString()),
        const SizedBox(height: 10),
        _MemberStrip(items: members),
      ],
      if (activity.isNotEmpty) ...[
        const SizedBox(height: 30),
        const _SectionHeader('RECENT WORK'),
        const SizedBox(height: 8),
        _ActivityList(items: activity),
      ],
      if (onOpenTeam != null) ...[
        const SizedBox(height: 24),
        _ActionBar(
          label: 'Team & access',
          icon: Icons.admin_panel_settings_outlined,
          onTap: onOpenTeam!,
        ),
      ],
    ];
  }

  List<Widget> _activity() {
    final source = _map(bootstrap['sourceHealth']);
    final team = _map(bootstrap['teamAccess']);
    final activity = _maps(team['recentActivity']);
    return [
      const _HeroLine(
        eyebrow: 'ACTIVITY',
        title: 'What changed, without the noise.',
      ),
      const SizedBox(height: 22),
      _SourceBand(
        state: _text(source['state'], fallback: 'unknown'),
        message: _text(
          source['message'],
          fallback: 'No source message.',
        ),
      ),
      const SizedBox(height: 28),
      _SectionHeader(
        'RECENT BUSINESS ACTIVITY',
        action: activity.isNotEmpty ? activity.length.toString() : null,
      ),
      const SizedBox(height: 8),
      if (activity.isEmpty)
        const _EmptyState('No recent business activity is connected.')
      else
        _ActivityList(items: activity),
      if (onOpenActivity != null) ...[
        const SizedBox(height: 24),
        _ActionBar(
          label: 'Verified activity feed',
          icon: Icons.fact_check_outlined,
          onTap: onOpenActivity!,
        ),
      ],
    ];
  }
}

class _ResortHeader extends StatelessWidget {
  const _ResortHeader({
    required this.section,
    required this.propertyName,
    required this.sourceState,
    required this.onOpenNavigation,
  });

  final PlpResortSection section;
  final String propertyName;
  final String sourceState;
  final VoidCallback onOpenNavigation;

  @override
  Widget build(BuildContext context) {
    final healthy = sourceState.toLowerCase() == 'healthy';
    return Row(
      children: [
        PandoraMenuButton(
          key: const ValueKey('plp-open-navigation'),
          onPressed: onOpenNavigation,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                propertyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PlpResortWorkspaceScreen.ink,
                  fontFamily: 'serif',
                  fontSize: 21,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -.35,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                section.label.toUpperCase(),
                style: const TextStyle(
                  color: PlpResortWorkspaceScreen.accent,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.7,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: healthy
                ? PlpResortWorkspaceScreen.good
                : PlpResortWorkspaceScreen.warn,
          ),
        ),
      ],
    );
  }
}

class _HeroLine extends StatelessWidget {
  const _HeroLine({
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: const TextStyle(
              color: PlpResortWorkspaceScreen.accent,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  title,
                  key: const ValueKey('plp-resort-hero'),
                  style: const TextStyle(
                    color: PlpResortWorkspaceScreen.ink,
                    fontFamily: 'serif',
                    fontSize: 38,
                    height: .98,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -1.2,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                Text(
                  trailing!,
                  style: const TextStyle(
                    color: PlpResortWorkspaceScreen.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: const TextStyle(
                color: PlpResortWorkspaceScreen.muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.7,
              ),
            ),
          ],
        ],
      );
}

class _Metric {
  const _Metric(this.label, this.value, this.detail);
  final String label;
  final String value;
  final String detail;
}

class _MetricRail extends StatelessWidget {
  const _MetricRail({required this.items});
  final List<_Metric> items;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 102,
        child: ListView.separated(
          key: const ValueKey('plp-metric-rail'),
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, index) {
            final item = items[index];
            return Container(
              width: 116,
              decoration: const BoxDecoration(
                color: PlpResortWorkspaceScreen.paper,
                border: Border.fromBorderSide(
                  BorderSide(color: PlpResortWorkspaceScreen.line),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(13, 13, 13, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label.toUpperCase(),
                    style: const TextStyle(
                      color: PlpResortWorkspaceScreen.accent,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.25,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    item.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PlpResortWorkspaceScreen.ink,
                      fontFamily: 'serif',
                      fontSize: 25,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PlpResortWorkspaceScreen.muted,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
}

class _MovementPair extends StatelessWidget {
  const _MovementPair({
    required this.arrivals,
    required this.departures,
    this.onArrivals,
    this.onDepartures,
  });

  final String arrivals;
  final String departures;
  final VoidCallback? onArrivals;
  final VoidCallback? onDepartures;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: _MovementTile(
              label: 'ARRIVALS',
              value: arrivals,
              icon: Icons.south_west_rounded,
              onTap: onArrivals,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MovementTile(
              label: 'DEPARTURES',
              value: departures,
              icon: Icons.north_east_rounded,
              onTap: onDepartures,
            ),
          ),
        ],
      );
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: PlpResortWorkspaceScreen.ink,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 17, 14, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: Color(0xFFD8D0C2),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        value,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'serif',
                          fontSize: 34,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(icon, color: Colors.white, size: 22),
              ],
            ),
          ),
        ),
      );
}

class _RoomPulse extends StatelessWidget {
  const _RoomPulse({
    required this.total,
    required this.occupied,
    required this.available,
    required this.arriving,
    required this.departing,
  });

  final num total;
  final num occupied;
  final num available;
  final num arriving;
  final num departing;

  @override
  Widget build(BuildContext context) {
    final ratio = total <= 0
        ? 0.0
        : (occupied / total).clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('ROOM PULSE'),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(1),
          child: Container(
            height: 10,
            color: const Color(0xFFE5DED2),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: ratio,
              child: Container(color: PlpResortWorkspaceScreen.ink),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                _integer(occupied) +
                    ' occupied · ' +
                    _integer(available) +
                    ' available',
                style: const TextStyle(
                  color: PlpResortWorkspaceScreen.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              _integer(arriving) + ' in · ' + _integer(departing) + ' out',
              style: const TextStyle(
                color: PlpResortWorkspaceScreen.muted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, {this.action});
  final String label;
  final String? action;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: PlpResortWorkspaceScreen.accent,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.8,
              ),
            ),
          ),
          if (action != null)
            Text(
              action!,
              style: const TextStyle(
                color: PlpResortWorkspaceScreen.muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: .7,
              ),
            ),
        ],
      );
}

class _AttentionList extends StatelessWidget {
  const _AttentionList({
    required this.items,
    required this.conflicts,
    required this.onAskPandora,
  });

  final List<Map<String, Object?>> items;
  final num conflicts;
  final ValueChanged<String> onAskPandora;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final item in items.take(4)) {
      rows.add(
        _CompactRow(
          title: _text(item['title'], fallback: 'Open resort task'),
          meta: <String>[
            _text(item['priority'], fallback: 'normal').toUpperCase(),
            _text(item['fullName'], fallback: ''),
          ].where((value) => value.isNotEmpty).join(' · '),
          tone: _text(item['priority']).toLowerCase() == 'high'
              ? PlpResortWorkspaceScreen.warn
              : PlpResortWorkspaceScreen.accent,
          onTap: () => onAskPandora(
            'Open this resort task and tell me the safest next action: ' +
                _text(item['title']) +
                '.',
          ),
        ),
      );
    }
    if (conflicts > 0) {
      rows.add(
        _CompactRow(
          title: _integer(conflicts) +
              ' OTA channel ' +
              (conflicts == 1 ? 'exception' : 'exceptions'),
          meta: 'Booking inventory needs reconciliation',
          tone: PlpResortWorkspaceScreen.warn,
          onTap: () => onAskPandora(
            'Show the open OTA conflicts and what needs action first.',
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _CompactRow extends StatelessWidget {
  const _CompactRow({
    required this.title,
    required this.meta,
    this.tone = PlpResortWorkspaceScreen.accent,
    this.onTap,
  });

  final String title;
  final String meta;
  final Color tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: PlpResortWorkspaceScreen.line),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Row(
              children: [
                Container(width: 7, height: 7, color: tone),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PlpResortWorkspaceScreen.ink,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: PlpResortWorkspaceScreen.muted,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onTap != null)
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 17,
                    color: PlpResortWorkspaceScreen.muted,
                  ),
              ],
            ),
          ),
        ),
      );
}

class _GuestStrip extends StatelessWidget {
  const _GuestStrip({required this.items, this.onTap});
  final List<Map<String, Object?>> items;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 126,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.take(8).length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, index) {
            final item = items[index];
            final name = _text(item['fullName'], fallback: 'Guest');
            return Material(
              color: PlpResortWorkspaceScreen.paper,
              child: InkWell(
                onTap: onTap,
                child: Container(
                  width: 178,
                  decoration: const BoxDecoration(
                    border: Border.fromBorderSide(
                      BorderSide(color: PlpResortWorkspaceScreen.line),
                    ),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: PlpResortWorkspaceScreen.softGold,
                        foregroundColor: PlpResortWorkspaceScreen.ink,
                        child: Text(
                          name.characters.first.toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PlpResortWorkspaceScreen.ink,
                          fontFamily: 'serif',
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _text(
                          item['accommodationName'],
                          fallback: _text(
                            item['displayStatus'],
                            fallback: 'Current stay',
                          ),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PlpResortWorkspaceScreen.muted,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
}

class _StayList extends StatelessWidget {
  const _StayList({required this.items, required this.onAskPandora});
  final List<Map<String, Object?>> items;
  final ValueChanged<String> onAskPandora;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final item in items.take(12))
            _CompactRow(
              title: _text(item['fullName'], fallback: 'Guest stay'),
              meta: _text(item['accommodationName'], fallback: 'Room') +
                  ' · ' +
                  _text(item['checkIn']) +
                  ' → ' +
                  _text(item['checkOut']) +
                  ' · ' +
                  _text(item['paymentStatus'], fallback: 'payment n/a'),
              tone: _text(item['status']).toLowerCase().contains('cancel')
                  ? PlpResortWorkspaceScreen.warn
                  : PlpResortWorkspaceScreen.good,
              onTap: () => onAskPandora(
                'Open stay ' +
                    _text(item['bookingReference']) +
                    ' for ' +
                    _text(item['fullName']) +
                    ' and summarize what matters.',
              ),
            ),
        ],
      );
}

class _RoomGrid extends StatelessWidget {
  const _RoomGrid({required this.rooms, required this.onAskPandora});
  final List<Map<String, Object?>> rooms;
  final ValueChanged<String> onAskPandora;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 8) / 2;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final room in rooms)
                SizedBox(
                  width: width,
                  child: Material(
                    color: PlpResortWorkspaceScreen.paper,
                    child: InkWell(
                      onTap: () => onAskPandora(
                        'Open ' +
                            _text(room['name'], fallback: 'this room') +
                            ' and show the current operational context.',
                      ),
                      child: Container(
                        height: 106,
                        decoration: const BoxDecoration(
                          border: Border.fromBorderSide(
                            BorderSide(
                              color: PlpResortWorkspaceScreen.line,
                            ),
                          ),
                        ),
                        padding: const EdgeInsets.all(13),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _text(room['name'], fallback: 'Room'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: PlpResortWorkspaceScreen.ink,
                                      fontFamily: 'serif',
                                      fontSize: 17,
                                    ),
                                  ),
                                ),
                                _StateDot(
                                  state: _text(
                                    room['state'],
                                    fallback: 'available',
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Text(
                              _text(
                                room['state'],
                                fallback: 'available',
                              ).toUpperCase(),
                              style: const TextStyle(
                                color: PlpResortWorkspaceScreen.accent,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _integer(_number(room['capacity'])) +
                                  ' guests · ' +
                                  _integer(_number(room['bedrooms'])) +
                                  ' bed',
                              style: const TextStyle(
                                color: PlpResortWorkspaceScreen.muted,
                                fontSize: 9.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
}

class _StateDot extends StatelessWidget {
  const _StateDot({required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    final tone = switch (state.toLowerCase()) {
      'occupied' => PlpResortWorkspaceScreen.ink,
      'arrival' => PlpResortWorkspaceScreen.accent,
      'departure' => PlpResortWorkspaceScreen.warn,
      _ => PlpResortWorkspaceScreen.good,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
    );
  }
}

class _RequestList extends StatelessWidget {
  const _RequestList({required this.items, required this.onAskPandora});
  final List<Map<String, Object?>> items;
  final ValueChanged<String> onAskPandora;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final item in items.take(8))
            _CompactRow(
              title: _text(item['fullName'], fallback: 'Guest request'),
              meta: _text(
                item['request'],
                fallback: 'Connected guest request',
              ),
              onTap: () => onAskPandora(
                'Help coordinate this guest request for ' +
                    _text(item['fullName']) +
                    ': ' +
                    _text(item['request']),
              ),
            ),
        ],
      );
}

class _Capability {
  const _Capability(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class _CapabilityGrid extends StatelessWidget {
  const _CapabilityGrid({required this.items});
  final List<_Capability> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 8) / 2;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in items)
                SizedBox(
                  width: width,
                  child: Material(
                    color: PlpResortWorkspaceScreen.paper,
                    child: InkWell(
                      onTap: item.onTap,
                      child: Container(
                        height: 82,
                        decoration: const BoxDecoration(
                          border: Border.fromBorderSide(
                            BorderSide(
                              color: PlpResortWorkspaceScreen.line,
                            ),
                          ),
                        ),
                        padding: const EdgeInsets.all(13),
                        child: Row(
                          children: [
                            Icon(
                              item.icon,
                              size: 21,
                              color: PlpResortWorkspaceScreen.accent,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item.label,
                                maxLines: 2,
                                style: const TextStyle(
                                  color: PlpResortWorkspaceScreen.ink,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                              color: PlpResortWorkspaceScreen.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
}

class _SectionLaunchRail extends StatelessWidget {
  const _SectionLaunchRail({this.onOpen});
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final items = plpResortSections
        .where((item) => item.id != 'today')
        .toList(growable: false);
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final item = items[index];
          return Material(
            color: PlpResortWorkspaceScreen.paper,
            child: InkWell(
              onTap: () => onOpen?.call(item.id),
              child: Container(
                width: 116,
                decoration: const BoxDecoration(
                  border: Border.fromBorderSide(
                    BorderSide(color: PlpResortWorkspaceScreen.line),
                  ),
                ),
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      item.icon,
                      size: 20,
                      color: PlpResortWorkspaceScreen.accent,
                    ),
                    const Spacer(),
                    Text(
                      item.label,
                      style: const TextStyle(
                        color: PlpResortWorkspaceScreen.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MoneyBand extends StatelessWidget {
  const _MoneyBand({
    required this.label,
    required this.value,
    this.tone = PlpResortWorkspaceScreen.ink,
  });

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: PlpResortWorkspaceScreen.line),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: PlpResortWorkspaceScreen.muted,
                  fontSize: 12,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: tone,
                fontFamily: 'serif',
                fontSize: 24,
              ),
            ),
          ],
        ),
      );
}

class _MemberStrip extends StatelessWidget {
  const _MemberStrip({required this.items});
  final List<Map<String, Object?>> items;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final item in items.take(10))
            _CompactRow(
              title: _text(
                item['displayName'],
                fallback: 'PLP team member',
              ),
              meta: _text(item['roleLabel'], fallback: 'Member') +
                  ' · ' +
                  _text(item['accessStatus'], fallback: 'unknown'),
              tone: _text(item['active']).toLowerCase() == 'true'
                  ? PlpResortWorkspaceScreen.good
                  : PlpResortWorkspaceScreen.muted,
            ),
        ],
      );
}

class _ActivityList extends StatelessWidget {
  const _ActivityList({required this.items});
  final List<Map<String, Object?>> items;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final item in items.take(10))
            _CompactRow(
              title: _text(item['title'], fallback: 'Resort activity'),
              meta: <String>[
                _text(item['actor'], fallback: ''),
                _text(item['status'], fallback: ''),
              ].where((value) => value.isNotEmpty).join(' · '),
            ),
        ],
      );
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: PlpResortWorkspaceScreen.ink,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      );
}

class _SourceBand extends StatelessWidget {
  const _SourceBand({required this.state, required this.message});

  final String state;
  final String message;

  @override
  Widget build(BuildContext context) {
    final healthy = state.toLowerCase() == 'healthy';
    return Container(
      decoration: const BoxDecoration(
        color: PlpResortWorkspaceScreen.paper,
        border: Border.fromBorderSide(
          BorderSide(color: PlpResortWorkspaceScreen.line),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: healthy
                  ? PlpResortWorkspaceScreen.good
                  : PlpResortWorkspaceScreen.warn,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.toUpperCase(),
                  style: const TextStyle(
                    color: PlpResortWorkspaceScreen.ink,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PlpResortWorkspaceScreen.muted,
                    fontSize: 11,
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
}

class _ClearState extends StatelessWidget {
  const _ClearState(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: PlpResortWorkspaceScreen.softGold,
        ),
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_outline_rounded,
              size: 18,
              color: PlpResortWorkspaceScreen.good,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: PlpResortWorkspaceScreen.ink,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          border: Border.fromBorderSide(
            BorderSide(color: PlpResortWorkspaceScreen.line),
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Text(
          text,
          style: const TextStyle(
            color: PlpResortWorkspaceScreen.muted,
            fontSize: 11.5,
            height: 1.4,
          ),
        ),
      );
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry(key.toString(), item),
    );
  }
  return const <String, Object?>{};
}

List<Map<String, Object?>> _maps(Object? value) {
  if (value is! List) return const <Map<String, Object?>>[];
  return value.map(_map).toList(growable: false);
}

String _text(Object? value, {String fallback = '—'}) {
  final normalized = value?.toString().trim();
  return normalized == null || normalized.isEmpty
      ? fallback
      : normalized;
}

num _number(Object? value, {num fallback = 0}) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? fallback;
}

String _integer(num value) => value.round().toString();

String _peso(Object? value) {
  final amount = _number(value).round();
  final raw = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 == 0) buffer.write(',');
    buffer.write(raw[i]);
  }
  return (amount < 0 ? '-₱' : '₱') + buffer.toString();
}
