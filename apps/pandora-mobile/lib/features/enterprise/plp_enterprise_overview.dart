import 'dart:async';

import 'package:flutter/material.dart';

class PlpEnterpriseOverview extends StatefulWidget {
  const PlpEnterpriseOverview({
    super.key,
    required this.bootstrap,
    required this.onOpenNavigation,
    required this.onSearch,
    required this.onOpenOccupancy,
    required this.onOpenRooms,
    required this.onOpenTasks,
    required this.onOpenRevenue,
    required this.onOpenBookings,
    required this.onOpenNeedsAttention,
    required this.onOperations,
    required this.onGuestRequests,
    required this.onTeamTasks,
    required this.onReports,
  });

  final Map<String, Object?> bootstrap;
  final VoidCallback onOpenNavigation;
  final VoidCallback onSearch;
  final VoidCallback onOpenOccupancy;
  final VoidCallback onOpenRooms;
  final VoidCallback onOpenTasks;
  final VoidCallback onOpenRevenue;
  final VoidCallback onOpenBookings;
  final VoidCallback onOpenNeedsAttention;
  final VoidCallback onOperations;
  final VoidCallback onGuestRequests;
  final VoidCallback onTeamTasks;
  final VoidCallback onReports;

  @override
  State<PlpEnterpriseOverview> createState() => _PlpEnterpriseOverviewState();
}

class _PlpEnterpriseOverviewState extends State<PlpEnterpriseOverview> {
  static const canvas = Color(0xFFFAF8F3);
  static const surface = Color(0xFFFFFDF9);
  static const ink = Color(0xFF251E18);
  static const muted = Color(0xFF7D746B);
  static const line = Color(0xFFEAE2D8);
  static const bronze = Color(0xFFA46D32);
  static const bronzeSoft = Color(0xFFD4AE79);
  static const green = Color(0xFF66866A);
  static const amber = Color(0xFFB8844A);
  static const red = Color(0xFFA45D56);

  Timer? _timer;
  DateTime _clock = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _clock = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Map<String, Object?> _map(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const <String, Object?>{};
  }

  num? _numberOrNull(Object? value) {
    if (value is num) return value;
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return num.tryParse(text);
  }

  num _number(Object? value) => _numberOrNull(value) ?? 0;

  String _text(Object? value, {String fallback = '—'}) {
    final result = value?.toString().trim();
    return result == null || result.isEmpty ? fallback : result;
  }

  String _integer(Object? value) => _number(value).round().toString();

  String _percent(Object? value) {
    final number = _number(value);
    return '${number.toStringAsFixed(number % 1 == 0 ? 0 : 2)}%';
  }

  String _peso(Object? value) {
    final rounded = _number(value).round();
    final digits = rounded.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return '${rounded < 0 ? '-' : ''}₱$buffer';
  }

  String _firstName(String displayName) {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? 'Owner' : parts.first;
  }

  String _greeting() {
    if (_clock.hour < 12) return 'Good morning';
    if (_clock.hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  String _clockLabel() {
    const weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hh = _clock.hour.toString().padLeft(2, '0');
    final mm = _clock.minute.toString().padLeft(2, '0');
    return '${weekdays[_clock.weekday - 1]}, ${months[_clock.month - 1]} '
        '${_clock.day}, ${_clock.year} · $hh:$mm';
  }

  DateTime? _parseTime(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : DateTime.tryParse(text)?.toLocal();
  }

  String _updatedLabel(Map<String, Object?> today, Map<String, Object?> source) {
    final time = _parseTime(today['generated_at']) ??
        _parseTime(source['observedAt']) ??
        _parseTime(widget.bootstrap['generatedAt']);
    if (time == null) return 'Update time unavailable';
    return 'Updated ${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  String _insight({
    required num? occupancy,
    required int? available,
    required int? tasks,
    required int? conflicts,
    required int? notReady,
  }) {
    if (conflicts != null && conflicts > 0) {
      return '$conflicts booking conflict${conflicts == 1 ? '' : 's'} need review. '
          'Resolve channel discrepancies before the next arrival window.';
    }
    if (notReady != null && notReady > 0) {
      return '$notReady room${notReady == 1 ? ' is' : 's are'} not ready in the '
          'latest hospitality snapshot. Operations should clear readiness before demand tightens.';
    }
    if (tasks != null && tasks > 0 && occupancy != null) {
      return '$tasks staff task${tasks == 1 ? ' remains' : 's remain'} open while '
          'occupancy is ${_percent(occupancy)}. The workload is ready to review.';
    }
    if (occupancy != null && available != null && conflicts != null) {
      return 'No open OTA conflicts are currently reported. Occupancy is '
          '${_percent(occupancy)} with $available room${available == 1 ? '' : 's'} available.';
    }
    return 'Pandora is waiting for a complete verified resort snapshot before '
        'drawing an operational conclusion.';
  }

  @override
  Widget build(BuildContext context) {
    final organization = _map(widget.bootstrap['organization']);
    final user = _map(widget.bootstrap['user']);
    final today = _map(widget.bootstrap['today']);
    final source = _map(widget.bootstrap['sourceHealth']);
    final hospitality = _map(widget.bootstrap['latestHospitalitySnapshot']);

    final propertyName = _text(organization['propertyName'], fallback: 'PLP Boracay');
    final businessIdentity =
        _text(organization['businessIdentity'], fallback: 'Luxury Resort');
    final displayName = _text(user['displayName'], fallback: 'Owner');
    final firstName = _firstName(displayName);

    final occupancy = _numberOrNull(today['occupancy_percent']) ??
        _numberOrNull(hospitality['occupancy_percent']);
    final totalRooms = (_numberOrNull(today['rooms_total']) ??
            _numberOrNull(hospitality['rooms_total']))
        ?.round();
    final available = (_numberOrNull(today['rooms_available']) ??
            _numberOrNull(hospitality['rooms_available']))
        ?.round();
    final occupied = _numberOrNull(today['occupied_rooms'])?.round() ??
        (totalRooms != null && available != null
            ? (totalRooms - available).clamp(0, totalRooms).toInt()
            : null);
    final arrivals = (_numberOrNull(today['arrivals_today']) ??
            _numberOrNull(hospitality['arrivals_today']))
        ?.round();
    final departures = (_numberOrNull(today['departures_today']) ??
            _numberOrNull(hospitality['departures_today']))
        ?.round();
    final revenue = _numberOrNull(today['sales_today_php']) ??
        _numberOrNull(hospitality['revenue_today']);
    final tasks = _numberOrNull(today['open_staff_tasks'])?.round();
    final conflicts = _numberOrNull(today['open_ota_conflicts'])?.round();
    final unpaid = _numberOrNull(today['unpaid_active_bookings'])?.round();
    final notReady = _numberOrNull(hospitality['rooms_not_ready'])?.round();

    final offline = widget.bootstrap['offlineBootstrap'] == true;
    final sourceState = _text(source['state'], fallback: 'unknown');
    final healthy = !offline &&
        <String>{'healthy', 'live', 'verified', 'ready'}
            .contains(sourceState.toLowerCase());

    return ColoredBox(
      color: canvas,
      child: SafeArea(
        key: const ValueKey<String>('plp-enterprise-overview-light'),
        bottom: false,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 188),
          children: [
            _Status(
              label: offline ? 'CACHED SNAPSHOT' : healthy ? 'LIVE DATA' : sourceState.toUpperCase(),
              updated: _updatedLabel(today, source),
              good: healthy,
            ),
            const SizedBox(height: 12),
            _Hero(
              propertyName: propertyName,
              businessIdentity: businessIdentity,
              ownerInitial: firstName.substring(0, 1).toUpperCase(),
              onMenu: widget.onOpenNavigation,
              onSearch: widget.onSearch,
            ),
            const SizedBox(height: 26),
            _Greeting(
              title: '${_greeting()}, $firstName',
              dateTime: _clockLabel(),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 760
                    ? 4
                    : constraints.maxWidth < 330
                        ? 1
                        : 2;
                const gap = 12.0;
                final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    _Kpi(
                      key: const ValueKey<String>('plp-overview-occupancy'),
                      width: width,
                      icon: Icons.hotel_rounded,
                      label: 'Occupancy',
                      value: occupancy == null ? '—' : _percent(occupancy),
                      detail: occupied != null && totalRooms != null && totalRooms > 0
                          ? '$occupied of $totalRooms rooms occupied'
                          : 'Occupancy detail unavailable',
                      onTap: widget.onOpenOccupancy,
                    ),
                    _Kpi(
                      key: const ValueKey<String>('plp-overview-available'),
                      width: width,
                      icon: Icons.bed_outlined,
                      label: 'Rooms available',
                      value: available?.toString() ?? '—',
                      detail: totalRooms != null && totalRooms > 0
                          ? 'of $totalRooms rooms'
                          : 'Room inventory unavailable',
                      onTap: widget.onOpenRooms,
                    ),
                    _Kpi(
                      key: const ValueKey<String>('plp-overview-occupied'),
                      width: width,
                      icon: Icons.meeting_room_outlined,
                      label: 'Occupied rooms',
                      value: occupied?.toString() ?? '—',
                      detail: occupied == null
                          ? 'Occupied-room count unavailable'
                          : 'Current in-house room count',
                      onTap: widget.onOpenOccupancy,
                    ),
                    _Kpi(
                      key: const ValueKey<String>('plp-overview-tasks'),
                      width: width,
                      icon: Icons.assignment_outlined,
                      label: 'Open staff tasks',
                      value: tasks?.toString() ?? '—',
                      detail: tasks == null
                          ? 'Task data unavailable'
                          : tasks == 0
                              ? 'No staff tasks waiting'
                              : 'Ready to review or assign',
                      onTap: widget.onOpenTasks,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 26),
            LayoutBuilder(
              builder: (context, constraints) {
                final revenueCard = _Revenue(
                  value: revenue == null ? '—' : _peso(revenue),
                  onTap: widget.onOpenRevenue,
                );
                final bookings = _Bookings(
                  arrivals: arrivals,
                  departures: departures,
                  occupied: occupied,
                  onTap: widget.onOpenBookings,
                );
                if (constraints.maxWidth >= 720) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: revenueCard),
                      const SizedBox(width: 14),
                      Expanded(flex: 4, child: bookings),
                    ],
                  );
                }
                return Column(
                  children: [revenueCard, const SizedBox(height: 14), bookings],
                );
              },
            ),
            const SizedBox(height: 30),
            _SectionTitle(
              title: 'Needs attention',
              action: 'View all →',
              onAction: widget.onOpenNeedsAttention,
            ),
            const SizedBox(height: 12),
            _Attention(
              conflicts: conflicts,
              tasks: tasks,
              unpaid: unpaid,
              notReady: notReady,
              onBookings: widget.onOpenBookings,
              onTasks: widget.onOpenTasks,
              onRevenue: widget.onOpenRevenue,
              onOperations: widget.onOperations,
            ),
            const SizedBox(height: 28),
            _ResortCard(onTap: widget.onGuestRequests),
            const SizedBox(height: 18),
            _Insight(
              text: _insight(
                occupancy: occupancy,
                available: available,
                tasks: tasks,
                conflicts: conflicts,
                notReady: notReady,
              ),
            ),
            const SizedBox(height: 30),
            const _SectionTitle(title: 'Quick actions'),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 720 ? 4 : 2;
                const gap = 10.0;
                final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    _Quick(
                      width: width,
                      icon: Icons.hub_outlined,
                      title: 'Operations Room',
                      detail: 'Live operations',
                      onTap: widget.onOperations,
                    ),
                    _Quick(
                      width: width,
                      icon: Icons.room_service_outlined,
                      title: 'Guest Requests',
                      detail: 'View & respond',
                      onTap: widget.onGuestRequests,
                    ),
                    _Quick(
                      width: width,
                      icon: Icons.task_alt_outlined,
                      title: 'Team Tasks',
                      detail: 'Assign & track',
                      onTap: widget.onTeamTasks,
                    ),
                    _Quick(
                      width: width,
                      icon: Icons.query_stats_outlined,
                      title: 'Reports',
                      detail: 'View insights',
                      onTap: widget.onReports,
                    ),
                  ],
                );
              },
            ),
            if (!healthy) ...[
              const SizedBox(height: 20),
              _DataNotice(
                text: '${offline ? 'Cached data' : sourceState}: '
                    '${_text(source['message'], fallback: 'The latest source status is unavailable.')}',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.label, required this.updated, required this.good});

  final String label;
  final String updated;
  final bool good;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: good ? _PlpEnterpriseOverviewState.green : _PlpEnterpriseOverviewState.amber,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: good ? _PlpEnterpriseOverviewState.green : _PlpEnterpriseOverviewState.amber,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const Spacer(),
          Text(
            updated,
            style: const TextStyle(
              color: _PlpEnterpriseOverviewState.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.propertyName,
    required this.businessIdentity,
    required this.ownerInitial,
    required this.onMenu,
    required this.onSearch,
  });

  final String propertyName;
  final String businessIdentity;
  final String ownerInitial;
  final VoidCallback onMenu;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          height: 316,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const _PlpHeroImage(),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x0D000000), Color(0x33000000), Color(0x990D0A07)],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                top: 16,
                child: _HeroButton(icon: Icons.menu_rounded, tooltip: 'Open navigation', onTap: onMenu),
              ),
              Positioned(
                right: 16,
                top: 16,
                child: Row(
                  children: [
                    _HeroButton(
                      icon: Icons.search_rounded,
                      tooltip: 'Search PLP with Pandora',
                      onTap: onSearch,
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 50,
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xE6FFFDF9),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0x99FFFFFF)),
                      ),
                      child: Text(
                        ownerInitial,
                        style: const TextStyle(
                          color: _PlpEnterpriseOverviewState.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: const Alignment(0, .24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 78,
                      height: 78,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xDFFFFDF9),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xA6FFFFFF)),
                      ),
                      child: Image.asset(
                        'assets/workspaces/plp.webp',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Text(
                            'PLP',
                            style: TextStyle(
                              color: _PlpEnterpriseOverviewState.bronze,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      propertyName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'serif',
                        fontSize: 34,
                        height: 1,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.8,
                        shadows: [Shadow(color: Color(0x4D000000), blurRadius: 12)],
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      businessIdentity.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFFF7E9D7),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'POWERED BY PANDORA',
                      style: TextStyle(
                        color: Color(0xFFD9D4CD),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.7,
                      ),
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      'Extraordinary stays. Effortless operations.',
                      style: TextStyle(
                        color: Color(0xFFF7F3ED),
                        fontFamily: 'serif',
                        fontStyle: FontStyle.italic,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _PlpHeroImage extends StatelessWidget {
  const _PlpHeroImage();

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/workspaces/plp-hero.webp',
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => const _HeroFallback(),
      );
}

class _HeroFallback extends StatelessWidget {
  const _HeroFallback();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFD7C2A7), Color(0xFF9EB8A3), Color(0xFF6F8F86), Color(0xFF9A6C48)],
          ),
        ),
      );
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xE6FFFDF9),
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          icon: Icon(icon, color: _PlpEnterpriseOverviewState.ink, size: 25),
          constraints: const BoxConstraints.tightFor(width: 52, height: 52),
        ),
      );
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.title, required this.dateTime});

  final String title;
  final String dateTime;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                key: const ValueKey<String>('plp-overview-greeting'),
                style: const TextStyle(
                  color: _PlpEnterpriseOverviewState.ink,
                  fontFamily: 'serif',
                  fontSize: 31,
                  height: 1.08,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.5,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Here’s what’s happening at PLP today.',
                style: TextStyle(
                  color: _PlpEnterpriseOverviewState.muted,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          );
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                copy,
                const SizedBox(height: 10),
                Text(dateTime, style: const TextStyle(color: _PlpEnterpriseOverviewState.muted, fontSize: 11.5)),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: copy),
              Text(dateTime, style: const TextStyle(color: _PlpEnterpriseOverviewState.muted, fontSize: 11.5)),
            ],
          );
        },
      );
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    super.key,
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Material(
          color: _PlpEnterpriseOverviewState.surface,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 144),
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _PlpEnterpriseOverviewState.line),
                boxShadow: const [
                  BoxShadow(color: Color(0x0D6E4A2C), blurRadius: 18, offset: Offset(0, 7)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: _PlpEnterpriseOverviewState.bronze),
                  const SizedBox(height: 13),
                  Text(label, style: const TextStyle(color: _PlpEnterpriseOverviewState.muted, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      color: _PlpEnterpriseOverviewState.ink,
                      fontFamily: 'serif',
                      fontSize: 29,
                      height: 1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(detail, style: const TextStyle(color: _PlpEnterpriseOverviewState.muted, fontSize: 10.5, height: 1.3)),
                ],
              ),
            ),
          ),
        ),
      );
}

class _Revenue extends StatelessWidget {
  const _Revenue({required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Card(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Expanded(child: Text('Revenue today', style: TextStyle(color: _PlpEnterpriseOverviewState.ink, fontSize: 15, fontWeight: FontWeight.w800))),
                _PeriodPill(),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              value,
              key: const ValueKey<String>('plp-overview-revenue'),
              style: const TextStyle(
                color: _PlpEnterpriseOverviewState.ink,
                fontFamily: 'serif',
                fontSize: 34,
                height: 1,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Live total from the current PLP business snapshot',
              style: TextStyle(color: _PlpEnterpriseOverviewState.muted, fontSize: 11.5),
            ),
            const SizedBox(height: 18),
            Container(
              height: 54,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(color: const Color(0xFFF8F3EC), borderRadius: BorderRadius.circular(14)),
              child: const Text(
                'Comparative trend appears when verified historical data is connected.',
                style: TextStyle(color: _PlpEnterpriseOverviewState.muted, fontSize: 10.5, height: 1.3),
              ),
            ),
          ],
        ),
      );
}

class _PeriodPill extends StatelessWidget {
  const _PeriodPill();

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Additional periods appear when comparative history is available.',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F0E8),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: _PlpEnterpriseOverviewState.line),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Today', style: TextStyle(color: _PlpEnterpriseOverviewState.ink, fontSize: 10.5, fontWeight: FontWeight.w700)),
              SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down_rounded, size: 15, color: _PlpEnterpriseOverviewState.muted),
            ],
          ),
        ),
      );
}

class _Bookings extends StatelessWidget {
  const _Bookings({
    required this.arrivals,
    required this.departures,
    required this.occupied,
    required this.onTap,
  });

  final int? arrivals;
  final int? departures;
  final int? occupied;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Card(
        onTap: onTap,
        child: Column(
          children: [
            const Row(
              children: [
                Expanded(child: Text('Today’s bookings', style: TextStyle(color: _PlpEnterpriseOverviewState.ink, fontSize: 15, fontWeight: FontWeight.w800))),
                Icon(Icons.chevron_right_rounded, color: _PlpEnterpriseOverviewState.muted),
              ],
            ),
            const SizedBox(height: 15),
            _BookingRow(label: 'Arrivals', value: arrivals?.toString() ?? '—', tone: _PlpEnterpriseOverviewState.bronze),
            const SizedBox(height: 12),
            _BookingRow(label: 'Departures', value: departures?.toString() ?? '—', tone: Color(0xFF8A7A6A)),
            const SizedBox(height: 12),
            _BookingRow(label: 'Occupied rooms', value: occupied?.toString() ?? '—', tone: _PlpEnterpriseOverviewState.green),
          ],
        ),
      );
}

class _BookingRow extends StatelessWidget {
  const _BookingRow({required this.label, required this.value, required this.tone});

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: tone, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(color: _PlpEnterpriseOverviewState.muted, fontSize: 12, fontWeight: FontWeight.w600))),
          Text(value, style: const TextStyle(color: _PlpEnterpriseOverviewState.ink, fontSize: 17, fontWeight: FontWeight.w800)),
        ],
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: _PlpEnterpriseOverviewState.surface,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _PlpEnterpriseOverviewState.line),
            ),
            child: child,
          ),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _PlpEnterpriseOverviewState.ink,
                fontFamily: 'serif',
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (action != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: _PlpEnterpriseOverviewState.bronze),
              child: Text(action!),
            ),
        ],
      );
}

class _Attention extends StatelessWidget {
  const _Attention({
    required this.conflicts,
    required this.tasks,
    required this.unpaid,
    required this.notReady,
    required this.onBookings,
    required this.onTasks,
    required this.onRevenue,
    required this.onOperations,
  });

  final int? conflicts;
  final int? tasks;
  final int? unpaid;
  final int? notReady;
  final VoidCallback onBookings;
  final VoidCallback onTasks;
  final VoidCallback onRevenue;
  final VoidCallback onOperations;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      if (conflicts != null && conflicts! > 0)
        _AttentionRow(
          icon: Icons.sync_problem_outlined,
          tone: _PlpEnterpriseOverviewState.amber,
          title: '$conflicts OTA conflict${conflicts == 1 ? '' : 's'}',
          detail: 'Booking-channel discrepancy · current snapshot',
          onTap: onBookings,
        ),
      if (notReady != null && notReady! > 0)
        _AttentionRow(
          icon: Icons.cleaning_services_outlined,
          tone: _PlpEnterpriseOverviewState.red,
          title: '$notReady room${notReady == 1 ? '' : 's'} not ready',
          detail: 'Housekeeping readiness · latest hospitality snapshot',
          onTap: onOperations,
        ),
      if (tasks != null && tasks! > 0)
        _AttentionRow(
          icon: Icons.assignment_late_outlined,
          tone: _PlpEnterpriseOverviewState.bronze,
          title: '$tasks open staff task${tasks == 1 ? '' : 's'}',
          detail: 'Team workload · current snapshot',
          onTap: onTasks,
        ),
      if (unpaid != null && unpaid! > 0)
        _AttentionRow(
          icon: Icons.payments_outlined,
          tone: _PlpEnterpriseOverviewState.amber,
          title: '$unpaid unpaid active booking${unpaid == 1 ? '' : 's'}',
          detail: 'Payment follow-up · current snapshot',
          onTap: onRevenue,
        ),
    ];
    if (rows.isEmpty) {
      final complete =
          conflicts != null && tasks != null && unpaid != null && notReady != null;
      return Container(
        key: const ValueKey<String>('plp-overview-attention-empty'),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _PlpEnterpriseOverviewState.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _PlpEnterpriseOverviewState.line),
        ),
        child: Row(
          children: [
            Icon(
              complete
                  ? Icons.check_circle_outline_rounded
                  : Icons.info_outline_rounded,
              color: complete
                  ? _PlpEnterpriseOverviewState.green
                  : _PlpEnterpriseOverviewState.amber,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                complete
                    ? 'No items need your attention in the current verified snapshot.'
                    : 'Attention data is incomplete. Pandora will not treat missing values as zero.',
                style: const TextStyle(
                  color: _PlpEnterpriseOverviewState.muted,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _PlpEnterpriseOverviewState.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _PlpEnterpriseOverviewState.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i != rows.length - 1) const Divider(height: 1, color: _PlpEnterpriseOverviewState.line),
          ],
        ],
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.icon,
    required this.tone,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: tone.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 19, color: tone),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: _PlpEnterpriseOverviewState.ink, fontSize: 12.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(detail, style: const TextStyle(color: _PlpEnterpriseOverviewState.muted, fontSize: 10.5, height: 1.25)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _PlpEnterpriseOverviewState.muted, size: 20),
            ],
          ),
        ),
      );
}

class _ResortCard extends StatelessWidget {
  const _ResortCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 154,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const _PlpHeroImage(),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0xCC2B2119), Color(0x302B2119)],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 250,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Create extraordinary guest experiences.',
                            style: TextStyle(color: Colors.white, fontFamily: 'serif', fontSize: 22, height: 1.1, fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 9),
                          Text(
                            'Open guest and service operations →',
                            style: TextStyle(color: Color(0xFFF0E0CC), fontSize: 11.5, fontWeight: FontWeight.w700),
                          ),
                        ],
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

class _Insight extends StatelessWidget {
  const _Insight({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(19),
        decoration: BoxDecoration(
          color: const Color(0xFFF5EFE6),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE7DAC9)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PANDORA',
              style: TextStyle(color: _PlpEnterpriseOverviewState.bronze, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.6),
            ),
            const SizedBox(height: 10),
            Text(
              text,
              key: const ValueKey<String>('plp-overview-pandora-insight'),
              style: const TextStyle(
                color: _PlpEnterpriseOverviewState.ink,
                fontFamily: 'serif',
                fontSize: 17,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
}

class _Quick extends StatelessWidget {
  const _Quick({
    required this.width,
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Material(
          color: _PlpEnterpriseOverviewState.surface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Container(
              height: 106,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _PlpEnterpriseOverviewState.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: _PlpEnterpriseOverviewState.bronze),
                  const Spacer(),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _PlpEnterpriseOverviewState.ink, fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _PlpEnterpriseOverviewState.muted, fontSize: 9.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _DataNotice extends StatelessWidget {
  const _DataNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF6E9),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEBD7B8)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, color: _PlpEnterpriseOverviewState.amber, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(color: _PlpEnterpriseOverviewState.muted, fontSize: 11.5, height: 1.35))),
          ],
        ),
      );
}
