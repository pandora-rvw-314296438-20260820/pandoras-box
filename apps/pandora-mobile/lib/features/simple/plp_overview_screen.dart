import 'package:flutter/material.dart';
import '../../core/data/plp_overview_repository.dart';
import '../../core/widgets/pandora_page.dart';
import 'ask_pandora_screen.dart';
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
        subtitle: 'Your property at a glance.',
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
        const SizedBox(height: 12),
        _quickActions(),
        const SizedBox(height: 12),
        if (connected) ...[
          _metrics(data),
          const SizedBox(height: 12),
          _insight(data),
          const SizedBox(height: 12),
        ] else ...[
          _connectionState(data),
          const SizedBox(height: 12),
        ],
        _attention(data, connected),
        const SizedBox(height: 12),
        _handled(data, connected),
        const SizedBox(height: 12),
        _dataCoverage(data),
        const SizedBox(height: 10),
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
    return _panel(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: PandoraV2Colors.soft,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.hotel_rounded, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${overview['display_name'] ?? 'PLP Boracay'}',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                    connected
                        ? 'Live business view'
                        : 'Business view is being connected',
                    style: const TextStyle(
                        color: PandoraV2Colors.muted, fontSize: 13)),
                if (connected && asOf != null) ...[
                  const SizedBox(height: 4),
                  Text('Data as of ${_relative(asOf)}',
                      style: const TextStyle(
                          color: PandoraV2Colors.muted, fontSize: 11.5)),
                ],
              ],
            ),
          ),
          _statusChip(connected ? 'Live' : 'Connecting', connected),
        ],
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
    final metrics = <_Metric>[
      _Metric('Occupancy', _percent(o['occupancy_percent']), Icons.bed_rounded),
      _Metric(
          'Sales today', _money(o['revenue_today']), Icons.payments_outlined),
      _Metric('Rooms available', _count(o['rooms_available']),
          Icons.meeting_room_outlined),
      _Metric('Arrivals', _count(o['arrivals_today']), Icons.login_rounded),
      _Metric(
          'Departures', _count(o['departures_today']), Icons.logout_rounded),
      _Metric('Rooms ready', _count(o['rooms_ready']), Icons.task_alt_rounded),
    ];
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.insights_rounded, 'Today at a glance'),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 720 ? 3 : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 10) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final metric in metrics)
                    SizedBox(width: width, child: _metricCard(metric)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _metricCard(_Metric metric) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: PandoraV2Colors.soft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: PandoraV2Colors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(metric.icon, size: 18, color: PandoraV2Colors.muted),
            const SizedBox(height: 10),
            Text(metric.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(metric.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: PandoraV2Colors.muted, fontSize: 11.5)),
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
          const Icon(Icons.auto_awesome_rounded, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pandora insight',
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
                          minimumSize: const Size(0, 30),
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

  Widget _quickActions() => _panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(Icons.bolt_rounded, 'Quick actions'),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = (constraints.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                        width: width,
                        child: _actionButton(
                          'Ask Pandora',
                          Icons.chat_bubble_outline_rounded,
                          'How is PLP Boracay doing today? Use only verified connected business data and clearly identify anything unavailable.',
                        )),
                    SizedBox(
                        width: width,
                        child: _actionButton(
                          'Today’s report',
                          Icons.summarize_outlined,
                          'Prepare today’s PLP Boracay management report using only verified connected business data.',
                        )),
                    SizedBox(
                        width: width,
                        child: _actionButton(
                          'Create task',
                          Icons.add_task_rounded,
                          'Create a PLP Boracay management task. Ask me what needs to be done if my next message does not make it clear.',
                        )),
                  ],
                );
              },
            ),
          ],
        ),
      );

  Widget _actionButton(String label, IconData icon, String prompt) =>
      OutlinedButton.icon(
        onPressed: () => _openAsk(prompt),
        icon: Icon(icon, size: 17),
        label: Text(label, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          foregroundColor: PandoraV2Colors.ink,
          backgroundColor: PandoraV2Colors.soft,
          side: const BorderSide(color: PandoraV2Colors.line),
          minimumSize: const Size.fromHeight(46),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
        ),
      );

  void _openAsk(String prompt) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AskPandoraScreen(initialPrompt: prompt),
      ),
    );
  }

  Widget _panel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) =>
      Container(
        padding: padding,
        decoration: BoxDecoration(
          color: PandoraV2Colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: PandoraV2Colors.line),
        ),
        child: child,
      );

  Widget _sectionTitle(IconData icon, String title) => Row(
        children: [
          Icon(icon, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ],
      );

  Widget _statusChip(String label, bool healthy) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: PandoraV2Colors.soft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: PandoraV2Colors.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: healthy ? PandoraV2Colors.success : PandoraV2Colors.muted,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
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
