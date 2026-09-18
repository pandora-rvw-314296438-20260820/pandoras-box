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
        subtitle: 'PLP Boracay command center',
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
        const SizedBox(height: 18),
        if (connected) ...[
          _insight(data),
          const SizedBox(height: 18),
        ],
        _quickActions(),
        const SizedBox(height: 18),
        _handled(data, connected),
        const SizedBox(height: 18),
        _dataCoverage(data),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        height: 292,
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
                        width: 58,
                        height: 70,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0x9E080808),
                          borderRadius: BorderRadius.circular(18),
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
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                      height: 1.05,
                      letterSpacing: -.45,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'P O W E R E D   B Y   P A N D O R A',
                    style: TextStyle(
                      color: Color(0xFFE6B784),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
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
            'Pandora will show verified occupancy, sales, arrivals, departures and room readiness here as soon as the first live update arrives.',
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
        _sectionTitle(Icons.insights_rounded, 'Today at a glance'),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 520 ? 2 : 1;
            final width = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final metric in primary)
                  SizedBox(
                    width: width,
                    child: _metricCard(metric, primary: true),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 720 ? 4 : 2;
            final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final metric in secondary)
                  SizedBox(width: width, child: _metricCard(metric)),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _metricCard(_Metric metric, {bool primary = false}) => Container(
        constraints: BoxConstraints(minHeight: primary ? 116 : 96),
        padding: EdgeInsets.all(primary ? 16 : 14),
        decoration: BoxDecoration(
          color: const Color(0xD90A0A0A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x3DE6B784)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(metric.icon,
                size: primary ? 21 : 18, color: const Color(0xFFE6B784)),
            SizedBox(height: primary ? 15 : 11),
            Text(metric.value,
                softWrap: true,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: primary ? 24 : 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.35,
                )),
            const SizedBox(height: 3),
            Text(metric.label,
                softWrap: true,
                style: const TextStyle(
                  color: Color(0xFFAAA6A0),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                )),
          ],
        ),
      );

  Widget _insight(PlpOverviewData data) {
    final o = data.overview!;
    final arrivals = _int(o['arrivals_today']);
    final notReady = _int(o['rooms_not_ready']);
    final roomsAvailable = _int(o['rooms_available']);
    String message;
    if (arrivals > 0 && notReady > 0) {
      message =
          '$notReady rooms are not ready with $arrivals arrivals expected today.';
    } else if (arrivals > 0 && roomsAvailable == 0) {
      message =
          '$arrivals arrivals are expected today and no rooms are currently marked available.';
    } else {
      message =
          'Pandora is monitoring today’s verified occupancy, sales, arrivals and room readiness.';
    }
    return _panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome_rounded,
              size: 20, color: Color(0xFFE6B784)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pandora brief',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(message,
                    style: const TextStyle(
                        color: PandoraV2Colors.muted, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _attention(PlpOverviewData data, bool connected) => _panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(Icons.priority_high_rounded, 'Needs your attention'),
            const SizedBox(height: 10),
            if (data.attention.isEmpty)
              Text(
                connected
                    ? 'Nothing from connected business feeds needs your attention right now.'
                    : 'Business alerts will appear here once live operating data is connected.',
                style: const TextStyle(color: PandoraV2Colors.muted),
              )
            else
              for (final item in data.attention) _attentionRow(item),
          ],
        ),
      );

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
                        child: const Text('Ask Pandora'),
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

  Widget _handled(PlpOverviewData data, bool connected) => _panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(Icons.auto_awesome_rounded, 'Pandora handled'),
            const SizedBox(height: 10),
            if (data.activity.isEmpty)
              Text(
                connected
                    ? 'No completed business activity has been recorded yet.'
                    : 'Completed business actions will appear here once live operating data is connected.',
                style: const TextStyle(color: PandoraV2Colors.muted),
              )
            else
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

  Widget _dataCoverage(PlpOverviewData data) => _panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(Icons.hub_outlined, 'Business data coverage'),
            const SizedBox(height: 10),
            if (data.sources.isEmpty)
              const Text('No business sources are configured yet.',
                  style: TextStyle(color: PandoraV2Colors.muted))
            else
              for (final source in data.sources)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(_sourceIcon('${source['source_type']}'),
                          size: 17, color: _sourceColor('${source['status']}')),
                      const SizedBox(width: 9),
                      Expanded(
                          child: Text(
                              '${source['display_name'] ?? 'Business feed'}')),
                      Text(_sourceLabel('${source['status']}'),
                          style: TextStyle(
                              color: _sourceColor('${source['status']}'),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
          ],
        ),
      );

  Widget _quickActions() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.bolt_rounded, 'Quick actions'),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final half = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: half,
                    child: _actionButton(
                      'Ask Pandora',
                      Icons.chat_bubble_outline_rounded,
                      'How is PLP Boracay doing today? Use only verified connected business data and clearly identify anything unavailable.',
                    ),
                  ),
                  SizedBox(
                    width: half,
                    child: _actionButton(
                      'Today’s report',
                      Icons.summarize_outlined,
                      'Prepare today’s PLP Boracay management report using only verified connected business data.',
                    ),
                  ),
                  SizedBox(
                    width: constraints.maxWidth,
                    child: _actionButton(
                      'Create task',
                      Icons.add_task_rounded,
                      'Create a PLP Boracay management task. Ask me what needs to be done if my next message does not make it clear.',
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      );

  Widget _actionButton(String label, IconData icon, String prompt) =>
      OutlinedButton.icon(
        onPressed: () => _openAsk(prompt),
        icon: Icon(icon, size: 18, color: const Color(0xFFE6B784)),
        label: Text(label, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          foregroundColor: PandoraV2Colors.ink,
          backgroundColor: PandoraV2Colors.soft,
          side: const BorderSide(color: Color(0x3DE6B784)),
          minimumSize: const Size.fromHeight(50),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
        ),
      );

  void _openAsk(String prompt) {
    EnterpriseCommandDraftBus.shared.offer(prompt);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Command prepared in the Pandora bar below.'),
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
          border: Border.all(color: const Color(0x33E6B784)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
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
          border: Border.all(color: PandoraV2Colors.line),
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
          side: const BorderSide(color: PandoraV2Colors.line),
        ),
      );

  static IconData _sourceIcon(String type) => switch (type) {
        'reservations' => Icons.calendar_month_outlined,
        'payments' => Icons.payments_outlined,
        'housekeeping' => Icons.cleaning_services_outlined,
        'guest_requests' => Icons.support_agent_outlined,
        _ => Icons.hub_outlined,
      };

  static Color _sourceColor(String status) => switch (status) {
        'healthy' => PandoraV2Colors.success,
        'stale' => PandoraV2Colors.warning,
        'error' => PandoraV2Colors.danger,
        _ => PandoraV2Colors.muted,
      };

  static String _sourceLabel(String status) => switch (status) {
        'healthy' => 'Live',
        'connecting' => 'Connecting',
        'stale' => 'Needs refresh',
        'error' => 'Needs attention',
        _ => 'Not connected',
      };
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

  static int _int(Object? value) => value is num ? value.round() : 0;

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
