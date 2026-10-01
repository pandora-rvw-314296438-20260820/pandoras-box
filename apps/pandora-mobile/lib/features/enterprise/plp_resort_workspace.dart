import 'package:flutter/material.dart';

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
  PlpResortSection(
      id: 'today',
      label: 'Today',
      icon: Icons.wb_sunny_outlined,
      commandHint: 'Ask what matters today…'),
  PlpResortSection(
      id: 'stays',
      label: 'Stays',
      icon: Icons.event_available_outlined,
      commandHint: 'Ask about a stay or arrival…'),
  PlpResortSection(
      id: 'rooms',
      label: 'Rooms',
      icon: Icons.bed_outlined,
      commandHint: 'Ask about rooms or housekeeping…'),
  PlpResortSection(
      id: 'guests',
      label: 'Guests',
      icon: Icons.person_outline_rounded,
      commandHint: 'Ask about a guest or request…'),
  PlpResortSection(
      id: 'operations',
      label: 'Operations',
      icon: Icons.hub_outlined,
      commandHint: 'Ask about resort operations…'),
  PlpResortSection(
      id: 'revenue',
      label: 'Revenue',
      icon: Icons.insights_outlined,
      commandHint: 'Ask about revenue or availability…'),
  PlpResortSection(
      id: 'experiences',
      label: 'Experiences',
      icon: Icons.spa_outlined,
      commandHint: 'Ask about concierge or experiences…'),
  PlpResortSection(
      id: 'team',
      label: 'Team',
      icon: Icons.groups_outlined,
      commandHint: 'Ask about team or access…'),
  PlpResortSection(
      id: 'activity',
      label: 'Activity',
      icon: Icons.history_rounded,
      commandHint: 'Ask what changed recently…'),
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
    this.onOpenSection,
    this.onOpenModule,
    this.onOpenRecord,
    this.onCreateReservation,
    this.onOpenOperationsRoom,
    this.onOpenGuestExperience,
    this.onOpenTeam,
    this.onOpenActivity,
  });

  final PlpResortSection section;
  final Map<String, Object?> bootstrap;
  final VoidCallback onOpenNavigation;
  final VoidCallback onRefresh;
  final ValueChanged<String>? onOpenSection;
  final ValueChanged<String>? onOpenModule;
  final void Function(String kind, Map<String, Object?> record)? onOpenRecord;
  final VoidCallback? onCreateReservation;
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
      _ => <Widget>[
          const _EmptyState('This resort workspace is not available.')
        ],
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
            padding: EdgeInsets.fromLTRB(
              18,
              12,
              18,
              48 + MediaQuery.viewPaddingOf(context).bottom,
            ),
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
              ),
              const SizedBox(height: 26),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  bool get _liveOperationalDataAvailable {
    final source = _map(bootstrap['sourceHealth']);
    final explicit = source['liveOperationalDataAvailable'];
    if (explicit is bool) return explicit;
    final sourceState =
        _text(source['state'], fallback: 'unknown').toLowerCase();
    return const {'healthy', 'current', 'live', 'ready'}.contains(sourceState);
  }

  List<Widget> _sourceUnavailable({
    required String eyebrow,
    required String title,
    required String detail,
    bool includeWorkspaceRail = false,
  }) {
    final sourceState = _text(
      _map(bootstrap['sourceHealth'])['state'],
      fallback: 'unknown',
    );
    return [
      _HeroLine(eyebrow: eyebrow, title: title),
      const SizedBox(height: 18),
      _SourceBand(
        state: sourceState,
        message: _clientSourceMessage(sourceState),
      ),
      const SizedBox(height: 16),
      _EmptyState(detail),
      if (includeWorkspaceRail) ...[
        const SizedBox(height: 28),
        const _SectionHeader('RESORT WORKSPACES'),
        const SizedBox(height: 10),
        _SectionLaunchRail(onOpen: onOpenSection),
      ],
    ];
  }

  List<Widget> _today() {
    if (!_liveOperationalDataAvailable) {
      return _sourceUnavailable(
        eyebrow: 'RESORT STATUS',
        title: 'Today',
        detail:
            'Live occupancy, arrivals, room availability, and sales are hidden '
            'until a verified resort source is connected.',
        includeWorkspaceRail: true,
      );
    }

    final today = _map(bootstrap['today']);
    final guest = _map(bootstrap['guestExperience']);
    final command = _map(bootstrap['resortCommandCenter']);
    final pulse = _map(command['roomPulse']);
    final source = _map(bootstrap['sourceHealth']);
    final directSourceEmpty =
        _text(source['sourceProvider'], fallback: '').toLowerCase() ==
            'pandora_direct' &&
        _number(pulse['total'], fallback: _number(today['rooms_total'])) == 0;
    if (directSourceEmpty) {
      return [
        const _HeroLine(eyebrow: 'RESORT STATUS', title: 'Today'),
        const SizedBox(height: 18),
        _SourceBand(
          state: _text(source['state'], fallback: 'healthy'),
          message: _clientSourceMessage(
            _text(source['state'], fallback: 'healthy'),
          ),
        ),
        const SizedBox(height: 16),
        const _EmptyState(
          'Pandora Direct is connected and isolated to this resort. '
          'No customer room or reservation records have been entered yet, '
          'so Pandora will not invent occupancy, availability, or sales.',
        ),
        const SizedBox(height: 28),
        const _SectionHeader('RESORT WORKSPACES'),
        const SizedBox(height: 10),
        _SectionLaunchRail(onOpen: onOpenSection),
      ];
    }
    final operations = _map(command['operations']);
    final inHouse = _clientRecords(_maps(guest['inHouse']));
    final arrivals = _clientRecords(_maps(guest['arrivals']));
    final departing = _clientRecords(_maps(guest['departing']));
    final attention = _clientRecords(_maps(guest['attention']));
    final total =
        _number(pulse['total'], fallback: _number(today['rooms_total']));
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
      const _HeroLine(
        eyebrow: 'RESORT STATUS',
        title: 'Today',
      ),
      const SizedBox(height: 18),
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
          _Metric('Sales today', _peso(today['sales_today_php']), 'recorded'),
        ],
      ),
      const SizedBox(height: 24),
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
      const SizedBox(height: 24),
      _RoomPulse(
        total: total,
        occupied: occupied,
        available: available,
        arriving: _number(pulse['arriving'], fallback: arrivals.length),
        departing: _number(pulse['departing'], fallback: departing.length),
      ),
      const SizedBox(height: 26),
      _SectionHeader(
        'NEEDS ATTENTION',
        action: attention.isNotEmpty ? attention.length.toString() : null,
      ),
      const SizedBox(height: 8),
      if (attention.isEmpty && conflicts == 0)
        const _ClearState(
          'No guest or channel exception needs owner attention.',
        )
      else
        _AttentionList(
          items: attention,
          conflicts: conflicts,
          onOpenRecord: onOpenRecord,
        ),
      if (inHouse.isNotEmpty) ...[
        const SizedBox(height: 28),
        _SectionHeader('IN HOUSE', action: inHouse.length.toString()),
        const SizedBox(height: 10),
        _GuestStrip(items: inHouse),
      ],
      const SizedBox(height: 28),
      const _SectionHeader('RESORT WORKSPACES'),
      const SizedBox(height: 10),
      _SectionLaunchRail(onOpen: onOpenSection),
    ];
  }

  List<Widget> _stays() {
    if (!_liveOperationalDataAvailable) {
      return _sourceUnavailable(
        eyebrow: 'RESERVATIONS & STAYS',
        title: 'Stays',
        detail:
            'Live arrivals, departures, in-house guests, and stays are unavailable until a verified resort source is connected.',
      );
    }
    final guest = _map(bootstrap['guestExperience']);
    final command = _map(bootstrap['resortCommandCenter']);
    final stays = _clientRecords(_maps(command['stays']));
    final arrivals = _clientRecords(_maps(guest['arrivals']));
    final inHouse = _clientRecords(_maps(guest['inHouse']));
    final departing = _clientRecords(_maps(guest['departing']));
    return [
      const _HeroLine(
        eyebrow: 'RESERVATIONS & STAYS',
        title: 'Stays',
      ),
      const SizedBox(height: 18),
      _MetricRail(
        items: [
          _Metric('Arriving', arrivals.length.toString(), 'today'),
          _Metric('In house', inHouse.length.toString(), 'current'),
          _Metric('Departing', departing.length.toString(), 'today'),
          _Metric('Visible stays', stays.length.toString(), 'next 30 days'),
        ],
      ),
      if (onCreateReservation != null) ...[
        const SizedBox(height: 22),
        _ActionBar(
          label: 'New reservation',
          icon: Icons.add_circle_outline_rounded,
          onTap: onCreateReservation!,
        ),
      ],
      const SizedBox(height: 24),
      _SectionHeader(
        'UPCOMING & ACTIVE',
        action: stays.isNotEmpty ? stays.length.toString() : null,
      ),
      const SizedBox(height: 8),
      if (stays.isEmpty)
        const _EmptyState('No stay records are available.')
      else
        _StayList(
          items: stays,
          onOpen: (stay) => onOpenRecord?.call('stay', stay),
        ),
    ];
  }

  List<Widget> _rooms() {
    if (!_liveOperationalDataAvailable) {
      return _sourceUnavailable(
        eyebrow: 'PROPERTY OPERATIONS',
        title: 'Rooms & housekeeping',
        detail:
            'Live room occupancy and availability are unavailable until a verified resort source is connected.',
      );
    }
    final command = _map(bootstrap['resortCommandCenter']);
    final pulse = _map(command['roomPulse']);
    final rooms = _clientRecords(_maps(command['rooms']));
    final universal = _map(command['universalHospitality']);
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
        eyebrow: 'PROPERTY OPERATIONS',
        title: 'Rooms & housekeeping',
      ),
      const SizedBox(height: 18),
      _RoomPulse(
        total: total,
        occupied: occupied,
        available: available,
        arriving: _number(pulse['arriving']),
        departing: _number(pulse['departing']),
      ),
      const SizedBox(height: 24),
      _SectionHeader(
        'ROOM BOARD',
        action: rooms.isNotEmpty ? rooms.length.toString() : null,
      ),
      const SizedBox(height: 10),
      if (rooms.isEmpty)
        const _EmptyState(
          'Room-level status will appear when accommodation records are connected.',
        )
      else
        _RoomGrid(
          rooms: rooms,
          onOpen: (room) => onOpenRecord?.call('room', room),
        ),
      const SizedBox(height: 30),
      _CapabilityGrid(
        items: [
          _Capability(
            'Housekeeping',
            Icons.cleaning_services_outlined,
            () => onOpenModule?.call('housekeeping'),
            detail: _integer(_number(universal['housekeepingJobs'])) + ' jobs',
          ),
          _Capability(
            'Maintenance',
            Icons.build_outlined,
            () => onOpenModule?.call('maintenance'),
          ),
          _Capability(
            'Linen',
            Icons.local_laundry_service_outlined,
            () => onOpenModule?.call('linen'),
          ),
          _Capability(
            'Available',
            Icons.bed_outlined,
            null,
            detail: _integer(available) + ' rooms ready',
          ),
        ],
      ),
    ];
  }

  List<Widget> _guests() {
    if (!_liveOperationalDataAvailable) {
      return _sourceUnavailable(
        eyebrow: 'GUEST OPERATIONS',
        title: 'Guests',
        detail:
            'Live guest presence, arrivals, and requests are unavailable until a verified resort source is connected.',
      );
    }
    final guest = _map(bootstrap['guestExperience']);
    final command = _map(bootstrap['resortCommandCenter']);
    final inHouse = _clientRecords(_maps(guest['inHouse']));
    final arrivals = _clientRecords(_maps(guest['arrivals']));
    final requests = _clientRecords(_maps(command['experienceSignals']));
    return [
      const _HeroLine(
        eyebrow: 'GUEST OPERATIONS',
        title: 'Guests',
      ),
      const SizedBox(height: 18),
      _MetricRail(
        items: [
          _Metric('In house', inHouse.length.toString(), 'guests'),
          _Metric('Arriving', arrivals.length.toString(), 'today'),
          _Metric('Requests', requests.length.toString(), 'open signals'),
        ],
      ),
      if (inHouse.isNotEmpty) ...[
        const SizedBox(height: 24),
        _SectionHeader(
          'CURRENT GUESTS',
          action: inHouse.length.toString(),
        ),
        const SizedBox(height: 10),
        _GuestStrip(items: inHouse),
      ],
      if (arrivals.isNotEmpty) ...[
        const SizedBox(height: 24),
        _SectionHeader(
          'ARRIVING TODAY',
          action: arrivals.length.toString(),
        ),
        const SizedBox(height: 10),
        _GuestStrip(items: arrivals),
      ],
      const SizedBox(height: 24),
      _SectionHeader(
        'REQUESTS & PREFERENCES',
        action: requests.isNotEmpty ? requests.length.toString() : null,
      ),
      const SizedBox(height: 8),
      if (requests.isEmpty)
        const _ClearState('No special request is waiting.')
      else
        _RequestList(
          items: requests,
          onOpen: (request) => onOpenRecord?.call('request', request),
        ),
      const SizedBox(height: 30),
      _CapabilityGrid(
        items: [
          _Capability(
            'Concierge',
            Icons.support_agent_outlined,
            () => onOpenModule?.call('concierge'),
            detail: requests.length.toString() + ' guest signals',
          ),
          _Capability(
            'VIP',
            Icons.workspace_premium_outlined,
            () => onOpenModule?.call('vip'),
          ),
          _Capability(
            'Transfers',
            Icons.airport_shuttle_outlined,
            () => onOpenModule?.call('transfers'),
            detail: _experienceCount(requests, const [
                  'transfer',
                  'airport',
                  'transport',
                  'pickup',
                  'dropoff'
                ]).toString() +
                ' requests',
          ),
        ],
      ),
    ];
  }

  List<Widget> _operations() {
    final command = _map(bootstrap['resortCommandCenter']);
    final liveSource = _liveOperationalDataAvailable;
    final operations = _map(command['operations']);
    final guest = _map(bootstrap['guestExperience']);
    final attention = _clientRecords(_maps(guest['attention']));
    return [
      const _HeroLine(
        eyebrow: 'LIVE WORK',
        title: 'Operations',
      ),
      const SizedBox(height: 18),
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
            liveSource
                ? _integer(_number(operations['channelExceptions']))
                : '—',
            liveSource ? 'exceptions' : 'source unavailable',
          ),
        ],
      ),
      const SizedBox(height: 24),
      _SectionHeader(
        'ACTIVE WORK',
        action: attention.isNotEmpty ? attention.length.toString() : null,
      ),
      const SizedBox(height: 8),
      if (attention.isEmpty && !liveSource)
        const _EmptyState(
          'No manual work item is open. Channel exceptions cannot be verified '
          'until a live resort source is connected.',
        )
      else if (attention.isEmpty &&
          _number(operations['channelExceptions']) == 0)
        const _ClearState('No operational exception is waiting.')
      else
        _AttentionList(
          items: attention,
          conflicts: _number(operations['channelExceptions']),
          onOpenRecord: onOpenRecord,
        ),
      const SizedBox(height: 30),
      _CapabilityGrid(
        items: [
          _Capability(
            'Property',
            Icons.domain_outlined,
            () => onOpenModule?.call('property'),
          ),
          _Capability(
            'Security',
            Icons.shield_outlined,
            () => onOpenModule?.call('security'),
          ),
          _Capability(
            'Transport',
            Icons.directions_car_outlined,
            () => onOpenModule?.call('transport'),
          ),
        ],
      ),
      if (onOpenOperationsRoom != null) ...[
        const SizedBox(height: 22),
        _ActionBar(
          label: 'Open Operations Room',
          icon: Icons.hub_outlined,
          onTap: onOpenOperationsRoom!,
        ),
      ],
    ];
  }

  List<Widget> _revenue() {
    if (!_liveOperationalDataAvailable) {
      return _sourceUnavailable(
        eyebrow: 'COMMERCIAL',
        title: 'Revenue',
        detail:
            'Live sales, occupancy, channel, and booking-value metrics are unavailable until a verified resort source is connected.',
      );
    }
    final today = _map(bootstrap['today']);
    final command = _map(bootstrap['resortCommandCenter']);
    final finance = _map(command['finance']);
    final operations = _map(command['operations']);
    return [
      const _HeroLine(
        eyebrow: 'COMMERCIAL',
        title: 'Revenue',
      ),
      const SizedBox(height: 18),
      _MetricRail(
        items: [
          _Metric('Sales today', _peso(today['sales_today_php']), 'recorded'),
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
      const SizedBox(height: 24),
      const _SectionHeader('NEXT 30 DAYS'),
      const SizedBox(height: 10),
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
      const SizedBox(height: 24),
      _CapabilityGrid(
        items: [
          _Capability(
            'Rates',
            Icons.sell_outlined,
            () => onOpenModule?.call('rates'),
            detail: _integer(_number(today['rooms_available'])) +
                ' rooms available',
          ),
          _Capability(
            'Channels',
            Icons.travel_explore_outlined,
            () => onOpenModule?.call('channels'),
            detail: _integer(_number(operations['channelExceptions'])) +
                ' exceptions',
          ),
          _Capability(
            'Forecast',
            Icons.query_stats_outlined,
            () => onOpenModule?.call('forecast'),
            detail: _peso(finance['bookedValue30dPhp']) + ' booked',
          ),
        ],
      ),
    ];
  }

  List<Widget> _experiences() {
    if (!_liveOperationalDataAvailable) {
      return [
        ..._sourceUnavailable(
          eyebrow: 'SERVICE DELIVERY',
          title: 'Guest experiences',
          detail: 'Live guest requests and preferences are unavailable until a '
              'verified resort source is connected.',
        ),
        const SizedBox(height: 24),
        _CapabilityGrid(
          items: [
            _Capability('Concierge', Icons.support_agent_outlined,
                () => onOpenModule?.call('concierge')),
            _Capability('Transfers', Icons.airport_shuttle_outlined,
                () => onOpenModule?.call('transfers')),
            _Capability('Dining', Icons.restaurant_outlined,
                () => onOpenModule?.call('dining')),
            _Capability('Wellness', Icons.spa_outlined,
                () => onOpenModule?.call('wellness')),
            _Capability('Activities', Icons.explore_outlined,
                () => onOpenModule?.call('activities')),
            _Capability('Events', Icons.celebration_outlined,
                () => onOpenModule?.call('events')),
          ],
        ),
      ];
    }
    final requests = _clientRecords(
      _maps(_map(bootstrap['resortCommandCenter'])['experienceSignals']),
    );
    return [
      const _HeroLine(
        eyebrow: 'SERVICE DELIVERY',
        title: 'Guest experiences',
      ),
      const SizedBox(height: 18),
      _CapabilityGrid(
        items: [
          _Capability(
            'Concierge',
            Icons.support_agent_outlined,
            () => onOpenModule?.call('concierge'),
          ),
          _Capability(
            'Transfers',
            Icons.airport_shuttle_outlined,
            () => onOpenModule?.call('transfers'),
          ),
          _Capability(
            'Dining',
            Icons.restaurant_outlined,
            () => onOpenModule?.call('dining'),
            detail: _experienceCount(requests, const [
                  'dining',
                  'food',
                  'restaurant',
                  'breakfast',
                  'dinner'
                ]).toString() +
                ' requests',
          ),
          _Capability(
            'Wellness',
            Icons.spa_outlined,
            () => onOpenModule?.call('wellness'),
            detail:
                _experienceCount(requests, const ['spa', 'massage', 'wellness'])
                        .toString() +
                    ' requests',
          ),
          _Capability(
            'Activities',
            Icons.explore_outlined,
            () => onOpenModule?.call('activities'),
            detail: _experienceCount(requests, const [
                  'activity',
                  'tour',
                  'island',
                  'excursion'
                ]).toString() +
                ' requests',
          ),
          _Capability(
            'Events',
            Icons.celebration_outlined,
            () => onOpenModule?.call('events'),
            detail: _experienceCount(requests, const [
                  'event',
                  'birthday',
                  'anniversary',
                  'wedding',
                  'celebration'
                ]).toString() +
                ' requests',
          ),
        ],
      ),
      const SizedBox(height: 24),
      _SectionHeader(
        'GUEST REQUESTS',
        action: requests.isNotEmpty ? requests.length.toString() : null,
      ),
      const SizedBox(height: 8),
      if (requests.isEmpty)
        const _ClearState('No experience request is waiting.')
      else
        _RequestList(
          items: requests,
          onOpen: (request) => onOpenRecord?.call('request', request),
        ),
    ];
  }

  List<Widget> _team() {
    final team = _map(bootstrap['teamAccess']);
    final members = _clientRecords(_maps(team['members']));
    final activity = _clientRecords(_maps(team['recentActivity']));
    final active = members.where((item) => _truthy(item['active'])).length;
    final administrators = members
        .where(
          (item) => const {'owner', 'admin'}
              .contains(_text(item['accessRole'], fallback: '').toLowerCase()),
        )
        .length;
    return [
      const _HeroLine(
        eyebrow: 'PEOPLE & PERMISSIONS',
        title: 'Team & access',
      ),
      const SizedBox(height: 18),
      _MetricRail(
        items: [
          _Metric('Active', active.toString(), 'people'),
          _Metric('Members', members.length.toString(), 'visible'),
          _Metric('Admins', administrators.toString(), 'owner / admin'),
        ],
      ),
      const SizedBox(height: 24),
      _SectionHeader('TEAM MEMBERS', action: members.length.toString()),
      const SizedBox(height: 8),
      if (members.isEmpty)
        const _EmptyState('No team member is available.')
      else
        _MemberStrip(items: members),
      if (activity.isNotEmpty) ...[
        const SizedBox(height: 24),
        const _SectionHeader('RECENT TEAM ACTIVITY'),
        const SizedBox(height: 8),
        _ActivityList(items: activity),
      ],
      if (onOpenTeam != null) ...[
        const SizedBox(height: 22),
        _ActionBar(
          label: 'Manage team & access',
          icon: Icons.admin_panel_settings_outlined,
          onTap: onOpenTeam!,
        ),
      ],
    ];
  }

  List<Widget> _activity() {
    final source = _map(bootstrap['sourceHealth']);
    final team = _map(bootstrap['teamAccess']);
    final teamActivity = _clientRecords(_maps(team['recentActivity']));
    final auditItems = _maps(_map(bootstrap['resortAudit'])['items'])
        .map(
          (item) => <String, Object?>{
            'title': _humanStatus(item['action']),
            'actor': _humanStatus(item['actorRole']),
            'status': _truthy(item['providerReadbackVerified'])
                ? 'verified'
                : 'unverified',
            'category': item['entityKind'],
            'updatedAt': item['createdAt'],
          },
        )
        .toList(growable: false);
    final sourceState = _text(source['state'], fallback: 'unknown');
    return [
      const _HeroLine(
        eyebrow: 'VERIFIED HISTORY',
        title: 'Activity & audit',
      ),
      const SizedBox(height: 18),
      _SourceBand(
        state: sourceState,
        message: _clientSourceMessage(sourceState),
      ),
      const SizedBox(height: 24),
      _SectionHeader(
        'RESORT CHANGES',
        action: auditItems.isNotEmpty ? auditItems.length.toString() : null,
      ),
      const SizedBox(height: 8),
      if (auditItems.isEmpty)
        const _EmptyState('No verified resort change has been recorded yet.')
      else
        _ActivityList(items: auditItems),
      const SizedBox(height: 24),
      _SectionHeader(
        'TEAM ACTIVITY',
        action: teamActivity.isNotEmpty ? teamActivity.length.toString() : null,
      ),
      const SizedBox(height: 8),
      if (teamActivity.isEmpty)
        const _EmptyState('No recent team activity is available.')
      else
        _ActivityList(items: teamActivity),
      if (onOpenActivity != null) ...[
        const SizedBox(height: 22),
        _ActionBar(
          label: 'Open verified activity feed',
          icon: Icons.fact_check_outlined,
          onTap: onOpenActivity!,
        ),
      ],
    ];
  }}

class _ResortHeader extends StatelessWidget {
  const _ResortHeader({
    required this.section,
    required this.propertyName,
    required this.sourceState,
  });

  final PlpResortSection section;
  final String propertyName;
  final String sourceState;

  @override
  Widget build(BuildContext context) {
    final healthy = sourceState.toLowerCase() == 'healthy';
    return Row(
      children: [
        const SizedBox(width: 56),
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
          const SizedBox(height: 8),
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
                    fontSize: 30,
                    height: 1.02,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -.8,
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
    final ratio =
        total <= 0 ? 0.0 : (occupied / total).clamp(0.0, 1.0).toDouble();
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
    this.onOpenRecord,
  });

  final List<Map<String, Object?>> items;
  final num conflicts;
  final void Function(String kind, Map<String, Object?> record)? onOpenRecord;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final item in items.take(6)) {
      rows.add(
        _CompactRow(
          title: _text(item['title'], fallback: 'Open resort task'),
          meta: <String>[
            _humanStatus(item['priority']),
            _text(item['fullName'], fallback: ''),
            _humanStatus(item['status']),
          ].where((value) => value.isNotEmpty).join(' · '),
          tone: _text(item['priority']).toLowerCase() == 'high'
              ? PlpResortWorkspaceScreen.warn
              : PlpResortWorkspaceScreen.accent,
          onTap: () => onOpenRecord?.call('work', item),
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
          onTap: () => onOpenRecord?.call(
            'conflict-summary',
            <String, Object?>{
              'title': 'OTA channel exceptions',
              'count': conflicts,
              'status': 'open',
            },
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _CompactRow extends StatelessWidget {
  const _CompactRow({
    super.key,
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
  const _GuestStrip({required this.items});
  final List<Map<String, Object?>> items;

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
                onTap: () => _showDetailSheet(
                  context,
                  title: name,
                  fields: [
                    _DetailField(
                      'Room',
                      _text(item['accommodationName'], fallback: ''),
                    ),
                    _DetailField(
                      'Status',
                      _text(
                        item['displayStatus'],
                        fallback: _humanStatus(item['status']),
                      ),
                    ),
                    _DetailField(
                        'Check-in', _text(item['checkIn'], fallback: '')),
                    _DetailField(
                        'Check-out', _text(item['checkOut'], fallback: '')),
                    _DetailField(
                      'Guests',
                      _text(item['guestCount'], fallback: ''),
                    ),
                    _DetailField(
                      'Booking',
                      _text(item['bookingReference'], fallback: ''),
                    ),
                    _DetailField(
                      'Special request',
                      _text(item['specialRequest'], fallback: ''),
                    ),
                  ],
                ),
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
  const _StayList({required this.items, required this.onOpen});
  final List<Map<String, Object?>> items;
  final ValueChanged<Map<String, Object?>> onOpen;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final item in items.take(16))
            _CompactRow(
              key: ValueKey<String>(
                'plp-stay-' + _recordControlId(item),
              ),
              title: _text(item['fullName'], fallback: 'Guest stay'),
              meta: _text(item['accommodationName'], fallback: 'Room') +
                  ' · ' +
                  _text(item['checkIn']) +
                  ' → ' +
                  _text(item['checkOut']) +
                  ' · ' +
                  _humanStatus(item['paymentStatus']),
              tone: _text(item['status']).toLowerCase().contains('cancel')
                  ? PlpResortWorkspaceScreen.warn
                  : PlpResortWorkspaceScreen.good,
              onTap: () => onOpen(item),
            ),
        ],
      );
}

class _RoomGrid extends StatelessWidget {
  const _RoomGrid({required this.rooms, required this.onOpen});
  final List<Map<String, Object?>> rooms;
  final ValueChanged<Map<String, Object?>> onOpen;

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
                      key: ValueKey<String>(
                        'plp-room-' + _recordControlId(room),
                      ),
                      onTap: () => onOpen(room),
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
                              _humanStatus(room['state']).toUpperCase(),
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
  const _RequestList({required this.items, required this.onOpen});
  final List<Map<String, Object?>> items;
  final ValueChanged<Map<String, Object?>> onOpen;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final item in items.take(12))
            _CompactRow(
              key: ValueKey<String>(
                'plp-request-' + _recordControlId(item),
              ),
              title: _text(item['fullName'], fallback: 'Guest request'),
              meta: _text(
                item['request'],
                fallback: 'Guest request',
              ),
              onTap: () => onOpen(item),
            ),
        ],
      );
}

class _Capability {
  const _Capability(
    this.label,
    this.icon,
    this.onTap, {
    this.detail,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final String? detail;
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
                      key: ValueKey<String>(
                        'plp-capability-' + _capabilityControlId(item.label),
                      ),
                      onTap: item.onTap,
                      child: Container(
                        height: 88,
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
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: PlpResortWorkspaceScreen.ink,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (item.detail != null &&
                                      item.detail!.trim().isNotEmpty) ...[
                                    const SizedBox(height: 5),
                                    Text(
                                      item.detail!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: PlpResortWorkspaceScreen.muted,
                                        fontSize: 9.5,
                                        height: 1.25,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (item.onTap != null)
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
          for (final item in items.take(12))
            _CompactRow(
              title: _text(
                item['displayName'],
                fallback: 'PLP team member',
              ),
              meta: _text(item['roleLabel'], fallback: 'Member') +
                  ' · ' +
                  (_truthy(item['active'])
                      ? 'Active'
                      : _humanStatus(item['accessStatus'])),
              tone: _truthy(item['active'])
                  ? PlpResortWorkspaceScreen.good
                  : PlpResortWorkspaceScreen.muted,
              onTap: () => _showDetailSheet(
                context,
                title: _text(item['displayName'], fallback: 'Team member'),
                fields: [
                  _DetailField(
                      'Role', _text(item['roleLabel'], fallback: 'Member')),
                  _DetailField(
                    'Access',
                    _truthy(item['active'])
                        ? 'Active'
                        : _humanStatus(item['accessStatus']),
                  ),
                  _DetailField(
                    'Current user',
                    _truthy(item['isCurrentUser']) ? 'Yes' : 'No',
                  ),
                ],
              ),
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
          for (final item in items.take(12))
            _CompactRow(
              title: _text(item['title'], fallback: 'Resort activity'),
              meta: <String>[
                _clientActor(item['actor']),
                _humanStatus(item['status']),
                _friendlyTimestamp(item['updatedAt']),
              ].where((value) => value.isNotEmpty).join(' · '),
              onTap: () => _showDetailSheet(
                context,
                title: _text(item['title'], fallback: 'Resort activity'),
                fields: [
                  _DetailField('Status', _humanStatus(item['status'])),
                  _DetailField('Category', _humanStatus(item['category'])),
                  _DetailField('Actor', _clientActor(item['actor'])),
                  _DetailField(
                      'Updated', _friendlyTimestamp(item['updatedAt'])),
                ],
              ),
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
    final normalized = state.toLowerCase();
    final healthy =
        const {'healthy', 'current', 'live', 'ready'}.contains(normalized);
    final label = healthy
        ? 'Connected'
        : normalized == 'cached_offline'
            ? 'Offline snapshot'
            : 'Needs attention';
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
                  label.toUpperCase(),
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

class _DetailField {
  const _DetailField(this.label, this.value);
  final String label;
  final String value;
}

void _showDetailSheet(
  BuildContext context, {
  required String title,
  required List<_DetailField> fields,
}) {
  final visible = fields
      .where((field) => field.value.trim().isNotEmpty && field.value != '—')
      .toList(growable: false);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: PlpResortWorkspaceScreen.paper,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .72,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 3,
                margin: const EdgeInsets.only(bottom: 18),
                color: PlpResortWorkspaceScreen.line,
              ),
              Text(
                title,
                style: const TextStyle(
                  color: PlpResortWorkspaceScreen.ink,
                  fontFamily: 'serif',
                  fontSize: 27,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 18),
              for (final field in visible)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: PlpResortWorkspaceScreen.line,
                      ),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 102,
                        child: Text(
                          field.label.toUpperCase(),
                          style: const TextStyle(
                            color: PlpResortWorkspaceScreen.accent,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          field.value,
                          style: const TextStyle(
                            color: PlpResortWorkspaceScreen.ink,
                            fontSize: 12.5,
                            height: 1.35,
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
    ),
  );
}

bool _truthy(Object? value) {
  if (value is bool) return value;
  return const {'true', '1', 'yes'}
      .contains(value?.toString().trim().toLowerCase());
}

bool _isInternalRecord(Map<String, Object?> item) {
  if (_truthy(item['isMock'])) return true;
  final identities = <Object?>[
    item['displayName'],
    item['fullName'],
    item['actor'],
    item['source'],
  ].whereType<Object>().map(
        (value) => value.toString().trim().toLowerCase(),
      );
  return identities.any(
    (identity) => const {
      'mcpmaster',
      'mcpmaster staging owner',
      'staging owner',
      'alfred qa',
      'fixture',
    }.contains(identity),
  );
}

List<Map<String, Object?>> _clientRecords(
  List<Map<String, Object?>> items,
) =>
    items.where((item) => !_isInternalRecord(item)).toList(growable: false);

String _recordControlId(Map<String, Object?> record) {
  for (final key in const [
    'id',
    'bookingReference',
    'name',
    'fullName',
  ]) {
    final value = record[key]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value.toLowerCase().replaceAll(' ', '-');
    }
  }
  return 'record';
}

String _capabilityControlId(String label) =>
    label.trim().toLowerCase().replaceAll(' ', '-');

String _humanStatus(Object? value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return '';
  final normalized =
      raw.toLowerCase().replaceAll('-', '_').replaceAll(RegExp(r'\s+'), '_');
  const labels = <String, String>{
    'in_progress': 'In progress',
    'not_started': 'Not started',
    'waiting_review': 'Waiting review',
    'waiting_approval': 'Waiting approval',
    'checked_in': 'Checked in',
    'checked_out': 'Checked out',
    'partially_paid': 'Partially paid',
  };
  final mapped = labels[normalized];
  if (mapped != null) return mapped;
  return normalized
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}

String _clientActor(Object? value) {
  final actor = _text(value, fallback: '');
  final lower = actor.trim().toLowerCase();
  if (const {
    'qa',
    'mcpmaster',
    'mcpmaster staging owner',
    'staging',
    'staging owner',
    'alfred qa',
    'fixture',
  }.contains(lower)) {
    return 'Pandora';
  }
  return actor;
}

String _clientSourceMessage(String state) {
  final normalized = state.toLowerCase();
  if (const {'healthy', 'current', 'live', 'ready'}.contains(normalized)) {
    return 'Resort data is current.';
  }
  if (normalized == 'cached_offline') {
    return 'Showing the last verified resort snapshot while live data is unavailable.';
  }
  if (normalized == 'not_connected') {
    return 'Live resort data is not connected yet.';
  }
  return 'Some resort data may be delayed. Verified records remain available where possible.';
}

String _friendlyTimestamp(Object? value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return '';
  final parsed = DateTime.tryParse(raw)?.toLocal();
  if (parsed == null) return raw;
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final minute = parsed.minute.toString().padLeft(2, '0');
  return '${months[parsed.month - 1]} ${parsed.day} · '
      '${parsed.hour.toString().padLeft(2, '0')}:$minute';
}

int _experienceCount(
  List<Map<String, Object?>> items,
  List<String> keywords,
) {
  var count = 0;
  for (final item in items) {
    final request = _text(item['request'], fallback: '').toLowerCase();
    if (keywords.any(request.contains)) count += 1;
  }
  return count;
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
  return normalized == null || normalized.isEmpty ? fallback : normalized;
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
