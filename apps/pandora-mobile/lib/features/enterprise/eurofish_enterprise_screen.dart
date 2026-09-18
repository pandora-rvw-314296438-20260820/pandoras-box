import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_intelligence_api.dart';
import '../../core/data/eurofish_workspace_api.dart';

class EurofishEnterpriseScreen extends StatefulWidget {
  const EurofishEnterpriseScreen({super.key, this.api});

  final EurofishWorkspaceApi? api;

  @override
  State<EurofishEnterpriseScreen> createState() =>
      _EurofishEnterpriseScreenState();
}

class _EurofishEnterpriseScreenState extends State<EurofishEnterpriseScreen> {
  static const _navy = Color(0xFF07111F);
  static const _panel = Color(0xFF0C1728);
  static const _panelRaised = Color(0xFF111E31);
  static const _line = Color(0xFF263750);
  static const _ink = Color(0xFFF5F1E8);
  static const _muted = Color(0xFF9FB0C5);
  static const _blue = Color(0xFF4D8DFF);
  static const _gold = Color(0xFFD7AE59);
  static const _green = Color(0xFF51C88A);
  static const _amber = Color(0xFFF2B84B);
  static const _red = Color(0xFFF06A6A);

  late final EurofishWorkspaceApi _api;
  final TextEditingController _command = TextEditingController();
  final FocusNode _commandFocus = FocusNode();
  StreamSubscription<Map<String, dynamic>>? _activitySubscription;

  EurofishSurface _surface = EurofishSurface.commandCenter;
  EurofishWorkspaceSnapshot? _snapshot;
  bool _loading = true;
  bool _running = false;
  String? _loadError;
  String? _selectedObject;
  String? _receipt;
  final List<Map<String, dynamic>> _events = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? EurofishWorkspaceApi();
    unawaited(_loadSurface());
  }

  @override
  void dispose() {
    _activitySubscription?.cancel();
    _command.dispose();
    _commandFocus.dispose();
    super.dispose();
  }

  Future<void> _loadSurface({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() => _loading = true);
    try {
      final snapshot = await _api.load(_surface);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loadError = null;
        _loading = false;
      });
    } on EurofishWorkspaceException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _changeSurface(EurofishSurface surface) async {
    if (surface == _surface) return;
    setState(() {
      _surface = surface;
      _selectedObject = null;
      _receipt = null;
      _events.clear();
    });
    await _loadSurface();
  }

  Future<void> _submitCommand([String? suggested]) async {
    if (_running) return;
    final objective = (suggested ?? _command.text).trim();
    if (objective.isEmpty) {
      _commandFocus.requestFocus();
      return;
    }

    final intelligence = PandoraDependencies.of(context).intelligence;
    if (intelligence == null) {
      setState(() => _receipt =
          'Pandora intelligence is not available in this signed-in session.');
      return;
    }

    await _activitySubscription?.cancel();
    final requestId =
        'eurofish-${DateTime.now().microsecondsSinceEpoch}-${_surface.rpcName}';
    final selected = _selectedObject == null
        ? 'No specific business object is selected.'
        : 'Selected business context: $_selectedObject.';
    final message = '''
1064 Euro-Fish Trading — Pandora Enterprise.
Current surface: ${_surface.label}.
$selected
Use only verified connected business data for operational claims. Unknown values must remain unknown, never zero. Keep external intelligence separate from internal truth. Execute in place when authorized and provide provider readback/evidence before claiming success.

Owner command: $objective
''';

    setState(() {
      _running = true;
      _receipt = null;
      _events.clear();
      if (suggested == null) _command.clear();
    });

    try {
      final execution = await intelligence.startChatExecution(
        message: message,
        requestId: requestId,
      );
      _activitySubscription = execution.events.listen(
        (event) {
          if (!mounted) return;
          setState(() {
            _events.add(event);
            if (_events.length > 8) _events.removeAt(0);
          });
        },
        onError: (_) {
          if (!mounted) return;
          setState(() => _receipt =
              'Live Activity lost connection. Check persisted Activity before retrying a write.');
        },
      );

      final turn = await execution.turn;
      if (!mounted) return;
      setState(() => _receipt = turn.reply);
      await _loadSurface(showLoading: false);
    } on PandoraIntelligenceException catch (error) {
      if (!mounted) return;
      setState(() => _receipt = error.message);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _navy,
      child: SafeArea(
        child: Column(
          children: [
            _header(),
            _surfaceNavigation(),
            const Divider(height: 1, color: _line),
            Expanded(child: _workspace()),
            _activityTheatre(),
            _commandDock(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final profile = _snapshot?.profile ?? const <String, dynamic>{};
    final name = (profile['displayName'] ?? '1064 Euro-Fish Trading').toString();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: _gold.withValues(alpha: .48)),
            ),
            child: const Icon(Icons.set_meal_rounded, color: _gold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Biological imports · Perishables · Clearance · Allocation',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _truthBadge('PROVIDER-BACKED', _blue),
        ],
      ),
    );
  }

  Widget _surfaceNavigation() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 700) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: DropdownButtonFormField<EurofishSurface>(
              initialValue: _surface,
              isExpanded: true,
              dropdownColor: _panelRaised,
              decoration: InputDecoration(
                labelText: 'Workspace',
                labelStyle: const TextStyle(color: _muted),
                filled: true,
                fillColor: _panel,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _line),
                ),
              ),
              items: [
                for (final surface in EurofishSurface.values)
                  DropdownMenuItem(
                    value: surface,
                    child: Text(surface.label),
                  ),
              ],
              onChanged: (value) {
                if (value != null) unawaited(_changeSurface(value));
              },
            ),
          );
        }

        return SizedBox(
          height: 54,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            scrollDirection: Axis.horizontal,
            itemCount: EurofishSurface.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final surface = EurofishSurface.values[index];
              final selected = surface == _surface;
              return ChoiceChip(
                selected: selected,
                onSelected: (_) => unawaited(_changeSurface(surface)),
                label: Text(surface.label),
                showCheckmark: false,
                side: BorderSide(color: selected ? _blue : _line),
                backgroundColor: _panel,
                selectedColor: _blue.withValues(alpha: .14),
                labelStyle: TextStyle(
                  color: selected ? _ink : _muted,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _workspace() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null && _snapshot == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _stateCard(
            icon: Icons.cloud_off_rounded,
            title: 'Workspace unavailable',
            body: _loadError!,
            color: _red,
            action: TextButton(
              onPressed: () => unawaited(_loadSurface()),
              child: const Text('Retry'),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSurface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          _surfaceIntro(),
          const SizedBox(height: 14),
          _dashboardGrid(),
          const SizedBox(height: 14),
          _operatingCanvas(),
          const SizedBox(height: 14),
          _lineageStrip(),
          const SizedBox(height: 14),
          _evidenceAndCoverage(),
        ],
      ),
    );
  }

  Widget _surfaceIntro() {
    final copy = switch (_surface) {
      EurofishSurface.commandCenter =>
        'Owner control tower: attention, arrivals, clearance, availability, commitments, cash and what Pandora handled.',
      EurofishSurface.commercial =>
        'Turn customer demand into fulfilment truth across quotes, commitments, allocations and delivery promises.',
      EurofishSurface.importOperations =>
        'Run inbound biological and perishable shipments as evidence-backed timelines, not status labels.',
      EurofishSurface.aquaculture =>
        'Track milkfish fry as biological inventory: quantity, condition, mortality, reservations and available-to-promise.',
      EurofishSurface.floriculture =>
        'Manage flower lots by condition, age, cold-chain integrity, reservations and sell-first urgency.',
      EurofishSurface.customers =>
        'See each relationship as one operating history across demand, delivery, collections and reorder opportunity.',
      EurofishSurface.suppliers =>
        'Separate confirmed supplier truth from external candidates, then measure reliability by lane and outcome.',
      EurofishSurface.compliance =>
        'Treat BFAR and BPI/NPQSD evidence as shipment-linked operating constraints with validity and freshness.',
      EurofishSurface.finance =>
        'Expose receivables, due dates, unbilled commitments, landed-cost context and collection risk only from connected sources.',
      EurofishSurface.evidence =>
        'Keep permits, airway bills, certificates, invoices and verification evidence attached to the business object they prove.',
      EurofishSurface.integrations =>
        'Control source connections, access, provider health and business settings without pretending disconnected systems are live.',
    };

    return _sectionPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_surfaceIcon(_surface), color: _gold, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _surface.label,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  copy,
                  style: const TextStyle(
                    color: _muted,
                    height: 1.45,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardGrid() {
    final metrics = _metricsFor(_surface);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1080
            ? 4
            : constraints.maxWidth >= 620
                ? 2
                : 1;
        final width =
            (constraints.maxWidth - (columns - 1) * 10) / columns;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final metric in metrics)
              SizedBox(width: width, child: _metricCard(metric)),
          ],
        );
      },
    );
  }

  Widget _metricCard(_MetricSpec metric) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => setState(() => _selectedObject = metric.context),
      child: Container(
        constraints: const BoxConstraints(minHeight: 116),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: _selectedObject == metric.context ? _panelRaised : _panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _selectedObject == metric.context ? _blue : _line,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(metric.icon, size: 18, color: metric.color),
                const Spacer(),
                _truthBadge(metric.truth, metric.color),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              metric.value,
              style: const TextStyle(
                color: _ink,
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              metric.label,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _operatingCanvas() {
    final rows = _canvasRowsFor(_surface);
    return _sectionPanel(
      title: 'Operating canvas',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            _canvasRow(rows[index]),
            if (index < rows.length - 1)
              const Divider(height: 1, color: _line),
          ],
        ],
      ),
    );
  }

  Widget _canvasRow(_CanvasRow row) {
    final selected = _selectedObject == row.context;
    return InkWell(
      onTap: () => setState(() => _selectedObject = row.context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: row.color.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(row.icon, size: 19, color: row.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.title,
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    row.body,
                    style: const TextStyle(
                      color: _muted,
                      height: 1.4,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? _blue : _muted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineageStrip() {
    const stages = [
      'Demand',
      'Quote',
      'Commitment',
      'Supplier',
      'Permit',
      'Flight',
      'Arrival',
      'Clearance',
      'Receiving',
      'Lot',
      'Delivery',
      'Invoice',
      'Payment',
    ];

    return _sectionPanel(
      title: 'Business lineage',
      child: SizedBox(
        height: 42,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: stages.length,
          separatorBuilder: (_, __) => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              Icons.chevron_right_rounded,
              color: _muted,
              size: 18,
            ),
          ),
          itemBuilder: (context, index) => Center(
            child: Text(
              stages[index],
              style: const TextStyle(
                color: _ink,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _evidenceAndCoverage() {
    final snapshot = _snapshot;
    if (snapshot == null) return const SizedBox.shrink();

    if (_surface == EurofishSurface.compliance ||
        _surface == EurofishSurface.evidence) {
      return _sectionPanel(
        title: 'Verified evidence',
        child: Column(
          children: [
            for (final fact in snapshot.facts)
              _evidenceRow(
                (fact['label'] ?? fact['key'] ?? 'Evidence').toString(),
                (fact['sourceName'] ?? 'Source unavailable').toString(),
                (fact['truthStatus'] ?? 'unverified').toString(),
              ),
          ],
        ),
      );
    }

    return _sectionPanel(
      title: 'Data coverage',
      child: Column(
        children: [
          for (final source in snapshot.sources)
            _coverageRow(
              (source['name'] ?? source['key'] ?? 'Source').toString(),
              (source['message'] ?? '').toString(),
              (source['status'] ?? 'not_connected').toString(),
            ),
        ],
      ),
    );
  }

  Widget _activityTheatre() {
    if (!_running && _events.isEmpty && _receipt == null) {
      return const SizedBox.shrink();
    }

    final latest = _events.isEmpty ? null : _events.last;
    final state =
        latest?['state']?.toString() ?? (_running ? 'acting' : 'result');
    final announce = state == 'failed' ||
        state == 'result' ||
        state == 'needs_choice' ||
        state == 'needs_permission' ||
        state == 'needs_special_access';

    return Semantics(
      liveRegion: announce,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: _panelRaised,
          border: Border(top: BorderSide(color: _line)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_running)
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    _stateIcon(state),
                    color: _stateColor(state),
                    size: 18,
                  ),
                const SizedBox(width: 9),
                Text(
                  _running ? 'Pandora is working here' : 'Pandora result',
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                _truthBadge(state.toUpperCase(), _stateColor(state)),
              ],
            ),
            if (_events.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final event in _events.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    '• ${(event['message'] ?? event['state'] ?? 'Activity').toString()}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
            if (_receipt != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                _receipt!,
                maxLines: 6,
                style: const TextStyle(
                  color: _ink,
                  height: 1.4,
                  fontSize: 12.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _commandDock() {
    final selectedText =
        _selectedObject == null ? 'No object selected' : _selectedObject!;

    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        10,
        14,
        10 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF081321),
        border: Border(top: BorderSide(color: _line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.near_me_outlined, color: _gold, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${_surface.label} · $selectedText',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ),
              if (_selectedObject != null)
                TextButton(
                  onPressed: () => setState(() => _selectedObject = null),
                  child: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _command,
                  focusNode: _commandFocus,
                  enabled: !_running,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => unawaited(_submitCommand()),
                  decoration: InputDecoration(
                    hintText: 'Ask Pandora to work on this page…',
                    filled: true,
                    fillColor: _panel,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(color: _line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(color: _line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(color: _blue, width: 1.2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: _running ? 'Pandora is working' : 'Send to Pandora',
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: FilledButton(
                    onPressed:
                        _running ? null : () => unawaited(_submitCommand()),
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: Icon(
                      _running
                          ? Icons.more_horiz_rounded
                          : Icons.arrow_upward_rounded,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<_MetricSpec> _metricsFor(EurofishSurface surface) {
    final snapshot = _snapshot;
    const unknown = '—';
    const disconnected = 'NOT CONNECTED';

    switch (surface) {
      case EurofishSurface.commandCenter:
        return const [
          _MetricSpec('Arriving ≤72h', unknown, disconnected,
              Icons.flight_land_rounded, _amber, 'Inbound arrivals in next 72 hours'),
          _MetricSpec('Clearance blockers', unknown, disconnected,
              Icons.gpp_maybe_outlined, _red, 'Shipment clearance blockers'),
          _MetricSpec('Fry ATP', unknown, disconnected, Icons.water_rounded,
              _blue, 'Milkfish fry available to promise'),
          _MetricSpec('Sell-first flowers', unknown, disconnected,
              Icons.local_florist_outlined, _amber, 'Flower lots that must sell first'),
          _MetricSpec('Customer commitments', unknown, disconnected,
              Icons.handshake_outlined, _blue, 'Customer commitments at risk'),
          _MetricSpec('Receivables due', unknown, disconnected,
              Icons.payments_outlined, _amber, 'Receivables due and overdue'),
        ];
      case EurofishSurface.commercial:
        return const [
          _MetricSpec('New inquiries', unknown, disconnected,
              Icons.chat_bubble_outline_rounded, _blue, 'Commercial inquiries'),
          _MetricSpec('Open quotes', unknown, disconnected,
              Icons.request_quote_outlined, _blue, 'Open customer quotes'),
          _MetricSpec('Confirmed orders', unknown, disconnected,
              Icons.inventory_outlined, _green, 'Confirmed customer orders'),
          _MetricSpec('Allocation risk', unknown, disconnected,
              Icons.warning_amber_rounded, _amber, 'Orders at allocation risk'),
        ];
      case EurofishSurface.importOperations:
        return const [
          _MetricSpec('Inbound shipments', unknown, disconnected,
              Icons.flight_takeoff_rounded, _blue, 'Inbound shipment portfolio'),
          _MetricSpec('Arriving today', unknown, disconnected,
              Icons.schedule_rounded, _amber, 'Shipments arriving today'),
          _MetricSpec('Awaiting clearance', unknown, disconnected,
              Icons.fact_check_outlined, _amber, 'Shipments awaiting clearance'),
          _MetricSpec('Delivery risk', unknown, disconnected,
              Icons.local_shipping_outlined, _red, 'Shipment delivery risk'),
        ];
      case EurofishSurface.aquaculture:
        return const [
          _MetricSpec('Expected heads', unknown, disconnected,
              Icons.outbound_outlined, _blue, 'Expected milkfish fry'),
          _MetricSpec('Received heads', unknown, disconnected,
              Icons.move_to_inbox_outlined, _green, 'Received milkfish fry'),
          _MetricSpec('Mortality', unknown, disconnected,
              Icons.monitor_heart_outlined, _amber, 'Observed fry mortality'),
          _MetricSpec('Available to promise', unknown, disconnected,
              Icons.check_circle_outline_rounded, _blue, 'Fry ATP'),
        ];
      case EurofishSurface.floriculture:
        return const [
          _MetricSpec('Sellable stems', unknown, disconnected,
              Icons.local_florist_outlined, _green, 'Sellable flower inventory'),
          _MetricSpec('Sell-first lots', unknown, disconnected,
              Icons.timer_outlined, _amber, 'Flower sell-first queue'),
          _MetricSpec('Cold-chain exceptions', unknown, disconnected,
              Icons.ac_unit_outlined, _red, 'Cold-chain exceptions'),
          _MetricSpec('Incoming lots', unknown, disconnected,
              Icons.flight_land_outlined, _blue, 'Incoming flower lots'),
        ];
      case EurofishSurface.customers:
        return const [
          _MetricSpec('Active customers', unknown, disconnected,
              Icons.groups_outlined, _blue, 'Active customer accounts'),
          _MetricSpec('Follow-up today', unknown, disconnected,
              Icons.notification_important_outlined, _amber, 'Customer follow-up queue'),
          _MetricSpec('Reorder opportunities', unknown, disconnected,
              Icons.repeat_rounded, _green, 'Customer reorder opportunities'),
          _MetricSpec('Outstanding', unknown, disconnected,
              Icons.account_balance_wallet_outlined, _amber, 'Customer outstanding balance'),
        ];
      case EurofishSurface.suppliers:
        return const [
          _MetricSpec('Confirmed suppliers', unknown, disconnected,
              Icons.factory_outlined, _blue, 'Confirmed supplier relationships'),
          _MetricSpec('External candidates', unknown, 'EXTERNAL ONLY',
              Icons.public_outlined, _amber, 'External supplier candidates'),
          _MetricSpec('Open commitments', unknown, disconnected,
              Icons.assignment_outlined, _blue, 'Open supplier commitments'),
          _MetricSpec('Lane exceptions', unknown, disconnected,
              Icons.alt_route_rounded, _red, 'Supplier lane exceptions'),
        ];
      case EurofishSurface.compliance:
        final bfar = snapshot?.fact('bfar_commercial_importer_2026_05_15');
        final npqsd = snapshot?.fact('npqsd_importer_record_2022_2025');
        return [
          _MetricSpec(
            'BFAR importer status',
            bfar == null ? unknown : 'Commercial',
            bfar == null ? 'NOT VERIFIED' : 'VERIFIED',
            Icons.verified_user_outlined,
            bfar == null ? _amber : _green,
            'BFAR commercial importer evidence',
          ),
          _MetricSpec(
            'BPI / NPQSD',
            npqsd == null ? unknown : 'Renewal evidence needed',
            'REQUIRES CURRENT VERIFICATION',
            Icons.eco_outlined,
            _amber,
            'BPI / NPQSD importer evidence',
          ),
          const _MetricSpec('Shipment blockers', unknown, disconnected,
              Icons.block_outlined, _red, 'Compliance blockers by shipment'),
          const _MetricSpec('Expiring documents', unknown, disconnected,
              Icons.event_busy_outlined, _amber, 'Expiring compliance documents'),
        ];
      case EurofishSurface.finance:
        return const [
          _MetricSpec('Due today', unknown, disconnected,
              Icons.today_outlined, _amber, 'Receivables due today'),
          _MetricSpec('Overdue', unknown, disconnected,
              Icons.warning_amber_rounded, _red, 'Overdue receivables'),
          _MetricSpec('Unbilled', unknown, disconnected,
              Icons.receipt_long_outlined, _blue, 'Unbilled commitments'),
          _MetricSpec('Collected', unknown, disconnected,
              Icons.payments_outlined, _green, 'Collections received'),
        ];
      case EurofishSurface.evidence:
        return [
          _MetricSpec('Verified evidence',
              '${snapshot?.verifiedEvidenceCount ?? 0}', 'EVIDENCE COUNT',
              Icons.verified_outlined, _green, 'Verified evidence records'),
          _MetricSpec('Needs current verification',
              '${snapshot?.needsVerificationCount ?? 0}', 'EVIDENCE COUNT',
              Icons.manage_search_outlined, _amber, 'Evidence requiring current verification'),
          const _MetricSpec('Shipment documents', unknown, disconnected,
              Icons.description_outlined, _blue, 'Shipment-linked documents'),
          const _MetricSpec('Missing evidence', unknown, disconnected,
              Icons.find_in_page_outlined, _red, 'Missing operational evidence'),
        ];
      case EurofishSurface.integrations:
        return [
          _MetricSpec('Connected / verified',
              '${snapshot?.connectedSourceCount ?? 0}', 'SOURCE COUNT',
              Icons.link_rounded, _green, 'Connected data sources'),
          _MetricSpec('Not connected',
              '${snapshot?.notConnectedSourceCount ?? 0}', 'SOURCE COUNT',
              Icons.link_off_rounded, _amber, 'Unconnected data sources'),
          const _MetricSpec('Failed syncs', unknown, 'NO LIVE SYNC SOURCE',
              Icons.sync_problem_rounded, _red, 'Integration sync failures'),
          const _MetricSpec('Access exceptions', unknown, disconnected,
              Icons.admin_panel_settings_outlined, _amber, 'User and access exceptions'),
        ];
    }
  }

  List<_CanvasRow> _canvasRowsFor(EurofishSurface surface) => switch (surface) {
        EurofishSurface.commandCenter => const [
            _CanvasRow(Icons.priority_high_rounded, 'Needs You',
                'Only consequential decisions and unresolved blockers belong here.', _amber, 'Owner attention queue'),
            _CanvasRow(Icons.flight_land_rounded, 'Arriving',
                'Inbound fry, flowers and other confirmed lanes ordered by time-to-arrival.', _blue, 'Arriving shipments'),
            _CanvasRow(Icons.fact_check_outlined, 'Clearing',
                'Inspection, quarantine and evidence gates linked to affected commitments.', _amber, 'Clearance workspace'),
            _CanvasRow(Icons.inventory_2_outlined, 'Available & committed',
                'Physical, reserved and available-to-promise inventory without invented values.', _green, 'Availability and commitments'),
            _CanvasRow(Icons.payments_outlined, 'Collecting',
                'Receivables and collections appear only after an accounting source is connected.', _blue, 'Collections workspace'),
          ],
        EurofishSurface.commercial => const [
            _CanvasRow(Icons.chat_outlined, 'Demand',
                'Capture customer request, commodity, quantity, target date and confidence.', _blue, 'Demand queue'),
            _CanvasRow(Icons.request_quote_outlined, 'Quote',
                'Price, validity, source availability and fulfilment assumptions stay explicit.', _gold, 'Quote pipeline'),
            _CanvasRow(Icons.handshake_outlined, 'Commitment',
                'Confirmed customer promises are linked to allocations and delivery dates.', _green, 'Customer commitments'),
            _CanvasRow(Icons.account_tree_outlined, 'Allocation',
                'Reservations resolve to biological or flower lots before fulfilment is claimed.', _amber, 'Allocation workspace'),
          ],
        EurofishSurface.importOperations => const [
            _CanvasRow(Icons.calendar_today_outlined, 'Planned → Booked',
                'Supplier commitment, booking and evidence readiness.', _blue, 'Planned and booked shipments'),
            _CanvasRow(Icons.flight_takeoff_rounded, 'Departed → Arriving',
                'Flight movement, ETA changes and time-sensitive downstream impact.', _blue, 'In-transit shipments'),
            _CanvasRow(Icons.health_and_safety_outlined, 'Inspection → Clearance',
                'Regulatory gates, missing evidence and blocking conditions.', _amber, 'Inspection and clearance'),
            _CanvasRow(Icons.inventory_2_outlined, 'Released → Received',
                'Provider-confirmed release, receiving condition and final handoff.', _green, 'Released and received shipments'),
          ],
        EurofishSurface.aquaculture => const [
            _CanvasRow(Icons.numbers_rounded, 'Quantity truth',
                'Expected, shipped, received and variance remain separate observations.', _blue, 'Fry quantity lineage'),
            _CanvasRow(Icons.monitor_heart_outlined, 'Biological condition',
                'Condition, mortality and post-conditioning outcomes are first-class facts.', _amber, 'Fry biological condition'),
            _CanvasRow(Icons.warehouse_outlined, 'Conditioned stock',
                'Location and conditioning state precede commercial availability.', _green, 'Conditioned fry inventory'),
            _CanvasRow(Icons.fact_check_outlined, 'Reserved → ATP → Dispatched',
                'Customer reservations cannot silently exceed biological availability.', _gold, 'Fry allocation state'),
          ],
        EurofishSurface.floriculture => const [
            _CanvasRow(Icons.local_florist_outlined, 'Lot condition',
                'Variety, origin, received stems, rejects and visual condition.', _green, 'Flower lot condition'),
            _CanvasRow(Icons.ac_unit_outlined, 'Cold-chain',
                'Temperature and handling evidence follow each lot.', _blue, 'Flower cold-chain'),
            _CanvasRow(Icons.hourglass_bottom_rounded, 'Age & sell-first',
                'Older sellable lots rise before newer stock without hiding reservations.', _amber, 'Flower sell-first queue'),
            _CanvasRow(Icons.inventory_outlined, 'Reserved → sellable → dispatched',
                'Commercial availability follows physical condition and reservations.', _gold, 'Flower allocation state'),
          ],
        EurofishSurface.customers => const [
            _CanvasRow(Icons.person_search_outlined, 'Account',
                'Canonical customer identity, contacts and commercial status.', _blue, 'Customer account'),
            _CanvasRow(Icons.timeline_rounded, 'Relationship timeline',
                'Quotes, orders, deliveries, payments and outcomes in one sequence.', _gold, 'Customer timeline'),
            _CanvasRow(Icons.notification_important_outlined, 'Follow-up',
                'Attention is tied to a real commitment or overdue action.', _amber, 'Customer follow-up'),
            _CanvasRow(Icons.repeat_rounded, 'Reorder',
                'Reorder suggestions require actual purchase history, never web inference.', _green, 'Reorder opportunity'),
          ],
        EurofishSurface.suppliers => const [
            _CanvasRow(Icons.verified_outlined, 'Confirmed suppliers',
                'Internal relationship truth stays separate from public trade matches.', _green, 'Confirmed suppliers'),
            _CanvasRow(Icons.public_outlined, 'External candidates',
                'Trade intelligence carries source, date and entity-match confidence.', _amber, 'External supplier intelligence'),
            _CanvasRow(Icons.alt_route_rounded, 'Lane performance',
                'Origin, logistics reliability, evidence quality and receiving outcomes.', _blue, 'Supplier lane performance'),
            _CanvasRow(Icons.history_rounded, 'Outcome history',
                'Future sourcing decisions can compound from verified prior outcomes.', _gold, 'Supplier outcome history'),
          ],
        EurofishSurface.compliance => const [
            _CanvasRow(Icons.verified_user_outlined, 'Accreditation',
                'Official source, observation date, scope and validity state.', _green, 'Accreditation evidence'),
            _CanvasRow(Icons.description_outlined, 'Shipment evidence',
                'Permit, health or phytosanitary, airway bill and release evidence by shipment.', _blue, 'Shipment compliance evidence'),
            _CanvasRow(Icons.event_busy_outlined, 'Expiry watch',
                'Expiring evidence becomes attention only when a current record is connected.', _amber, 'Compliance expiry watch'),
            _CanvasRow(Icons.block_outlined, 'Blocking conditions',
                'A missing or invalid requirement shows exactly which shipment or order it blocks.', _red, 'Compliance blockers'),
          ],
        EurofishSurface.finance => const [
            _CanvasRow(Icons.receipt_long_outlined, 'Invoice',
                'Invoice state is linked back to order and delivery evidence.', _blue, 'Invoices'),
            _CanvasRow(Icons.today_outlined, 'Due',
                'Due dates appear only from an authoritative finance source.', _amber, 'Receivables due'),
            _CanvasRow(Icons.warning_amber_rounded, 'Overdue',
                'Collections risk carries customer and commitment context.', _red, 'Overdue receivables'),
            _CanvasRow(Icons.payments_outlined, 'Collected',
                'Payment completion requires finance or provider readback.', _green, 'Collections'),
          ],
        EurofishSurface.evidence => const [
            _CanvasRow(Icons.flight_outlined, 'By shipment',
                'Airway bills, permits and release evidence grouped by import movement.', _blue, 'Shipment evidence graph'),
            _CanvasRow(Icons.gavel_outlined, 'By regulator',
                'Government evidence separated by authority and observation date.', _gold, 'Regulatory evidence'),
            _CanvasRow(Icons.groups_outlined, 'By counterparty',
                'Supplier and customer documents stay linked to the business object they prove.', _green, 'Counterparty evidence'),
            _CanvasRow(Icons.folder_copy_outlined, 'Missing / stale',
                'Evidence gaps are explicit; stale records never masquerade as current.', _amber, 'Evidence gaps'),
          ],
        EurofishSurface.integrations => const [
            _CanvasRow(Icons.hub_outlined, 'Source connections',
                'Each provider shows permission scope, freshness and last successful readback.', _blue, 'Source integrations'),
            _CanvasRow(Icons.manage_accounts_outlined, 'Users & roles',
                'Euro-Fish business access remains distinct from Pandora organization roles.', _gold, 'Users and roles'),
            _CanvasRow(Icons.admin_panel_settings_outlined, 'Security',
                'Operational tables remain closed until an authorized identity is bound.', _green, 'Security boundary'),
            _CanvasRow(Icons.settings_outlined, 'Business settings',
                'Timezone, currency and operating defaults are explicit and auditable.', _blue, 'Business settings'),
          ],
      };

  Widget _sectionPanel({String? title, required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      );

  Widget _stateCard({
    required IconData icon,
    required String title,
    required String body,
    required Color color,
    Widget? action,
  }) =>
      _sectionPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                color: _ink,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, height: 1.4),
            ),
            if (action != null) ...[const SizedBox(height: 8), action],
          ],
        ),
      );

  Widget _coverageRow(String name, String message, String status) {
    final color = _truthColor(status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (message.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    message,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          _truthBadge(status.replaceAll('_', ' ').toUpperCase(), color),
        ],
      ),
    );
  }

  Widget _evidenceRow(String label, String source, String truthStatus) {
    final color = _truthColor(truthStatus);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.description_outlined, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  source,
                  style: const TextStyle(color: _muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          _truthBadge(
            truthStatus.replaceAll('_', ' ').toUpperCase(),
            color,
          ),
        ],
      ),
    );
  }

  Widget _truthBadge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: .48)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: .35,
          ),
        ),
      );

  Color _truthColor(String status) {
    final value = status.toLowerCase();
    if (value.contains('verified') && !value.contains('requires')) {
      return _green;
    }
    if (value.contains('connected')) return _blue;
    if (value.contains('failed') || value.contains('blocked')) return _red;
    return _amber;
  }

  Color _stateColor(String state) {
    if (state == 'result') return _green;
    if (state == 'failed' || state == 'cancelled') return _red;
    if (state.startsWith('needs_')) return _amber;
    return _blue;
  }

  IconData _stateIcon(String state) {
    if (state == 'result') return Icons.check_circle_rounded;
    if (state == 'failed' || state == 'cancelled') {
      return Icons.error_rounded;
    }
    if (state.startsWith('needs_')) return Icons.priority_high_rounded;
    return Icons.auto_awesome_rounded;
  }

  IconData _surfaceIcon(EurofishSurface surface) => switch (surface) {
        EurofishSurface.commandCenter => Icons.dashboard_outlined,
        EurofishSurface.commercial => Icons.request_quote_outlined,
        EurofishSurface.importOperations => Icons.flight_land_outlined,
        EurofishSurface.aquaculture => Icons.water_outlined,
        EurofishSurface.floriculture => Icons.local_florist_outlined,
        EurofishSurface.customers => Icons.groups_outlined,
        EurofishSurface.suppliers => Icons.factory_outlined,
        EurofishSurface.compliance => Icons.fact_check_outlined,
        EurofishSurface.finance => Icons.account_balance_wallet_outlined,
        EurofishSurface.evidence => Icons.description_outlined,
        EurofishSurface.integrations => Icons.hub_outlined,
      };
}

class _MetricSpec {
  const _MetricSpec(
    this.label,
    this.value,
    this.truth,
    this.icon,
    this.color,
    this.context,
  );

  final String label;
  final String value;
  final String truth;
  final IconData icon;
  final Color color;
  final String context;
}

class _CanvasRow {
  const _CanvasRow(
    this.icon,
    this.title,
    this.body,
    this.color,
    this.context,
  );

  final IconData icon;
  final String title;
  final String body;
  final Color color;
  final String context;
}
