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

  static const _text = Color(0xFFFFFBF7);
  static const _muted = Color(0xFFD0C8C1);
  static const _gold = Color(0xFFF0B17F);
  static const _card = Color(0xB5080808);
  static const _cardBorder = Color(0xA47F563A);

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
    final propertyName =
        _textValue(organization['propertyName'], fallback: 'PLP Boracay');
    final guestName =
        _greetingName(_textValue(user['displayName'], fallback: 'Doctora'));

    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        key: const ValueKey('plp-enterprise-home'),
        bottom: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _ReleaseBackdrop(),
            RefreshIndicator(
              color: _gold,
              onRefresh: () async => onRefresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 146),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RoundControl(
                        key: const ValueKey<String>('plp-open-navigation'),
                        icon: Icons.menu_rounded,
                        tooltip: 'Open navigation',
                        onPressed: onOpenNavigation,
                      ),
                      const Spacer(),
                      _ReleaseStatusControl(
                        onRefresh: onRefresh,
                        onMore: onOpenNavigation,
                      ),
                    ],
                  ),
                  const SizedBox(height: 82),
                  Center(
                    child: Image.asset(
                      'assets/workspaces/plp.webp',
                      key: const ValueKey<String>('plp-release-logo'),
                      width: 112,
                      height: 160,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Container(
                        width: 104,
                        height: 142,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF5B2B16),
                          borderRadius: BorderRadius.circular(52),
                          border: Border.all(color: const Color(0xFFF7EFE5), width: 2),
                        ),
                        child: const Text(
                          'PLP',
                          style: TextStyle(
                            color: _text,
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
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
                      color: _text,
                      fontSize: 34,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                    ),
                  ),
                  const SizedBox(height: 13),
                  const Text(
                    'P O W E R E D   B Y   P A N D O R A',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _gold,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.2,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Center(
                    child: Container(
                      width: 182,
                      height: 1,
                      color: const Color(0x7AB4764B),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    '${_daypart()}, $guestName',
                    key: const ValueKey('plp-authenticated-greeting'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFF3ECE6),
                      fontSize: 16.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'What can I help with?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _text,
                      fontSize: 31.5,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.9,
                    ),
                  ),
                  const SizedBox(height: 13),
                  const Text(
                    'Ask about PLP, make a change, or let Pandora handle it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _muted,
                      fontSize: 14.5,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: _ReleaseActionCard(
                          key: const ValueKey('plp-home-todays-briefing'),
                          icon: Icons.auto_awesome_rounded,
                          title: 'Today’s briefing',
                          subtitle: 'Sales, occupancy &\npriorities',
                          onTap: onAskAlfred,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _ReleaseActionCard(
                          key: const ValueKey('plp-home-bookings'),
                          icon: Icons.calendar_month_outlined,
                          title: 'Bookings',
                          subtitle: 'Arrivals, departures &\nreservations',
                          onTap: onBookings,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _ReleaseActionCard(
                          key: const ValueKey('plp-home-business-performance'),
                          icon: Icons.query_stats_rounded,
                          title: 'Business performance',
                          subtitle: 'Revenue, occupancy &\ntrends',
                          onTap: onBusinessPerformance,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _ReleaseActionCard(
                          key: const ValueKey('plp-open-alfred'),
                          icon: Icons.grid_view_rounded,
                          title: 'Ask Pandora',
                          subtitle: 'Request a change or new\ncapability',
                          onTap: onAskAlfred,
                        ),
                      ),
                    ],
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

class _ReleaseBackdrop extends StatelessWidget {
  const _ReleaseBackdrop();

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/workspaces/plp-hero.webp',
            key: const ValueKey<String>('plp-release-background'),
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (_, __, ___) => const ColoredBox(
              color: Color(0xFF07101B),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x3D21496B),
                  Color(0x3D0E1B27),
                  Color(0x8D050607),
                  Color(0xE8000000),
                ],
                stops: [0, .26, .62, 1],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -.15),
                radius: 1.1,
                colors: [
                  Color(0x001A0A02),
                  Color(0x4D000000),
                ],
                stops: [.42, 1],
              ),
            ),
          ),
        ],
      );
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
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
          color: const Color(0x75111922),
          border: Border.all(color: const Color(0x3DFFFFFF)),
        ),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, color: PlpEnterpriseHome._text, size: 28),
        ),
      );
}

class _ReleaseStatusControl extends StatelessWidget {
  const _ReleaseStatusControl({
    required this.onRefresh,
    required this.onMore,
  });

  final VoidCallback onRefresh;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) => Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: const Color(0x72101922),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0x3DFFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const ValueKey<String>('plp-release-refresh'),
              tooltip: 'Refresh PLP data',
              onPressed: onRefresh,
              icon: const Icon(
                Icons.sync_rounded,
                color: PlpEnterpriseHome._text,
                size: 24,
              ),
            ),
            IconButton(
              key: const ValueKey<String>('plp-release-more'),
              tooltip: 'More',
              onPressed: onMore,
              icon: const Icon(
                Icons.more_vert_rounded,
                color: PlpEnterpriseHome._text,
                size: 24,
              ),
            ),
          ],
        ),
      );
}

class _ReleaseActionCard extends StatelessWidget {
  const _ReleaseActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            height: 154,
            padding: const EdgeInsets.fromLTRB(18, 18, 14, 16),
            decoration: BoxDecoration(
              color: PlpEnterpriseHome._card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: PlpEnterpriseHome._cardBorder),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x36000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, color: PlpEnterpriseHome._gold, size: 29),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PlpEnterpriseHome._text,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PlpEnterpriseHome._muted,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: PlpEnterpriseHome._gold,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      );
}
