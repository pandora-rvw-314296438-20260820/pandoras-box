import 'package:flutter/material.dart';
import '../../core/data/plp_overview_repository.dart';
import '../../core/widgets/pandora_page.dart';
import '../enterprise/enterprise_command_bus.dart';
import 'pandora_v2_ui.dart';

class PlpOverviewScreen extends StatefulWidget {
  const PlpOverviewScreen({super.key, required this.description});

  final String description;

  @override
  State<PlpOverviewScreen> createState() => _PlpOverviewScreenState();
}

class _PlpOverviewScreenState extends State<PlpOverviewScreen> {
  late Future<PlpOverviewData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _data = next);
    await next;
  }

  Future<PlpOverviewData> _load() => const PlpOverviewRepository().load();

  @override
  Widget build(BuildContext context) => PandoraPage(
        title: 'Overview',
        subtitle: 'Property overview',
        onRefresh: _refresh,
        child: FutureBuilder<PlpOverviewData>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return _errorState();
            }
            return _content(snapshot.data!);
          },
        ),
      );

  Widget _errorState() => _panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PLP overview is temporarily unavailable.',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('No business data was changed. Try refreshing the page.',
                style: TextStyle(color: PandoraV2Colors.muted)),
            const SizedBox(height: 14),
            _smallButton('Try again', Icons.refresh_rounded, _refresh),
          ],
        ),
      );
  Widget _content(PlpOverviewData data) {
    final overview = data.overview;
    if (overview == null) {
      return _panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PLP Boracay',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text(
                'The business workspace is not available to this account.',
                style: TextStyle(color: PandoraV2Colors.muted)),
            const SizedBox(height: 14),
            _smallButton('Refresh', Icons.refresh_rounded, _refresh),
          ],
        ),
      );
    }

    final connected =
        overview['source_status'] == 'healthy' && overview['as_of'] != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _hero(data, connected),
        const SizedBox(height: 18),
        if (connected) ...[
          _metrics(data),
          const SizedBox(height: 18),
        ] else ...[
          _connectionState(data),
          const SizedBox(height: 18),
        ],
        _attention(data, connected),
        if (data.activity.isNotEmpty) ...[
          const SizedBox(height: 18),
          _handled(data),
        ],
        const SizedBox(height: 12),
        Text(
          connected
              ? 'Refreshed ${_clock(data.refreshedAt)}'
              : 'Awaiting the first verified live business update',
          textAlign: TextAlign.right,
          style: const TextStyle(color: PandoraV2Colors.muted, fontSize: 11.5),
        ),
      ],
    );
  }

  Widget _hero(PlpOverviewData data, bool connected) {
    final overview = data.overview!;
    final asOf = _date(overview['as_of']);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final baseHeight = narrow ? 190.0 : 224.0;
    final heroHeight = textScale >= 1.8
        ? baseHeight + 84
        : textScale >= 1.4
            ? baseHeight + 46
            : baseHeight;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: heroHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/enterprise/plp_hero_dusk.webp',
              fit: BoxFit.cover,
              alignment: const Alignment(0.36, 0),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x26000000),
                    Color(0x4D000000),
                    Color(0xD9000000),
                  ],
                  stops: [0.0, 0.46, 1.0],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 58,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0x9E080808),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: const Color(0x66E6B784),
                          ),
                        ),
                        child: Image.asset(
                          'assets/enterprise/plp_logo.webp',
                          fit: BoxFit.contain,
                        ),
                      ),
                      const Spacer(),
                      _statusChip(connected ? 'LIVE' : 'CONNECTING', connected),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    _greeting(),
                    style: const TextStyle(
                      color: Color(0xFFE8E2DB),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${overview['display_name'] ?? 'PLP Boracay'}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'serif',
                      fontSize: 29,
                      fontWeight: FontWeight.w600,
                      height: 1.05,
                      letterSpacing: -.45,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'PRIVATE OPERATING SYSTEM',
                    style: TextStyle(
                      color: Color(0xFFD0A16F),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.15,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    connected && asOf != null
                        ? 'Verified business data • ${_relative(asOf)}'
                        : 'Connecting verified business data',
                    style: const TextStyle(
                      color: Color(0xFFD0CBC4),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
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

  Widget _connectionState(PlpOverviewData data) {
    final total = data.sources.length;
    final healthy = data.sources.where((e) => e['status'] == 'healthy').length;
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.sync_rounded, 'Connecting live business data'),
          const SizedBox(height: 8),
          const Text(
            'Alfred will show verified occupancy, sales, arrivals, departures and room readiness here as soon as the first live update arrives.',
            style: TextStyle(color: PandoraV2Colors.muted, height: 1.45),
          ),
          if (total > 0) ...[
            const SizedBox(height: 12),
            Text('$healthy of $total business feeds connected',
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }

  Widget _metrics(PlpOverviewData data) {
    final o = data.overview!;
    final primary = <_Metric>[
      _Metric('Occupancy', _percent(o['occupancy_percent']), Icons.bed_rounded),
      _Metric(
          'Sales today', _money(o['revenue_today']), Icons.payments_outlined),
    ];
    final secondary = <_Metric>[
      _Metric('Rooms available', _count(o['rooms_available']),
          Icons.meeting_room_outlined),
      _Metric('Arrivals', _count(o['arrivals_today']), Icons.login_rounded),
      _Metric(
          'Departures', _count(o['departures_today']), Icons.logout_rounded),
      _Metric('Rooms ready', _count(o['rooms_ready']), Icons.task_alt_rounded),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(Icons.insights_rounded, 'Today'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            color: const Color(0xE611100F),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0x3DD0A16F)),
          ),
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final textScale = MediaQuery.textScalerOf(context).scale(1);
                  final split =
                      constraints.maxWidth >= 520 && textScale < 1.4;
                  final width = split
                      ? (constraints.maxWidth - 1) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    children: [
                      for (var i = 0; i < primary.length; i++) ...[
                        SizedBox(
                          width: width,
                          child: _ledgerMetric(primary[i], primary: true),
                        ),
                        if (split && i == 0)
                          Container(
                            width: 1,
                            height: 78,
                            color: const Color(0x2ED0A16F),
                          ),
                      ],
                    ],
                  );
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1, color: Color(0x2ED0A16F)),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final textScale = MediaQuery.textScalerOf(context).scale(1);
                  final columns = textScale >= 1.4
                      ? 1
                      : constraints.maxWidth >= 700
                          ? 4
                          : constraints.maxWidth >= 430
                              ? 2
                              : 1;
                  final width = constraints.maxWidth / columns;
                  return Wrap(
                    children: [
                      for (final metric in secondary)
                        SizedBox(
                          width: width,
                          child: _ledgerMetric(metric),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ledgerMetric(_Metric metric, {bool primary = false}) => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: primary ? 12 : 8,
          vertical: primary ? 4 : 7,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                metric.icon,
                size: primary ? 20 : 17,
                color: const Color(0xFFD0A16F),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    metric.value,
                    softWrap: true,
                    style: TextStyle(
                      color: const Color(0xFFF4EFE6),
                      fontSize: primary ? 24 : 17,
                      fontWeight: primary ? FontWeight.w700 : FontWeight.w600,
                      letterSpacing: primary ? -.45 : -.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    metric.label,
                    softWrap: true,
                    style: const TextStyle(
                      color: Color(0xFFAAA298),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _attention(PlpOverviewData data, bool connected) {
    if (data.attention.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xB30A0A0A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x3DE6B784)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.check_circle_outline_rounded,
                size: 19,
                color: PandoraV2Colors.success,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nothing needs your attention',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    connected
                        ? 'No verified business issue currently requires a decision.'
                        : 'Business alerts will appear after live operating data connects.',
                    style: const TextStyle(
                      color: PandoraV2Colors.muted,
                      fontSize: 12.5,
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

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.priority_high_rounded, 'Needs your attention'),
          const SizedBox(height: 10),
          for (final item in data.attention) _attentionRow(item),
        ],
      ),
    );
  }

  Widget _attentionRow(Map<String, dynamic> item) {
    final priority = '${item['priority'] ?? 'medium'}';
    final occurred = _date(item['occurred_at']);
    final prompt = '${item['action_prompt'] ?? ''}'.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _priorityDot(priority),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${item['title'] ?? 'Business item'}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if ('${item['summary'] ?? ''}'.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text('${item['summary']}',
                      style: const TextStyle(
                          color: PandoraV2Colors.muted, fontSize: 12.5)),
                ],
                const SizedBox(height: 5),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _tag(priority.toUpperCase()),
                    if (occurred != null)
                      Text(_relative(occurred),
                          style: const TextStyle(
                              color: PandoraV2Colors.muted, fontSize: 11)),
                    if (prompt.isNotEmpty)
                      TextButton(
                        onPressed: () => _openAsk(prompt),
                        style: TextButton.styleFrom(
                          foregroundColor: PandoraV2Colors.ink,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: const Size(48, 48),
                        ),
                        child: const Text('Review'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _handled(PlpOverviewData data) => _panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(Icons.auto_awesome_rounded, 'Alfred handled'),
            const SizedBox(height: 10),
            for (final item in data.activity) _activityRow(item),
          ],
        ),
      );

  Widget _activityRow(Map<String, dynamic> item) {
    final occurred = _date(item['occurred_at']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline_rounded,
              size: 18, color: PandoraV2Colors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${item['title'] ?? 'Completed business action'}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if ('${item['summary'] ?? ''}'.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('${item['summary']}',
                      style: const TextStyle(
                          color: PandoraV2Colors.muted, fontSize: 12.5)),
                ],
                if (occurred != null) ...[
                  const SizedBox(height: 3),
                  Text(_relative(occurred),
                      style: const TextStyle(
                          color: PandoraV2Colors.muted, fontSize: 11)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }



  void _openAsk(String prompt) {
    EnterpriseCommandDraftBus.shared.offer(prompt);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Command prepared in the Alfred bar below.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _panel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(17),
  }) =>
      Container(
        padding: padding,
        decoration: BoxDecoration(
          color: const Color(0xD90A0A0A),
          borderRadius: BorderRadius.circular(21),
          border: Border.all(color: const Color(0x2ED0A16F)),
        ),
        child: child,
      );

  Widget _sectionTitle(IconData icon, String title) => Row(
        children: [
          Icon(icon, size: 19, color: const Color(0xFFE6B784)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -.2,
              ),
            ),
          ),
        ],
      );

  Widget _statusChip(String label, bool healthy) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xA80A0A0A),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: healthy ? const Color(0x8066C58A) : const Color(0x66E6B784),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color:
                    healthy ? PandoraV2Colors.success : const Color(0xFFE6B784),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color:
                    healthy ? PandoraV2Colors.success : const Color(0xFFE6B784),
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: .45,
              ),
            ),
          ],
        ),
      );
  Widget _priorityDot(String priority) {
    final color = switch (priority) {
      'critical' => PandoraV2Colors.danger,
      'high' => PandoraV2Colors.warning,
      _ => PandoraV2Colors.muted,
    };
    return Container(
      margin: const EdgeInsets.only(top: 5),
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _tag(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: PandoraV2Colors.soft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: PandoraV2Colors.muted),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)),
      );

  Widget _smallButton(
          String label, IconData icon, Future<void> Function() action) =>
      OutlinedButton.icon(
        onPressed: () => action(),
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: PandoraV2Colors.ink,
          side: const BorderSide(color: PandoraV2Colors.muted),
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      );



  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning, Doctora';
    if (hour < 18) return 'Good afternoon, Doctora';
    return 'Good evening, Doctora';
  }

  static String _percent(Object? value) {
    if (value is num) {
      return '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}%';
    }
    return 'Unavailable';
  }

  static String _money(Object? value) {
    if (value is! num) return 'Unavailable';
    final whole = value.round().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
      buffer.write(whole[i]);
    }
    return '₱${buffer.toString()}';
  }

  static String _count(Object? value) =>
      value is num ? '${value.round()}' : 'Unavailable';


  static DateTime? _date(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }

  static String _clock(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  static String _relative(DateTime value) {
    final delta = DateTime.now().difference(value);
    if (delta.inMinutes < 1) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes} min ago';
    if (delta.inHours < 24) return '${delta.inHours} hr ago';
    if (delta.inDays == 1) return 'yesterday';
    return '${delta.inDays} days ago';
  }
}

class _Metric {
  const _Metric(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
}