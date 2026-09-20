import 'package:flutter/material.dart';

class PlpEnterpriseHome extends StatelessWidget {
  const PlpEnterpriseHome({
    super.key,
    required this.bootstrap,
    required this.onRefresh,
    required this.onAskAlfred,
    required this.onOperations,
    required this.onVision,
  });

  final Map<String, Object?> bootstrap;
  final VoidCallback onRefresh;
  final VoidCallback onAskAlfred;
  final VoidCallback onOperations;
  final VoidCallback onVision;

  Map<String, Object?> _map(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, Object?>{};
  }

  String _text(Object? value, {String fallback = '—'}) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? fallback : normalized;
  }

  @override
  Widget build(BuildContext context) {
    final user = _map(bootstrap['user']);
    final organization = _map(bootstrap['organization']);
    final today = _map(bootstrap['today']);
    final source = _map(bootstrap['sourceHealth']);
    final displayName = _text(user['displayName'], fallback: 'PLP administrator');
    final propertyName = _text(organization['propertyName'], fallback: 'PLP Boracay');
    final businessIdentity =
        _text(organization['businessIdentity'], fallback: 'Luxury Resort');

    final metrics = <({String label, String value, String detail})>[
      (
        label: 'Occupancy',
        value: '${_text(today['occupancy_percent'], fallback: '0')}%',
        detail: '${_text(today['occupied_rooms'], fallback: '0')} occupied'
      ),
      (
        label: 'Rooms',
        value: _text(today['rooms_total'], fallback: '0'),
        detail: '${_text(today['rooms_available'], fallback: '0')} available'
      ),
      (
        label: 'Arrivals',
        value: _text(today['arrivals_today'], fallback: '0'),
        detail: 'today'
      ),
      (
        label: 'Departures',
        value: _text(today['departures_today'], fallback: '0'),
        detail: 'today'
      ),
      (
        label: 'Sales',
        value: '₱${_text(today['sales_today_php'], fallback: '0')}',
        detail: 'today'
      ),
      (
        label: 'Open tasks',
        value: _text(today['open_staff_tasks'], fallback: '0'),
        detail: 'staff'
      ),
      (
        label: 'OTA conflicts',
        value: _text(today['open_ota_conflicts'], fallback: '0'),
        detail: 'needs attention'
      ),
    ];

    return SafeArea(
      key: const ValueKey('plp-enterprise-home'),
      child: RefreshIndicator(
        onRefresh: () async => onRefresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        propertyName,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        businessIdentity,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh PLP data',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Welcome, $displayName',
              key: const ValueKey('plp-authenticated-greeting'),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your resort command center for today.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: metrics
                  .map(
                    (metric) => SizedBox(
                      width: 164,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                metric.label,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                metric.value,
                                key: ValueKey(
                                  'plp-metric-${metric.label.toLowerCase().replaceAll(' ', '-')}',
                                ),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 2),
                              Text(metric.detail),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.cloud_done_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Source health',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_text(source['state'], fallback: 'unknown')} · '
                            '${_text(source['message'], fallback: 'No provider status message')}',
                            key: const ValueKey('plp-source-health'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Command center',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.tonalIcon(
                  key: const ValueKey('plp-open-alfred'),
                  onPressed: onAskAlfred,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Ask Alfred'),
                ),
                FilledButton.tonalIcon(
                  key: const ValueKey('plp-open-operations-room'),
                  onPressed: onOperations,
                  icon: const Icon(Icons.hub_outlined),
                  label: const Text('Operations Room'),
                ),
                FilledButton.tonalIcon(
                  key: const ValueKey('plp-open-vision'),
                  onPressed: onVision,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Vision Intelligence'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
