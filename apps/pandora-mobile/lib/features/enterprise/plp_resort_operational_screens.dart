import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'plp_staff_task_action.dart';

typedef PlpResortRecordOpener = void Function(
  String kind,
  Map<String, Object?> record,
);

class PlpResortOperationalScreen extends StatefulWidget {
  const PlpResortOperationalScreen({
    super.key,
    required this.moduleId,
    required this.bootstrap,
    required this.onBack,
    required this.onRefresh,
    required this.onOpenRecord,
  });

  final String moduleId;
  final Map<String, Object?> bootstrap;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final PlpResortRecordOpener onOpenRecord;

  @override
  State<PlpResortOperationalScreen> createState() =>
      _PlpResortOperationalScreenState();
}

class _PlpResortOperationalScreenState
    extends State<PlpResortOperationalScreen> {
  static const canvas = Color(0xFFFAF7F1);
  static const paper = Color(0xFFFFFDFC);
  static const ink = Color(0xFF171512);
  static const muted = Color(0xFF756F67);
  static const line = Color(0xFFE4DCCF);
  static const accent = Color(0xFF776A43);
  static const good = Color(0xFF60745F);
  static const warn = Color(0xFFA46C31);
  static const softGold = Color(0xFFF0E8D8);

  final TextEditingController _search = TextEditingController();
  Map<String, Object?>? _operationsOverride;
  bool _showCompleted = false;
  bool _creating = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  _ModuleSpec get _spec => _ModuleSpec.forId(widget.moduleId);
  Map<String, Object?> get _command =>
      _map(widget.bootstrap['resortCommandCenter']);
  Map<String, Object?> get _operations =>
      _operationsOverride ?? _map(widget.bootstrap['resortOperations']);
  List<Map<String, Object?>> get _workItems =>
      _maps(_operations['workItems']);
  List<Map<String, Object?>> get _conflicts =>
      _maps(_operations['channelConflicts']);
  List<Map<String, Object?>> get _rooms => _maps(_command['rooms']);
  List<Map<String, Object?>> get _stays => _maps(_command['stays']);
  List<Map<String, Object?>> get _requests =>
      _maps(_command['experienceSignals']);

  bool _containsAny(Map<String, Object?> item, List<String> words) {
    final haystack = <Object?>[
      item['title'], item['note'], item['category'], item['kind'],
      item['accommodationName'], item['fullName'], item['request'],
      item['channelKey'], item['conflictType'],
    ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
    return words.any(haystack.contains);
  }

  bool _isClosed(Map<String, Object?> item) {
    final status = _text(item['status'], fallback: '').toLowerCase();
    return const {
      'done', 'completed', 'complete', 'closed', 'cancelled', 'canceled',
    }.contains(status);
  }

  List<Map<String, Object?>> _taskRecords(List<String> words) => _workItems
      .where((item) => (_showCompleted || !_isClosed(item)) &&
          (words.isEmpty || _containsAny(item, words)))
      .map((item) => <String, Object?>{...item, '_recordKind': 'work'})
      .toList(growable: false);

  List<Map<String, Object?>> _experienceRecords(List<String> words) => [
        ..._taskRecords(words),
        ..._requests.where((item) => _containsAny(item, words)).map(
              (item) => <String, Object?>{...item, '_recordKind': 'request'},
            ),
      ];

  List<Map<String, Object?>> _primaryRecords() => switch (widget.moduleId) {
        'housekeeping' => _taskRecords(
            const ['housekeeping', 'clean', 'turnover', 'inspection']),
        'maintenance' => _taskRecords(
            const ['maintenance', 'repair', 'engineering', 'property']),
        'linen' => _taskRecords(const ['linen', 'laundry']),
        'concierge' => [
            ..._taskRecords(const ['concierge', 'guest', 'amenit']),
            ..._requests.map(
              (item) => <String, Object?>{...item, '_recordKind': 'request'},
            ),
          ],
        'vip' => [
            ..._requests.map(
              (item) => <String, Object?>{...item, '_recordKind': 'request'},
            ),
            ..._stays.where((item) => item['hasSpecialRequest'] == true).map(
              (item) => <String, Object?>{...item, '_recordKind': 'stay'},
            ),
          ],
        'transfers' || 'transport' => [
            ..._taskRecords(
              const ['transfer', 'transport', 'arrival', 'departure'],
            ),
            ..._stays.map(
              (item) => <String, Object?>{...item, '_recordKind': 'stay'},
            ),
          ],
        'property' => _taskRecords(const []),
        'security' => _taskRecords(const ['security', 'safety', 'incident']),
        'rates' => _rooms
            .map((item) => <String, Object?>{...item, '_recordKind': 'room'})
            .toList(growable: false),
        'channels' => _conflicts
            .map((item) => <String, Object?>{...item, '_recordKind': 'conflict'})
            .toList(growable: false),
        'forecast' => _stays
            .map((item) => <String, Object?>{...item, '_recordKind': 'stay'})
            .toList(growable: false),
        'dining' => _experienceRecords(
            const ['dining', 'restaurant', 'food', 'meal']),
        'wellness' => _experienceRecords(
            const ['wellness', 'spa', 'massage']),
        'activities' => _experienceRecords(
            const ['activity', 'excursion', 'tour', 'island', 'experience']),
        'events' => _experienceRecords(
            const ['event', 'celebration', 'wedding', 'birthday', 'anniversary']),
        _ => const <Map<String, Object?>>[],
      };

  List<Map<String, Object?>> _visibleRecords() {
    final query = _search.text.trim().toLowerCase();
    final records = _primaryRecords();
    if (query.isEmpty) return records;
    return records.where((item) {
      final haystack =
          item.values.map((value) => value?.toString().toLowerCase() ?? '').join(' ');
      return haystack.contains(query);
    }).toList(growable: false);
  }

  Future<void> _reloadOperations() async {
    try {
      final raw =
          await Supabase.instance.client.rpc('plp_resort_operations_v1');
      if (mounted) setState(() => _operationsOverride = _map(raw));
    } catch (_) {}
    widget.onRefresh();
  }

  Future<void> _createTask() async {
    final category = _spec.taskCategory;
    if (category == null || _creating) return;

    final title = TextEditingController();
    final note = TextEditingController();
    final booking = TextEditingController(text: 'PLP');
    var priority = 'normal';

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: paper,
      showDragHandle: false,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text(
                'New ' + _spec.singularLabel,
                style: const TextStyle(
                  color: ink, fontFamily: 'serif', fontSize: 28,
                ),
              ),
              const SizedBox(height: 18),
              _FormField(
                key: const ValueKey('plp-module-task-title'),
                controller: title,
                label: 'Task',
                hint: 'What needs to be done?',
              ),
              const SizedBox(height: 10),
              _FormField(
                controller: booking,
                label: 'Room / booking reference',
                hint: 'Optional context',
              ),
              const SizedBox(height: 10),
              _FormField(
                controller: note,
                label: 'Note',
                hint: 'Operational detail',
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              const Text(
                'Priority',
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final value in const ['normal', 'medium', 'high'])
                    _PriorityButton(
                      label: value,
                      selected: priority == value,
                      onTap: () => setSheetState(() => priority = value),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('plp-module-create-task'),
                  style: FilledButton.styleFrom(
                    backgroundColor: ink,
                    foregroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  onPressed: () {
                    if (title.text.trim().length < 3) return;
                    Navigator.of(sheetContext, rootNavigator: true).pop(true);
                  },
                  child: const Text('Create task'),
                ),
              ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) {
      title.dispose(); note.dispose(); booking.dispose();
      return;
    }

    setState(() => _creating = true);
    try {
      final result = await const PlpStaffTaskAction().execute(
        requestId: 'plp-ui-' + widget.moduleId + '-' +
            DateTime.now().microsecondsSinceEpoch.toString(),
        command: PlpStaffTaskCommand(
          bookingReference:
              booking.text.trim().isEmpty ? 'PLP' : booking.text.trim(),
          title: title.text.trim(),
          note: note.text.trim().isEmpty
              ? 'Created from the PLP ' + _spec.label + ' workspace.'
              : note.text.trim(),
          category: category,
          priority: priority,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.providerReadbackVerified
                ? 'Task created and verified.'
                : 'Task outcome could not be verified.',
          ),
        ),
      );
      await _reloadOperations();
    } on PlpStaffTaskActionException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      title.dispose(); note.dispose(); booking.dispose();
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = _visibleRecords();
    final openWork = _workItems.where((item) => !_isClosed(item)).length;
    return Material(
      color: canvas,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: ink,
          backgroundColor: paper,
          onRefresh: _reloadOperations,
          child: ListView(
            key: ValueKey<String>('plp-module-' + widget.moduleId),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 190),
            children: [
              _ModuleHeader(label: _spec.label, onBack: widget.onBack),
              const SizedBox(height: 28),
              Text(_spec.eyebrow,
                  style: const TextStyle(
                    color: accent, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 2,
                  )),
              const SizedBox(height: 10),
              Text(_spec.title,
                  style: const TextStyle(
                    color: ink, fontFamily: 'serif', fontSize: 38,
                    height: .98, fontWeight: FontWeight.w400,
                    letterSpacing: -1.15,
                  )),
              const SizedBox(height: 22),
              _MetricBand(items: [
                _Metric('Visible', records.length.toString(), _spec.unitLabel),
                _Metric('Open work', openWork.toString(), 'resort'),
                _moduleMetric(),
              ]),
              const SizedBox(height: 28),
              _ModuleControls(
                controller: _search,
                showCompleted: _showCompleted,
                canCreate: _spec.taskCategory != null,
                creating: _creating,
                onSearchChanged: (_) => setState(() {}),
                onToggleCompleted: () =>
                    setState(() => _showCompleted = !_showCompleted),
                onCreate: _createTask,
              ),
              const SizedBox(height: 26),
              _SectionLabel(_spec.queueLabel, count: records.length),
              const SizedBox(height: 8),
              if (records.isEmpty)
                _TruthfulEmptyState(message: _spec.emptyMessage)
              else
                ...records.take(40).map(
                      (record) => _OperationalRow(
                        record: record,
                        onTap: () => widget.onOpenRecord(
                          _text(record['_recordKind'], fallback: 'work'),
                          record,
                        ),
                      ),
                    ),
              const SizedBox(height: 30),
              ..._secondaryContext(),
            ],
          ),
        ),
      ),
    );
  }

  _Metric _moduleMetric() {
    if (widget.moduleId == 'channels') {
      return _Metric('Exceptions', _conflicts.length.toString(), 'channels');
    }
    if (widget.moduleId == 'rates') {
      return _Metric('Rooms', _rooms.length.toString(), 'priced');
    }
    if (widget.moduleId == 'forecast') {
      return _Metric('Stays', _stays.length.toString(), '30 days');
    }
    if (widget.moduleId == 'housekeeping') {
      final turnovers = _rooms.where((room) =>
          const {'arrival', 'departure'}
              .contains(_text(room['state']).toLowerCase())).length;
      return _Metric('Turnovers', turnovers.toString(), 'rooms');
    }
    return _Metric('Requests', _requests.length.toString(), 'connected');
  }

  List<Widget> _secondaryContext() {
    if (const {'housekeeping', 'maintenance', 'linen', 'property'}
        .contains(widget.moduleId)) {
      return [
        const _SectionLabel('ROOM CONTEXT'),
        const SizedBox(height: 10),
        _RoomContextStrip(
          rooms: _rooms,
          onTap: (room) => widget.onOpenRecord('room', room),
        ),
      ];
    }
    if (const {'concierge', 'vip', 'transfers', 'transport'}
        .contains(widget.moduleId)) {
      return [
        const _SectionLabel('STAY CONTEXT'),
        const SizedBox(height: 8),
        ..._stays.take(8).map(
              (stay) => _OperationalRow(
                record: <String, Object?>{
                  ...stay, '_recordKind': 'stay',
                },
                onTap: () => widget.onOpenRecord('stay', stay),
              ),
            ),
      ];
    }
    if (const {'rates', 'forecast'}.contains(widget.moduleId)) {
      return [
        const _SectionLabel('COMMERCIAL PULSE'),
        const SizedBox(height: 10),
        _FinanceStrip(finance: _map(_command['finance'])),
      ];
    }
    return [
      const _SectionLabel('CONNECTED GUEST SIGNALS'),
      const SizedBox(height: 8),
      if (_requests.isEmpty)
        const _TruthfulEmptyState(
          message: 'No matching guest request is connected.',
          healthy: true,
        )
      else
        ..._requests.take(8).map(
              (request) => _OperationalRow(
                record: <String, Object?>{
                  ...request, '_recordKind': 'request',
                },
                onTap: () => widget.onOpenRecord('request', request),
              ),
            ),
    ];
  }
}

class PlpResortRecordScreen extends StatelessWidget {
  const PlpResortRecordScreen({
    super.key,
    required this.kind,
    required this.record,
    required this.onBack,
  });

  final String kind;
  final Map<String, Object?> record;
  final VoidCallback onBack;

  String get _title {
    if (kind == 'room') return _text(record['name'], fallback: 'Room');
    if (kind == 'stay' || kind == 'request') {
      return _text(record['fullName'], fallback: 'Guest');
    }
    if (kind == 'conflict') {
      return _text(record['channelKey'], fallback: 'Channel exception');
    }
    return _text(record['title'], fallback: 'Resort work');
  }

  String get _eyebrow {
    if (kind == 'room') return 'ROOM';
    if (kind == 'stay') return 'STAY';
    if (kind == 'request') return 'GUEST REQUEST';
    if (kind == 'conflict' || kind == 'conflict-summary') return 'CHANNELS';
    return 'WORK ITEM';
  }

  List<(String, Object?)> get _fields {
    if (kind == 'room') {
      return [
        ('Status', record['state']),
        ('Capacity', record['capacity']),
        ('Bedrooms', record['bedrooms']),
        ('Nightly rate', _peso(record['nightlyRatePhp'])),
      ];
    }
    if (kind == 'stay') {
      return [
        ('Booking', record['bookingReference']),
        ('Room', record['accommodationName']),
        ('Check-in', record['checkIn']),
        ('Check-out', record['checkOut']),
        ('Guests', record['guestCount']),
        ('Nights', record['nights']),
        ('Status', record['status']),
        ('Payment', record['paymentStatus']),
        ('Total', _peso(record['totalAmountPhp'])),
        ('Balance', _peso(record['balanceAmountPhp'])),
        ('Special request', record['specialRequest']),
      ];
    }
    if (kind == 'request') {
      return [
        ('Room', record['accommodationName']),
        ('Check-in', record['checkIn']),
        ('Check-out', record['checkOut']),
        ('Request', record['request']),
      ];
    }
    if (kind == 'conflict') {
      return [
        ('Channel', record['channelKey']),
        ('Type', record['conflictType']),
        ('Room', record['accommodationName']),
        ('Start', record['startDate']),
        ('End', record['endDate']),
        ('Severity', record['severity']),
        ('Status', record['status']),
        ('Resolution', record['resolutionStatus']),
      ];
    }
    return [
      ('Category', record['category']),
      ('Priority', record['priority']),
      ('Status', record['status']),
      ('Booking', record['bookingReference']),
      ('Assigned / actor', record['actor']),
      ('Note', record['note']),
      if (record['count'] != null) ('Open count', record['count']),
    ];
  }

  @override
  Widget build(BuildContext context) => Material(
        color: _PlpResortOperationalScreenState.canvas,
        child: SafeArea(
          bottom: false,
          child: ListView(
            key: ValueKey<String>('plp-record-' + kind),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 190),
            children: [
              _ModuleHeader(label: _eyebrow, onBack: onBack),
              const SizedBox(height: 30),
              Text(_eyebrow,
                  style: const TextStyle(
                    color: _PlpResortOperationalScreenState.accent,
                    fontSize: 10, fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  )),
              const SizedBox(height: 10),
              Text(_title,
                  style: const TextStyle(
                    color: _PlpResortOperationalScreenState.ink,
                    fontFamily: 'serif', fontSize: 39, height: .98,
                    fontWeight: FontWeight.w400, letterSpacing: -1.1,
                  )),
              const SizedBox(height: 28),
              for (final field in _fields)
                if (_hasValue(field.$2))
                  _DetailRow(label: field.$1, value: _text(field.$2)),
              if (record['isTestData'] == true || record['isMock'] == true) ...[
                const SizedBox(height: 18),
                const _TruthfulEmptyState(
                  message: 'This record is marked as QA/test data by its source.',
                ),
              ],
            ],
          ),
        ),
      );
}

class _ModuleSpec {
  const _ModuleSpec({
    required this.label,
    required this.singularLabel,
    required this.eyebrow,
    required this.title,
    required this.queueLabel,
    required this.emptyMessage,
    required this.unitLabel,
    this.taskCategory,
  });

  final String label;
  final String singularLabel;
  final String eyebrow;
  final String title;
  final String queueLabel;
  final String emptyMessage;
  final String unitLabel;
  final String? taskCategory;

  static _ModuleSpec forId(String id) {
    switch (id) {
      case 'housekeeping':
        return const _ModuleSpec(
          label: 'Housekeeping', singularLabel: 'housekeeping task',
          eyebrow: 'ROOMS & HOUSEKEEPING',
          title: 'Turn rooms over with precision.',
          queueLabel: 'HOUSEKEEPING QUEUE',
          emptyMessage: 'No connected housekeeping work is waiting.',
          unitLabel: 'items', taskCategory: 'housekeeping',
        );
      case 'maintenance':
        return const _ModuleSpec(
          label: 'Maintenance', singularLabel: 'maintenance task',
          eyebrow: 'PROPERTY CARE',
          title: 'Protect the guest experience before faults become visible.',
          queueLabel: 'MAINTENANCE QUEUE',
          emptyMessage: 'No connected maintenance work is waiting.',
          unitLabel: 'items', taskCategory: 'maintenance',
        );
      case 'linen':
        return const _ModuleSpec(
          label: 'Linen', singularLabel: 'linen task',
          eyebrow: 'HOUSEKEEPING', title: 'Keep linen readiness visible.',
          queueLabel: 'LINEN & LAUNDRY',
          emptyMessage: 'No connected linen or laundry work is waiting.',
          unitLabel: 'items', taskCategory: 'housekeeping',
        );
      case 'concierge':
        return const _ModuleSpec(
          label: 'Concierge', singularLabel: 'concierge task',
          eyebrow: 'GUEST SERVICES',
          title: 'Coordinate the details guests remember.',
          queueLabel: 'CONCIERGE QUEUE',
          emptyMessage: 'No connected concierge request is waiting.',
          unitLabel: 'requests', taskCategory: 'concierge',
        );
      case 'vip':
        return const _ModuleSpec(
          label: 'VIP', singularLabel: 'VIP preparation task',
          eyebrow: 'GUEST SERVICES',
          title: 'Handle high-touch stays deliberately.',
          queueLabel: 'VIP & SPECIAL STAYS',
          emptyMessage:
              'No dedicated VIP flag or special-request stay is connected.',
          unitLabel: 'stays', taskCategory: 'concierge',
        );
      case 'transfers':
        return const _ModuleSpec(
          label: 'Transfers', singularLabel: 'transfer task',
          eyebrow: 'GUEST MOVEMENT',
          title: 'Coordinate every arrival and departure.',
          queueLabel: 'TRANSFER QUEUE',
          emptyMessage: 'No connected transfer work is waiting.',
          unitLabel: 'items', taskCategory: 'arrival',
        );
      case 'property':
        return const _ModuleSpec(
          label: 'Property', singularLabel: 'property task',
          eyebrow: 'PROPERTY OPERATIONS',
          title: 'Run the physical resort as one system.',
          queueLabel: 'PROPERTY WORK',
          emptyMessage: 'No connected property work is waiting.',
          unitLabel: 'items', taskCategory: 'operations',
        );
      case 'security':
        return const _ModuleSpec(
          label: 'Security', singularLabel: 'security task',
          eyebrow: 'SAFETY',
          title: 'Keep safety issues visible and attributable.',
          queueLabel: 'SECURITY & SAFETY',
          emptyMessage: 'No connected security or safety work is waiting.',
          unitLabel: 'items', taskCategory: 'security',
        );
      case 'transport':
        return const _ModuleSpec(
          label: 'Transport', singularLabel: 'transport task',
          eyebrow: 'LOGISTICS',
          title: 'Coordinate movement without losing guest context.',
          queueLabel: 'TRANSPORT QUEUE',
          emptyMessage: 'No connected transport work is waiting.',
          unitLabel: 'items', taskCategory: 'transport',
        );
      case 'rates':
        return const _ModuleSpec(
          label: 'Rates', singularLabel: 'rate',
          eyebrow: 'COMMERCIAL',
          title: 'See sellable inventory and current room rates.',
          queueLabel: 'RATE BOARD',
          emptyMessage: 'No connected room rates are available.',
          unitLabel: 'rooms',
        );
      case 'channels':
        return const _ModuleSpec(
          label: 'Channels', singularLabel: 'channel exception',
          eyebrow: 'DISTRIBUTION',
          title: 'Keep OTA inventory aligned with the resort.',
          queueLabel: 'CHANNEL EXCEPTIONS',
          emptyMessage: 'No connected OTA exception is open.',
          unitLabel: 'exceptions',
        );
      case 'forecast':
        return const _ModuleSpec(
          label: 'Forecast', singularLabel: 'stay',
          eyebrow: 'FORWARD VIEW',
          title: 'Read the booked future without pretending it is a prediction.',
          queueLabel: 'UPCOMING STAYS',
          emptyMessage: 'No connected forward stay data is available.',
          unitLabel: 'stays',
        );
      case 'dining':
        return const _ModuleSpec(
          label: 'Dining', singularLabel: 'dining task',
          eyebrow: 'EXPERIENCES',
          title: 'Coordinate dining from the guest context.',
          queueLabel: 'DINING REQUESTS',
          emptyMessage: 'No connected dining request is waiting.',
          unitLabel: 'requests', taskCategory: 'concierge',
        );
      case 'wellness':
        return const _ModuleSpec(
          label: 'Wellness', singularLabel: 'wellness task',
          eyebrow: 'EXPERIENCES',
          title: 'Keep wellness requests organized.',
          queueLabel: 'WELLNESS REQUESTS',
          emptyMessage: 'No connected wellness request is waiting.',
          unitLabel: 'requests', taskCategory: 'concierge',
        );
      case 'activities':
        return const _ModuleSpec(
          label: 'Activities', singularLabel: 'activity task',
          eyebrow: 'EXPERIENCES',
          title: 'Coordinate activities around each stay.',
          queueLabel: 'ACTIVITY REQUESTS',
          emptyMessage: 'No connected activity request is waiting.',
          unitLabel: 'requests', taskCategory: 'concierge',
        );
      case 'events':
        return const _ModuleSpec(
          label: 'Events', singularLabel: 'event task',
          eyebrow: 'EXPERIENCES',
          title: 'Coordinate celebrations and events with the stay.',
          queueLabel: 'EVENT REQUESTS',
          emptyMessage: 'No connected event request is waiting.',
          unitLabel: 'requests', taskCategory: 'concierge',
        );
      default:
        return const _ModuleSpec(
          label: 'Resort', singularLabel: 'resort task',
          eyebrow: 'RESORT', title: 'Operational workspace.',
          queueLabel: 'CONNECTED WORK',
          emptyMessage: 'No connected records are available.',
          unitLabel: 'items',
        );
    }
  }
}

class _ModuleHeader extends StatelessWidget {
  const _ModuleHeader({required this.label, required this.onBack});
  final String label;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const SizedBox(width: 56),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('PLP Boracay',
                    style: TextStyle(
                      color: _PlpResortOperationalScreenState.ink,
                      fontFamily: 'serif', fontSize: 20,
                      fontWeight: FontWeight.w500,
                    )),
                const SizedBox(height: 3),
                Text(label.toUpperCase(),
                    style: const TextStyle(
                      color: _PlpResortOperationalScreenState.accent,
                      fontSize: 8.5, fontWeight: FontWeight.w700,
                      letterSpacing: 1.7,
                    )),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('plp-module-back'),
            onPressed: onBack,
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            color: _PlpResortOperationalScreenState.ink,
          ),
        ],
      );
}

class _Metric {
  const _Metric(this.label, this.value, this.detail);
  final String label;
  final String value;
  final String detail;
}

class _MetricBand extends StatelessWidget {
  const _MetricBand({required this.items});
  final List<_Metric> items;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 7),
            Expanded(
              child: Container(
                height: 94,
                decoration: const BoxDecoration(
                  color: _PlpResortOperationalScreenState.paper,
                  border: Border.fromBorderSide(
                    BorderSide(color: _PlpResortOperationalScreenState.line),
                  ),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(items[i].label.toUpperCase(),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _PlpResortOperationalScreenState.accent,
                          fontSize: 8, fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        )),
                    const Spacer(),
                    Text(items[i].value,
                        style: const TextStyle(
                          color: _PlpResortOperationalScreenState.ink,
                          fontFamily: 'serif', fontSize: 25, height: 1,
                        )),
                    const SizedBox(height: 3),
                    Text(items[i].detail,
                        style: const TextStyle(
                          color: _PlpResortOperationalScreenState.muted,
                          fontSize: 9,
                        )),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
}

class _ModuleControls extends StatelessWidget {
  const _ModuleControls({
    required this.controller,
    required this.showCompleted,
    required this.canCreate,
    required this.creating,
    required this.onSearchChanged,
    required this.onToggleCompleted,
    required this.onCreate,
  });

  final TextEditingController controller;
  final bool showCompleted;
  final bool canCreate;
  final bool creating;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onToggleCompleted;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          TextField(
            key: const ValueKey('plp-module-search'),
            controller: controller,
            onChanged: onSearchChanged,
            decoration: const InputDecoration(
              hintText: 'Search this workspace',
              prefixIcon: Icon(Icons.search_rounded),
              filled: true,
              fillColor: _PlpResortOperationalScreenState.paper,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(
                  color: _PlpResortOperationalScreenState.line,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(
                  color: _PlpResortOperationalScreenState.accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final history = TextButton.icon(
                onPressed: onToggleCompleted,
                icon: Icon(
                  showCompleted
                      ? Icons.visibility_off_outlined
                      : Icons.history_rounded,
                  size: 17,
                ),
                label: Text(showCompleted ? 'Hide completed' : 'Show completed'),
              );
              final create = canCreate
                  ? FilledButton.icon(
                      key: const ValueKey('plp-module-new-task'),
                      onPressed: creating ? null : onCreate,
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            _PlpResortOperationalScreenState.ink,
                        foregroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(),
                      ),
                      icon: creating
                          ? const SizedBox.square(
                              dimension: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add_rounded, size: 18),
                      label: const Text('New task'),
                    )
                  : null;

              if (constraints.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(alignment: Alignment.centerLeft, child: history),
                    if (create != null) ...[
                      const SizedBox(height: 6),
                      create,
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  history,
                  const Spacer(),
                  if (create != null) create,
                ],
              );
            },
          ),
        ],
      );
}

class _OperationalRow extends StatelessWidget {
  const _OperationalRow({required this.record, required this.onTap});
  final Map<String, Object?> record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kind = _text(record['_recordKind'], fallback: 'work');
    final title = kind == 'room'
        ? _text(record['name'], fallback: 'Room')
        : (kind == 'stay' || kind == 'request')
            ? _text(record['fullName'], fallback: 'Guest')
            : kind == 'conflict'
                ? _text(record['channelKey'], fallback: 'Channel exception')
                : _text(record['title'], fallback: 'Resort work');
    final meta = kind == 'room'
        ? _text(record['state']) + ' · ' + _peso(record['nightlyRatePhp'])
        : kind == 'stay'
            ? _text(record['accommodationName']) +
                ' · ' + _text(record['checkIn']) +
                ' → ' + _text(record['checkOut'])
            : kind == 'request'
                ? _text(record['request'], fallback: 'Guest request')
                : kind == 'conflict'
                    ? _text(record['severity']).toUpperCase() +
                        ' · ' + _text(record['accommodationName']) +
                        ' · ' + _text(record['conflictType'])
                    : <String>[
                        _text(record['priority'], fallback: 'normal')
                            .toUpperCase(),
                        _text(record['status'], fallback: 'open'),
                        if (record['isTestData'] == true) 'QA',
                      ].join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: _PlpResortOperationalScreenState.line),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            children: [
              _StatusDot(status: _text(
                record['status'],
                fallback: record['state']?.toString() ?? '',
              )),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _PlpResortOperationalScreenState.ink,
                          fontSize: 13.5, fontWeight: FontWeight.w600,
                        )),
                    const SizedBox(height: 4),
                    Text(meta,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _PlpResortOperationalScreenState.muted,
                          fontSize: 10.5, height: 1.3,
                        )),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded,
                  size: 17, color: _PlpResortOperationalScreenState.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final value = status.toLowerCase();
    final color = value.contains('open') || value.contains('high')
        ? _PlpResortOperationalScreenState.warn
        : value.contains('done') ||
                value.contains('complete') ||
                value.contains('available')
            ? _PlpResortOperationalScreenState.good
            : _PlpResortOperationalScreenState.accent;
    return Container(width: 7, height: 7, color: color);
  }
}

class _RoomContextStrip extends StatelessWidget {
  const _RoomContextStrip({required this.rooms, required this.onTap});
  final List<Map<String, Object?>> rooms;
  final ValueChanged<Map<String, Object?>> onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: rooms.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, index) {
            final room = rooms[index];
            return Material(
              color: _PlpResortOperationalScreenState.paper,
              child: InkWell(
                onTap: () => onTap(room),
                child: Container(
                  width: 154,
                  decoration: const BoxDecoration(
                    border: Border.fromBorderSide(
                      BorderSide(color: _PlpResortOperationalScreenState.line),
                    ),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_text(room['name'], fallback: 'Room'),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _PlpResortOperationalScreenState.ink,
                            fontFamily: 'serif', fontSize: 17,
                          )),
                      const Spacer(),
                      Text(_text(room['state']).toUpperCase(),
                          style: const TextStyle(
                            color: _PlpResortOperationalScreenState.accent,
                            fontSize: 8.5, fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          )),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
}

class _FinanceStrip extends StatelessWidget {
  const _FinanceStrip({required this.finance});
  final Map<String, Object?> finance;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _DetailRow(
              label: 'Booked value · 30 days',
              value: _peso(finance['bookedValue30dPhp'])),
          _DetailRow(
              label: 'Outstanding',
              value: _peso(finance['outstandingBalancePhp'])),
          _DetailRow(
              label: 'Collected',
              value: _peso(finance['paidValue30dPhp'])),
        ],
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {this.count});
  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                  color: _PlpResortOperationalScreenState.accent,
                  fontSize: 9.5, fontWeight: FontWeight.w700,
                  letterSpacing: 1.8,
                )),
          ),
          if (count != null)
            Text(count.toString(),
                style: const TextStyle(
                  color: _PlpResortOperationalScreenState.muted,
                  fontSize: 10, fontWeight: FontWeight.w700,
                )),
        ],
      );
}

class _TruthfulEmptyState extends StatelessWidget {
  const _TruthfulEmptyState({required this.message, this.healthy = false});
  final String message;
  final bool healthy;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: healthy
              ? _PlpResortOperationalScreenState.softGold
              : _PlpResortOperationalScreenState.paper,
          border: healthy
              ? null
              : const Border.fromBorderSide(
                  BorderSide(color: _PlpResortOperationalScreenState.line),
                ),
        ),
        padding: const EdgeInsets.all(15),
        child: Text(message,
            style: const TextStyle(
              color: _PlpResortOperationalScreenState.muted,
              fontSize: 11.5, height: 1.4,
            )),
      );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: _PlpResortOperationalScreenState.line),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 118,
              child: Text(label.toUpperCase(),
                  style: const TextStyle(
                    color: _PlpResortOperationalScreenState.accent,
                    fontSize: 8.5, fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  )),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                    color: _PlpResortOperationalScreenState.ink,
                    fontSize: 12.5, height: 1.35,
                  )),
            ),
          ],
        ),
      );
}

class _FormField extends StatelessWidget {
  const _FormField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;

  @override
  Widget build(BuildContext context) => TextField(
        key: key,
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: _PlpResortOperationalScreenState.paper,
          enabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(
              color: _PlpResortOperationalScreenState.line,
            ),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(
              color: _PlpResortOperationalScreenState.accent,
            ),
          ),
        ),
      );
}

class _PriorityButton extends StatelessWidget {
  const _PriorityButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: selected
                ? _PlpResortOperationalScreenState.ink
                : _PlpResortOperationalScreenState.paper,
            border: Border.all(
              color: selected
                  ? _PlpResortOperationalScreenState.ink
                  : _PlpResortOperationalScreenState.line,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          child: Text(label.toUpperCase(),
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : _PlpResortOperationalScreenState.muted,
                fontSize: 8, fontWeight: FontWeight.w700,
                letterSpacing: .8,
              )),
        ),
      );
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
  return value.map(_map).toList(growable: false);
}

String _text(Object? value, {String fallback = '—'}) {
  final normalized = value?.toString().trim();
  return normalized == null || normalized.isEmpty ? fallback : normalized;
}

bool _hasValue(Object? value) {
  final text = value?.toString().trim();
  return text != null && text.isNotEmpty && text != 'null' && text != '—';
}

num _number(Object? value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

String _peso(Object? value) {
  final amount = _number(value).round();
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return (amount < 0 ? '-₱' : '₱') + buffer.toString();
}
