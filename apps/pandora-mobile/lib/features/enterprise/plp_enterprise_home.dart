import 'dart:ui';

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

  static const _gold = Color(0xFFE6B784);

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

  String _greeting(String displayName) {
    final hour = DateTime.now().hour;
    final name = _greetingName(displayName);
    if (hour < 12) return 'Good morning, $name';
    if (hour < 18) return 'Good afternoon, $name';
    return 'Good evening, $name';
  }

  @override
  Widget build(BuildContext context) {
    final user = _map(bootstrap['user']);
    final organization = _map(bootstrap['organization']);
    final propertyName =
        _textValue(organization['propertyName'], fallback: 'PLP Boracay');
    final displayName = _textValue(user['displayName'], fallback: 'Doctora');

    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        key: const ValueKey<String>('plp-enterprise-home'),
        bottom: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _PlpEnterpriseBackdrop(),
            RefreshIndicator(
              color: _gold,
              onRefresh: () async => onRefresh(),
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 86, 20, 146),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: (constraints.maxHeight - 232).clamp(0, double.infinity),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              'assets/enterprise/plp_logo.webp',
                              key: const ValueKey<String>('plp-release-logo'),
                              width: 118,
                              height: 142,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              propertyName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'serif',
                                fontSize: 35,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -.5,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'P O W E R E D   B Y   P A N D O R A',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _gold,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.35,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              width: 174,
                              height: 1,
                              color: const Color(0x99E6B784),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              _greeting(displayName),
                              key: const ValueKey<String>('plp-authenticated-greeting'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFECE7E0),
                                fontSize: 14.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 7),
                            const Text(
                              'What can I help with?',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontFamily: 'serif',
                                fontSize: 31,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -.4,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 9),
                            const Text(
                              'Ask about PLP, make a change, or let Pandora handle it.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFFC7C2BC),
                                fontSize: 13.5,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 20),
                            GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              mainAxisExtent: 116,
                              children: [
                                _ReleaseAction(
                                  key: const ValueKey<String>('plp-home-todays-briefing'),
                                  icon: Icons.auto_awesome_outlined,
                                  title: 'Today’s briefing',
                                  subtitle: 'Sales, occupancy & priorities',
                                  onPressed: onAskAlfred,
                                ),
                                _ReleaseAction(
                                  key: const ValueKey<String>('plp-home-bookings'),
                                  icon: Icons.calendar_month_outlined,
                                  title: 'Bookings',
                                  subtitle: 'Arrivals, departures & reservations',
                                  onPressed: onBookings,
                                ),
                                _ReleaseAction(
                                  key: const ValueKey<String>('plp-home-business-performance'),
                                  icon: Icons.query_stats_rounded,
                                  title: 'Business performance',
                                  subtitle: 'Revenue, occupancy & trends',
                                  onPressed: onBusinessPerformance,
                                ),
                                _ReleaseAction(
                                  key: const ValueKey<String>('plp-open-alfred'),
                                  icon: Icons.grid_view_rounded,
                                  title: 'Ask Pandora',
                                  subtitle: 'Request a change or new capability',
                                  onPressed: onAskAlfred,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: _ReleaseHeader(
                onOpenNavigation: onOpenNavigation,
                onRefresh: onRefresh,
                onMore: onOpenNavigation,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReleaseHeader extends StatelessWidget {
  const _ReleaseHeader({
    required this.onOpenNavigation,
    required this.onRefresh,
    required this.onMore,
  });

  final VoidCallback? onOpenNavigation;
  final VoidCallback onRefresh;
  final VoidCallback? onMore;

  Widget _glass({
    required Widget child,
    required BorderRadius borderRadius,
  }) =>
      ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0x661B1B1B),
              borderRadius: borderRadius,
              border: Border.all(color: const Color(0x24FFFFFF)),
            ),
            child: child,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _glass(
                borderRadius: BorderRadius.circular(28),
                child: SizedBox.square(
                  dimension: 52,
                  child: IconButton(
                    key: const ValueKey<String>('plp-open-navigation'),
                    tooltip: 'Open navigation',
                    onPressed: onOpenNavigation,
                    icon: const Icon(Icons.menu_rounded, size: 25),
                    color: Colors.white,
                  ),
                ),
              ),
              const Spacer(),
              _glass(
                borderRadius: BorderRadius.circular(28),
                child: SizedBox(
                  height: 52,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 48,
                        child: IconButton(
                          key: const ValueKey<String>('plp-release-refresh'),
                          tooltip: 'Refresh',
                          onPressed: onRefresh,
                          icon: const Icon(
                            Icons.history_toggle_off_rounded,
                            size: 23,
                          ),
                          color: Colors.white,
                        ),
                      ),
                      SizedBox.square(
                        dimension: 48,
                        child: IconButton(
                          key: const ValueKey<String>('plp-release-more'),
                          tooltip: 'More',
                          onPressed: onMore,
                          icon: const Icon(Icons.more_vert_rounded, size: 25),
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _PlpEnterpriseBackdrop extends StatelessWidget {
  const _PlpEnterpriseBackdrop();

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/enterprise/plp_hero_dusk.webp',
            key: const ValueKey<String>('plp-release-background'),
            fit: BoxFit.cover,
            alignment: const Alignment(0.35, 0),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x66000000),
                  Color(0x7A000000),
                  Color(0xB3000000),
                  Color(0xF0000000),
                ],
                stops: [0.0, 0.34, 0.68, 1.0],
              ),
            ),
          ),
        ],
      );
}

class _ReleaseAction extends StatelessWidget {
  const _ReleaseAction({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xB30A0A0A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: const BorderSide(color: Color(0x66D6A36C)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 24, color: _PlpEnterpriseHomeColors.gold),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFAFAAA4),
                          fontSize: 11.5,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: Color(0xFFB78153),
                ),
              ],
            ),
          ),
        ),
      );
}

abstract final class _PlpEnterpriseHomeColors {
  static const gold = Color(0xFFE6B784);
}
