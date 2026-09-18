import 'package:flutter/material.dart';

import '../../core/widgets/pandora_page.dart';
import '../simple/ask_pandora_screen.dart';
import 'eurofish_enterprise_command_bar.dart';

class EurofishOverviewScreen extends StatelessWidget {
  const EurofishOverviewScreen({super.key});

  static const _navy = Color(0xFF0A192F);
  static const _gold = Color(0xFFEAB308);
  static const _softBlue = Color(0xFF93C5FD);
  static const _muted = Color(0xFF9CA3AF);

  @override
  Widget build(BuildContext context) => EurofishEnterprisePage(
        contextLabel: 'Overview',
        suggestedPrompt:
            'Tell me what needs my attention across Euro-Fish today.',
        child: PandoraPage(
          title: 'Overview',
          subtitle: '1064 Euro-Fish Trading owner command center',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _hero(),
              const SizedBox(height: 18),
              _verifiedProfile(),
              const SizedBox(height: 18),
              _operatingLanes(),
              const SizedBox(height: 18),
              _liveOperations(),
              const SizedBox(height: 18),
              _setupPriorities(),
              const SizedBox(height: 18),
              _quickActions(context),
              const SizedBox(height: 18),
              _dataCoverage(),
            ],
          ),
        ),
      );

  Widget _hero() => ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          height: 300,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                'https://images.unsplash.com/photo-1524704654690-b56c05c78a00'
                '?q=80&w=1800&auto=format&fit=crop',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(color: _navy),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x660A192F),
                      Color(0xB30A192F),
                      Color(0xF20A192F),
                    ],
                    stops: [0, .52, 1],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: _gold,
                          ),
                          child: const Icon(
                            Icons.set_meal_rounded,
                            color: _navy,
                            size: 30,
                          ),
                        ),
                        const Spacer(),
                        _chip('EURO-FISH LAB', _softBlue),
                      ],
                    ),
                    const Spacer(),
                    const Text(
                      '1064 EURO-FISH TRADING',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 29,
                        height: 1.05,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.4,
                      ),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'AQUACULTURE â€¢ FLORICULTURE â€¢ IMPORT LOGISTICS',
                      style: TextStyle(
                        color: _gold,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.25,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Owner workspace prepared from the public Euro-Fish '
                      'business profile. Live operating values remain off '
                      'until verified company data is connected.',
                      style: TextStyle(
                        color: Color(0xFFE5E7EB),
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _verifiedProfile() => _panel(
        title: 'Verified business profile',
        icon: Icons.verified_outlined,
        child: Column(
          children: [
            _statusRow(
              'BFAR commercial importer',
              'Listed by BFAR as of May 15, 2026',
              'VERIFIED',
              const Color(0xFF34D399),
            ),
            const Divider(height: 24),
            _statusRow(
              'BPI / NPQSD import licensing',
              'Registry record found; current renewal should be connected',
              'CHECK',
              _gold,
            ),
            const Divider(height: 24),
            _statusRow(
              'Primary office',
              'Putatan, Muntinlupa City',
              'PROFILE',
              _softBlue,
            ),
          ],
        ),
      );

  Widget _operatingLanes() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Operating lanes', Icons.route_outlined),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              final width =
                  wide ? (constraints.maxWidth - 20) / 3 : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: width,
                    child: _lane(
                      Icons.water_rounded,
                      'Milkfish fry',
                      'Indonesia-sourced commercial fry import operations, '
                          'biosecurity and farm delivery.',
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _lane(
                      Icons.local_florist_outlined,
                      'Imported flowers',
                      'Roses, orchids and ornamental products with '
                          'time-sensitive cold-chain handling.',
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _lane(
                      Icons.flight_land_rounded,
                      'Import logistics',
                      'Airport arrival, quarantine clearance, release, '
                          'handoff and destination delivery.',
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      );

  Widget _liveOperations() => _panel(
        title: 'Live operations',
        icon: Icons.monitor_heart_outlined,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 720 ? 3 : 2;
            final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
            final metrics = const [
              ('Inbound shipments', Icons.flight_land_rounded),
              ('Fry available', Icons.set_meal_outlined),
              ('Flower lots', Icons.local_florist_outlined),
              ('Open quotes', Icons.request_quote_outlined),
              ('Deliveries today', Icons.local_shipping_outlined),
              ('Compliance deadlines', Icons.event_available_outlined),
            ];
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final metric in metrics)
                  SizedBox(width: width, child: _metric(metric.$1, metric.$2)),
              ],
            );
          },
        ),
      );

  Widget _setupPriorities() => _panel(
        title: 'What needs connection',
        icon: Icons.link_off_rounded,
        child: const Column(
          children: [
            _SetupRow(
              title: 'Orders & quotes',
              body:
                  'Connect the sales source used for bulk fry and flower orders.',
            ),
            Divider(height: 24),
            _SetupRow(
              title: 'Shipment tracking',
              body: 'Connect inbound load, clearance and delivery status.',
            ),
            Divider(height: 24),
            _SetupRow(
              title: 'Permits & compliance documents',
              body: 'Connect BFAR, BPI/NPQSD and shipment document records.',
            ),
            Divider(height: 24),
            _SetupRow(
              title: 'Inventory & availability',
              body:
                  'Connect live fry batches, flower lots and expected arrivals.',
            ),
          ],
        ),
      );

  Widget _quickActions(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Quick actions', Icons.bolt_rounded),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 620
                  ? (constraints.maxWidth - 10) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: width,
                    child: _action(
                      context,
                      'Operations brief',
                      Icons.summarize_outlined,
                      'Prepare todayâ€™s Euro-Fish operations brief across '
                          'orders, shipments, inventory and compliance.',
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _action(
                      context,
                      'Shipment watch',
                      Icons.flight_takeoff_rounded,
                      'Show incoming milkfish fry and flower shipments, '
                          'clearance status and delivery risks.',
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _action(
                      context,
                      'Quote follow-up',
                      Icons.request_quote_outlined,
                      'Which customer quotes or orders need follow-up today?',
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _action(
                      context,
                      'Compliance check',
                      Icons.fact_check_outlined,
                      'Show permits, accreditations or shipment documents '
                          'that need attention or renewal.',
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      );

  Widget _dataCoverage() => _panel(
        title: 'Business data coverage',
        icon: Icons.hub_outlined,
        child: Column(
          children: [
            _coverage('Website business profile', 'CONNECTED', _softBlue),
            _coverage(
              'BFAR public accreditation registry',
              'VERIFIED',
              const Color(0xFF34D399),
            ),
            _coverage('Orders & quotes', 'NOT CONNECTED', _muted),
            _coverage('Inventory & availability', 'NOT CONNECTED', _muted),
            _coverage('Shipments & delivery', 'NOT CONNECTED', _muted),
            _coverage('Finance & receivables', 'NOT CONNECTED', _muted),
            _coverage('Compliance documents', 'NOT CONNECTED', _muted),
          ],
        ),
      );

  Widget _lane(IconData icon, String title, String body) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF101827),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x334B82F6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _gold, size: 24),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              body,
              style: const TextStyle(
                color: Color(0xFFCBD5E1),
                height: 1.4,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      );

  Widget _metric(String label, IconData icon) => Container(
        constraints: const BoxConstraints(minHeight: 104),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1220),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x334B82F6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _softBlue, size: 19),
            const Spacer(),
            const Text(
              'â€”',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: _muted, fontSize: 11.5)),
          ],
        ),
      );

  Widget _panel({
    required String title,
    required IconData icon,
    required Widget child,
  }) =>
      Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1524),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0x334B82F6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(title, icon),
            const SizedBox(height: 13),
            child
          ],
        ),
      );

  Widget _sectionTitle(String title, IconData icon) => Row(
        children: [
          Icon(icon, size: 19, color: _gold),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      );

  Widget _statusRow(String title, String body, String status, Color color) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    color: _muted,
                    height: 1.35,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _chip(status, color),
        ],
      );

  Widget _coverage(String label, String state, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style:
                    const TextStyle(color: Color(0xFFD1D5DB), fontSize: 12.5),
              ),
            ),
            _chip(state, color),
          ],
        ),
      );

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: .55)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: .5,
          ),
        ),
      );

  Widget _action(
    BuildContext context,
    String label,
    IconData icon,
    String prompt,
  ) =>
      OutlinedButton.icon(
        onPressed: () => _ask(context, prompt),
        icon: Icon(icon, size: 18, color: _gold),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: Color(0x334B82F6)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
        ),
      );

  void _ask(BuildContext context, String prompt) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AskPandoraScreen(
          initialPrompt:
              '1064 Euro-Fish Trading. $prompt Use verified connected '
              'business data only and clearly identify unavailable values.',
        ),
      ),
    );
  }
}

class _SetupRow extends StatelessWidget {
  const _SetupRow({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.radio_button_unchecked_rounded,
            size: 18,
            color: Color(0xFF93C5FD),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}
