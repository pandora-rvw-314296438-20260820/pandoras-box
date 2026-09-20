import 'package:flutter/material.dart';

class PlpEnterpriseHome extends StatelessWidget {
  const PlpEnterpriseHome({
    super.key,
    required this.bootstrap,
    this.onOpenNavigation,
    required this.onRefresh,
    required this.onAskAlfred,
    required this.onBookings,
    required this.onBusinessPerformance,
    required this.onGuestExperience,
  });

  final Map<String, Object?> bootstrap;
  final VoidCallback? onOpenNavigation;
  final VoidCallback onRefresh;
  final VoidCallback onAskAlfred;
  final VoidCallback onBookings;
  final VoidCallback onBusinessPerformance;
  final VoidCallback onGuestExperience;

  static const _canvas = Color(0xFF050607);
  static const _text = Color(0xFFFFFBF6);
  static const _muted = Color(0xFFC9C0B7);
  static const _gold = Color(0xFFD69A6B);
  static const _goldSoft = Color(0x66D69A6B);
  static const _glass = Color(0xB20A0A0A);

  Map<String, Object?> _map(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, Object?>{};
  }

  String _textValue(Object? value, {String fallback = '—'}) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? fallback : normalized;
  }

  num _number(Object? value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _integer(Object? value) => _number(value).round().toString();

  String _peso(Object? value) {
    final amount = _number(value).round().abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < amount.length; i++) {
      if (i > 0 && (amount.length - i) % 3 == 0) buffer.write(',');
      buffer.write(amount[i]);
    }
    return '${_number(value) < 0 ? '-₱' : '₱'}$buffer';
  }

  String _greetingName(String displayName) {
    final clean = displayName.trim();
    if (clean.isEmpty || clean.toLowerCase() == 'plp administrator') {
      return 'Doctora';
    }
    return clean;
  }

  String _daypart() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final user = _map(bootstrap['user']);
    final organization = _map(bootstrap['organization']);
    final today = _map(bootstrap['today']);
    final source = _map(bootstrap['sourceHealth']);

    final propertyName =
        _textValue(organization['propertyName'], fallback: 'PLP Boracay');
    final guestName =
        _greetingName(_textValue(user['displayName'], fallback: 'Doctora'));
    final occupancy = _textValue(today['occupancy_percent'], fallback: '0');
    final arrivals = _integer(today['arrivals_today']);
    final departures = _integer(today['departures_today']);
    final sales = _peso(today['sales_today_php']);
    final conflicts = _integer(today['open_ota_conflicts']);
    final sourceState = _textValue(source['state'], fallback: 'live');

    return ColoredBox(
      color: _canvas,
      child: SafeArea(
        key: const ValueKey('plp-enterprise-home'),
        bottom: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _AtmosphericBackdrop(),
            RefreshIndicator(
              color: _gold,
              onRefresh: () async => onRefresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 154),
                children: [
                  Row(
                    children: [
                      _RoundGlassButton(
                        key: const ValueKey<String>('plp-open-navigation'),
                        icon: Icons.menu_rounded,
                        tooltip: 'Open navigation',
                        onPressed: onOpenNavigation,
                      ),
                      const Spacer(),
                      _StatusPill(
                        sourceState: sourceState,
                        onRefresh: onRefresh,
                      ),
                    ],
                  ),
                  const SizedBox(height: 92),
                  Center(
                    child: Container(
                      width: 126,
                      height: 126,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0x7A2A1308),
                        border: Border.all(color: _gold, width: 1.5),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x52000000),
                            blurRadius: 34,
                            offset: Offset(0, 16),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(9),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/workspaces/plp.webp',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Text(
                              'PLP',
                              style: TextStyle(
                                color: _text,
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    propertyName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _text,
                      fontSize: 34,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'P O W E R E D   B Y   P A N D O R A',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFF0B987),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.1,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Center(
                    child: Container(
                      width: 178,
                      height: 1,
                      color: _goldSoft,
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    '${_daypart()}, $guestName',
                    key: const ValueKey('plp-authenticated-greeting'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFF0E8E0),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'What can I help with?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _text,
                      fontSize: 31,
                      height: 1.08,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.9,
                    ),
                  ),
                  const SizedBox(height: 11),
                  const Text(
                    'Ask about PLP, make a change, or let Pandora handle it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _muted,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Expanded(
                        child: _HomeActionCard(
                          key: const ValueKey('plp-home-todays-briefing'),
                          icon: Icons.auto_awesome_rounded,
                          title: 'Today’s briefing',
                          subtitle:
                              'Sales $sales · occupancy $occupancy% · priorities',
                          onTap: onAskAlfred,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _HomeActionCard(
                          key: const ValueKey('plp-home-bookings'),
                          icon: Icons.calendar_month_outlined,
                          title: 'Bookings',
                          subtitle:
                              '$arrivals arrivals · $departures departures',
                          onTap: onBookings,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _HomeActionCard(
                          key: const ValueKey('plp-home-business-performance'),
                          icon: Icons.query_stats_rounded,
                          title: 'Business performance',
                          subtitle: 'Revenue, occupancy & trends',
                          onTap: onBusinessPerformance,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _HomeActionCard(
                          key: const ValueKey('plp-home-guest-experience'),
                          icon: Icons.room_service_outlined,
                          title: 'Guest experience',
                          subtitle: conflicts == '0'
                              ? 'Arrivals, stays & guest care'
                              : '$conflicts guest-impacting item${conflicts == '1' ? '' : 's'}',
                          onTap: onGuestExperience,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _HomeActionCard(
                    key: const ValueKey('plp-open-alfred'),
                    icon: Icons.grid_view_rounded,
                    title: 'Ask Pandora',
                    subtitle: 'Request a change or new capability',
                    onTap: onAskAlfred,
                    compact: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AtmosphericBackdrop extends StatelessWidget {
  const _AtmosphericBackdrop();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF14304B),
              Color(0xFF101A27),
              Color(0xFF090B0E),
              Color(0xFF030304),
            ],
            stops: [0, .27, .59, 1],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              left: -120,
              top: 210,
              child: _Glow(
                size: 360,
                color: Color(0x2447784E),
              ),
            ),
            Positioned(
              right: -150,
              top: 330,
              child: _Glow(
                size: 390,
                color: Color(0x264A2B18),
              ),
            ),
            Positioned(
              left: 30,
              right: 30,
              bottom: 90,
              child: _Glow(
                size: 240,
                color: Color(0x183B2417),
              ),
            ),
          ],
        ),
      );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, Colors.transparent],
          ),
        ),
      );
}

class _RoundGlassButton extends StatelessWidget {
  const _RoundGlassButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0x66151A20),
          border: Border.all(color: const Color(0x2FFFFFFF)),
        ),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, color: _text, size: 28),
        ),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.sourceState,
    required this.onRefresh,
  });

  final String sourceState;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Container(
        height: 58,
        padding: const EdgeInsets.only(left: 6, right: 3),
        decoration: BoxDecoration(
          color: const Color(0x66151A20),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0x2FFFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Refresh PLP data',
              onPressed: onRefresh,
              icon: const Icon(
                Icons.sync_rounded,
                color: _text,
                size: 22,
              ),
            ),
            Container(
              width: 1,
              height: 24,
              color: const Color(0x24FFFFFF),
            ),
            const SizedBox(width: 8),
            Text(
              sourceState.toLowerCase() == 'healthy' ? 'Live' : sourceState,
              style: const TextStyle(
                color: Color(0xFFE9E0D8),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
          ],
        ),
      );
}

class _HomeActionCard extends StatelessWidget {
  const _HomeActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            minHeight: compact ? 92 : 148,
            decoration: BoxDecoration(
              color: _glass,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x8B8E5E3B)),
            ),
            padding: EdgeInsets.fromLTRB(
              compact ? 18 : 16,
              compact ? 15 : 18,
              compact ? 16 : 14,
              compact ? 15 : 17,
            ),
            child: compact
                ? Row(
                    children: [
                      Icon(icon, color: _gold, size: 26),
                      const SizedBox(width: 15),
                      Expanded(child: _CardCopy(title: title, subtitle: subtitle)),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: _gold,
                        size: 25,
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, color: _gold, size: 27),
                      const Spacer(),
                      _CardCopy(title: title, subtitle: subtitle),
                      const SizedBox(height: 5),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: _gold,
                          size: 23,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      );
}

class _CardCopy extends StatelessWidget {
  const _CardCopy({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _text,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _muted,
              fontSize: 11.5,
              height: 1.25,
            ),
          ),
        ],
      );
}
