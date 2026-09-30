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
  static const _paper = Color(0xFFFFFDFC);
  static const _ink = Color(0xFF171512);
  static const _muted = Color(0xFF706B64);
  static const _line = Color(0xFFE6DED2);
  static const _accent = Color(0xFF70643F);
  static const _good = Color(0xFF5E765F);

  static const _capabilities = <_CapabilitySpec>[
    _CapabilitySpec(
      'dedicated-internet',
      'Dedicated Internet & Fiber',
      'Primary resort connectivity with enterprise-grade capacity and service assurance.',
    ),
    _CapabilitySpec(
      'smart-mobility',
      'Smart Enterprise Mobility',
      'Business phones, SIMs and managed mobile connectivity for resort teams.',
    ),
    _CapabilitySpec(
      'fiveg-backup',
      '5G Backup & Failover',
      'A secondary mobile path for continuity when the primary connection is unavailable.',
    ),
    _CapabilitySpec(
      'sd-wan',
      'SD-WAN & Private Networking',
      'Securely connect resort locations, offices and future properties as one managed network.',
    ),
    _CapabilitySpec(
      'security',
      'Managed Cybersecurity',
      'Network, endpoint and access protection around Pandora and resort operations.',
    ),
    _CapabilitySpec(
      'messaging',
      'Business Messaging',
      'Operational messaging, alerts and guest communications through governed enterprise channels.',
    ),
    _CapabilitySpec(
      'cloud-connectivity',
      'Cloud Connectivity',
      'Reliable paths from the resort to Pandora, Supabase and other approved cloud services.',
    ),
    _CapabilitySpec(
      'iot',
      'IoT & Camera Connectivity',
      'Connectivity for cameras, sensors, scanners and future property devices.',
    ),
  ];

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

  Map<String, Object?> _service(String key) {
    final root = _map(bootstrap['enterpriseConnectivity']);
    final services = _map(root['services']);
    return _map(services[key]);
  }

  bool _providerVerified(Map<String, Object?> service) {
    final evidenceRef = _text(service['evidenceRef'], fallback: '');
    return service['providerVerified'] == true && evidenceRef.isNotEmpty;
  }

  String _stateLabel(Map<String, Object?> service) {
    if (_providerVerified(service)) return 'Provider verified';
    final raw = _text(service['state'], fallback: '').toLowerCase();
    if (raw == 'configured' || raw == 'pending_verification') {
      return 'Awaiting verification';
    }
    return 'Available to activate';
  }

  Color _stateColor(Map<String, Object?> service) =>
      _providerVerified(service) ? _good : _accent;

  @override
  Widget build(BuildContext context) {
    final enterprise = _map(bootstrap['enterpriseConnectivity']);
    final channelStatus = _text(
      enterprise['channelStatus'],
      fallback: 'Commercial integration not connected',
    );
    final assignedRm = _text(enterprise['assignedRelationshipManager'], fallback: '');
    final verifiedAt = _text(enterprise['verifiedAt'], fallback: '');

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
            const _Eyebrow('PLDT ENTERPRISE READY'),
            const SizedBox(height: 12),
            const Text(
              'The resort’s digital foundation.',
              style: TextStyle(
                color: _ink,
                fontFamily: 'serif',
                fontSize: 43,
                height: .98,
                fontWeight: FontWeight.w400,
                letterSpacing: -1.35,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Pandora can coordinate connectivity, mobility, security, cloud and physical devices around PLP without changing how the resort operates.',
              style: TextStyle(color: _muted, fontSize: 14, height: 1.55),
            ),
            const SizedBox(height: 13),
            const Text(
              'Nothing on this page is shown as active until provider evidence is available.',
              key: ValueKey('plp-connectivity-truth-contract'),
              style: TextStyle(
                color: _accent,
                fontSize: 10.5,
                height: 1.45,
                fontWeight: FontWeight.w700,
                letterSpacing: .45,
              ),
            ),
            const SizedBox(height: 30),
            const Divider(height: 1, color: _line),
            const SizedBox(height: 24),
            const _Eyebrow('CHANNEL STATE'),
            const SizedBox(height: 12),
            Text(
              channelStatus,
              key: const ValueKey('plp-connectivity-channel-status'),
              style: const TextStyle(
                color: _ink,
                fontFamily: 'serif',
                fontSize: 27,
                height: 1.08,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              assignedRm.isEmpty
                  ? 'No PLDT Enterprise relationship manager routing is connected yet.'
                  : 'Assigned relationship manager: ' + assignedRm,
              style: const TextStyle(color: _muted, fontSize: 12.5, height: 1.45),
            ),
            if (verifiedAt.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                'Last provider verification: ' + verifiedAt,
                style: const TextStyle(color: _accent, fontSize: 10.5),
              ),
            ],
            const SizedBox(height: 30),
            const _Eyebrow('ENTERPRISE CAPABILITIES'),
            const SizedBox(height: 8),
            for (var index = 0; index < _capabilities.length; index++) ...[
              _CapabilityRow(
                spec: _capabilities[index],
                service: _service(_capabilities[index].key),
                stateLabel: _stateLabel(_service(_capabilities[index].key)),
                stateColor: _stateColor(_service(_capabilities[index].key)),
              ),
              if (index != _capabilities.length - 1)
                const Divider(height: 1, color: _line),
            ],
            const SizedBox(height: 30),
            const Divider(height: 1, color: _line),
            const SizedBox(height: 24),
            const _Eyebrow('WHEN PANDORA FINDS AN OPPORTUNITY'),
            const SizedBox(height: 14),
            const _OpportunityStep(
              number: '01',
              title: 'Verify the need',
              detail:
                  'Pandora uses resort evidence first — new locations, devices, workloads, continuity gaps or sustained demand.',
            ),
            const _OpportunityStep(
              number: '02',
              title: 'Ask the owner',
              detail:
                  'A commercial conversation is not triggered silently. PLP keeps control of whether the opportunity should move forward.',
            ),
            const _OpportunityStep(
              number: '03',
              title: 'Route it to the RM',
              detail:
                  'When partner routing is connected, the approved opportunity can go to the assigned PLDT Enterprise relationship manager.',
            ),
            const SizedBox(height: 30),
            _AskPandoraPanel(onAskPandora: onAskPandora),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pueblo La Perla',
                  style: TextStyle(
                    color: PlpConnectivityInfrastructureScreen._ink,
                    fontFamily: 'serif',
                    fontSize: 21,
                    height: 1,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -.35,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'CONNECTIVITY & INFRASTRUCTURE',
                  style: TextStyle(
                    color: PlpConnectivityInfrastructureScreen._accent,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
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
          color: PlpConnectivityInfrastructureScreen._accent,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.9,
        ),
      );
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.spec,
    required this.service,
    required this.stateLabel,
    required this.stateColor,
  });

  final _CapabilitySpec spec;
  final Map<String, Object?> service;
  final String stateLabel;
  final Color stateColor;

  @override
  Widget build(BuildContext context) {
    final providerVerified =
        service['providerVerified'] == true &&
        (service['evidenceRef']?.toString().trim().isNotEmpty ?? false);
    final detail = providerVerified &&
            (service['message']?.toString().trim().isNotEmpty ?? false)
        ? service['message'].toString().trim()
        : spec.detail;

    return Padding(
      key: ValueKey<String>('plp-connectivity-' + spec.key),
      padding: const EdgeInsets.symmetric(vertical: 17),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spec.title,
                  style: const TextStyle(
                    color: PlpConnectivityInfrastructureScreen._ink,
                    fontFamily: 'serif',
                    fontSize: 20,
                    height: 1.12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  detail,
                  style: const TextStyle(
                    color: PlpConnectivityInfrastructureScreen._muted,
                    fontSize: 11.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 105),
            child: Text(
              stateLabel.toUpperCase(),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: stateColor,
                fontSize: 9.5,
                height: 1.3,
                fontWeight: FontWeight.w800,
                letterSpacing: .75,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpportunityStep extends StatelessWidget {
  const _OpportunityStep({
    required this.number,
    required this.title,
    required this.detail,
  });

  final String number;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 19),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 34,
              child: Text(
                number,
                style: const TextStyle(
                  color: PlpConnectivityInfrastructureScreen._accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: PlpConnectivityInfrastructureScreen._ink,
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
                      color: PlpConnectivityInfrastructureScreen._muted,
                      fontSize: 11.5,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _AskPandoraPanel extends StatelessWidget {
  const _AskPandoraPanel({required this.onAskPandora});

  final ValueChanged<String> onAskPandora;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: PlpConnectivityInfrastructureScreen._ink,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 21),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ASK PANDORA',
                style: TextStyle(
                  color: Color(0xFFD5CCB7),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Turn infrastructure into an operating decision.',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'serif',
                  fontSize: 27,
                  height: 1.05,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 17),
              _ActionButton(
                key: const ValueKey('plp-connectivity-review-action'),
                label: 'Review my connectivity setup',
                onTap: () => onAskPandora(
                  'Review PLP’s current connectivity, mobility, security, cloud and IoT needs. Use only verified PLP data. Clearly separate active provider-verified services from recommendations and unknowns.',
                ),
              ),
              const SizedBox(height: 8),
              _ActionButton(
                key: const ValueKey('plp-connectivity-expansion-action'),
                label: 'Prepare a PLDT expansion plan',
                onTap: () => onAskPandora(
                  'Prepare a PLDT Enterprise-compatible expansion plan for PLP covering dedicated internet, Smart mobility, 5G failover, SD-WAN, cybersecurity, business messaging, cloud connectivity and IoT. Do not claim any service is active unless provider-verified. Route any commercial opportunity only after owner approval.',
                ),
              ),
            ],
          ),
        ),
      );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF26231E),
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Color(0xFFD5CCB7),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _CapabilitySpec {
  const _CapabilitySpec(this.key, this.title, this.detail);

  final String key;
  final String title;
  final String detail;
}
