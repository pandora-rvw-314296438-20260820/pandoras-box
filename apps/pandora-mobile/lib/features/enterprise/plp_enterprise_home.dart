
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

  static const _canvas = Color(0xFFFAF7F1);
  static const _paper = Color(0xFFFFFDFC);
  static const _ink = Color(0xFF171512);
  static const _muted = Color(0xFF706B64);
  static const _line = Color(0xFFE6DED2);
  static const _accent = Color(0xFF82764F);
  static const _good = Color(0xFF5E765F);
  static const _warn = Color(0xFFA56B2C);

  Map<String, Object?> _map(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const <String, Object?>{};
  }

  String _text(Object? value, {String fallback = '—'}) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? fallback : normalized;
  }

  num _number(Object? value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _integer(Object? value) => _number(value).round().toString();

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

  @override
  Widget build(BuildContext context) {
    final user = _map(bootstrap['user']);
    final organization = _map(bootstrap['organization']);
    final today = _map(bootstrap['today']);
    final source = _map(bootstrap['sourceHealth']);

    final displayName = _text(
      user['displayName'],
      fallback: 'PLP administrator',
    );
    final propertyName = _text(
      organization['propertyName'],
      fallback: 'PLP Boracay',
    );
    final businessIdentity = _text(
      organization['businessIdentity'],
      fallback: 'Luxury Resort',
    );
    final occupancy = _text(today['occupancy_percent'], fallback: '0');
    final occupied = _integer(today['occupied_rooms']);
    final rooms = _integer(today['rooms_total']);
    final available = _integer(today['rooms_available']);
    final arrivals = _integer(today['arrivals_today']);
    final departures = _integer(today['departures_today']);
    final sales = _peso(today['sales_today_php']);
    final tasks = _integer(today['open_staff_tasks']);
    final conflicts = _integer(today['open_ota_conflicts']);
    final sourceState = _text(source['state'], fallback: 'unknown');
    final sourceMessage = _text(
      source['message'],
      fallback: 'No provider status message',
    );

    return Material(
      color: _canvas,
      child: SafeArea(
        key: const ValueKey('plp-enterprise-home'),
        bottom: false,
        child: RefreshIndicator(
          color: _ink,
          backgroundColor: _paper,
          onRefresh: () async => onRefresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 190),
            children: [
              _HomeHeader(
                propertyName: propertyName,
                businessIdentity: businessIdentity,
                onOpenNavigation: onOpenNavigation,
                onRefresh: onRefresh,
              ),
              const SizedBox(height: 38),
              const _Eyebrow('OWNER’S HOME'),
              const SizedBox(height: 13),
              const Text(
                'Pueblo La Perla',
                style: TextStyle(
                  color: _ink,
                  fontFamily: 'serif',
                  fontSize: 48,
                  height: 0.94,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -1.8,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Welcome, $displayName',
                key: const ValueKey('plp-authenticated-greeting'),
                style: const TextStyle(
                  color: _accent,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.7,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Your private operating view of the resort — performance, movement, attention, and the next action.',
                style: TextStyle(
                  color: _muted,
                  fontSize: 14.5,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 30),
              const Divider(height: 1, color: _line),
              const SizedBox(height: 24),
              const _Eyebrow('TODAY AT PUEBLO LA PERLA'),
              const SizedBox(height: 18),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _Metric(
                        label: 'Occupancy',
                        value: '$occupancy%',
                        detail: '$occupied of $rooms rooms occupied',
                        valueKey: const ValueKey('plp-metric-occupancy'),
                      ),
                    ),
                    const VerticalDivider(
                      width: 24,
                      thickness: 1,
                      color: _line,
                    ),
                    Expanded(
                      child: _Metric(
                        label: 'Revenue',
                        value: sales,
                        detail: 'today',
                        valueKey: const ValueKey('plp-metric-sales'),
                      ),
                    ),
                    const VerticalDivider(
                      width: 24,
                      thickness: 1,
                      color: _line,
                    ),
                    Expanded(
                      child: _Metric(
                        label: 'Available',
                        value: available,
                        detail: 'rooms',
                        valueKey: const ValueKey('plp-metric-available'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const Divider(height: 1, color: _line),
              const SizedBox(height: 25),
              const _Eyebrow('MOVEMENT TODAY'),
              const SizedBox(height: 8),
              _Movement(
                label: 'Arrivals',
                value: arrivals,
                detail: 'Guests expected today',
              ),
              const Divider(height: 1, color: _line),
              _Movement(
                label: 'Departures',
                value: departures,
                detail: 'Guests leaving today',
              ),
              const Divider(height: 1, color: _line),
              const SizedBox(height: 31),
              _Attention(
                conflicts: conflicts,
                tasks: tasks,
                onTap: onAskAlfred,
              ),
              const SizedBox(height: 34),
              const _Eyebrow('COMMAND PLP'),
              const SizedBox(height: 7),
              const Text(
                'Move from insight to action without leaving the owner workspace.',
                style: TextStyle(
                  color: _muted,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 15),
              _Command(
                key: const ValueKey('plp-open-alfred'),
                title: 'Pandora',
                detail: 'Ask, decide, or act across the resort',
                onTap: onAskAlfred,
                primary: true,
              ),
              _Command(
                key: const ValueKey('plp-open-operations-room'),
                title: 'Operations',
                detail: 'See live execution and operating work',
                onTap: onOperations,
              ),
              _Command(
                key: const ValueKey('plp-open-vision'),
                title: 'Vision',
                detail: 'Observe the property and visual intelligence',
                onTap: onVision,
              ),
              const SizedBox(height: 28),
              _SourceHealth(
                state: sourceState,
                message: sourceMessage,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.propertyName,
    required this.businessIdentity,
    required this.onOpenNavigation,
    required this.onRefresh,
  });

  final String propertyName;
  final String businessIdentity;
  final VoidCallback? onOpenNavigation;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          if (onOpenNavigation != null &&
              PandoraNavigationScope.maybeOf(context)?.openDrawer != null)
            PandoraMenuButton(
              key: const ValueKey<String>('plp-open-navigation'),
              onPressed: onOpenNavigation!,
            )
          else
            const SizedBox.square(dimension: 44),
          const SizedBox(width: 7),
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: PlpEnterpriseHome._paper,
              border: Border.all(color: PlpEnterpriseHome._line),
            ),
            child: Image.asset(
              'assets/workspaces/plp.webp',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Center(
                child: Text(
                  'PLP',
                  style: TextStyle(
                    color: PlpEnterpriseHome._ink,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  propertyName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PlpEnterpriseHome._ink,
                    fontFamily: 'serif',
                    fontSize: 21,
                    height: 1,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.35,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  businessIdentity.toUpperCase(),
                  style: const TextStyle(
                    color: PlpEnterpriseHome._accent,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.7,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox.square(
            dimension: 42,
            child: IconButton(
              tooltip: 'Refresh PLP data',
              onPressed: onRefresh,
              style: IconButton.styleFrom(
                foregroundColor: PlpEnterpriseHome._ink,
                backgroundColor: PlpEnterpriseHome._paper,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                  side: BorderSide(color: PlpEnterpriseHome._line),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ),
        ],
      );
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: PlpEnterpriseHome._accent,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric({
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
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              key: valueKey,
              style: const TextStyle(
                color: PlpEnterpriseHome._ink,
                fontFamily: 'serif',
                fontSize: 31,
                height: 1,
                fontWeight: FontWeight.w400,
                letterSpacing: -0.8,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: PlpEnterpriseHome._muted,
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
        ],
      );
}

class _Movement extends StatelessWidget {
  const _Movement({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: PlpEnterpriseHome._ink,
                      fontFamily: 'serif',
                      fontSize: 22,
                      fontWeight: FontWeight.w400,
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
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: PlpEnterpriseHome._ink,
                fontFamily: 'serif',
                fontSize: 35,
                height: 1,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      );
}

class _Attention extends StatelessWidget {
  const _Attention({
    required this.conflicts,
    required this.tasks,
    required this.onTap,
  });

  final String conflicts;
  final String tasks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final clear = conflicts == '0' && tasks == '0';
    return Material(
      color: PlpEnterpriseHome._ink,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 21),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                clear ? 'RESORT STATUS' : 'NEEDS YOUR ATTENTION',
                style: const TextStyle(
                  color: Color(0xFFD5CCB7),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                clear
                    ? 'Everything important is clear.'
                    : 'A few things need a decision.',
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'serif',
                  fontSize: 29,
                  height: 1.03,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 19),
              _Status(
                title: conflicts +
                    ' OTA conflict' +
                    (conflicts == '1' ? '' : 's'),
                detail: conflicts == '0'
                    ? 'No channel conflicts are open.'
                    : 'Review the conflicting booking before the next arrival.',
                tone: conflicts == '0'
                    ? PlpEnterpriseHome._good
                    : PlpEnterpriseHome._warn,
              ),
              const Divider(height: 25, color: Color(0xFF393631)),
              _Status(
                title: tasks +
                    ' open staff task' +
                    (tasks == '1' ? '' : 's'),
                detail: tasks == '0'
                    ? 'No staff tasks are waiting.'
                    : 'Pandora can summarize, assign, or create the next task.',
                tone: tasks == '0'
                    ? PlpEnterpriseHome._good
                    : const Color(0xFFC8B98F),
              ),
              const SizedBox(height: 18),
              const Row(
                children: [
                  Text(
                    'OPEN IN PANDORA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.7,
                    ),
                  ),
                  SizedBox(width: 7),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 17,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({
    required this.title,
    required this.detail,
    required this.tone,
  });

  final String title;
  final String detail;
  final Color tone;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 5),
            color: tone,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: const TextStyle(
                    color: Color(0xFFBEB8AE),
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class _Command extends StatelessWidget {
  const _Command({
    super.key,
    required this.title,
    required this.detail,
    required this.onTap,
    this.primary = false,
  });

  final String title;
  final String detail;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => Material(
        color: primary ? PlpEnterpriseHome._ink : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: primary
                  ? null
                  : const Border(
                      top: BorderSide(color: PlpEnterpriseHome._line),
                    ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 15,
              vertical: 16,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: primary
                              ? Colors.white
                              : PlpEnterpriseHome._ink,
                          fontFamily: 'serif',
                          fontSize: 20,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        style: TextStyle(
                          color: primary
                              ? const Color(0xFFBEB8AE)
                              : PlpEnterpriseHome._muted,
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: primary ? Colors.white : PlpEnterpriseHome._ink,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      );
}

class _SourceHealth extends StatelessWidget {
  const _SourceHealth({
    required this.state,
    required this.message,
  });

  final String state;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('plp-source-health'),
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: PlpEnterpriseHome._line),
            bottom: BorderSide(color: PlpEnterpriseHome._line),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(top: 4),
              color: state.toLowerCase() == 'healthy'
                  ? PlpEnterpriseHome._good
                  : PlpEnterpriseHome._warn,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(
                    color: PlpEnterpriseHome._muted,
                    fontSize: 10.5,
                    height: 1.4,
                  ),
                  children: [
                    TextSpan(
                      text: state.toUpperCase(),
                      style: const TextStyle(
                        color: PlpEnterpriseHome._ink,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    TextSpan(text: ' · $message'),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}
