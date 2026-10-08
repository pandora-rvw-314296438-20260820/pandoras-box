import 'package:flutter/material.dart';

import 'plp_activity_read_model.dart';

class PlpResortSection {
  const PlpResortSection({
    required this.id,
    required this.label,
    required this.headerTitle,
    required this.icon,
    required this.commandHint,
  });

  final String id;
  final String label;
  final String headerTitle;
  final IconData icon;
  final String commandHint;
}

const plpResortSections = <PlpResortSection>[
  PlpResortSection(
      id: 'today',
      label: 'Today',
      headerTitle: 'RESORT STATUS',
      icon: Icons.wb_sunny_outlined,
      commandHint: 'Ask what matters today…'),
  PlpResortSection(
      id: 'stays',
      label: 'Stays',
      headerTitle: 'STAYS',
      icon: Icons.event_available_outlined,
      commandHint: 'Ask about a stay or arrival…'),
  PlpResortSection(
      id: 'rooms',
      label: 'Rooms',
      headerTitle: 'ROOMS & HOUSEKEEPING',
      icon: Icons.bed_outlined,
      commandHint: 'Ask about rooms or housekeeping…'),
  PlpResortSection(
      id: 'guests',
      label: 'Guests',
      headerTitle: 'GUESTS',
      icon: Icons.person_outline_rounded,
      commandHint: 'Ask about a guest or request…'),
  PlpResortSection(
      id: 'operations',
      label: 'Operations',
      headerTitle: 'OPERATIONS',
      icon: Icons.hub_outlined,
      commandHint: 'Ask about resort operations…'),
  PlpResortSection(
      id: 'revenue',
      label: 'Revenue',
      headerTitle: 'REVENUE',
      icon: Icons.insights_outlined,
      commandHint: 'Ask about revenue or availability…'),
  PlpResortSection(
      id: 'experiences',
      label: 'Experiences',
      headerTitle: 'EXPERIENCES',
      icon: Icons.spa_outlined,
      commandHint: 'Ask about concierge or experiences…'),
  PlpResortSection(
      id: 'team',
      label: 'Team',
      headerTitle: 'TEAM & ACCESS',
      icon: Icons.groups_outlined,
      commandHint: 'Ask about team or access…'),
  PlpResortSection(
      id: 'activity',
      label: 'Activity',
      headerTitle: 'ACTIVITY & AUDIT',
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
    this.onOpenSourceSettings,
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
  final VoidCallback? onOpenSourceSettings;

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
          const PlpNoticeBox('This resort workspace is not available.')
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
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Align(
                  alignment: Alignment.topLeft,
                  heightFactor: 1,
                  child: _ResortHeader(section: section),
                ),
              ),
              const SizedBox(height: 12),
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

  bool get _cachedOperationalSnapshot =>
      bootstrap['offlineBootstrap'] == true &&
      bootstrap['cachedOperationalDataAvailable'] == true;

  bool get _operationalSnapshotAvailable =>
      bootstrap['offlineBootstrap'] == true
          ? _cachedOperationalSnapshot
          : _liveOperationalDataAvailable;

  List<Widget> _sourceContextPrelude() {
    if (!_cachedOperationalSnapshot) return const <Widget>[];
    return const <Widget>[
      _SourceBand(
        state: 'cached_offline',
        message:
            'Showing the last verified resort snapshot. Live changes are unavailable until the resort source reconnects.',
      ),
      SizedBox(height: 14),
    ];
  }

  List<Widget> _sourceAvailableActions() {
    switch (section.id) {
      case 'stays':
        if (onCreateReservation == null) return const <Widget>[];
        return <Widget>[
          _ActionBar(
            label: 'New reservation',
            icon: Icons.add_circle_outline_rounded,
            onTap: onCreateReservation!,
          ),
        ];
      case 'rooms':
        return <Widget>[
          PlpCapabilityGrid(items: <PlpCapability>[
            PlpCapability(
              'Housekeeping',
              Icons.cleaning_services_outlined,
              onOpenModule == null
                  ? null
                  : () => onOpenModule!.call('housekeeping'),
            ),
            PlpCapability(
              'Maintenance',
              Icons.build_outlined,
              onOpenModule == null
                  ? null
                  : () => onOpenModule!.call('maintenance'),
            ),
            PlpCapability(
              'Linen',
              Icons.local_laundry_service_outlined,
              onOpenModule == null ? null : () => onOpenModule!.call('linen'),
            ),
          ]),
        ];
      case 'guests':
        return <Widget>[
          PlpCapabilityGrid(items: <PlpCapability>[
            PlpCapability(
              'Concierge',
              Icons.support_agent_outlined,
              onOpenModule == null
                  ? null
                  : () => onOpenModule!.call('concierge'),
            ),
            PlpCapability(
              'Transfers',
              Icons.airport_shuttle_outlined,
              onOpenModule == null
                  ? null
                  : () => onOpenModule!.call('transfers'),
            ),
          ]),
        ];
      case 'revenue':
        return <Widget>[
          PlpCapabilityGrid(items: <PlpCapability>[
            PlpCapability(
              'Rates',
              Icons.sell_outlined,
              onOpenModule == null ? null : () => onOpenModule!.call('rates'),
            ),
            PlpCapability(
              'Channels',
              Icons.hub_outlined,
              onOpenModule == null
                  ? null
                  : () => onOpenModule!.call('channels'),
            ),
            PlpCapability(
              'Forecast',
              Icons.timeline_outlined,
              onOpenModule == null
                  ? null
                  : () => onOpenModule!.call('forecast'),
            ),
          ]),
        ];
      case 'experiences':
        return <Widget>[
          PlpCapabilityGrid(items: <PlpCapability>[
            PlpCapability(
              'Concierge',
              Icons.support_agent_outlined,
              onOpenModule == null
                  ? null
                  : () => onOpenModule!.call('concierge'),
            ),
            PlpCapability(
              'Dining',
              Icons.restaurant_outlined,
              onOpenModule == null ? null : () => onOpenModule!.call('dining'),
            ),
            PlpCapability(
              'Wellness',
              Icons.spa_outlined,
              onOpenModule == null
                  ? null
                  : () => onOpenModule!.call('wellness'),
            ),
          ]),
        ];
      default:
        return const <Widget>[];
    }
  }

  List<Widget> _sourceUnavailable({
    required String eyebrow,
    required String detail,
    bool includeWorkspaceRail = false,
  }) {
    final source = _map(bootstrap['sourceHealth']);
    final sourceState = _text(source['state'], fallback: 'unknown');
    final provider = _humanStatus(
      _text(source['sourceProvider'], fallback: 'Resort source'),
    );
    final availableActions = _sourceAvailableActions();
    return <Widget>[
      if (includeWorkspaceRail)
        _SourceRecoveryPanel(
          source: provider,
          state: sourceState,
          affectedArea: eyebrow,
          unavailable: detail,
          remainsAvailable:
              'Pandora, team access, manual resort work, and verified history remain available.',
          onRefresh: onRefresh,
          onOpenSettings: onOpenSourceSettings,
        )
      else
        PlpNoticeBox(detail),
      if (availableActions.isNotEmpty) ...[
        const SizedBox(height: 16),
        ...availableActions,
      ],
      if (includeWorkspaceRail) ...[
        const SizedBox(height: 20),
        const _SectionHeader('RESORT WORKSPACES'),
        const SizedBox(height: 10),
        _SectionLaunchRail(onOpen: onOpenSection),
      ],
    ];
  }

  List<Widget> _today() {
    if (!_operationalSnapshotAvailable) {
      return _sourceUnavailable(
        eyebrow: 'RESORT STATUS',
        detail:
            'Live occupancy, arrivals, room availability, and sales are unavailable until a verified resort source is connected.',
        includeWorkspaceRail: true,
      );
    }

    final today = _map(bootstrap['today']);
    final guest = _map(bootstrap['guestExperience']);
    final command = _map(bootstrap['resortCommandCenter']);
    final pulse = _map(command['roomPulse']);
    final source = _map(bootstrap['sourceHealth']);
    final directSourceEmpty = _text(source['sourceProvider'], fallback: '')
                .toLowerCase() ==
            'pandora_direct' &&
        _number(pulse['total'], fallback: _number(today['rooms_total'])) == 0;
    if (directSourceEmpty) {
      return <Widget>[
        _SourceRecoveryPanel(
          source: 'Pandora Direct',
          state: _text(source['state'], fallback: 'connected'),
          affectedArea: 'RESORT STATUS',
          unavailable:
              'No customer room or reservation records have been entered yet, so occupancy, availability, arrivals, and sales cannot be shown.',
          remainsAvailable:
              'Pandora, team access, manual resort work, and setup actions remain available.',
          onRefresh: onRefresh,
          onOpenSettings: onOpenSourceSettings,
        ),
        const SizedBox(height: 20),
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

    return <Widget>[
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
      const SizedBox(height: 18),
      ..._sourceContextPrelude(),
      _MetricRail(
        items: <_Metric>[
          _Metric(
            'Occupancy',
            _text(today['occupancy_percent'], fallback: '—') + '%',
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
      const SizedBox(height: 18),
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
      const SizedBox(height: 18),
      _RoomPulse(
        total: total,
        occupied: occupied,
        available: available,
        arriving: _number(pulse['arriving'], fallback: arrivals.length),
        departing: _number(pulse['departing'], fallback: departing.length),
      ),
      if (inHouse.isNotEmpty) ...[
        const SizedBox(height: 20),
        _SectionHeader('IN HOUSE', action: inHouse.length.toString()),
        const SizedBox(height: 10),
        _GuestStrip(items: inHouse),
      ],
      const SizedBox(height: 20),
      const _SectionHeader('RESORT WORKSPACES'),
      const SizedBox(height: 10),
      _SectionLaunchRail(onOpen: onOpenSection),
    ];
  }

  List<Widget> _stays() {
    if (!_operationalSnapshotAvailable) {
      return _sourceUnavailable(
        eyebrow: 'RESERVATIONS & STAYS',
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
      ..._sourceContextPrelude(),
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
      const SizedBox(height: 18),
      _SectionHeader(
        'UPCOMING & ACTIVE',
        action: stays.isNotEmpty ? stays.length.toString() : null,
      ),
      const SizedBox(height: 8),
      if (stays.isEmpty)
        const PlpNoticeBox('No stay records are available.')
      else
        _StayList(
          items: stays,
          onOpen: (stay) => onOpenRecord?.call('stay', stay),
        ),
    ];
  }

  List<Widget> _rooms() {
    if (!_operationalSnapshotAvailable) {
      return _sourceUnavailable(
        eyebrow: 'PROPERTY OPERATIONS',
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
      ..._sourceContextPrelude(),
      _RoomPulse(
        total: total,
        occupied: occupied,
        available: available,
        arriving: _number(pulse['arriving']),
        departing: _number(pulse['departing']),
      ),
      const SizedBox(height: 18),
      _SectionHeader(
        'ROOM BOARD',
        action: rooms.isNotEmpty ? rooms.length.toString() : null,
      ),
      const SizedBox(height: 10),
      if (rooms.isEmpty)
        const PlpNoticeBox(
          'Room-level status will appear when accommodation records are connected.',
        )
      else
        _RoomGrid(
          rooms: rooms,
          onOpen: (room) => onOpenRecord?.call('room', room),
        ),
      const SizedBox(height: 22),
      PlpCapabilityGrid(
        items: [
          PlpCapability(
            'Housekeeping',
            Icons.cleaning_services_outlined,
            () => onOpenModule?.call('housekeeping'),
            detail: _integer(_number(universal['housekeepingJobs'])) + ' jobs',
          ),
          PlpCapability(
            'Maintenance',
            Icons.build_outlined,
            () => onOpenModule?.call('maintenance'),
          ),
          PlpCapability(
            'Linen',
            Icons.local_laundry_service_outlined,
            () => onOpenModule?.call('linen'),
          ),
          PlpCapability(
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
    if (!_operationalSnapshotAvailable) {
      return _sourceUnavailable(
        eyebrow: 'GUEST OPERATIONS',
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
      ..._sourceContextPrelude(),
      _MetricRail(
        items: [
          _Metric('In house', inHouse.length.toString(), 'guests'),
          _Metric('Arriving', arrivals.length.toString(), 'today'),
          _Metric('Requests', requests.length.toString(), 'open signals'),
        ],
      ),
      if (inHouse.isNotEmpty) ...[
        const SizedBox(height: 18),
        _SectionHeader(
          'CURRENT GUESTS',
          action: inHouse.length.toString(),
        ),
        const SizedBox(height: 10),
        _GuestStrip(items: inHouse),
      ],
      if (arrivals.isNotEmpty) ...[
        const SizedBox(height: 18),
        _SectionHeader(
          'ARRIVING TODAY',
          action: arrivals.length.toString(),
        ),
        const SizedBox(height: 10),
        _GuestStrip(items: arrivals),
      ],
      const SizedBox(height: 18),
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
      const SizedBox(height: 22),
      PlpCapabilityGrid(
        items: [
          PlpCapability(
            'Concierge',
            Icons.support_agent_outlined,
            () => onOpenModule?.call('concierge'),
            detail: requests.length.toString() + ' guest signals',
          ),
          PlpCapability(
            'VIP',
            Icons.workspace_premium_outlined,
            () => onOpenModule?.call('vip'),
          ),
          PlpCapability(
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
      const SizedBox(height: 18),
      _SectionHeader(
        'ACTIVE WORK',
        action: attention.isNotEmpty ? attention.length.toString() : null,
      ),
      const SizedBox(height: 8),
      if (attention.isEmpty && !liveSource)
        const PlpNoticeBox(
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
      const SizedBox(height: 22),
      PlpCapabilityGrid(
        items: [
          PlpCapability(
            'Property',
            Icons.domain_outlined,
            () => onOpenModule?.call('property'),
          ),
          PlpCapability(
            'Security',
            Icons.shield_outlined,
            () => onOpenModule?.call('security'),
          ),
          PlpCapability(
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
    if (!_operationalSnapshotAvailable) {
      return _sourceUnavailable(
        eyebrow: 'COMMERCIAL',
        detail:
            'Live sales, occupancy, channel, and booking-value metrics are unavailable until a verified resort source is connected.',
      );
    }
    final today = _map(bootstrap['today']);
    final command = _map(bootstrap['resortCommandCenter']);
    final finance = _map(command['finance']);
    final operations = _map(command['operations']);
    return [
      ..._sourceContextPrelude(),
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
      const SizedBox(height: 18),
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
      const SizedBox(height: 18),
      PlpCapabilityGrid(
        items: [
          PlpCapability(
            'Rates',
            Icons.sell_outlined,
            () => onOpenModule?.call('rates'),
            detail: _integer(_number(today['rooms_available'])) +
                ' rooms available',
          ),
          PlpCapability(
            'Channels',
            Icons.travel_explore_outlined,
            () => onOpenModule?.call('channels'),
            detail: _integer(_number(operations['channelExceptions'])) +
                ' exceptions',
          ),
          PlpCapability(
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
    if (!_operationalSnapshotAvailable) {
      return [
        ..._sourceUnavailable(
          eyebrow: 'SERVICE DELIVERY',
          detail: 'Live guest requests and preferences are unavailable until a '
              'verified resort source is connected.',
        ),
        const SizedBox(height: 18),
        PlpCapabilityGrid(
          items: [
            PlpCapability('Concierge', Icons.support_agent_outlined,
                () => onOpenModule?.call('concierge')),
            PlpCapability('Transfers', Icons.airport_shuttle_outlined,
                () => onOpenModule?.call('transfers')),
            PlpCapability('Dining', Icons.restaurant_outlined,
                () => onOpenModule?.call('dining')),
            PlpCapability('Wellness', Icons.spa_outlined,
                () => onOpenModule?.call('wellness')),
            PlpCapability('Activities', Icons.explore_outlined,
                () => onOpenModule?.call('activities')),
            PlpCapability('Events', Icons.celebration_outlined,
                () => onOpenModule?.call('events')),
          ],
        ),
      ];
    }
    final requests = _clientRecords(
      _maps(_map(bootstrap['resortCommandCenter'])['experienceSignals']),
    );
    return [
      ..._sourceContextPrelude(),
      PlpCapabilityGrid(
        items: [
          PlpCapability(
            'Concierge',
            Icons.support_agent_outlined,
            () => onOpenModule?.call('concierge'),
          ),
          PlpCapability(
            'Transfers',
            Icons.airport_shuttle_outlined,
            () => onOpenModule?.call('transfers'),
          ),
          PlpCapability(
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
          PlpCapability(
            'Wellness',
            Icons.spa_outlined,
            () => onOpenModule?.call('wellness'),
            detail:
                _experienceCount(requests, const ['spa', 'massage', 'wellness'])
                        .toString() +
                    ' requests',
          ),
          PlpCapability(
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
          PlpCapability(
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
      const SizedBox(height: 18),
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
      _MetricRail(
        items: [
          _Metric('Active', active.toString(), 'people'),
          _Metric('Members', members.length.toString(), 'visible'),
          _Metric('Admins', administrators.toString(), 'owner / admin'),
        ],
      ),
      const SizedBox(height: 18),
      _SectionHeader('TEAM MEMBERS', action: members.length.toString()),
      const SizedBox(height: 8),
      if (members.isEmpty)
        const PlpNoticeBox('No team member is available.')
      else
        _MemberStrip(items: members),
      if (activity.isNotEmpty) ...[
        const SizedBox(height: 18),
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
    final rawActivity = bootstrap['verifiedActivity'];
    final loaded = rawActivity is Map;
    final verified = loaded
        ? plpProductionActivityRecords(_map(rawActivity)['items'])
        : const <Map<String, Object?>>[];
    final rows = verified
        .map(
          (item) => <String, Object?>{
            'title': item['title'],
            'actor': item['sourceLabel'],
            'status': 'verified',
            'category': item['category'],
            'updatedAt': item['occurredAt'],
          },
        )
        .toList(growable: false);

    return <Widget>[
      _SectionHeader(
        'VERIFIED ACTIVITY',
        action: rows.isNotEmpty ? rows.length.toString() : null,
      ),
      const SizedBox(height: 8),
      if (!loaded && bootstrap['verifiedActivityLoading'] == true)
        const PlpNoticeBox('Loading verified activity…')
      else if (!loaded)
        const PlpNoticeBox(
          'Verified resort activity is temporarily unavailable. Refresh or open the activity feed to try again.',
        )
      else if (rows.isEmpty)
        const PlpNoticeBox(
          'No verified production activity has been recorded yet.',
        )
      else
        _ActivityList(items: rows),
      if (onOpenActivity != null) ...[
        const SizedBox(height: 16),
        _ActionBar(
          label: 'Open verified activity feed',
          icon: Icons.fact_check_outlined,
          onTap: onOpenActivity!,
        ),
      ],
    ];
  }
}

class _ResortHeader extends StatelessWidget {
  const _ResortHeader({required this.section});

  final PlpResortSection section;

  @override
  Widget build(BuildContext context) => PlpPageTitle(section.headerTitle);
}

/// Serif, uppercase, tracked page title; leaves room for the shell's
/// floating menu button.
class PlpPageTitle extends StatelessWidget {
  const PlpPageTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const SizedBox(width: 56),
          Expanded(
            child: Text(
              title,
              key: const ValueKey<String>('plp-contextual-page-title'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: PlpResortWorkspaceScreen.ink,
                fontFamily: 'serif',
                fontSize: 16,
                fontWeight: FontWeight.w400,
                letterSpacing: 2.6,
              ),
            ),
          ),
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
        height: 92,
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
                      fontSize: 23,
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

class PlpCapability {
  const PlpCapability(
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

class PlpCapabilityGrid extends StatelessWidget {
  const PlpCapabilityGrid({super.key, required this.items});
  final List<PlpCapability> items;

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

class _SourceRecoveryPanel extends StatelessWidget {
  const _SourceRecoveryPanel({
    required this.source,
    required this.state,
    required this.affectedArea,
    required this.unavailable,
    required this.remainsAvailable,
    required this.onRefresh,
    this.onOpenSettings,
  });

  final String source;
  final String state;
  final String affectedArea;
  final String unavailable;
  final String remainsAvailable;
  final VoidCallback onRefresh;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey<String>('plp-source-recovery'),
        width: double.infinity,
        decoration: const BoxDecoration(
          color: PlpResortWorkspaceScreen.paper,
          border: Border.fromBorderSide(
            BorderSide(color: PlpResortWorkspaceScreen.line),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 16,
                  color: PlpResortWorkspaceScreen.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    source + ' · ' + _humanStatus(state),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PlpResortWorkspaceScreen.accent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .35,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              unavailable,
              style: const TextStyle(
                color: PlpResortWorkspaceScreen.ink,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'Still available: ' + remainsAvailable,
              style: const TextStyle(
                color: PlpResortWorkspaceScreen.muted,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                TextButton.icon(
                  onPressed: onRefresh,
                  style: TextButton.styleFrom(
                    foregroundColor: PlpResortWorkspaceScreen.ink,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Refresh status'),
                ),
                if (onOpenSettings != null)
                  TextButton.icon(
                    onPressed: onOpenSettings,
                    style: TextButton.styleFrom(
                      foregroundColor: PlpResortWorkspaceScreen.ink,
                    ),
                    icon: const Icon(
                      Icons.settings_input_component_outlined,
                      size: 17,
                    ),
                    label: const Text('Open infrastructure'),
                  ),
              ],
            ),
          ],
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

/// Thin warm-bordered notice with one muted sentence, optionally led by a
/// bold line (same type as the capability tile labels).
class PlpNoticeBox extends StatelessWidget {
  const PlpNoticeBox(this.text, {super.key, this.title});
  final String text;
  final String? title;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          border: Border.fromBorderSide(
            BorderSide(color: PlpResortWorkspaceScreen.line),
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: const TextStyle(
                  color: PlpResortWorkspaceScreen.ink,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 5),
            ],
            Text(
              text,
              style: const TextStyle(
                color: PlpResortWorkspaceScreen.muted,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ],
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
  if (plpRecordIsTestData(item)) return true;
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
  if (const {'stale', 'delayed'}.contains(normalized)) {
    return 'The resort source is delayed. Previously verified records remain available.';
  }
  if (const {'offline', 'unavailable', 'error', 'failed'}
      .contains(normalized)) {
    return 'The resort source is unavailable. Refresh its status to check recovery.';
  }
  return 'The resort source status is not verified. Refresh to confirm what is available.';
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
