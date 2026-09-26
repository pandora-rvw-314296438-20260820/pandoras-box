import 'package:flutter/material.dart';

import '../../core/widgets/pandora_navigation.dart';

class PlpGuestsScreen extends StatefulWidget {
  const PlpGuestsScreen({
    super.key,
    required this.bootstrap,
    required this.onOpenNavigation,
  });

  final Map<String, Object?> bootstrap;
  final VoidCallback onOpenNavigation;

  @override
  State<PlpGuestsScreen> createState() => _PlpGuestsScreenState();
}

class _PlpGuestsScreenState extends State<PlpGuestsScreen> {
  static const _canvas = Color(0xFFFAF7F1);
  static const _paper = Color(0xFFFFFDFC);
  static const _ink = Color(0xFF171512);
  static const _muted = Color(0xFF706B64);
  static const _line = Color(0xFFE9E1D6);
  static const _gold = Color(0xFF70643F);
  static const _goldSoft = Color(0xFFF2EEE6);
  static const _green = Color(0xFF657965);

  String _filter = 'in-house';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
        .map(
          (item) => item.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        )
        .toList(growable: false);
  }

  String _text(Object? value, {String fallback = '—'}) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? fallback : normalized;
  }

  bool _bool(Object? value) {
    if (value is bool) return value;
    return const {'true', '1', 'yes'}
        .contains(value?.toString().trim().toLowerCase());
  }

  int _integer(Object? value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _initials(String name) {
    final words = name
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .take(2);
    final value = words.map((word) => word[0].toUpperCase()).join();
    return value.isEmpty ? 'G' : value;
  }

  List<Map<String, Object?>> _visibleGuests(
    Map<String, Object?> guestExperience,
  ) {
    if (_filter == 'arriving') return _maps(guestExperience['arrivals']);
    if (_filter == 'departing') return _maps(guestExperience['departing']);
    if (_filter != 'search') return _maps(guestExperience['inHouse']);

    final query = _searchController.text.trim().toLowerCase();
    final combined = <Map<String, Object?>>[
      ..._maps(guestExperience['inHouse']),
      ..._maps(guestExperience['arrivals']),
      ..._maps(guestExperience['departing']),
    ];
    final unique = <String, Map<String, Object?>>{};
    for (final guest in combined) {
      final key = _text(
        guest['bookingReference'],
        fallback: _text(guest['id'], fallback: guest.hashCode.toString()),
      );
      unique[key] = guest;
    }
    if (query.isEmpty) return unique.values.toList(growable: false);
    return unique.values
        .where(
          (guest) =>
              _text(guest['fullName']).toLowerCase().contains(query) ||
              _text(guest['accommodationName']).toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final organization = _map(widget.bootstrap['organization']);
    final guestExperience = _map(widget.bootstrap['guestExperience']);
    final propertyName =
        _text(organization['propertyName'], fallback: 'PLP Boracay');
    final businessDate =
        _text(guestExperience['businessDate'], fallback: '');
    final inHouse = _maps(guestExperience['inHouse']);
    final arrivals = _maps(guestExperience['arrivals']);
    final attention = _maps(guestExperience['attention']);
    final guests = _visibleGuests(guestExperience);

    return Material(
      color: _canvas,
      child: SafeArea(
        bottom: false,
        child: ListView(
          key: const ValueKey<String>('plp-guests-light-page'),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
          children: [
            _GuestHeader(onOpenNavigation: widget.onOpenNavigation),
            const SizedBox(height: 18),
            _PropertyIdentity(propertyName: propertyName),
            const SizedBox(height: 15),
            const _GuestExperienceHero(),
            const SizedBox(height: 16),
            _GuestFilters(
              selected: _filter,
              onSelect: (filter) => setState(() => _filter = filter),
            ),
            if (_filter == 'search') ...[
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey<String>('plp-guests-search-field'),
                controller: _searchController,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: _ink),
                decoration: InputDecoration(
                  hintText: 'Search guest or accommodation',
                  hintStyle: const TextStyle(color: _muted),
                  prefixIcon:
                      const Icon(Icons.search_rounded, color: _gold),
                  filled: true,
                  fillColor: _paper,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: const BorderSide(color: _line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: const BorderSide(color: _gold),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (_filter == 'requests')
              _AttentionPanel(items: attention)
            else ...[
              _SectionLead(
                title: switch (_filter) {
                  'arriving' => 'Today’s arrivals',
                  'departing' => 'Today’s departures',
                  'search' => 'Guest search',
                  _ => 'In-house guests',
                },
                detail: switch (_filter) {
                  'in-house' =>
                    '${inHouse.length} active stay${inHouse.length == 1 ? '' : 's'}',
                  'search' => 'Synchronized roster',
                  _ => businessDate,
                },
              ),
              const SizedBox(height: 4),
              if (guests.isEmpty)
                _EmptyRoster(
                  filter: _filter,
                  businessDate: businessDate,
                )
              else
                Column(
                  children: [
                    for (var index = 0; index < guests.length; index++) ...[
                      _GuestRow(
                        guest: guests[index],
                        initials: _initials(
                          _text(guests[index]['fullName'], fallback: 'Guest'),
                        ),
                      ),
                      if (index != guests.length - 1)
                        const Divider(height: 1, color: _line),
                    ],
                  ],
                ),
              if (_filter == 'in-house') ...[
                const SizedBox(height: 18),
                _AttentionPanel(items: attention),
                const SizedBox(height: 17),
                _ArrivalPanel(
                  items: arrivals,
                  businessDate: businessDate,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _GuestHeader extends StatelessWidget {
  const _GuestHeader({required this.onOpenNavigation});

  final VoidCallback onOpenNavigation;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          if (PandoraNavigationScope.maybeOf(context)?.openDrawer != null)
            PandoraMenuButton(
              key: const ValueKey<String>('plp-guests-open-navigation'),
              onPressed: onOpenNavigation,
            )
          else
            const SizedBox.square(dimension: 44),
          const SizedBox(width: 6),
          const Icon(
            Icons.people_alt_rounded,
            color: _PlpGuestsScreenState._gold,
            size: 30,
          ),
          const SizedBox(width: 9),
          const Expanded(
            child: Text(
              'Guests',
              maxLines: 1,
              overflow: TextOverflow.fade,
              style: TextStyle(
                color: _PlpGuestsScreenState._ink,
                fontSize: 30,
                height: 1,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.7,
              ),
            ),
          ),
        ],
      );
}

class _PropertyIdentity extends StatelessWidget {
  const _PropertyIdentity({required this.propertyName});

  final String propertyName;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  propertyName,
                  style: const TextStyle(
                    color: _PlpGuestsScreenState._ink,
                    fontSize: 24,
                    height: 1.05,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Luxury Resort · guest experience workspace',
                  style: TextStyle(
                    color: _PlpGuestsScreenState._muted,
                    fontSize: 12.8,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Extraordinary stays.\nA more human tomorrow.',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Color(0xFF7A593E),
              fontSize: 9.5,
              height: 1.2,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
}

class _GuestExperienceHero extends StatelessWidget {
  const _GuestExperienceHero();

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey<String>('plp-guests-editorial-hero'),
        decoration: const BoxDecoration(
          color: _PlpGuestsScreenState._paper,
          border: Border(
            top: BorderSide(color: _PlpGuestsScreenState._line),
            bottom: BorderSide(color: _PlpGuestsScreenState._line),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(4, 25, 4, 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GUEST EXPERIENCE',
                    style: TextStyle(
                      color: _PlpGuestsScreenState._gold,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.1,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Personal stays.\nThoughtful service.',
                    style: TextStyle(
                      color: _PlpGuestsScreenState._ink,
                      fontFamily: 'serif',
                      fontSize: 34,
                      height: .98,
                      fontWeight: FontWeight.w400,
                      letterSpacing: -.8,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Arrivals, in-house guests, requests and departures — organized around the guest journey.',
                    style: TextStyle(
                      color: _PlpGuestsScreenState._muted,
                      fontSize: 12.5,
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

class _GuestFilters extends StatelessWidget {
  const _GuestFilters({
    required this.selected,
    required this.onSelect,
  });

  final String selected;
  final ValueChanged<String> onSelect;

  static const _items = <({String key, String label, IconData icon})>[
    (key: 'arriving', label: 'Arriving', icon: Icons.flight_land_rounded),
    (key: 'in-house', label: 'In-house', icon: Icons.people_alt_rounded),
    (key: 'requests', label: 'Requests', icon: Icons.notifications_none_rounded),
    (key: 'departing', label: 'Departing', icon: Icons.luggage_rounded),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 350;
          return Row(
            children: [
              for (var index = 0; index < _items.length; index++) ...[
                Expanded(
                  child: _FilterPill(
                    key: ValueKey<String>(
                      'plp-guests-filter-${_items[index].key}',
                    ),
                    selected: selected == _items[index].key,
                    icon: _items[index].icon,
                    label: _items[index].label,
                    compact: compact,
                    onTap: () => onSelect(_items[index].key),
                  ),
                ),
                if (index != _items.length - 1)
                  const SizedBox(width: 2),
              ],
              const SizedBox(width: 3),
              InkWell(
                key: const ValueKey<String>('plp-guests-filter-search'),
                borderRadius: BorderRadius.zero,
                onTap: () => onSelect('search'),
                child: Container(
                  width: compact ? 36 : 40,
                  height: compact ? 38 : 42,
                  decoration: BoxDecoration(
                    color: selected == 'search'
                        ? _PlpGuestsScreenState._goldSoft
                        : _PlpGuestsScreenState._paper,
                    border: Border.all(color: _PlpGuestsScreenState._line),
                  ),
                  child: Icon(
                    Icons.search_rounded,
                    size: compact ? 18 : 20,
                    color: _PlpGuestsScreenState._ink,
                  ),
                ),
              ),
            ],
          );
        },
      );
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    super.key,
    required this.selected,
    required this.icon,
    required this.label,
    required this.compact,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.zero,
        onTap: onTap,
        child: Container(
          height: compact ? 38 : 42,
          padding: EdgeInsets.symmetric(horizontal: compact ? 3 : 7),
          decoration: BoxDecoration(
            color: selected
                ? _PlpGuestsScreenState._goldSoft
                : Colors.transparent,
            borderRadius: BorderRadius.zero,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: compact ? 14 : 17,
                color: selected
                    ? _PlpGuestsScreenState._gold
                    : _PlpGuestsScreenState._ink,
              ),
              SizedBox(width: compact ? 3 : 5),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFF70471E)
                          : _PlpGuestsScreenState._ink,
                      fontSize: compact ? 10 : 11.5,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _SectionLead extends StatelessWidget {
  const _SectionLead({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: _PlpGuestsScreenState._ink,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (detail.isNotEmpty)
              Text(
                detail,
                style: const TextStyle(
                  color: _PlpGuestsScreenState._muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      );
}

class _GuestRow extends StatelessWidget {
  const _GuestRow({
    required this.guest,
    required this.initials,
  });

  final Map<String, Object?> guest;
  final String initials;

  String _text(Object? value, {String fallback = '—'}) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? fallback : normalized;
  }

  int _integer(Object? value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _boolean(Object? value) {
    if (value is bool) return value;
    return const {'true', '1', 'yes'}
        .contains(value?.toString().trim().toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final name = _text(guest['fullName'], fallback: 'Guest');
    final accommodation =
        _text(guest['accommodationName'], fallback: 'Accommodation');
    final day = _integer(guest['dayOfStay']);
    final stayDays = _integer(guest['stayDays']);
    final request = _text(guest['specialRequest'], fallback: '')
        .replaceFirst(RegExp(r'^\[MOCK QA\]\s*'), '');
    final status = _text(guest['displayStatus'], fallback: 'In-house');
    final isMock = _boolean(guest['isMock']);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.zero,
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _PlpGuestsScreenState._goldSoft,
                  border: Border.all(color: _PlpGuestsScreenState._line),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Color(0xFF4C2F1A),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _PlpGuestsScreenState._ink,
                              fontSize: 17.5,
                              height: 1.05,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.25,
                            ),
                          ),
                        ),
                        if (isMock) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8E9C9),
                              borderRadius: BorderRadius.zero,
                            ),
                            child: const Text(
                              'QA',
                              style: TextStyle(
                                color: Color(0xFF996A21),
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      stayDays > 0
                          ? '$accommodation · Day ${day.clamp(1, stayDays)} of $stayDays'
                          : accommodation,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _PlpGuestsScreenState._muted,
                        fontSize: 12,
                      ),
                    ),
                    if (request.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        request,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF867F76),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        status,
                        style: const TextStyle(
                          color: _PlpGuestsScreenState._muted,
                          fontSize: 9.5,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const SizedBox(
                        width: 8,
                        height: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _PlpGuestsScreenState._green,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: _PlpGuestsScreenState._gold,
                    size: 22,
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

class _AttentionPanel extends StatelessWidget {
  const _AttentionPanel({required this.items});

  final List<Map<String, Object?>> items;

  String _text(Object? value, {String fallback = '—'}) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? fallback : normalized;
  }

  @override
  Widget build(BuildContext context) {
    final visible = items.take(3).toList(growable: false);
    return _LuxuryPanel(
      key: const ValueKey<String>('plp-guests-attention'),
      title: 'Needs personal attention',
      icon: Icons.notifications_active_outlined,
      child: visible.isEmpty
          ? const _PanelEmpty(
              icon: Icons.check_circle_outline_rounded,
              label: 'No open guest-attention tasks.',
            )
          : Column(
              children: [
                for (var index = 0; index < visible.length; index++) ...[
                  _AttentionItem(
                    title: _text(
                      visible[index]['title'],
                      fallback: 'Guest attention item',
                    ),
                    note: _text(visible[index]['note'], fallback: '')
                        .replaceFirst(RegExp(r'^\[MOCK QA\]\s*'), ''),
                    priority:
                        _text(visible[index]['priority'], fallback: 'open'),
                    category:
                        _text(visible[index]['category'], fallback: 'service'),
                  ),
                  if (index != visible.length - 1)
                    const Divider(
                      height: 1,
                      indent: 54,
                      color: _PlpGuestsScreenState._line,
                    ),
                ],
              ],
            ),
    );
  }
}

class _LuxuryPanel extends StatelessWidget {
  const _LuxuryPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: _PlpGuestsScreenState._paper,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: _PlpGuestsScreenState._line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 11, 10),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: _PlpGuestsScreenState._gold,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: _PlpGuestsScreenState._ink,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Text(
                    'View all',
                    style: TextStyle(
                      color: _PlpGuestsScreenState._gold,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: _PlpGuestsScreenState._gold,
                    size: 18,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _PlpGuestsScreenState._line),
            child,
          ],
        ),
      );
}

class _AttentionItem extends StatelessWidget {
  const _AttentionItem({
    required this.title,
    required this.note,
    required this.priority,
    required this.category,
  });

  final String title;
  final String note;
  final String priority;
  final String category;

  @override
  Widget build(BuildContext context) {
    final high = priority.toLowerCase() == 'high';
    final housekeeping = category.toLowerCase().contains('house');
    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 10, 9, 10),
      child: Row(
        children: [
          Container(
            width: 33,
            height: 33,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF7EEE2),
              border: Border.all(color: const Color(0xFFF0E1D0)),
            ),
            child: Icon(
              housekeeping
                  ? Icons.ac_unit_rounded
                  : Icons.card_giftcard_rounded,
              color: _PlpGuestsScreenState._gold,
              size: 17,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _PlpGuestsScreenState._ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _PlpGuestsScreenState._muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: high
                  ? const Color(0xFFF8E2D5)
                  : const Color(0xFFFFEDC3),
              borderRadius: BorderRadius.zero,
            ),
            child: Text(
              high ? 'Pending' : 'Due today',
              style: TextStyle(
                color: high
                    ? const Color(0xFFAF6A3E)
                    : const Color(0xFF996A1B),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 3),
          const Icon(
            Icons.chevron_right_rounded,
            color: _PlpGuestsScreenState._gold,
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _ArrivalPanel extends StatelessWidget {
  const _ArrivalPanel({
    required this.items,
    required this.businessDate,
  });

  final List<Map<String, Object?>> items;
  final String businessDate;

  String _text(Object? value, {String fallback = '—'}) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? fallback : normalized;
  }

  @override
  Widget build(BuildContext context) {
    final visible = items.take(3).toList(growable: false);
    return _LuxuryPanel(
      key: const ValueKey<String>('plp-guests-arrivals'),
      title: 'Today’s arrivals',
      icon: Icons.flight_land_rounded,
      child: visible.isEmpty
          ? _PanelEmpty(
              icon: Icons.event_available_rounded,
              label: businessDate.isEmpty
                  ? 'No synchronized arrivals are listed.'
                  : 'No arrivals are scheduled for $businessDate.',
            )
          : Column(
              children: [
                for (var index = 0; index < visible.length; index++) ...[
                  _ArrivalItem(
                    guest:
                        _text(visible[index]['fullName'], fallback: 'Guest'),
                    accommodation: _text(
                      visible[index]['accommodationName'],
                      fallback: 'Accommodation',
                    ),
                    reference:
                        _text(visible[index]['bookingReference'], fallback: ''),
                  ),
                  if (index != visible.length - 1)
                    const Divider(
                      height: 1,
                      indent: 54,
                      color: _PlpGuestsScreenState._line,
                    ),
                ],
              ],
            ),
    );
  }
}

class _ArrivalItem extends StatelessWidget {
  const _ArrivalItem({
    required this.guest,
    required this.accommodation,
    required this.reference,
  });

  final String guest;
  final String accommodation;
  final String reference;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(13, 10, 9, 10),
        child: Row(
          children: [
            Container(
              width: 33,
              height: 33,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFEFD8B8),
              ),
              child: const Icon(
                Icons.person_rounded,
                size: 17,
                color: Color(0xFF7A4A23),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    guest,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _PlpGuestsScreenState._ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    accommodation,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _PlpGuestsScreenState._muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            if (reference.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 88),
                child: Text(
                  reference,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _PlpGuestsScreenState._muted,
                    fontSize: 8.5,
                  ),
                ),
              ),
            const Icon(
              Icons.chevron_right_rounded,
              color: _PlpGuestsScreenState._gold,
              size: 20,
            ),
          ],
        ),
      );
}

class _PanelEmpty extends StatelessWidget {
  const _PanelEmpty({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: _PlpGuestsScreenState._green, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: _PlpGuestsScreenState._muted,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ),
      );
}

class _EmptyRoster extends StatelessWidget {
  const _EmptyRoster({
    required this.filter,
    required this.businessDate,
  });

  final String filter;
  final String businessDate;

  @override
  Widget build(BuildContext context) {
    final label = switch (filter) {
      'arriving' => 'No arrivals are scheduled',
      'departing' => 'No departures are scheduled',
      'search' => 'No guests match this search',
      _ => 'No in-house guests are synchronized',
    };
    return Container(
      margin: const EdgeInsets.only(top: 5),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _PlpGuestsScreenState._paper,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: _PlpGuestsScreenState._line),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.hotel_class_outlined,
            color: _PlpGuestsScreenState._gold,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              businessDate.isEmpty ? label : '$label for $businessDate.',
              style: const TextStyle(
                color: _PlpGuestsScreenState._muted,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
