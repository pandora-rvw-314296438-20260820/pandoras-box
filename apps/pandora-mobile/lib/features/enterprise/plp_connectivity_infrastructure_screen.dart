import 'package:flutter/material.dart';

import '../../core/widgets/pandora_navigation.dart';

class PlpConnectivityInfrastructureScreen extends StatelessWidget {
  const PlpConnectivityInfrastructureScreen({
    super.key,
    required this.bootstrap,
    this.onOpenNavigation,
    required this.onAskPandora,
  });

  final Map<String, Object?> bootstrap;
  final VoidCallback? onOpenNavigation;
  final ValueChanged<String> onAskPandora;

  static const _canvas = Color(0xFFFAF7F1);
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

  String _text(Object? value, {String fallback = ''}) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? fallback : normalized;
  }

  Map<String, Object?> _service(String key) {
    final root = _map(bootstrap['enterpriseConnectivity']);
    final services = _map(root['services']);
    return _map(services[key]);
  }

  bool _verified(String key) {
    final service = _service(key);
    final evidenceRef = _text(service['evidenceRef']);
    return service['providerVerified'] == true && evidenceRef.isNotEmpty;
  }

  bool _pending(String key) {
    final raw = _text(_service(key)['state']).toLowerCase();
    return raw == 'configured' || raw == 'pending_verification';
  }

  _InfrastructureSignal _signal(
    String key,
    String title,
    IconData icon,
    List<String> serviceKeys,
  ) {
    final verified = serviceKeys.where(_verified).length;
    final pending = serviceKeys.where(_pending).length;
    final state = switch ((verified, pending)) {
      (final count, _) when count == serviceKeys.length =>
        _InfrastructureState.verified,
      (final count, _) when count > 0 => _InfrastructureState.partial,
      (_, final count) when count > 0 => _InfrastructureState.pending,
      _ => _InfrastructureState.unknown,
    };
    return _InfrastructureSignal(
      key: key,
      title: title,
      icon: icon,
      state: state,
    );
  }

  @override
  Widget build(BuildContext context) {
    final signals = <_InfrastructureSignal>[
      _signal(
        'internet',
        'Internet',
        Icons.language_rounded,
        const ['dedicated-internet'],
      ),
      _signal(
        'resilience',
        'Resilience',
        Icons.swap_horiz_rounded,
        const ['fiveg-backup', 'sd-wan'],
      ),
      _signal(
        'team',
        'Team',
        Icons.smartphone_rounded,
        const ['smart-mobility', 'messaging'],
      ),
      _signal(
        'property',
        'Property',
        Icons.sensors_rounded,
        const ['cloud-connectivity', 'iot', 'security'],
      ),
    ];

    final verified =
        signals.where((signal) => signal.state == _InfrastructureState.verified).length;
    final evidenced = signals
        .where((signal) => signal.state != _InfrastructureState.unknown)
        .length;

    final headline = evidenced == 0
        ? 'Set the resort’s baseline.'
        : verified == signals.length
            ? 'The resort is connected.'
            : '$evidenced of ' +
                signals.length.toString() +
                ' areas have provider evidence.';

    final intro = evidenced == 0
        ? 'Pandora has not verified the network, backup path, team connectivity, or property devices yet.'
        : 'Pandora is showing only provider-backed infrastructure state. Anything unverified stays visibly unknown.';

    return Material(
      color: _canvas,
      child: SafeArea(
        key: const ValueKey('plp-connectivity-infrastructure'),
        bottom: false,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 190),
          children: [
            _Header(onOpenNavigation: onOpenNavigation),
            const SizedBox(height: 38),
            const _Eyebrow('RESORT RESILIENCE'),
            const SizedBox(height: 12),
            Text(
              headline,
              key: const ValueKey('plp-infrastructure-headline'),
              style: const TextStyle(
                color: _ink,
                fontFamily: 'serif',
                fontSize: 43,
                height: .98,
                fontWeight: FontWeight.w400,
                letterSpacing: -1.35,
              ),
            ),
            const SizedBox(height: 13),
            Text(
              intro,
              key: const ValueKey('plp-infrastructure-summary'),
              style: const TextStyle(
                color: _muted,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            _SignalGrid(signals: signals),
            const SizedBox(height: 28),
            _DecisionPanel(
              evidenced: evidenced,
              verified: verified,
              total: signals.length,
              onAskPandora: onAskPandora,
            ),
            const SizedBox(height: 32),
            const _Eyebrow('WHAT PANDORA CAN DO'),
            const SizedBox(height: 8),
            _ActionRow(
              key: const ValueKey('plp-infrastructure-continuity-action'),
              title: 'Keep the resort online',
              detail: 'Check the primary path and design a backup before an outage matters.',
              onTap: () => onAskPandora(
                'Assess PLP’s primary internet and failover resilience using only verified resort and provider evidence. Identify gaps, then propose the smallest practical continuity plan. If an external service is needed, compare eligible providers including PLDT Enterprise without assuming any provider is already connected.',
              ),
            ),
            const Divider(height: 1, color: _line),
            _ActionRow(
              key: const ValueKey('plp-infrastructure-team-action'),
              title: 'Keep the team reachable',
              detail: 'Review staff devices, mobile lines and operational messaging.',
              onTap: () => onAskPandora(
                'Review PLP staff mobility and operational messaging needs. Use verified team and provider evidence, identify only meaningful gaps, and recommend an owner-approved next action. Consider Smart or other eligible enterprise mobility providers only where the need supports it.',
              ),
            ),
            const Divider(height: 1, color: _line),
            _ActionRow(
              key: const ValueKey('plp-infrastructure-property-action'),
              title: 'Connect the property',
              detail: 'Check cameras, sensors, security and cloud paths as one system.',
              onTap: () => onAskPandora(
                'Review PLP property connectivity for cameras, sensors, security and cloud services. Separate verified state from unknowns, then recommend the next operational action. Provider choice must remain capability-led and owner-approved.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onOpenNavigation});

  final VoidCallback? onOpenNavigation;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          if (onOpenNavigation != null &&
              PandoraNavigationScope.maybeOf(context)?.openDrawer != null)
            PandoraMenuButton(
              key: const ValueKey<String>('plp-connectivity-open-navigation'),
              onPressed: onOpenNavigation!,
            )
          else
            const SizedBox.square(dimension: 44),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'INFRASTRUCTURE',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: PlpConnectivityInfrastructureScreen._ink,
                fontFamily: 'serif',
                fontSize: 16,
                letterSpacing: 2.6,
                fontWeight: FontWeight.w400,
              ),
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
          color: PlpConnectivityInfrastructureScreen._accent,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.9,
        ),
      );
}

class _SignalGrid extends StatelessWidget {
  const _SignalGrid({required this.signals});

  final List<_InfrastructureSignal> signals;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          const gap = 10.0;
          final width = (constraints.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final signal in signals)
                SizedBox(
                  width: width,
                  child: _SignalTile(signal: signal),
                ),
            ],
          );
        },
      );
}

class _SignalTile extends StatelessWidget {
  const _SignalTile({required this.signal});

  final _InfrastructureSignal signal;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (signal.state) {
      _InfrastructureState.verified => (
          'Verified',
          PlpConnectivityInfrastructureScreen._good,
        ),
      _InfrastructureState.partial => (
          'Partial',
          PlpConnectivityInfrastructureScreen._warn,
        ),
      _InfrastructureState.pending => (
          'Checking',
          PlpConnectivityInfrastructureScreen._accent,
        ),
      _InfrastructureState.unknown => (
          'Not verified',
          PlpConnectivityInfrastructureScreen._muted,
        ),
    };

    return Container(
      key: ValueKey<String>('plp-infra-signal-' + signal.key),
      constraints: const BoxConstraints(minHeight: 118),
      decoration: const BoxDecoration(
        border: Border.fromBorderSide(
          BorderSide(color: PlpConnectivityInfrastructureScreen._line),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            signal.icon,
            size: 20,
            color: PlpConnectivityInfrastructureScreen._accent,
          ),
          const SizedBox(height: 22),
          Text(
            signal.title,
            style: const TextStyle(
              color: PlpConnectivityInfrastructureScreen._ink,
              fontFamily: 'serif',
              fontSize: 19,
              height: 1,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: tone,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _DecisionPanel extends StatelessWidget {
  const _DecisionPanel({
    required this.evidenced,
    required this.verified,
    required this.total,
    required this.onAskPandora,
  });

  final int evidenced;
  final int verified;
  final int total;
  final ValueChanged<String> onAskPandora;

  @override
  Widget build(BuildContext context) {
    final allVerified = verified == total;
    final title = allVerified
        ? 'Keep the evidence current.'
        : evidenced == 0
            ? 'First move: verify the basics.'
            : 'Close only the gaps that matter.';
    final body = allVerified
        ? 'Pandora has provider evidence across the four infrastructure areas. Recheck when the resort changes.'
        : evidenced == 0
            ? 'A short baseline check is more useful than a catalogue of services.'
            : 'Pandora can work from the evidence already available and focus only on what remains uncertain.';
    final action = allVerified ? 'Recheck infrastructure' : 'Check infrastructure';

    return Material(
      color: PlpConnectivityInfrastructureScreen._ink,
      child: InkWell(
        key: const ValueKey('plp-infrastructure-baseline-action'),
        onTap: () => onAskPandora(
          'Establish a verified infrastructure baseline for PLP. Check primary internet, backup/failover, staff mobility and messaging, and property connectivity. Use provider evidence where available, mark unknowns clearly, and return only the risks or next actions that matter operationally. Do not turn this into a service catalogue.',
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 21),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PANDORA',
                style: TextStyle(
                  color: Color(0xFFD5CCB7),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 11),
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
              const SizedBox(height: 10),
              Text(
                body,
                style: const TextStyle(
                  color: Color(0xFFBDB7AE),
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 17),
              Row(
                children: [
                  Text(
                    action.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
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
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    super.key,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: PlpConnectivityInfrastructureScreen._ink,
                          fontFamily: 'serif',
                          fontSize: 21,
                          height: 1.08,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        detail,
                        style: const TextStyle(
                          color: PlpConnectivityInfrastructureScreen._muted,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: PlpConnectivityInfrastructureScreen._ink,
                ),
              ],
            ),
          ),
        ),
      );
}

enum _InfrastructureState { verified, partial, pending, unknown }

class _InfrastructureSignal {
  const _InfrastructureSignal({
    required this.key,
    required this.title,
    required this.icon,
    required this.state,
  });

  final String key;
  final String title;
  final IconData icon;
  final _InfrastructureState state;
}
