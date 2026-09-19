
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/data/enterprise_vision_repository.dart';
import '../../core/widgets/pandora_page.dart';
import '../../core/widgets/pandora_surface.dart';
import '../simple/pandora_v2_ui.dart';
import 'enterprise_vision_embed.dart';

typedef VisionAskPandora = void Function(
  String prompt,
  Map<String, String>? cameraSelection,
);

class EnterpriseVisionScreen extends StatefulWidget {
  const EnterpriseVisionScreen({
    super.key,
    this.onAskPandora,
  });

  final VisionAskPandora? onAskPandora;

  @override
  State<EnterpriseVisionScreen> createState() => _EnterpriseVisionScreenState();
}

class _EnterpriseVisionScreenState extends State<EnterpriseVisionScreen> {
  static final Uri _sourceUri = Uri.parse(
    'https://camstreamer.com/live/stream/47239-live-dong-jing-xin-su-ge-wu-ji-ting',
  );

  final EnterpriseVisionRepository _repository =
      const EnterpriseVisionRepository();

  EnterpriseVisionSnapshot? _snapshot;
  EnterpriseVisionCamera? _selectedCamera;
  bool _loading = true;
  bool _refreshing = false;
  bool _dataUnavailable = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh && mounted) setState(() => _refreshing = true);
    try {
      final snapshot = await _repository.load();
      if (!mounted) return;
      final priorId = _selectedCamera?.id;
      EnterpriseVisionCamera? selected;
      for (final camera in snapshot.cameras) {
        if (camera.id == priorId) {
          selected = camera;
          break;
        }
      }
      if (selected == null) {
        for (final camera in snapshot.cameras) {
          if (!camera.publicFeed && camera.analysisEnabled) {
            selected = camera;
            break;
          }
        }
      }
      setState(() {
        _snapshot = snapshot;
        _selectedCamera = selected;
        _dataUnavailable = false;
        _loading = false;
        _refreshing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dataUnavailable = true;
        _loading = false;
        _refreshing = false;
      });
    }
  }

  void _ask(String prompt) {
    widget.onAskPandora?.call(prompt, _selectedCamera?.selection);
  }

  Future<void> _openSource() async {
    await launchUrl(_sourceUri);
  }

  @override
  Widget build(BuildContext context) => PandoraPage(
        title: 'Vision Intelligence',
        subtitle:
            'Search, understand and act on authorized enterprise camera evidence.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _hero(),
            const SizedBox(height: 14),
            _metrics(),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 920;
                if (!wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _publicFeed(),
                      const SizedBox(height: 14),
                      _feedStatus(),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: _publicFeed()),
                    const SizedBox(width: 14),
                    Expanded(flex: 3, child: _feedStatus()),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            _authorizedCameras(),
            const SizedBox(height: 18),
            _quickAsk(),
            const SizedBox(height: 18),
            _eventsAndAlerts(),
            const SizedBox(height: 18),
            _capabilities(),
            const SizedBox(height: 18),
            _architecture(),
          ],
        ),
      );

  Widget _hero() => PandoraSurface(
        title: 'Operational vision',
        subtitle: 'Evidence first · human verification remains explicit',
        leading: const Icon(Icons.visibility_rounded),
        child: const Text(
          'Pandora can turn authorized camera frames into machine observations, '
          'events, alerts, searchable timelines, clip requests and incident '
          'reports. Public third-party feeds remain display-only.',
          style: TextStyle(
            color: PandoraV2Colors.muted,
            height: 1.45,
          ),
        ),
      );

  Widget _metrics() {
    final snapshot = _snapshot;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 820
            ? 4
            : constraints.maxWidth >= 500
                ? 2
                : 1;
        final width =
            (constraints.maxWidth - ((columns - 1) * 10)) / columns;
        final cards = <Widget>[
          _MetricCard(
            icon: Icons.videocam_outlined,
            label: 'Authorized live',
            value: _loading
                ? '—'
                : (snapshot?.liveAuthorizedCameras ?? 0).toString(),
          ),
          _MetricCard(
            icon: Icons.bolt_outlined,
            label: 'Events · 24h',
            value: _loading ? '—' : (snapshot?.events24h ?? 0).toString(),
          ),
          _MetricCard(
            icon: Icons.notifications_active_outlined,
            label: 'Open alerts',
            value: _loading ? '—' : (snapshot?.openAlerts ?? 0).toString(),
          ),
          _MetricCard(
            icon: Icons.assignment_outlined,
            label: 'Open incidents',
            value: _loading ? '—' : (snapshot?.incidentsOpen ?? 0).toString(),
          ),
        ];
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }

  Widget _publicFeed() => PandoraSurface(
        title: 'Live public feed',
        subtitle: 'Kabukicho · Shinjuku, Tokyo',
        leading: const Icon(Icons.live_tv_rounded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: const Color(0xFF111111),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      buildEnterpriseVisionEmbed(),
                      const Align(
                        alignment: Alignment.topLeft,
                        child: IgnorePointer(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: _LiveBadge(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Source: CamStreamer · Shinjuku Kabukicho 24/7 live street camera. '
              'This feed demonstrates live viewing; Pandora does not analyze or '
              'retain this public source.',
              style: TextStyle(
                color: PandoraV2Colors.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _openSource,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open live source'),
                ),
                FilledButton.icon(
                  onPressed: widget.onAskPandora == null
                      ? null
                      : () => _ask(
                            'Explain what Vision Intelligence can do with an '
                            'authorized enterprise camera. Do not claim the '
                            'public Kabukicho feed is being analyzed.',
                          ),
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Ask Pandora'),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _feedStatus() => PandoraSurface(
        title: 'Source status',
        subtitle: 'Public viewing and enterprise analysis are separated',
        leading: const Icon(Icons.verified_user_outlined),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusRow(
              icon: Icons.public_rounded,
              label: 'Public live source',
              value: 'CamStreamer · Kabukicho',
            ),
            SizedBox(height: 12),
            _StatusRow(
              icon: Icons.psychology_alt_outlined,
              label: 'Public-feed analysis',
              value: 'Off',
            ),
            SizedBox(height: 12),
            _StatusRow(
              icon: Icons.person_search_outlined,
              label: 'Identity / biometrics',
              value: 'Off by default',
            ),
            SizedBox(height: 12),
            _StatusRow(
              icon: Icons.inventory_2_outlined,
              label: 'Public-feed retention',
              value: 'None',
            ),
            SizedBox(height: 14),
            Divider(height: 1),
            SizedBox(height: 14),
            Text(
              'Enterprise-owned or otherwise authorized cameras use a separate '
              'governed path for analysis, event storage, alerting and retention.',
              style: TextStyle(
                color: PandoraV2Colors.muted,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ],
        ),
      );

  Widget _authorizedCameras() {
    final cameras = _snapshot?.cameras
            .where((camera) => !camera.publicFeed)
            .toList(growable: false) ??
        const <EnterpriseVisionCamera>[];

    return PandoraSurface(
      title: 'Authorized cameras',
      subtitle: _dataUnavailable
          ? 'Camera registry is unavailable in this session.'
          : cameras.isEmpty
              ? 'No enterprise-owned camera has been registered yet.'
              : 'Select a camera to scope Pandora questions and actions.',
      leading: const Icon(Icons.video_camera_back_outlined),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_dataUnavailable)
            const _EmptyPanel(
              icon: Icons.cloud_off_outlined,
              title: 'Live camera data unavailable',
              message:
                  'The public feed still works. Authorized camera evidence will '
                  'appear here when the signed-in enterprise session can read it.',
            )
          else if (cameras.isEmpty)
            const _EmptyPanel(
              icon: Icons.add_a_photo_outlined,
              title: 'Ready for enterprise cameras',
              message:
                  'The backend accepts RTSP, ONVIF, NVR, upload and edge-agent '
                  'registrations. Analysis stays off until the camera is '
                  'authorized and enabled.',
            )
          else
            ...cameras.map(
              (camera) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CameraTile(
                  camera: camera,
                  selected: camera.id == _selectedCamera?.id,
                  onTap: () => setState(() => _selectedCamera = camera),
                ),
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _refreshing ? null : () => _load(refresh: true),
                icon: _refreshing
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
              ),
              if (_selectedCamera != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Selected: ' + _selectedCamera!.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PandoraV2Colors.muted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickAsk() {
    const prompts = <_QuickAsk>[
      _QuickAsk(
        Icons.remove_red_eye_outlined,
        'What is happening now?',
        'What is happening on the selected authorized camera right now? '
            'Use only stored Vision evidence and state when the last analysis ran.',
      ),
      _QuickAsk(
        Icons.groups_outlined,
        'Count people',
        'How many people are visible in the latest analyzed frame on the selected camera?',
      ),
      _QuickAsk(
        Icons.directions_car_outlined,
        'Count vehicles',
        'How many vehicles are visible in the latest analyzed frame on the selected camera?',
      ),
      _QuickAsk(
        Icons.trending_up_rounded,
        'Crowding trend',
        'Is activity on the selected camera getting more crowded over the last hour?',
      ),
      _QuickAsk(
        Icons.warning_amber_rounded,
        'Unusual activity',
        'Show unusual activity detected on the selected camera during the last hour.',
      ),
      _QuickAsk(
        Icons.assignment_outlined,
        'Incident report',
        'Create an incident report from Vision events on the selected camera during the last hour.',
      ),
      _QuickAsk(
        Icons.notifications_active_outlined,
        'Restricted-area alert',
        'Alert me when the selected authorized camera records a restricted-zone entry.',
      ),
      _QuickAsk(
        Icons.content_cut_rounded,
        'Save last 10 minutes',
        'Extract and keep a clip from the selected authorized camera covering the last 10 minutes.',
      ),
    ];

    return PandoraSurface(
      title: 'Ask the cameras',
      subtitle:
          'Pandora queries stored machine observations and can take governed Vision actions.',
      leading: const Icon(Icons.auto_awesome_rounded),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final item in prompts)
            ActionChip(
              avatar: Icon(item.icon, size: 18),
              label: Text(item.label),
              onPressed: widget.onAskPandora == null
                  ? null
                  : () => _ask(item.prompt),
            ),
        ],
      ),
    );
  }

  Widget _eventsAndAlerts() {
    final events = _snapshot?.events ?? const <EnterpriseVisionEvent>[];
    final alerts = _snapshot?.alerts ?? const <EnterpriseVisionAlert>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        final eventPanel = PandoraSurface(
          title: 'Recent events',
          subtitle: 'Machine observations remain reviewable evidence',
          leading: const Icon(Icons.timeline_rounded),
          child: events.isEmpty
              ? const _EmptyPanel(
                  icon: Icons.event_available_outlined,
                  title: 'No stored events yet',
                  message:
                      'Events appear after an authorized camera sends analyzed frames.',
                )
              : Column(
                  children: [
                    for (final event in events.take(8))
                      _EventRow(event: event),
                  ],
                ),
        );
        final alertPanel = PandoraSurface(
          title: 'Alerts',
          subtitle: 'Rules fire only from recorded Vision events',
          leading: const Icon(Icons.notifications_active_outlined),
          child: alerts.isEmpty
              ? const _EmptyPanel(
                  icon: Icons.notifications_none_rounded,
                  title: 'No alerts',
                  message:
                      'Create a rule with Pandora for restricted-zone entry, '
                      'unattended objects, crowding, falls or after-hours activity.',
                )
              : Column(
                  children: [
                    for (final alert in alerts.take(8))
                      _AlertRow(
                        alert: alert,
                        onAsk: widget.onAskPandora == null
                            ? null
                            : () => _ask(
                                  'Explain Vision alert ' +
                                      alert.id +
                                      ', show its supporting evidence, and tell '
                                          'me what still needs human verification.',
                                ),
                      ),
                  ],
                ),
        );
        if (!wide) {
          return Column(
            children: [
              eventPanel,
              const SizedBox(height: 14),
              alertPanel,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: eventPanel),
            const SizedBox(width: 14),
            Expanded(child: alertPanel),
          ],
        );
      },
    );
  }

  Widget _capabilities() => PandoraSurface(
        title: 'Vision capabilities',
        subtitle:
            'Designed for enterprise-owned or otherwise authorized cameras',
        leading: const Icon(Icons.hub_outlined),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 840
                ? 3
                : width >= 520
                    ? 2
                    : 1;
            final cardWidth = (width - ((columns - 1) * 10)) / columns;
            const capabilities = <_Capability>[
              _Capability(
                Icons.manage_search_rounded,
                'Search footage',
                'Ask for moments, objects, clothing descriptions, vehicles, '
                    'visible text or events instead of scrubbing manually.',
              ),
              _Capability(
                Icons.center_focus_strong_rounded,
                'Detect & count',
                'Store observable people, vehicles, objects, OCR text, zones '
                    'and counts as machine observations.',
              ),
              _Capability(
                Icons.timeline_rounded,
                'Build timelines',
                'Correlate camera events with source timestamps and explicit '
                    'machine-versus-human verification state.',
              ),
              _Capability(
                Icons.route_outlined,
                'Anonymous tracks',
                'Use temporary non-identity track keys for continuity. Pandora '
                    'does not identify real people from appearance.',
              ),
              _Capability(
                Icons.content_cut_rounded,
                'Extract clips',
                'Queue the relevant recording interval while retaining source '
                    'provenance and integrity metadata.',
              ),
              _Capability(
                Icons.notifications_active_outlined,
                'Rules & alerts',
                'Trigger governed alerts for restricted areas, crowding, '
                    'loitering, falls, unattended objects and configured events.',
              ),
              _Capability(
                Icons.report_outlined,
                'Incident reports',
                'Build reviewable incident records from stored events without '
                    'promoting machine observations to facts.',
              ),
              _Capability(
                Icons.query_stats_rounded,
                'Operational analytics',
                'Compare counts, activity levels and event frequencies across '
                    'time windows and cameras.',
              ),
              _Capability(
                Icons.auto_awesome_rounded,
                'Pandora Chat',
                'Ask natural-language questions and take governed Vision actions '
                    'from the same Enterprise workspace.',
              ),
            ];
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final capability in capabilities)
                  SizedBox(
                    width: cardWidth,
                    child: _CapabilityCard(capability: capability),
                  ),
              ],
            );
          },
        ),
      );

  Widget _architecture() => PandoraSurface(
        title: 'Authorized camera path',
        subtitle: 'Camera evidence remains attributable from ingest to result',
        leading: const Icon(Icons.account_tree_outlined),
        child: const Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _PathChip(icon: Icons.videocam_outlined, label: 'Camera / NVR'),
            Icon(Icons.arrow_forward_rounded,
                size: 18, color: PandoraV2Colors.muted),
            _PathChip(icon: Icons.memory_rounded, label: 'Edge / ingest'),
            Icon(Icons.arrow_forward_rounded,
                size: 18, color: PandoraV2Colors.muted),
            _PathChip(icon: Icons.psychology_outlined, label: 'Vision analysis'),
            Icon(Icons.arrow_forward_rounded,
                size: 18, color: PandoraV2Colors.muted),
            _PathChip(icon: Icons.fact_check_outlined, label: 'Events & review'),
            Icon(Icons.arrow_forward_rounded,
                size: 18, color: PandoraV2Colors.muted),
            _PathChip(icon: Icons.auto_awesome_rounded, label: 'Pandora'),
          ],
        ),
      );
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xD9111111),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 8, color: Color(0xFFF04B45)),
              SizedBox(width: 6),
              Text(
                'LIVE KABUKICHO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .55,
                ),
              ),
            ],
          ),
        ),
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 96),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: PandoraV2Colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: PandoraV2Colors.muted),
        ),
        child: Row(
          children: [
            Icon(icon, size: 23),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: const TextStyle(
                      color: PandoraV2Colors.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: PandoraV2Colors.ink),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: PandoraV2Colors.muted,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class _CameraTile extends StatelessWidget {
  const _CameraTile({
    required this.camera,
    required this.selected,
    required this.onTap,
  });

  final EnterpriseVisionCamera camera;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? PandoraV2Colors.soft : PandoraV2Colors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color:
                    selected ? PandoraV2Colors.ink : PandoraV2Colors.muted,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  camera.sourceStatus == 'live'
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_outlined,
                  size: 22,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        camera.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if (camera.locationLabel.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          camera.locationLabel,
                          style: const TextStyle(
                            color: PandoraV2Colors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 7,
                        runSpacing: 4,
                        children: [
                          _TinyLabel(camera.sourceStatus),
                          _TinyLabel(
                            camera.analysisEnabled
                                ? 'analysis on'
                                : 'analysis off',
                          ),
                          _TinyLabel(
                            camera.anonymousTrackingEnabled
                                ? 'anonymous tracking'
                                : 'tracking off',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle_rounded, size: 21),
              ],
            ),
          ),
        ),
      );
}

class _TinyLabel extends StatelessWidget {
  const _TinyLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: PandoraV2Colors.soft,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: PandoraV2Colors.muted,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _QuickAsk {
  const _QuickAsk(this.icon, this.label, this.prompt);
  final IconData icon;
  final String label;
  final String prompt;
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});
  final EnterpriseVisionEvent event;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              event.severity == 'critical'
                  ? Icons.error_outline_rounded
                  : event.severity == 'warning'
                      ? Icons.warning_amber_rounded
                      : Icons.bolt_outlined,
              size: 20,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (event.description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      event.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PandoraV2Colors.muted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    event.humanState + ' · ' + event.startedAt,
                    style: const TextStyle(
                      color: PandoraV2Colors.muted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.alert,
    required this.onAsk,
  });

  final EnterpriseVisionAlert alert;
  final VoidCallback? onAsk;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.notifications_active_outlined, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    alert.message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PandoraV2Colors.muted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    alert.status + ' · ' + alert.severity,
                    style: const TextStyle(
                      color: PandoraV2Colors.muted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Ask Pandora',
              onPressed: onAsk,
              icon: const Icon(Icons.auto_awesome_rounded, size: 19),
            ),
          ],
        ),
      );
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 23),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(
                      color: PandoraV2Colors.muted,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Capability {
  const _Capability(this.icon, this.title, this.description);
  final IconData icon;
  final String title;
  final String description;
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({required this.capability});
  final _Capability capability;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 148),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: PandoraV2Colors.soft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: PandoraV2Colors.muted),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(capability.icon, size: 22),
            const SizedBox(height: 10),
            Text(
              capability.title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              capability.description,
              style: const TextStyle(
                color: PandoraV2Colors.muted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
}

class _PathChip extends StatelessWidget {
  const _PathChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: PandoraV2Colors.soft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: PandoraV2Colors.muted),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
}
