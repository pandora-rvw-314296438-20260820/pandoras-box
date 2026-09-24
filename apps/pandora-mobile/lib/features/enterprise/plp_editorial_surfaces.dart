import 'package:flutter/material.dart';

import '../../core/widgets/pandora_navigation.dart';
import 'enterprise_vision_embed.dart';

const plpCanvas = Color(0xFF050505);
const plpPaper = Color(0xFF0E0E0F);
const plpWarm = Color(0xFF17130D);
const plpInk = Color(0xFFF2EEE7);
const plpMuted = Color(0xFFA49D93);
const plpLine = Color(0xFF2C2924);
const plpAccent = Color(0xFFD6AD63);
const plpGood = Color(0xFF8FA889);
const plpWarn = Color(0xFFD4934C);

Map<String, Object?> _plpMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const <String, Object?>{};
}

List<Map<String, Object?>> _plpMaps(Object? value) {
  if (value is! List) return const <Map<String, Object?>>[];
  return value
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
      .toList(growable: false);
}

String _plpText(Object? value, {String fallback = '-'}) {
  final normalized = value?.toString().trim();
  return normalized == null || normalized.isEmpty ? fallback : normalized;
}

num _plpNumber(Object? value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

String _plpInt(Object? value) => _plpNumber(value).round().toString();

String _plpPeso(Object? value) {
  final amount = _plpNumber(value).round();
  final digits = amount.abs().toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return (amount < 0 ? '-\u20B1' : '\u20B1') + out.toString();
}

class PlpEditorialHeader extends StatelessWidget {
  const PlpEditorialHeader({
    super.key,
    required this.title,
    required this.onOpenNavigation,
    this.trailing,
  });

  final String title;
  final VoidCallback onOpenNavigation;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          if (PandoraNavigationScope.maybeOf(context)?.openDrawer != null) ...[
            PandoraMenuButton(
              key: ValueKey<String>(
                'plp-editorial-menu-${title.toLowerCase()}',
              ),
              onPressed: onOpenNavigation,
            ),
            const SizedBox(width: 12),
          ] else
            const SizedBox.square(dimension: 44),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PUEBLO LA PERLA',
                  style: TextStyle(
                    color: plpInk,
                    fontFamily: 'serif',
                    fontSize: 16,
                    letterSpacing: 2.6,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: plpAccent,
                    fontSize: 8.5,
                    letterSpacing: 2.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      );
}

class PlpEditorialPage extends StatelessWidget {
  const PlpEditorialPage({
    super.key,
    required this.pageKey,
    required this.eyebrow,
    required this.title,
    required this.intro,
    required this.onOpenNavigation,
    required this.children,
  });

  final Key pageKey;
  final String eyebrow;
  final String title;
  final String intro;
  final VoidCallback onOpenNavigation;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
        color: plpCanvas,
        child: SafeArea(
          bottom: false,
          child: ListView(
            key: pageKey,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 190),
            children: [
              PlpEditorialHeader(
                title: eyebrow,
                onOpenNavigation: onOpenNavigation,
              ),
              const SizedBox(height: 38),
              PlpEyebrow(eyebrow),
              const SizedBox(height: 13),
              Text(
                title,
                style: const TextStyle(
                  color: plpInk,
                  fontFamily: 'serif',
                  fontSize: 43,
                  height: 0.98,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -1.4,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                intro,
                style: const TextStyle(
                  color: plpMuted,
                  fontSize: 14.5,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 28),
              const Divider(height: 1, color: plpLine),
              ...children,
            ],
          ),
        ),
      );
}

class PlpEyebrow extends StatelessWidget {
  const PlpEyebrow(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: plpAccent,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      );
}

class PlpSectionTitle extends StatelessWidget {
  const PlpSectionTitle(this.title, {super.key, this.detail});
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: plpInk,
                fontFamily: 'serif',
                fontSize: 29,
                height: 1.02,
                fontWeight: FontWeight.w400,
                letterSpacing: -0.5,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 7),
              Text(
                detail!,
                style: const TextStyle(
                  color: plpMuted,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      );
}

class PlpMetricStrip extends StatelessWidget {
  const PlpMetricStrip({super.key, required this.items});
  final List<(String, String, String)> items;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0)
                const VerticalDivider(
                  width: 22,
                  thickness: 1,
                  color: plpLine,
                ),
              Expanded(
                child: _PlpMetric(
                  label: items[index].$1,
                  value: items[index].$2,
                  detail: items[index].$3,
                ),
              ),
            ],
          ],
        ),
      );
}

class _PlpMetric extends StatelessWidget {
  const _PlpMetric({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: plpMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: plpInk,
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
            style: const TextStyle(
              color: plpMuted,
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
        ],
      );
}

class PlpEditorialRow extends StatelessWidget {
  const PlpEditorialRow({
    super.key,
    required this.title,
    required this.detail,
    this.value,
    this.onTap,
    this.tone,
  });

  final String title;
  final String detail;
  final String? value;
  final VoidCallback? onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: plpLine)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 17),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tone != null) ...[
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(top: 6),
                    color: tone,
                  ),
                  const SizedBox(width: 11),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: plpInk,
                          fontFamily: 'serif',
                          fontSize: 20,
                          height: 1.05,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        detail,
                        style: const TextStyle(
                          color: plpMuted,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    value!,
                    style: const TextStyle(
                      color: plpInk,
                      fontFamily: 'serif',
                      fontSize: 28,
                      height: 1,
                    ),
                  ),
                ] else if (onTap != null) ...[
                  const SizedBox(width: 12),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: plpInk,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

class PlpBlackPanel extends StatelessWidget {
  const PlpBlackPanel({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.body,
    this.action,
    this.onTap,
  });

  final String eyebrow;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: plpPaper,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 21),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFDDBF86),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'serif',
                    fontSize: 29,
                    height: 1.03,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFFAFA9A0),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Text(
                        action!.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.7,
                        ),
                      ),
                      const SizedBox(width: 7),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 17,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

class PlpOverviewScreen extends StatelessWidget {
  const PlpOverviewScreen({
    super.key,
    required this.bootstrap,
    required this.onOpenNavigation,
    required this.onAskPandora,
  });

  final Map<String, Object?> bootstrap;
  final VoidCallback onOpenNavigation;
  final VoidCallback onAskPandora;

  @override
  Widget build(BuildContext context) {
    final today = _plpMap(bootstrap['today']);
    final source = _plpMap(bootstrap['sourceHealth']);
    final occupancy = _plpText(today['occupancy_percent'], fallback: '0');
    final rooms = _plpInt(today['rooms_total']);
    final occupied = _plpInt(today['occupied_rooms']);
    final available = _plpInt(today['rooms_available']);
    final arrivals = _plpInt(today['arrivals_today']);
    final departures = _plpInt(today['departures_today']);
    final conflicts = _plpInt(today['open_ota_conflicts']);
    final tasks = _plpInt(today['open_staff_tasks']);

    return PlpEditorialPage(
      pageKey: const ValueKey('plp-overview-editorial'),
      eyebrow: 'Overview',
      title: 'The resort, in one quiet view.',
      intro:
          'Today\'s operating picture without dashboard noise: occupancy, movement, revenue, exceptions, and the decisions that need the owner.',
      onOpenNavigation: onOpenNavigation,
      children: [
        const SizedBox(height: 24),
        PlpMetricStrip(
          items: [
            ('Occupancy', '$occupancy%', '$occupied of $rooms rooms'),
            ('Revenue', _plpPeso(today['sales_today_php']), 'today'),
            ('Available', available, 'rooms'),
          ],
        ),
        const PlpSectionTitle(
          'Movement today',
          detail: 'Arrivals and departures shape the operating rhythm.',
        ),
        PlpEditorialRow(
          title: 'Arrivals',
          detail: 'Guests expected today',
          value: arrivals,
        ),
        PlpEditorialRow(
          title: 'Departures',
          detail: 'Stays concluding today',
          value: departures,
        ),
        const PlpSectionTitle(
          'Attention',
          detail: 'Only exceptions and decisions should interrupt the owner.',
        ),
        PlpEditorialRow(
          title: 'OTA conflicts',
          detail: conflicts == '0'
              ? 'No channel conflicts are open.'
              : 'Review channel conflicts before the next arrival.',
          value: conflicts,
          tone: conflicts == '0' ? plpGood : plpWarn,
        ),
        PlpEditorialRow(
          title: 'Open staff work',
          detail: tasks == '0'
              ? 'No staff tasks are waiting.'
              : 'Work remains open across the resort.',
          value: tasks,
          tone: tasks == '0' ? plpGood : plpAccent,
        ),
        const SizedBox(height: 28),
        PlpBlackPanel(
          eyebrow: 'Pandora',
          title: 'Turn the overview into action.',
          body:
              'Ask for the reason behind a number, resolve an exception, prepare a briefing, or coordinate the next move.',
          action: 'Message Pandora',
          onTap: onAskPandora,
        ),
        const SizedBox(height: 28),
        PlpEditorialRow(
          title: _plpText(source['state'], fallback: 'Source status'),
          detail: _plpText(
            source['message'],
            fallback: 'No provider status message.',
          ),
          tone: _plpText(source['state']).toLowerCase() == 'healthy'
              ? plpGood
              : plpWarn,
        ),
      ],
    );
  }
}

class PlpOperationsScreen extends StatelessWidget {
  const PlpOperationsScreen({
    super.key,
    required this.bootstrap,
    required this.onOpenNavigation,
    required this.onOpenRoom,
    required this.onAskPandora,
  });

  final Map<String, Object?> bootstrap;
  final VoidCallback onOpenNavigation;
  final VoidCallback onOpenRoom;
  final VoidCallback onAskPandora;

  @override
  Widget build(BuildContext context) {
    final today = _plpMap(bootstrap['today']);
    final arrivals = _plpInt(today['arrivals_today']);
    final departures = _plpInt(today['departures_today']);
    final tasks = _plpInt(today['open_staff_tasks']);
    final conflicts = _plpInt(today['open_ota_conflicts']);

    return PlpEditorialPage(
      pageKey: const ValueKey('plp-operations-editorial'),
      eyebrow: 'Operations',
      title: 'The resort in motion.',
      intro:
          'A calm operating layer for arrivals, departures, staff work, exceptions, and coordinated execution.',
      onOpenNavigation: onOpenNavigation,
      children: [
        const SizedBox(height: 24),
        PlpMetricStrip(
          items: [
            ('Arrivals', arrivals, 'today'),
            ('Departures', departures, 'today'),
            ('Open work', tasks, 'staff tasks'),
          ],
        ),
        const PlpSectionTitle(
          'Today\'s operating rhythm',
          detail:
              'Sequence the work around guest movement instead of a generic task board.',
        ),
        PlpEditorialRow(
          title: 'Arrival readiness',
          detail: arrivals == '0'
              ? 'No arrivals are scheduled today.'
              : '$arrivals arrival(s) should be checked against transport, room readiness, and special requests.',
          tone: arrivals == '0' ? plpGood : plpAccent,
        ),
        PlpEditorialRow(
          title: 'Departure readiness',
          detail: departures == '0'
              ? 'No departures are scheduled today.'
              : '$departures departure(s) affect housekeeping, transport, and room turnover.',
          tone: plpAccent,
        ),
        PlpEditorialRow(
          title: 'Channel exceptions',
          detail: conflicts == '0'
              ? 'No OTA conflicts are open.'
              : '$conflicts conflict(s) need reconciliation.',
          value: conflicts,
          tone: conflicts == '0' ? plpGood : plpWarn,
        ),
        const SizedBox(height: 28),
        PlpBlackPanel(
          eyebrow: 'Operations Room',
          title: 'Coordinate the difficult work.',
          body:
              'Open Pandora\'s governed Operations Room when the task needs specialists, execution evidence, or incident coordination.',
          action: 'Open Operations Room',
          onTap: onOpenRoom,
        ),
        const SizedBox(height: 14),
        PlpEditorialRow(
          title: 'Ask Pandora',
          detail: 'Brief, assign, verify, or resolve resort operations.',
          onTap: onAskPandora,
        ),
      ],
    );
  }
}

class PlpVisionScreen extends StatelessWidget {
  const PlpVisionScreen({
    super.key,
    required this.onOpenNavigation,
    required this.onAskPandora,
  });

  final VoidCallback onOpenNavigation;
  final VoidCallback onAskPandora;

  @override
  Widget build(BuildContext context) => PlpEditorialPage(
        pageKey: const ValueKey('plp-vision-editorial'),
        eyebrow: 'Vision',
        title: 'See the property with context.',
        intro:
            'Vision should feel like part of resort operations: live views, verified observations, incidents, and the next action - not a wall of surveillance cards.',
        onOpenNavigation: onOpenNavigation,
        children: [
          const PlpSectionTitle(
            'Live view',
            detail:
                'Current demo feed. Customer-owned PLP cameras can replace this source under the same governed surface.',
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border.fromBorderSide(BorderSide(color: plpLine)),
              color: Colors.black,
            ),
            child: const AspectRatio(
              aspectRatio: 16 / 9,
              child: _PlpVisionEmbed(),
            ),
          ),
          const PlpSectionTitle(
            'Vision state',
            detail: 'Keep machine observation separate from verified fact.',
          ),
          PlpEditorialRow(
            title: 'Display',
            detail: enterpriseVisionEmbedAvailable
                ? 'Live source is visible in the owner workspace.'
                : 'Live public camera preview is unavailable on this platform.',
            value: enterpriseVisionEmbedAvailable ? 'Live' : 'Unavailable',
            tone: enterpriseVisionEmbedAvailable ? plpGood : plpAccent,
          ),
          const PlpEditorialRow(
            title: 'Automated analysis',
            detail:
                'Not active for this public demo source. PLP-owned feeds can be governed separately.',
            value: 'Off',
            tone: plpAccent,
          ),
          const PlpEditorialRow(
            title: 'Verified incident',
            detail: 'No verified incident is attached to this display feed.',
            value: 'None',
            tone: plpGood,
          ),
          const SizedBox(height: 28),
          PlpBlackPanel(
            eyebrow: 'Pandora Vision',
            title: 'Ask about what matters.',
            body:
                'Search an authorized feed, review an incident, build a timeline, or prepare an owner summary once verified camera events exist.',
            action: 'Ask Pandora',
            onTap: onAskPandora,
          ),
        ],
      );
}

class _PlpVisionEmbed extends StatelessWidget {
  const _PlpVisionEmbed();

  @override
  Widget build(BuildContext context) => buildEnterpriseVisionEmbed();
}

class PlpRevenueScreen extends StatelessWidget {
  const PlpRevenueScreen({
    super.key,
    required this.bootstrap,
    required this.onOpenNavigation,
    required this.onAskPandora,
  });

  final Map<String, Object?> bootstrap;
  final VoidCallback onOpenNavigation;
  final VoidCallback onAskPandora;

  @override
  Widget build(BuildContext context) {
    final today = _plpMap(bootstrap['today']);
    final occupancy = _plpText(today['occupancy_percent'], fallback: '0');
    final occupied = _plpInt(today['occupied_rooms']);
    final rooms = _plpInt(today['rooms_total']);
    final available = _plpInt(today['rooms_available']);
    final sales = _plpPeso(today['sales_today_php']);

    return PlpEditorialPage(
      pageKey: const ValueKey('plp-revenue-editorial'),
      eyebrow: 'Revenue',
      title: sales,
      intro:
          'Revenue should read like an owner\'s financial page: one clear number first, then the operating facts that explain it.',
      onOpenNavigation: onOpenNavigation,
      children: [
        const SizedBox(height: 24),
        PlpMetricStrip(
          items: [
            ('Occupancy', '$occupancy%', '$occupied of $rooms rooms'),
            ('Available', available, 'rooms'),
            ('Sales', sales, 'today'),
          ],
        ),
        const PlpSectionTitle(
          'What is shaping today',
          detail:
              'Availability, occupancy, and exceptions are the first layer behind revenue movement.',
        ),
        PlpEditorialRow(
          title: 'Occupied inventory',
          detail: '$occupied of $rooms rooms are occupied.',
          value: occupied,
        ),
        PlpEditorialRow(
          title: 'Sellable inventory',
          detail: 'Rooms still available to sell.',
          value: available,
        ),
        PlpEditorialRow(
          title: 'Channel conflicts',
          detail:
              'Open OTA conflicts can affect availability and booking confidence.',
          value: _plpInt(today['open_ota_conflicts']),
          tone: _plpNumber(today['open_ota_conflicts']) == 0
              ? plpGood
              : plpWarn,
        ),
        const SizedBox(height: 28),
        PlpBlackPanel(
          eyebrow: 'Revenue intelligence',
          title: 'Interrogate the number.',
          body:
              'Ask Pandora for variance, booking-channel context, occupancy implications, or the next commercial action.',
          action: 'Ask Pandora',
          onTap: onAskPandora,
        ),
      ],
    );
  }
}

class PlpNeedsYouScreen extends StatelessWidget {
  const PlpNeedsYouScreen({
    super.key,
    required this.bootstrap,
    required this.onOpenNavigation,
    required this.onOpenApprovals,
    required this.onAskPandora,
  });

  final Map<String, Object?> bootstrap;
  final VoidCallback onOpenNavigation;
  final VoidCallback onOpenApprovals;
  final VoidCallback onAskPandora;

  @override
  Widget build(BuildContext context) {
    final today = _plpMap(bootstrap['today']);
    final conflicts = _plpInt(today['open_ota_conflicts']);
    final tasks = _plpInt(today['open_staff_tasks']);
    final clear = conflicts == '0' && tasks == '0';

    return PlpEditorialPage(
      pageKey: const ValueKey('plp-needs-you-editorial'),
      eyebrow: 'Needs You',
      title: clear ? 'Nothing urgent needs you.' : 'Only the decisions that matter.',
      intro:
          'This surface stays deliberately quiet. Routine work belongs to Pandora and the team; owner attention is reserved for genuine decisions, risk, and exceptions.',
      onOpenNavigation: onOpenNavigation,
      children: [
        const SizedBox(height: 24),
        PlpEditorialRow(
          title: 'OTA conflicts',
          detail: conflicts == '0'
              ? 'No booking-channel conflict needs an owner decision.'
              : '$conflicts conflict(s) are open and should be reviewed.',
          value: conflicts,
          tone: conflicts == '0' ? plpGood : plpWarn,
        ),
        PlpEditorialRow(
          title: 'Open staff work',
          detail: tasks == '0'
              ? 'No staff task is currently escalated.'
              : '$tasks task(s) remain open; Pandora can determine which truly need you.',
          value: tasks,
          tone: tasks == '0' ? plpGood : plpAccent,
        ),
        const SizedBox(height: 28),
        PlpBlackPanel(
          eyebrow: 'Approvals',
          title: 'Review consequential actions.',
          body:
              'Open the governed approvals surface for actions that actually require owner authorization.',
          action: 'Open approvals',
          onTap: onOpenApprovals,
        ),
        const SizedBox(height: 14),
        PlpEditorialRow(
          title: 'Ask Pandora what needs attention',
          detail: 'Have Pandora separate routine work from real owner decisions.',
          onTap: onAskPandora,
        ),
      ],
    );
  }
}

class PlpSettingsScreen extends StatelessWidget {
  const PlpSettingsScreen({
    super.key,
    required this.bootstrap,
    required this.onOpenNavigation,
    required this.onOpenFullSettings,
    required this.onOpenLocalAi,
    required this.onOpenDeveloper,
  });

  final Map<String, Object?> bootstrap;
  final VoidCallback onOpenNavigation;
  final VoidCallback onOpenFullSettings;
  final VoidCallback onOpenLocalAi;
  final VoidCallback onOpenDeveloper;

  @override
  Widget build(BuildContext context) {
    final team = _plpMap(bootstrap['teamAccess']);
    final members = _plpMaps(team['members']).length;
    final source = _plpMap(bootstrap['sourceHealth']);

    return PlpEditorialPage(
      pageKey: const ValueKey('plp-settings-editorial'),
      eyebrow: 'Settings',
      title: 'Keep the operating system calm.',
      intro:
          'Daily PLP controls stay simple. Technical machinery remains available, but it is pushed behind clear owner-facing boundaries.',
      onOpenNavigation: onOpenNavigation,
      children: [
        const PlpSectionTitle(
          'Workspace',
          detail: 'People, intelligence, and the operating environment.',
        ),
        PlpEditorialRow(
          title: 'Team & access',
          detail: '$members member(s) visible in the current PLP access model.',
          value: members.toString(),
        ),
        PlpEditorialRow(
          title: 'On-device AI',
          detail: 'Inspect the phone-resident local inference runtime.',
          onTap: onOpenLocalAi,
        ),
        const PlpSectionTitle(
          'Trust & system',
          detail:
              'Provider health and technical controls stay separate from daily resort work.',
        ),
        PlpEditorialRow(
          title: 'Provider state',
          detail: _plpText(
            source['message'],
            fallback: 'No provider status message.',
          ),
          value: _plpText(source['state'], fallback: 'Unknown'),
          tone: _plpText(source['state']).toLowerCase() == 'healthy'
              ? plpGood
              : plpWarn,
        ),
        PlpEditorialRow(
          title: 'Pandora settings',
          detail:
              'Open owner controls, connections, safety, Android recovery, and account settings.',
          onTap: onOpenFullSettings,
        ),
        PlpEditorialRow(
          title: 'Developer diagnostics',
          detail: 'Privileged technical evidence and sanitized diagnostics.',
          onTap: onOpenDeveloper,
        ),
      ],
    );
  }
}
