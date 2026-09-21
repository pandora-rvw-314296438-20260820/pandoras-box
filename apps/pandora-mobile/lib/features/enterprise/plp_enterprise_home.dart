import 'package:flutter/material.dart';

import '../../core/widgets/pandora_navigation.dart';

class PlpEnterpriseHome extends StatelessWidget {
  const PlpEnterpriseHome({
    super.key,
    required this.bootstrap,
    this.onOpenNavigation,
    required this.onRefresh,
    required this.onAskAlfred,
    required this.onOperations,
    required this.onVision,
  });

  final Map<String, Object?> bootstrap;
  final VoidCallback? onOpenNavigation;
  final VoidCallback onRefresh;
  final VoidCallback onAskAlfred;
  final VoidCallback onOperations;
  final VoidCallback onVision;

  static const _canvas = Color(0xFF070A0F);
  static const _panel = Color(0xFF10151D);
  static const _panelRaised = Color(0xFF151B25);
  static const _line = Color(0xFF263040);
  static const _muted = Color(0xFF93A0B2);
  static const _text = Color(0xFFF4F7FB);
  static const _accent = Color(0xFF5ED8E6);
  static const _good = Color(0xFF6FE0A4);
  static const _warn = Color(0xFFF2C66D);

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
    final prefix = _number(value) < 0 ? '-₱' : '₱';
    return '$prefix$buffer';
  }

  @override
  Widget build(BuildContext context) {
    final user = _map(bootstrap['user']);
    final organization = _map(bootstrap['organization']);
    final today = _map(bootstrap['today']);
    final source = _map(bootstrap['sourceHealth']);

    final displayName =
        _textValue(user['displayName'], fallback: 'PLP administrator');
    final propertyName =
        _textValue(organization['propertyName'], fallback: 'PLP Boracay');
    final businessIdentity =
        _textValue(organization['businessIdentity'], fallback: 'Luxury Resort');

    final occupancy = _textValue(today['occupancy_percent'], fallback: '0');
    final occupied = _integer(today['occupied_rooms']);
    final rooms = _integer(today['rooms_total']);
    final available = _integer(today['rooms_available']);
    final arrivals = _integer(today['arrivals_today']);
    final departures = _integer(today['departures_today']);
    final sales = _peso(today['sales_today_php']);
    final tasks = _integer(today['open_staff_tasks']);
    final conflicts = _integer(today['open_ota_conflicts']);
    final sourceState = _textValue(source['state'], fallback: 'unknown');
    final sourceMessage = _textValue(
      source['message'],
      fallback: 'No provider status message',
    );

    return ColoredBox(
      color: _canvas,
      child: SafeArea(
        key: const ValueKey('plp-enterprise-home'),
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async => onRefresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 190),
            children: [
              Row(
                children: [
                  if (onOpenNavigation != null) ...[
                    if (PandoraNavigationScope.maybeOf(context)?.openDrawer != null)
                      PandoraMenuButton(
                        key: const ValueKey<String>('plp-open-navigation'),
                        onPressed: onOpenNavigation!,
                      )
                    else
                      const SizedBox.square(dimension: 44),
                    const SizedBox(width: 4),
                  ],
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _panelRaised,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _line),
                    ),
                    child: const Icon(
                      Icons.hotel_class_rounded,
                      color: _accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          propertyName,
                          style: const TextStyle(
                            color: _text,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        Text(
                          businessIdentity,
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Refresh PLP data',
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              Text(
                'Welcome, $displayName',
                key: const ValueKey('plp-authenticated-greeting'),
                style: const TextStyle(
                  color: _text,
                  fontSize: 28,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Here is what needs your attention at the resort today.',
                style: TextStyle(
                  color: _muted,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF152532), Color(0xFF101A25)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF294453)),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.insights_rounded, color: _accent, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'TODAY AT A GLANCE',
                          style: TextStyle(
                            color: _accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: _HeroMetric(
                            label: 'Occupancy',
                            value: '$occupancy%',
                            detail: '$occupied of $rooms rooms occupied',
                            valueKey:
                                const ValueKey('plp-metric-occupancy'),
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: _HeroMetric(
                            label: 'Sales',
                            value: sales,
                            detail: 'today',
                            valueKey: const ValueKey('plp-metric-sales'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _FlowCard(
                      icon: Icons.login_rounded,
                      label: 'Arrivals',
                      value: arrivals,
                      detail: 'today',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FlowCard(
                      icon: Icons.logout_rounded,
                      label: 'Departures',
                      value: departures,
                      detail: 'today',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FlowCard(
                      icon: Icons.bed_outlined,
                      label: 'Available',
                      value: available,
                      detail: 'rooms',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Needs attention',
                style: TextStyle(
                  color: _text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 12),
              _AttentionRow(
                icon: Icons.sync_problem_rounded,
                title:
                    '$conflicts OTA conflict${conflicts == '1' ? '' : 's'}',
                subtitle: conflicts == '0'
                    ? 'No channel conflicts are open.'
                    : 'Review the conflicting booking before the next arrival.',
                tone: conflicts == '0' ? _good : _warn,
                onTap: onAskAlfred,
              ),
              const SizedBox(height: 10),
              _AttentionRow(
                icon: Icons.assignment_outlined,
                title:
                    '$tasks open staff task${tasks == '1' ? '' : 's'}',
                subtitle: tasks == '0'
                    ? 'No staff tasks are waiting.'
                    : 'Alfred can summarize, assign, or create the next task.',
                tone: tasks == '0' ? _good : _accent,
                onTap: onAskAlfred,
              ),
              const SizedBox(height: 24),
              const Text(
                'Command center',
                style: TextStyle(
                  color: _text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _CommandTile(
                      key: const ValueKey('plp-open-alfred'),
                      icon: Icons.auto_awesome_rounded,
                      label: 'Alfred',
                      detail: 'Ask or act',
                      onTap: onAskAlfred,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CommandTile(
                      key: const ValueKey('plp-open-operations-room'),
                      icon: Icons.hub_rounded,
                      label: 'Operations',
                      detail: 'Live execution',
                      onTap: onOperations,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CommandTile(
                      key: const ValueKey('plp-open-vision'),
                      icon: Icons.visibility_rounded,
                      label: 'Vision',
                      detail: 'Observe',
                      onTap: onVision,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                key: const ValueKey('plp-source-health'),
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _line),
                ),
                padding: const EdgeInsets.all(15),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.verified_outlined,
                      color: _good,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                          children: [
                            TextSpan(
                              text: sourceState.toUpperCase(),
                              style: const TextStyle(
                                color: _good,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            TextSpan(text: ' · $sourceMessage'),
                          ],
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
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.label,
    required this.value,
    required this.detail,
    required this.valueKey,
  });

  final String label;
  final String value;
  final String detail;
  final Key valueKey;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: PlpEnterpriseHome._muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              key: valueKey,
              style: const TextStyle(
                color: PlpEnterpriseHome._text,
                fontSize: 31,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            detail,
            style: const TextStyle(
              color: PlpEnterpriseHome._muted,
              fontSize: 11.5,
            ),
          ),
        ],
      );
}

class _FlowCard extends StatelessWidget {
  const _FlowCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: PlpEnterpriseHome._panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: PlpEnterpriseHome._line),
        ),
        padding: const EdgeInsets.fromLTRB(13, 14, 13, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: PlpEnterpriseHome._accent, size: 18),
            const SizedBox(height: 14),
            Text(
              value,
              style: const TextStyle(
                color: PlpEnterpriseHome._text,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: PlpEnterpriseHome._text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              detail,
              style: const TextStyle(
                color: PlpEnterpriseHome._muted,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      );
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tone,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: PlpEnterpriseHome._panel,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: PlpEnterpriseHome._line),
            ),
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: tone, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: PlpEnterpriseHome._text,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: PlpEnterpriseHome._muted,
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: PlpEnterpriseHome._muted,
                ),
              ],
            ),
          ),
        ),
      );
}

class _CommandTile extends StatelessWidget {
  const _CommandTile({
    super.key,
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: PlpEnterpriseHome._panelRaised,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: PlpEnterpriseHome._line),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Column(
              children: [
                Icon(icon, color: PlpEnterpriseHome._accent, size: 22),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: PlpEnterpriseHome._text,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    color: PlpEnterpriseHome._muted,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
