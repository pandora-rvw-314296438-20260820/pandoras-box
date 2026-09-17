import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import '../../pandora_config.dart';
import 'ask_pandora_screen.dart';
import 'pandora_v2_ui.dart';

class PlpOverviewScreen extends StatefulWidget {
  const PlpOverviewScreen({super.key, required this.description});

  final String description;

  @override
  State<PlpOverviewScreen> createState() => _PlpOverviewScreenState();
}

class _PlpOverviewScreenState extends State<PlpOverviewScreen> {
  late Future<_PlpOverviewData> _data;

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

  Future<_PlpOverviewData> _load() async {
    final client = Supabase.instance.client;
    Map<String, dynamic>? plpProject;
    List<Map<String, dynamic>> events = const [];

    try {
      final rows = await client
          .from('projectos_projects')
          .select(
            'id,project_key,name,repository,status,objective,config,updated_at',
          )
          .eq('organization_id', PandoraConfig.organizationId)
          .neq('status', 'archived')
          .order('updated_at', ascending: false);
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw);
        final haystack =
            '${row['project_key']} ${row['name']} ${row['repository']} ${row['objective']}'
                .toLowerCase();
        final config = _map(row['config']);
        if ((haystack.contains('plp') ||
                haystack.contains('pueblo') ||
                haystack.contains('boracay')) &&
            config['enterpriseManaged'] == true) {
          plpProject = row;
          break;
        }
      }
    } catch (_) {
      plpProject = null;
    }

    try {
      final rows = await client
          .from('audit_events')
          .select('id,event_type,payload_redacted,created_at')
          .eq('organization_id', PandoraConfig.organizationId)
          .order('created_at', ascending: false)
          .limit(80);
      events = rows
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    } catch (_) {
      events = const [];
    }

    final config = _map(plpProject?['config']);
    final profile = _map(config['enterpriseProfile']);
    final operations = _map(profile['hotelOperations']).isNotEmpty
        ? _map(profile['hotelOperations'])
        : _map(config['hotelOperations']);

    return _PlpOverviewData(
      project: plpProject,
      profile: profile,
      operations: operations,
      attention: _attention(events),
      handled: _handled(events),
      refreshedAt: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) => PandoraPage(
        title: 'Overview',
        subtitle: widget.description,
        onRefresh: _refresh,
        child: FutureBuilder<_PlpOverviewData>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return _unavailable();
            }
            return _content(snapshot.data!);
          },
        ),
      );

  Widget _unavailable() => PandoraSurface(
        title: 'PLP overview unavailable',
        subtitle: 'Pandora could not refresh the Enterprise overview.',
        leading: const Icon(Icons.cloud_off_outlined),
        child: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ),
      );

  Widget _content(_PlpOverviewData data) {
    final project = data.project;
    final connected = data.operations.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PandoraSurface(
          title: 'PLP Boracay',
          subtitle: 'Business command center',
          leading: const Icon(Icons.hotel_rounded),
          trailing: _statusPill(
            connected
                ? 'Live operations connected'
                : 'Operations not connected',
            connected,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                connected
                    ? 'Live hotel operations are available to Pandora.'
                    : 'Pandora has the PLP system context, but booking, sales, room and housekeeping feeds are not connected yet.',
              ),
              if (project != null) ...[
                const SizedBox(height: 10),
                Text(
                  '${project['repository'] ?? 'PLP source'} • ${project['status'] ?? 'managed'}',
                  style: const TextStyle(color: PandoraV2Colors.muted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _businessSnapshot(data),
        const SizedBox(height: 14),
        _movement(data),
        const SizedBox(height: 14),
        _attentionCard(data),
        const SizedBox(height: 14),
        _handledCard(data),
        const SizedBox(height: 14),
        _quickActions(),
        const SizedBox(height: 10),
        Text(
          'Refreshed ${_time(data.refreshedAt)}',
          textAlign: TextAlign.right,
          style: const TextStyle(color: PandoraV2Colors.muted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _businessSnapshot(_PlpOverviewData data) {
    final ops = data.operations;
    return PandoraSurface(
      title: 'Today',
      subtitle: 'Current business snapshot',
      leading: const Icon(Icons.insights_rounded),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          final width =
              wide ? (constraints.maxWidth - 24) / 3 : constraints.maxWidth;
          final cards = <Widget>[
            _metric(
              'Occupancy',
              _percent(ops['occupancyPercent']),
              Icons.bed_rounded,
            ),
            _metric(
              'Sales today',
              _money(ops['salesTodayPhp']),
              Icons.payments_outlined,
            ),
            _metric(
              'Rooms available',
              _count(ops['roomsAvailable']),
              Icons.meeting_room_outlined,
            ),
          ];
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final card in cards) SizedBox(width: width, child: card),
            ],
          );
        },
      ),
    );
  }

  Widget _movement(_PlpOverviewData data) {
    final ops = data.operations;
    return PandoraSurface(
      title: 'Guest movement',
      subtitle: 'Arrivals and departures for today',
      leading: const Icon(Icons.swap_horiz_rounded),
      child: Row(
        children: [
          Expanded(
            child: _metric(
              'Arriving',
              _count(ops['arrivalsToday']),
              Icons.login_rounded,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _metric(
              'Departing',
              _count(ops['departuresToday']),
              Icons.logout_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _attentionCard(_PlpOverviewData data) => PandoraSurface(
        title: 'Needs your attention',
        subtitle: data.operations.isEmpty
            ? 'Business alerts will appear here after PLP operational feeds are connected.'
            : 'Issues Pandora has not resolved automatically.',
        leading: const Icon(Icons.priority_high_rounded),
        child: data.attention.isEmpty
            ? const Text(
                'No current Pandora system blockers were found in recent evidence.',
              )
            : Column(
                children: [
                  for (final item in data.attention.take(4))
                    _eventRow(item, warning: true),
                ],
              ),
      );

  Widget _handledCard(_PlpOverviewData data) => PandoraSurface(
        title: 'Pandora handled',
        subtitle: 'Recent verified or completed system activity',
        leading: const Icon(Icons.auto_awesome_rounded),
        child: data.handled.isEmpty
            ? const Text('No recent completed activity is available to show.')
            : Column(
                children: [
                  for (final item in data.handled.take(5)) _eventRow(item),
                ],
              ),
      );

  Widget _quickActions() => PandoraSurface(
        title: 'Quick actions',
        subtitle: 'Ask Pandora in PLP business context',
        leading: const Icon(Icons.bolt_rounded),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _action(
              'Ask Pandora',
              Icons.chat_bubble_outline_rounded,
              'How is PLP Boracay doing today? Use only connected live business data and clearly identify anything that is unavailable.',
            ),
            _action(
              'Today’s report',
              Icons.summarize_outlined,
              'Prepare today’s PLP Boracay management report using only connected live data. Include occupancy, sales, arrivals, departures, issues and actions Pandora handled.',
            ),
            _action(
              'Create task',
              Icons.add_task_rounded,
              'Create a PLP Boracay management task. Ask me for the task only if the objective is not clear from my next message.',
            ),
          ],
        ),
      );

  Widget _action(String label, IconData icon, String prompt) =>
      OutlinedButton.icon(
        onPressed: () => _openAsk(prompt),
        icon: Icon(icon, size: 18),
        label: Text(label),
      );

  void _openAsk(String prompt) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AskPandoraScreen(initialPrompt: prompt),
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: PandoraV2Colors.soft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: PandoraV2Colors.line),
        ),
        child: Row(
          children: [
            Icon(icon, color: PandoraV2Colors.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: PandoraV2Colors.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    value,
                    style: const TextStyle(
                      color: PandoraV2Colors.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _eventRow(_OverviewEvent item, {bool warning = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              warning
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              size: 18,
              color:
                  warning ? PandoraV2Colors.warning : PandoraV2Colors.success,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title),
                  if (item.detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.detail,
                      style: const TextStyle(
                        color: PandoraV2Colors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  Widget _statusPill(String label, bool ready) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: PandoraV2Colors.soft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: PandoraV2Colors.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: ready ? PandoraV2Colors.success : PandoraV2Colors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  static String _percent(Object? value) {
    if (value is num) {
      return '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}%';
    }
    return '—';
  }

  static String _money(Object? value) {
    if (value is! num) return '—';
    final whole = value.round().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
      buffer.write(whole[i]);
    }
    return '₱${buffer.toString()}';
  }

  static String _count(Object? value) =>
      value is num ? '${value.round()}' : '—';

  static String _time(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<_OverviewEvent> _attention(List<Map<String, dynamic>> events) {
    final result = <_OverviewEvent>[];
    for (final event in events) {
      final payload = _map(event['payload_redacted']);
      final state =
          '${payload['state'] ?? payload['outcome'] ?? ''}'.toLowerCase();
      if (!const {
        'failed',
        'failing',
        'missing',
        'mismatched',
        'unavailable',
        'degraded',
      }.contains(state)) {
        continue;
      }
      result.add(_eventFrom(event, payload));
    }
    return result;
  }

  static List<_OverviewEvent> _handled(List<Map<String, dynamic>> events) {
    final result = <_OverviewEvent>[];
    for (final event in events) {
      final payload = _map(event['payload_redacted']);
      final state =
          '${payload['state'] ?? payload['outcome'] ?? ''}'.toLowerCase();
      if (!const {
        'completed',
        'verified',
        'healthy',
        'success',
        'succeeded',
      }.contains(state)) {
        continue;
      }
      result.add(_eventFrom(event, payload));
    }
    return result;
  }

  static _OverviewEvent _eventFrom(
    Map<String, dynamic> event,
    Map<String, dynamic> payload,
  ) {
    final provider = '${payload['provider'] ?? ''}'.trim();
    final resource = '${payload['resourceId'] ?? payload['tool'] ?? ''}'.trim();
    final summary = '${payload['summary'] ?? ''}'.trim();
    final state = '${payload['state'] ?? payload['outcome'] ?? ''}'.trim();
    final title = summary.isNotEmpty
        ? summary
        : resource.isNotEmpty
            ? resource
            : '${event['event_type'] ?? 'Pandora activity'}';
    final parts = <String>[
      if (provider.isNotEmpty) provider,
      if (state.isNotEmpty) state,
    ];
    return _OverviewEvent(title: title, detail: parts.join(' • '));
  }
}

class _PlpOverviewData {
  const _PlpOverviewData({
    required this.project,
    required this.profile,
    required this.operations,
    required this.attention,
    required this.handled,
    required this.refreshedAt,
  });

  final Map<String, dynamic>? project;
  final Map<String, dynamic> profile;
  final Map<String, dynamic> operations;
  final List<_OverviewEvent> attention;
  final List<_OverviewEvent> handled;
  final DateTime refreshedAt;
}

class _OverviewEvent {
  const _OverviewEvent({required this.title, required this.detail});

  final String title;
  final String detail;
}
