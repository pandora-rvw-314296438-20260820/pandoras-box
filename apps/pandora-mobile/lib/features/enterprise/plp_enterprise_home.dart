
import 'package:flutter/material.dart';

import '../../core/widgets/pandora_navigation.dart';

class PlpEnterpriseHome extends StatelessWidget {
  const PlpEnterpriseHome({
    super.key,
    required this.bootstrap,
    this.onOpenNavigation,
    required this.onRefresh,
    required this.onAskAlfred,
  });

  final Map<String, Object?> bootstrap;
  final VoidCallback? onOpenNavigation;
  final VoidCallback onRefresh;
  final VoidCallback onAskAlfred;

  static const _canvas = Color(0xFFFAF7F1);
  static const _paper = Color(0xFFFFFDFC);
  static const _ink = Color(0xFF171512);
  static const _muted = Color(0xFF706B64);
  static const _line = Color(0xFFE6DED2);
  static const _accent = Color(0xFF70643F);
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

    final displayName = _text(user['displayName'], fallback: 'PLP administrator');
    final propertyName = _text(organization['propertyName'], fallback: 'PLP Boracay');
    final businessIdentity = _text(organization['businessIdentity'], fallback: 'Luxury Resort');
    final occupancy = _text(today['occupancy_percent'], fallback: '0');
    final available = _integer(today['rooms_available']);
    final arrivals = _integer(today['arrivals_today']);
    final departures = _integer(today['departures_today']);
    final sales = _peso(today['sales_today_php']);
    final tasks = _integer(today['open_staff_tasks']);
    final conflicts = _integer(today['open_ota_conflicts']);
    final sourceState = _text(source['state'], fallback: 'unknown');
    final sourceMessage = _text(source['message'], fallback: 'No provider status message');

    final attentionParts = <String>[];
    if (conflicts != '0') {
      attentionParts.add('$conflicts OTA conflict${conflicts == '1' ? '' : 's'}');
    }
    if (tasks != '0') {
      attentionParts.add('$tasks open staff task${tasks == '1' ? '' : 's'}');
    }
    final hasAttention = attentionParts.isNotEmpty;
    final hasMovement = arrivals != '0' || departures != '0';
    final briefingTitle = hasAttention
        ? 'A few things need you.'
        : hasMovement
            ? 'The resort is moving today.'
            : 'The resort is quiet today.';
    final briefingDetail = hasAttention
        ? attentionParts.join(' · ')
        : hasMovement
            ? '$arrivals arrival${arrivals == '1' ? '' : 's'} · '
                '$departures departure${departures == '1' ? '' : 's'}'
            : 'No arrivals or departures are scheduled.';
    final contextLine =
        '$occupancy% occupancy · $available ${available == '1' ? 'room' : 'rooms'} available · $sales today';

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
                'Your private briefing for what matters now.',
                style: TextStyle(color: _muted, fontSize: 14.5, height: 1.55),
              ),
              const SizedBox(height: 30),
              const Divider(height: 1, color: _line),
              const SizedBox(height: 24),
              const _Eyebrow('TODAY'),
              const SizedBox(height: 12),
              Text(
                briefingTitle,
                key: const ValueKey('plp-owner-briefing'),
                style: const TextStyle(
                  color: _ink,
                  fontFamily: 'serif',
                  fontSize: 36,
                  height: 1,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.9,
                ),
              ),
              const SizedBox(height: 10),
              Text(briefingDetail, style: const TextStyle(color: _muted, fontSize: 13, height: 1.45)),
              const SizedBox(height: 9),
              Text(
                contextLine,
                key: const ValueKey('plp-owner-context-line'),
                style: const TextStyle(
                  color: _accent,
                  fontSize: 10.5,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .35,
                ),
              ),
              if (hasAttention) ...[
                const SizedBox(height: 28),
                _Attention(conflicts: conflicts, tasks: tasks, onTap: onAskAlfred),
              ],
              if (hasMovement) ...[
                const SizedBox(height: 30),
                const _Eyebrow('MOVEMENT TODAY'),
                const SizedBox(height: 7),
                if (arrivals != '0')
                  _Movement(label: 'Arrivals', value: arrivals, detail: 'Guests expected today'),
                if (arrivals != '0' && departures != '0')
                  const Divider(height: 1, color: _line),
                if (departures != '0')
                  _Movement(label: 'Departures', value: departures, detail: 'Guests leaving today'),
              ],
              const SizedBox(height: 30),
              _SourceHealth(state: sourceState, message: sourceMessage),
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
  });

  final String propertyName;
  final String businessIdentity;
  final VoidCallback? onOpenNavigation;

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
          const SizedBox(width: 12),
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

class _SourceHealth extends StatelessWidget {
  const _SourceHealth({
    required this.state,
    required this.message,
  });

  final String state;
  final String message;

  @override
  Widget build(BuildContext context) {
    final normalized = state.toLowerCase();
    final label = switch (normalized) {
      'healthy' => 'LIVE DATA',
      'cached_offline' => 'OFFLINE SNAPSHOT',
      'stale' => 'DATA NEEDS REFRESH',
      _ => 'DATA STATUS',
    };
    final healthy = normalized == 'healthy';
    return Container(
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
            color: healthy ? PlpEnterpriseHome._good : PlpEnterpriseHome._warn,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(color: PlpEnterpriseHome._muted, fontSize: 10.5, height: 1.4),
                children: [
                  TextSpan(
                    text: label,
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
}
