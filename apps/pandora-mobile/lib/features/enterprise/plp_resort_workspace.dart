import 'package:flutter/material.dart';

class PlpResortModule {
  const PlpResortModule({
    required this.group,
    required this.id,
    required this.label,
    required this.icon,
    required this.eyebrow,
    required this.headline,
    required this.description,
    required this.workstreams,
  });

  final String group;
  final String id;
  final String label;
  final IconData icon;
  final String eyebrow;
  final String headline;
  final String description;
  final List<String> workstreams;
}

const plpResortGroupOrder = <String>[
  "Guest & Stay",
  "Rooms & Property",
  "Hospitality & Experiences",
  "Commercial",
  "Finance & Supply",
  "People & Governance",
  "Intelligence & System",
];

const plpResortModules = <PlpResortModule>[
  PlpResortModule(
    group: "Guest & Stay",
    id: "reservations",
    label: "Reservations",
    icon: Icons.event_available_outlined,
    eyebrow: "BOOKINGS & STAY",
    headline: "Every reservation, one calm operating picture.",
    description: "Search, create and modify stays while keeping guarantees, requests and guest context together.",
    workstreams: <String>["Reservation calendar", "Create & modify", "Deposits & guarantees"],
  ),
  PlpResortModule(
    group: "Guest & Stay",
    id: "front-desk",
    label: "Front Desk",
    icon: Icons.meeting_room_outlined,
    eyebrow: "ARRIVAL DESK",
    headline: "A composed front desk, even at peak arrival.",
    description: "Bring check-in, check-out, room assignment and readiness into one service workspace.",
    workstreams: <String>["Check-in queue", "Check-out queue", "Room assignment"],
  ),
  PlpResortModule(
    group: "Guest & Stay",
    id: "arrivals-departures",
    label: "Arrivals & Departures",
    icon: Icons.flight_land_outlined,
    eyebrow: "DAILY MOVEMENT",
    headline: "Know every arrival before it reaches the lobby.",
    description: "Coordinate the day’s movement across rooms, transfers, welcome preparation and departures.",
    workstreams: <String>["Arrival board", "Departure board", "Transfer coordination"],
  ),
  PlpResortModule(
    group: "Guest & Stay",
    id: "in-house-guests",
    label: "In-House Guests",
    icon: Icons.hotel_outlined,
    eyebrow: "IN-HOUSE",
    headline: "A living view of every current stay.",
    description: "Keep active stays, open requests and important guest moments visible without overwhelming the team.",
    workstreams: <String>["Current stay roster", "Open requests", "Service recovery"],
  ),
  PlpResortModule(
    group: "Guest & Stay",
    id: "guest-profiles",
    label: "Guest Profiles & CRM",
    icon: Icons.badge_outlined,
    eyebrow: "GUEST INTELLIGENCE",
    headline: "Remember the guest, not just the booking.",
    description: "Bring verified stay history, preferences and service context together for more personal hospitality.",
    workstreams: <String>["Guest 360", "Preferences", "Communication history"],
  ),
  PlpResortModule(
    group: "Guest & Stay",
    id: "concierge",
    label: "Concierge",
    icon: Icons.support_agent_outlined,
    eyebrow: "CONCIERGE",
    headline: "Turn requests into beautifully coordinated experiences.",
    description: "Organize concierge work around the guest itinerary, partners and promised service times.",
    workstreams: <String>["Concierge inbox", "Itineraries", "Partner bookings"],
  ),
  PlpResortModule(
    group: "Guest & Stay",
    id: "guest-requests",
    label: "Guest Requests & Recovery",
    icon: Icons.notifications_active_outlined,
    eyebrow: "SERVICE RECOVERY",
    headline: "Nothing important gets lost between departments.",
    description: "Make guest requests, ownership, service deadlines and recovery moments explicit.",
    workstreams: <String>["Request queue", "Assignment & SLA", "Recovery follow-through"],
  ),
  PlpResortModule(
    group: "Guest & Stay",
    id: "vip-preferences",
    label: "VIP & Preferences",
    icon: Icons.workspace_premium_outlined,
    eyebrow: "VIP PREPARATION",
    headline: "Anticipate the details that make a stay memorable.",
    description: "Coordinate room, welcome, dining, transfer and preference preparation from one guest-specific plan.",
    workstreams: <String>["VIP arrivals", "Preparation checklist", "Preference moments"],
  ),
  PlpResortModule(
    group: "Guest & Stay",
    id: "lost-found",
    label: "Lost & Found",
    icon: Icons.inventory_2_outlined,
    eyebrow: "GUEST CARE",
    headline: "Handle lost property with traceable care.",
    description: "Keep reports, found items, matching and custody evidence in a controlled workflow.",
    workstreams: <String>["Found-item register", "Guest reports", "Chain of custody"],
  ),
  PlpResortModule(
    group: "Rooms & Property",
    id: "rooms",
    label: "Rooms",
    icon: Icons.bed_outlined,
    eyebrow: "ROOM CONTROL",
    headline: "Every room’s operational truth in one place.",
    description: "See room availability, readiness, guest context and exceptions without merging unrelated workflows.",
    workstreams: <String>["Room board", "Readiness", "Room exceptions"],
  ),
  PlpResortModule(
    group: "Rooms & Property",
    id: "housekeeping",
    label: "Housekeeping",
    icon: Icons.cleaning_services_outlined,
    eyebrow: "HOUSEKEEPING",
    headline: "A live room-turnover canvas for the floor team.",
    description: "Coordinate clean, inspect, release and turndown work with room and arrival context.",
    workstreams: <String>["Turnover queue", "Assignments", "Inspection & release"],
  ),
  PlpResortModule(
    group: "Rooms & Property",
    id: "laundry-linen",
    label: "Laundry & Linen",
    icon: Icons.local_laundry_service_outlined,
    eyebrow: "LINEN OPERATIONS",
    headline: "Keep linen flowing without last-minute shortages.",
    description: "Track linen par, laundry batches, issue and return, and exceptions by operating area.",
    workstreams: <String>["Linen par", "Laundry batches", "Damage & loss"],
  ),
  PlpResortModule(
    group: "Rooms & Property",
    id: "maintenance",
    label: "Maintenance",
    icon: Icons.build_outlined,
    eyebrow: "PROPERTY CARE",
    headline: "Fix the property before the guest feels the problem.",
    description: "Run work orders, priorities, parts and verification in a property-aware maintenance workspace.",
    workstreams: <String>["Work orders", "Technician assignment", "Completion evidence"],
  ),
  PlpResortModule(
    group: "Rooms & Property",
    id: "engineering",
    label: "Engineering",
    icon: Icons.engineering_outlined,
    eyebrow: "ENGINEERING",
    headline: "Keep critical property systems healthy and visible.",
    description: "Coordinate preventive maintenance, plant health and engineering exceptions around guest operations.",
    workstreams: <String>["Preventive schedule", "Plant health", "Engineering exceptions"],
  ),
  PlpResortModule(
    group: "Rooms & Property",
    id: "security-incidents",
    label: "Security & Incidents",
    icon: Icons.security_outlined,
    eyebrow: "SAFETY & SECURITY",
    headline: "Respond quickly without compromising privacy.",
    description: "Manage incident reporting, safety checks and authorized follow-through with a clear evidence trail.",
    workstreams: <String>["Incident log", "Safety checks", "Access incidents"],
  ),
  PlpResortModule(
    group: "Rooms & Property",
    id: "transport-fleet",
    label: "Transport & Fleet",
    icon: Icons.airport_shuttle_outlined,
    eyebrow: "GUEST MOVEMENT",
    headline: "Coordinate every transfer as part of the stay.",
    description: "Bring trips, drivers, vehicles and guest timing into one transport workspace.",
    workstreams: <String>["Trip board", "Drivers", "Fleet readiness"],
  ),
  PlpResortModule(
    group: "Rooms & Property",
    id: "beach-pool",
    label: "Beach, Pool & Facilities",
    icon: Icons.pool_outlined,
    eyebrow: "RESORT FACILITIES",
    headline: "Operate shared spaces with quiet precision.",
    description: "Coordinate beach, pool, cabana and facility readiness around weather, guests and safety.",
    workstreams: <String>["Facility readiness", "Cabana & space reservations", "Safety checks"],
  ),
  PlpResortModule(
    group: "Rooms & Property",
    id: "utilities",
    label: "Utilities",
    icon: Icons.bolt_outlined,
    eyebrow: "PROPERTY UTILITIES",
    headline: "Keep essential services resilient.",
    description: "Monitor connected power, generator, water and internet health while clearly labeling unavailable telemetry.",
    workstreams: <String>["Power & generator", "Water systems", "Connectivity"],
  ),
  PlpResortModule(
    group: "Hospitality & Experiences",
    id: "food-beverage",
    label: "Food & Beverage",
    icon: Icons.restaurant_outlined,
    eyebrow: "F&B",
    headline: "One hospitality picture across every outlet.",
    description: "Connect covers, reservations, service demand and operational exceptions without flattening each outlet’s character.",
    workstreams: <String>["Outlet pulse", "Kitchen load", "Service exceptions"],
  ),
  PlpResortModule(
    group: "Hospitality & Experiences",
    id: "restaurants-bars",
    label: "Restaurants & Bars",
    icon: Icons.local_bar_outlined,
    eyebrow: "DINING",
    headline: "Make every dining touchpoint feel intentional.",
    description: "Operate reservations, tables, menu availability and service flow in a guest-aware workspace.",
    workstreams: <String>["Reservations", "Table plan", "Menu availability"],
  ),
  PlpResortModule(
    group: "Hospitality & Experiences",
    id: "room-service",
    label: "Room Service",
    icon: Icons.room_service_outlined,
    eyebrow: "IN-ROOM DINING",
    headline: "From order to door, one accountable flow.",
    description: "Track order intake, kitchen state, dispatch and delivery evidence against the guest stay.",
    workstreams: <String>["Order queue", "Kitchen status", "Delivery SLA"],
  ),
  PlpResortModule(
    group: "Hospitality & Experiences",
    id: "spa-wellness",
    label: "Spa & Wellness",
    icon: Icons.spa_outlined,
    eyebrow: "WELLNESS",
    headline: "A calmer operating system for a calmer guest experience.",
    description: "Coordinate appointments, therapists, treatment rooms and guest preferences with appropriate privacy.",
    workstreams: <String>["Spa schedule", "Therapists", "Treatment rooms"],
  ),
  PlpResortModule(
    group: "Hospitality & Experiences",
    id: "experiences-activities",
    label: "Experiences & Activities",
    icon: Icons.explore_outlined,
    eyebrow: "EXPERIENCES",
    headline: "Curate the island around the guest.",
    description: "Organize activities, private experiences, partners and waivers as part of the guest itinerary.",
    workstreams: <String>["Activity calendar", "Private experiences", "Partner confirmation"],
  ),
  PlpResortModule(
    group: "Hospitality & Experiences",
    id: "weddings-events",
    label: "Weddings & Events",
    icon: Icons.celebration_outlined,
    eyebrow: "EVENTS",
    headline: "Make complex events feel effortless to the guest.",
    description: "Run pipeline, room blocks, event orders and day-of dependencies from one event workspace.",
    workstreams: <String>["Event pipeline", "Room blocks", "Function schedule"],
  ),
  PlpResortModule(
    group: "Commercial",
    id: "rates-availability",
    label: "Rates & Availability",
    icon: Icons.sell_outlined,
    eyebrow: "REVENUE CONTROL",
    headline: "Price the right room without losing operational truth.",
    description: "Bring rate calendar, inventory, restrictions and packages into one controlled commercial view.",
    workstreams: <String>["Rate calendar", "Availability", "Restrictions & packages"],
  ),
  PlpResortModule(
    group: "Commercial",
    id: "sales-crm",
    label: "Sales & CRM",
    icon: Icons.handshake_outlined,
    eyebrow: "SALES",
    headline: "Keep relationships connected to real resort capacity.",
    description: "Organize accounts, contacts and opportunities while grounding proposals in current property context.",
    workstreams: <String>["Sales pipeline", "Accounts & contacts", "Proposals"],
  ),
  PlpResortModule(
    group: "Commercial",
    id: "marketing-campaigns",
    label: "Marketing & Campaigns",
    icon: Icons.campaign_outlined,
    eyebrow: "MARKETING",
    headline: "Turn the resort story into measurable demand.",
    description: "Coordinate campaign calendar, offers, creative and audiences without mixing marketing claims with operational facts.",
    workstreams: <String>["Campaign calendar", "Offers", "Creative & audiences"],
  ),
  PlpResortModule(
    group: "Commercial",
    id: "distribution-channels",
    label: "Distribution & Channels",
    icon: Icons.hub_outlined,
    eyebrow: "DISTRIBUTION",
    headline: "Keep channels synchronized and exceptions obvious.",
    description: "Monitor channel health, inventory sync, mapping and parity from a single distribution workspace.",
    workstreams: <String>["Channel health", "Inventory sync", "Rate parity"],
  ),
  PlpResortModule(
    group: "Commercial",
    id: "reviews-reputation",
    label: "Reviews & Reputation",
    icon: Icons.reviews_outlined,
    eyebrow: "REPUTATION",
    headline: "Listen to the guest at scale without losing nuance.",
    description: "Bring reviews, surveys, sentiment themes and response work into one hospitality-aware view.",
    workstreams: <String>["Review inbox", "Guest surveys", "Themes & responses"],
  ),
  PlpResortModule(
    group: "Finance & Supply",
    id: "finance-billing",
    label: "Finance & Billing",
    icon: Icons.receipt_long_outlined,
    eyebrow: "FINANCE",
    headline: "Follow the money without losing the stay behind it.",
    description: "Bring folios, receivables, payables and reconciliation into an owner-aware finance workspace.",
    workstreams: <String>["Guest folios", "Receivables & payables", "Reconciliation"],
  ),
  PlpResortModule(
    group: "Finance & Supply",
    id: "procurement",
    label: "Procurement",
    icon: Icons.shopping_cart_outlined,
    eyebrow: "PROCUREMENT",
    headline: "Buy with context, approvals and traceability.",
    description: "Run purchase requests, quotes, approvals and purchase orders against real operating need.",
    workstreams: <String>["Purchase requests", "Quote comparison", "Approvals & POs"],
  ),
  PlpResortModule(
    group: "Finance & Supply",
    id: "suppliers",
    label: "Suppliers",
    icon: Icons.storefront_outlined,
    eyebrow: "SUPPLIERS",
    headline: "Know who supplies the resort and how reliably.",
    description: "Maintain supplier directory, contracts, terms and delivery performance in one controlled workspace.",
    workstreams: <String>["Supplier directory", "Contracts & terms", "Delivery performance"],
  ),
  PlpResortModule(
    group: "Finance & Supply",
    id: "inventory-stock",
    label: "Inventory & Stock",
    icon: Icons.inventory_outlined,
    eyebrow: "STOCK",
    headline: "Know what is on hand, where it is, and what needs replenishment.",
    description: "Coordinate stock by location, par levels, reorder needs and internal transfers.",
    workstreams: <String>["Stock by location", "Par & reorder", "Transfers"],
  ),
  PlpResortModule(
    group: "Finance & Supply",
    id: "cash-payments",
    label: "Cash & Payments",
    icon: Icons.payments_outlined,
    eyebrow: "PAYMENTS",
    headline: "Make settlement state explicit and auditable.",
    description: "Bring payment settlements, cash counts, deposits and refunds into a controlled finance surface.",
    workstreams: <String>["Payment settlements", "Cash counts & deposits", "Refunds"],
  ),
  PlpResortModule(
    group: "Finance & Supply",
    id: "capex-assets",
    label: "CapEx & Assets",
    icon: Icons.account_balance_outlined,
    eyebrow: "ASSETS",
    headline: "Plan property investment against real operating priorities.",
    description: "Manage capital requests, business cases, budget status and asset records with long-term context.",
    workstreams: <String>["CapEx pipeline", "Budget vs actual", "Asset register"],
  ),
  PlpResortModule(
    group: "People & Governance",
    id: "scheduling-attendance",
    label: "Scheduling & Attendance",
    icon: Icons.calendar_month_outlined,
    eyebrow: "PEOPLE OPERATIONS",
    headline: "Put the right people where the guest needs them.",
    description: "Coordinate schedules, attendance, leave and coverage while keeping access boundaries intact.",
    workstreams: <String>["Team schedule", "Attendance & leave", "Coverage"],
  ),
  PlpResortModule(
    group: "People & Governance",
    id: "training-sops",
    label: "Training & SOPs",
    icon: Icons.school_outlined,
    eyebrow: "SERVICE STANDARDS",
    headline: "Turn standards into repeatable service.",
    description: "Connect SOP library, assignments, competency checks and acknowledgements to the work people perform.",
    workstreams: <String>["SOP library", "Training assignments", "Competency & acknowledgement"],
  ),
  PlpResortModule(
    group: "People & Governance",
    id: "documents-compliance",
    label: "Documents & Compliance",
    icon: Icons.folder_outlined,
    eyebrow: "GOVERNANCE",
    headline: "Keep the resort’s critical records controlled and findable.",
    description: "Organize documents, version control, approvals and compliance evidence without exposing restricted material.",
    workstreams: <String>["Document library", "Version & approval", "Compliance register"],
  ),
  PlpResortModule(
    group: "People & Governance",
    id: "permits-expiry",
    label: "Permits & Expiry",
    icon: Icons.verified_outlined,
    eyebrow: "COMPLIANCE CALENDAR",
    headline: "Never discover an expiry too late.",
    description: "Track permits, licenses, insurance and inspections with accountable renewal planning.",
    workstreams: <String>["Permit register", "Expiry calendar", "Renewal evidence"],
  ),
  PlpResortModule(
    group: "People & Governance",
    id: "sustainability",
    label: "Sustainability",
    icon: Icons.eco_outlined,
    eyebrow: "SUSTAINABILITY",
    headline: "Measure responsible operations without greenwashing.",
    description: "Bring connected energy, water, waste and program evidence into a transparent resort sustainability view.",
    workstreams: <String>["Energy & water", "Waste", "Programs"],
  ),
  PlpResortModule(
    group: "Intelligence & System",
    id: "reports-forecasts",
    label: "Reports & Forecasts",
    icon: Icons.assessment_outlined,
    eyebrow: "INTELLIGENCE",
    headline: "Turn resort activity into decision-ready briefings.",
    description: "Compose owner, operations, revenue and finance reports from verified source context.",
    workstreams: <String>["Owner brief", "Operations report", "Forecasts"],
  ),
  PlpResortModule(
    group: "Intelligence & System",
    id: "automations",
    label: "Automations",
    icon: Icons.auto_awesome_outlined,
    eyebrow: "AUTOMATION",
    headline: "Automate routine coordination without hiding authority.",
    description: "Define triggers, schedules, conditions and approval gates while keeping every execution observable.",
    workstreams: <String>["Triggers", "Conditions", "Approval gates"],
  ),
  PlpResortModule(
    group: "Intelligence & System",
    id: "integrations",
    label: "Integrations",
    icon: Icons.extension_outlined,
    eyebrow: "CONNECTIONS",
    headline: "Know what PLP is connected to and what each connection can do.",
    description: "See connector health, scopes and read/write modes without exposing credentials.",
    workstreams: <String>["Connector catalog", "Health & read-back", "Scopes & modes"],
  ),
  PlpResortModule(
    group: "Intelligence & System",
    id: "notifications",
    label: "Notifications",
    icon: Icons.notifications_outlined,
    eyebrow: "ALERTING",
    headline: "Route attention without creating alert fatigue.",
    description: "Configure critical alerts, escalation paths and digests around role and operating impact.",
    workstreams: <String>["Critical alerts", "Routing rules", "Digests"],
  ),
  PlpResortModule(
    group: "Intelligence & System",
    id: "audit-provenance",
    label: "Audit & Provenance",
    icon: Icons.fact_check_outlined,
    eyebrow: "EVIDENCE",
    headline: "Know what happened, who acted, and what proved the result.",
    description: "Bring actor, authority, before/after state and provider evidence together for important resort actions.",
    workstreams: <String>["Audit stream", "Authority & provenance", "Before / after evidence"],
  ),
];

PlpResortModule? plpResortModuleById(String id) {
  for (final module in plpResortModules) {
    if (module.id == id) return module;
  }
  return null;
}

class PlpResortWorkspaceScreen extends StatefulWidget {
  const PlpResortWorkspaceScreen({
    super.key,
    required this.module,
    required this.bootstrap,
    required this.onAskMfr,
  });

  final PlpResortModule module;
  final Map<String, Object?> bootstrap;
  final VoidCallback onAskMfr;

  @override
  State<PlpResortWorkspaceScreen> createState() =>
      _PlpResortWorkspaceScreenState();
}

class _PlpResortWorkspaceScreenState
    extends State<PlpResortWorkspaceScreen> {
  static const _canvas = Color(0xFFFAF7F1);
  static const _paper = Color(0xFFFFFDFC);
  static const _ink = Color(0xFF171512);
  static const _muted = Color(0xFF706B64);
  static const _line = Color(0xFFE6DED2);
  static const _accent = Color(0xFF8A6C43);
  static const _accentSoft = Color(0xFFF0E7DA);

  int _selected = 0;

  Map<String, Object?> _map(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const <String, Object?>{};
  }

  List<Map<String, Object?>> _maps(Object? value) {
    if (value is! List) return const <Map<String, Object?>>[];
    return value
        .whereType<Map>()
        .map((item) =>
            item.map((key, value) => MapEntry(key.toString(), value)))
        .toList(growable: false);
  }

  num? _number(Object? value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '');
  }

  String _whole(Object? value) {
    final number = _number(value);
    return number == null ? '—' : number.round().toString();
  }

  String _percent(Object? value) {
    final number = _number(value);
    if (number == null) return '—';
    return '${number.toStringAsFixed(number % 1 == 0 ? 0 : 1)}%';
  }

  String _money(Object? value) {
    final number = _number(value);
    if (number == null) return '—';
    final rounded = number.round();
    final digits = rounded.abs().toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return '${rounded < 0 ? '-' : ''}₱$out';
  }

  String _text(Object? value, {String fallback = '—'}) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? fallback : normalized;
  }

  @override
  Widget build(BuildContext context) {
    final module = widget.module;
    final snapshot = _map(widget.bootstrap['latestHospitalitySnapshot']);
    final today = _map(widget.bootstrap['today']);
    final guest = _map(widget.bootstrap['guestExperience']);
    final team = _map(widget.bootstrap['teamAccess']);
    final source = _map(widget.bootstrap['sourceHealth']);
    final manifest = _map(widget.bootstrap['resortOperatingSystem']);
    final arrivals = _maps(guest['arrivals']);
    final departing = _maps(guest['departing']);
    final attention = _maps(guest['attention']);

    final occupancy =
        snapshot['occupancy_percent'] ?? today['occupancy_pct'];
    final revenue = snapshot['revenue_today'] ?? today['sales_today_php'];
    final sourceState = _text(source['state'], fallback: 'unknown');

    return Material(
      color: _canvas,
      child: SafeArea(
        bottom: false,
        child: ListView(
          key: ValueKey<String>('plp-resort-module-${module.id}'),
          padding: const EdgeInsets.fromLTRB(18, 66, 18, 34),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _accentSoft,
                    border: Border.all(color: _line),
                  ),
                  child: Icon(module.icon, color: _accent, size: 23),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        module.group.toUpperCase(),
                        style: const TextStyle(
                          color: _accent,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        module.label,
                        style: const TextStyle(
                          color: _ink,
                          fontFamily: 'serif',
                          fontSize: 27,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              decoration: const BoxDecoration(
                color: _paper,
                border: Border(
                  top: BorderSide(color: _line),
                  bottom: BorderSide(color: _line),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(4, 25, 4, 25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    module.eyebrow,
                    style: const TextStyle(
                      color: _accent,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    module.headline,
                    style: const TextStyle(
                      color: _ink,
                      fontFamily: 'serif',
                      fontSize: 31,
                      height: 1.05,
                      fontWeight: FontWeight.w400,
                      letterSpacing: -.6,
                    ),
                  ),
                  const SizedBox(height: 11),
                  Text(
                    module.description,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12.5,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Metric(label: 'Occupancy', value: _percent(occupancy)),
                _Metric(
                  label: 'Arrivals',
                  value: arrivals.isNotEmpty
                      ? arrivals.length.toString()
                      : _whole(snapshot['arrivals_today']),
                ),
                _Metric(
                  label: 'Departures',
                  value: departing.isNotEmpty
                      ? departing.length.toString()
                      : _whole(snapshot['departures_today']),
                ),
                _Metric(label: 'Revenue today', value: _money(revenue)),
                _Metric(
                  label: 'Rooms ready',
                  value: _whole(snapshot['rooms_ready']),
                ),
                _Metric(
                  label: 'Open attention',
                  value: attention.length.toString(),
                ),
                _Metric(
                  label: 'Active team',
                  value: _whole(team['activeMemberCount']),
                ),
              ],
            ),
            const SizedBox(height: 28),
            const _Lead(
              eyebrow: 'WORKING AREA',
              title: 'Operate this part of PLP',
              detail:
                  'Work surfaces stay role-aware. Connected facts are visible; unavailable state stays explicitly unavailable.',
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < module.workstreams.length; i++) ...[
              Material(
                color: i == _selected ? _accentSoft : Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _selected = i),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 62),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              module.workstreams[i],
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Icon(
                            i == _selected
                                ? Icons.radio_button_checked_rounded
                                : Icons.arrow_forward_ios_rounded,
                            size: i == _selected ? 18 : 13,
                            color: i == _selected ? _accent : _muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (i != module.workstreams.length - 1)
                const Divider(height: 1, color: _line),
            ],
            const SizedBox(height: 15),
            Container(
              decoration: BoxDecoration(
                color: _paper,
                border: Border.all(color: _line),
              ),
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SELECTED WORKSTREAM',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    module.workstreams[_selected],
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'MFR can use this page context to answer, prepare authorized actions, and route work through connected PLP capabilities. Execution is never shown complete without verified read-back.',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 11.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: ValueKey<String>(
                      'plp-module-ask-mfr-${module.id}',
                    ),
                    onPressed: widget.onAskMfr,
                    style: FilledButton.styleFrom(
                      backgroundColor: _ink,
                      foregroundColor: const Color(0xFFF6F0E7),
                      shape: const RoundedRectangleBorder(),
                      minimumSize: const Size(0, 44),
                    ),
                    icon: const Icon(
                      Icons.auto_awesome_outlined,
                      size: 18,
                    ),
                    label: Text(
                      'Ask MFR about ${module.workstreams[_selected]}',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            _Lead(
              eyebrow: 'NEEDS ATTENTION',
              title: 'Verified open resort items',
              detail: attention.isEmpty
                  ? 'No open attention item is present in the synchronized PLP snapshot.'
                  : 'Only synchronized PLP items appear here; this page does not invent tasks or approvals.',
            ),
            const SizedBox(height: 9),
            if (attention.isEmpty)
              const _Empty(
                message:
                    'No verified open attention item is present in the current PLP snapshot.',
              )
            else
              for (final item in attention.take(4))
                _Attention(
                  title: _text(
                    item['title'],
                    fallback: 'PLP attention item',
                  ),
                  detail: _text(
                    item['note'],
                    fallback: _text(
                      item['category'],
                      fallback: 'Open item',
                    ),
                  ),
                  priority: _text(item['priority'], fallback: 'open'),
                ),
            const SizedBox(height: 22),
            Container(
              decoration: BoxDecoration(
                color: _paper,
                border: Border.all(color: _line),
              ),
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    sourceState == 'healthy'
                        ? Icons.verified_outlined
                        : Icons.info_outline_rounded,
                    color: sourceState == 'healthy'
                        ? const Color(0xFF5E765F)
                        : _accent,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Source truth · $sourceState',
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _text(
                            source['message'],
                            fallback:
                                'No verified source message is available.',
                          ),
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 11,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _text(
                            manifest['schemaVersion'],
                            fallback: 'PLP resort operating system',
                          ),
                          style: const TextStyle(
                            color: _accent,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        width: 128,
        constraints: const BoxConstraints(minHeight: 74),
        decoration: BoxDecoration(
          color: _PlpResortWorkspaceScreenState._paper,
          border: Border.all(
            color: _PlpResortWorkspaceScreenState._line,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(11, 10, 11, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: _PlpResortWorkspaceScreenState._muted,
                fontSize: 8.2,
                fontWeight: FontWeight.w600,
                letterSpacing: .7,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _PlpResortWorkspaceScreenState._ink,
                fontSize: 19,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
}

class _Lead extends StatelessWidget {
  const _Lead({
    required this.eyebrow,
    required this.title,
    required this.detail,
  });
  final String eyebrow;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: const TextStyle(
              color: _PlpResortWorkspaceScreenState._accent,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(
              color: _PlpResortWorkspaceScreenState._ink,
              fontFamily: 'serif',
              fontSize: 23,
              height: 1.05,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            detail,
            style: const TextStyle(
              color: _PlpResortWorkspaceScreenState._muted,
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
        ],
      );
}

class _Attention extends StatelessWidget {
  const _Attention({
    required this.title,
    required this.detail,
    required this.priority,
  });
  final String title;
  final String detail;
  final String priority;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 7),
        decoration: const BoxDecoration(
          color: _PlpResortWorkspaceScreenState._paper,
          border: Border(
            bottom: BorderSide(
              color: _PlpResortWorkspaceScreenState._line,
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.priority_high_rounded,
              color: _PlpResortWorkspaceScreenState._accent,
              size: 18,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _PlpResortWorkspaceScreenState._ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: _PlpResortWorkspaceScreenState._muted,
                      fontSize: 10.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              priority.toUpperCase(),
              style: const TextStyle(
                color: _PlpResortWorkspaceScreenState._accent,
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: .8,
              ),
            ),
          ],
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: _PlpResortWorkspaceScreenState._paper,
          border: Border.all(
            color: _PlpResortWorkspaceScreenState._line,
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Text(
          message,
          style: const TextStyle(
            color: _PlpResortWorkspaceScreenState._muted,
            fontSize: 11,
            height: 1.45,
          ),
        ),
      );
}
