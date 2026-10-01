import 'package:flutter/material.dart';

import 'plp_resort_transaction_action.dart';

const _canvas = Color(0xFFFAF7F1);
const _paper = Color(0xFFFFFDFC);
const _ink = Color(0xFF171512);
const _muted = Color(0xFF756F67);
const _line = Color(0xFFE4DCCF);
const _accent = Color(0xFF776A43);

bool plpRoleCanOperate(Map<String, Object?> bootstrap) {
  final role = _text(_map(bootstrap['user'])['role']).toLowerCase();
  return const {'owner', 'admin', 'operator'}.contains(role);
}

bool plpRoleCanAdmin(Map<String, Object?> bootstrap) {
  final role = _text(_map(bootstrap['user'])['role']).toLowerCase();
  return const {'owner', 'admin'}.contains(role);
}

class PlpReservationCreateScreen extends StatefulWidget {
  const PlpReservationCreateScreen({
    super.key,
    required this.bootstrap,
    required this.onBack,
    required this.onChanged,
    this.action = const PlpResortTransactionAction(),
  });

  final Map<String, Object?> bootstrap;
  final VoidCallback onBack;
  final VoidCallback onChanged;
  final PlpResortTransactionAction action;

  @override
  State<PlpReservationCreateScreen> createState() =>
      _PlpReservationCreateScreenState();
}

class _PlpReservationCreateScreenState
    extends State<PlpReservationCreateScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _guestCount = TextEditingController(text: '1');
  final _specialRequests = TextEditingController();
  String? _roomId;
  DateTime? _checkIn;
  DateTime? _checkOut;
  bool _saving = false;
  String? _error;

  List<Map<String, Object?>> get _rooms =>
      _maps(_map(widget.bootstrap['resortCommandCenter'])['rooms']);

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _guestCount.dispose();
    _specialRequests.dispose();
    super.dispose();
  }

  Future<void> _pickCheckIn() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _checkIn ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _checkIn = picked;
      if (_checkOut == null || !_checkOut!.isAfter(picked)) {
        _checkOut = picked.add(const Duration(days: 1));
      }
    });
  }

  Future<void> _pickCheckOut() async {
    final base = _checkIn ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _checkOut ?? base.add(const Duration(days: 1)),
      firstDate: base.add(const Duration(days: 1)),
      lastDate: DateTime(base.year + 3),
    );
    if (picked == null || !mounted) return;
    setState(() => _checkOut = picked);
  }

  Future<void> _submit() async {
    if (_saving) return;
    final roomId = _roomId;
    final checkIn = _checkIn;
    final checkOut = _checkOut;
    final count = int.tryParse(_guestCount.text.trim());
    if (_name.text.trim().length < 2 ||
        !_email.text.contains('@') ||
        roomId == null ||
        checkIn == null ||
        checkOut == null ||
        count == null ||
        count < 1) {
      setState(() => _error = 'Complete the guest, room, dates, and guest count.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.action.execute(
        requestId:
            'plp-create-booking-${DateTime.now().microsecondsSinceEpoch}',
        action: 'create_booking',
        payload: <String, Object?>{
          'guestFullName': _name.text.trim(),
          'guestEmail': _email.text.trim(),
          if (_phone.text.trim().isNotEmpty) 'guestPhone': _phone.text.trim(),
          'accommodationId': roomId,
          'checkIn': _date(checkIn),
          'checkOut': _date(checkOut),
          'guestCount': count,
          if (_specialRequests.text.trim().isNotEmpty)
            'specialRequests': _specialRequests.text.trim(),
        },
      );
      widget.onChanged();
      if (!mounted) return;
      widget.onBack();
    } on PlpResortTransactionFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _TransactionScaffold(
        key: const ValueKey('plp-new-reservation'),
        title: 'New reservation',
        eyebrow: 'STAYS',
        onBack: widget.onBack,
        error: _error,
        children: [
          _Field(
            fieldKey: const ValueKey('plp-reservation-name'),
            controller: _name,
            label: 'Guest name',
          ),
          _Field(
            fieldKey: const ValueKey('plp-reservation-email'),
            controller: _email,
            label: 'Email',
            keyboardType: TextInputType.emailAddress,
          ),
          _Field(
            controller: _phone,
            label: 'Phone',
            keyboardType: TextInputType.phone,
          ),
          DropdownButtonFormField<String>(
            key: const ValueKey('plp-reservation-room'),
            value: _roomId,
            decoration: _decoration('Room'),
            items: [
              for (final room in _rooms)
                DropdownMenuItem<String>(
                  value: _text(room['id']),
                  child: Text(_text(room['name'], fallback: 'Room')),
                ),
            ],
            onChanged: (value) => setState(() => _roomId = value),
          ),
          _DateButton(
            buttonKey: const ValueKey('plp-reservation-check-in'),
            label: 'Check-in',
            value: _checkIn,
            onTap: _pickCheckIn,
          ),
          _DateButton(
            buttonKey: const ValueKey('plp-reservation-check-out'),
            label: 'Check-out',
            value: _checkOut,
            onTap: _pickCheckOut,
          ),
          _Field(
            controller: _guestCount,
            label: 'Guests',
            keyboardType: TextInputType.number,
          ),
          _Field(
            controller: _specialRequests,
            label: 'Special requests',
            maxLines: 3,
          ),
          _SubmitButton(
            buttonKey: const ValueKey('plp-reservation-save'),
            label: 'Create reservation',
            busy: _saving,
            onPressed: _submit,
          ),
        ],
      );
}

class PlpResortMutationScreen extends StatefulWidget {
  const PlpResortMutationScreen({
    super.key,
    required this.actionId,
    required this.record,
    required this.bootstrap,
    required this.onBack,
    required this.onChanged,
    this.action = const PlpResortTransactionAction(),
  });

  final String actionId;
  final Map<String, Object?> record;
  final Map<String, Object?> bootstrap;
  final VoidCallback onBack;
  final VoidCallback onChanged;
  final PlpResortTransactionAction action;

  @override
  State<PlpResortMutationScreen> createState() =>
      _PlpResortMutationScreenState();
}

class _PlpResortMutationScreenState extends State<PlpResortMutationScreen> {
  late final TextEditingController _guestCount;
  late final TextEditingController _specialRequests;
  late final TextEditingController _guestName;
  late final TextEditingController _guestEmail;
  late final TextEditingController _guestPhone;
  late final TextEditingController _amount;
  late final TextEditingController _reference;
  late final TextEditingController _note;
  late final TextEditingController _rate;
  DateTime? _checkIn;
  DateTime? _checkOut;
  String? _roomId;
  String _roomState = 'ready';
  String _resolutionType = 'manual';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _guestCount = TextEditingController(text: _text(r['guestCount'], fallback: '1'));
    _specialRequests =
        TextEditingController(text: _text(r['specialRequest'], fallback: ''));
    _guestName = TextEditingController(text: _text(r['fullName'], fallback: ''));
    _guestEmail = TextEditingController();
    _guestPhone = TextEditingController();
    _amount = TextEditingController();
    _reference = TextEditingController();
    _note = TextEditingController();
    _rate = TextEditingController(text: _text(r['nightlyRatePhp'], fallback: ''));
    _checkIn = _parseDate(r['checkIn']);
    _checkOut = _parseDate(r['checkOut']);
    if (widget.actionId == 'edit_booking') {
      final currentRoomName =
          _text(r['accommodationName'], fallback: '').toLowerCase();
      for (final room in _rooms) {
        if (_text(room['name']).toLowerCase() == currentRoomName) {
          _roomId = _text(room['id']);
          break;
        }
      }
    } else {
      _roomId = _text(r['id']).isEmpty ? null : _text(r['id']);
    }
    _roomState = _text(r['operationalState'], fallback: 'ready').toLowerCase();
    if (!const {'ready','cleaning','maintenance','out_of_order'}
        .contains(_roomState)) {
      _roomState = 'ready';
    }
  }

  @override
  void dispose() {
    _guestCount.dispose();
    _specialRequests.dispose();
    _guestName.dispose();
    _guestEmail.dispose();
    _guestPhone.dispose();
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    _rate.dispose();
    super.dispose();
  }

  List<Map<String, Object?>> get _rooms =>
      _maps(_map(widget.bootstrap['resortCommandCenter'])['rooms']);

  Future<void> _pickDate(bool checkIn) async {
    final current = checkIn ? _checkIn : _checkOut;
    final base = checkIn ? DateTime.now() : (_checkIn ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? (checkIn ? base : base.add(const Duration(days: 1))),
      firstDate: checkIn ? DateTime(base.year - 1) : base.add(const Duration(days: 1)),
      lastDate: DateTime(base.year + 3),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (checkIn) {
        _checkIn = picked;
        if (_checkOut == null || !_checkOut!.isAfter(picked)) {
          _checkOut = picked.add(const Duration(days: 1));
        }
      } else {
        _checkOut = picked;
      }
    });
  }

  (String, Map<String, Object?>) _transaction() {
    final bookingReference = _text(widget.record['bookingReference']);
    switch (widget.actionId) {
      case 'edit_booking':
        return (
          'update_booking',
          <String, Object?>{
            'bookingReference': bookingReference,
            if (_roomId != null) 'accommodationId': _roomId!,
            if (_checkIn != null) 'checkIn': _date(_checkIn!),
            if (_checkOut != null) 'checkOut': _date(_checkOut!),
            'guestCount': int.tryParse(_guestCount.text.trim()) ?? 1,
            'specialRequests': _specialRequests.text.trim(),
          },
        );
      case 'check_in':
        return ('check_in', <String, Object?>{'bookingReference': bookingReference});
      case 'check_out':
        return ('check_out', <String, Object?>{'bookingReference': bookingReference});
      case 'cancel_booking':
        return ('cancel_booking', <String, Object?>{'bookingReference': bookingReference});
      case 'update_guest':
        return (
          'update_guest',
          <String, Object?>{
            'bookingReference': bookingReference,
            if (_guestName.text.trim().isNotEmpty)
              'guestFullName': _guestName.text.trim(),
            if (_guestEmail.text.trim().isNotEmpty)
              'guestEmail': _guestEmail.text.trim(),
            if (_guestPhone.text.trim().isNotEmpty)
              'guestPhone': _guestPhone.text.trim(),
            if (_specialRequests.text.trim().isNotEmpty)
              'specialRequests': _specialRequests.text.trim(),
          },
        );
      case 'manual_payment':
        return (
          'record_manual_payment',
          <String, Object?>{
            'bookingReference': bookingReference,
            'amountPhp': num.tryParse(_amount.text.trim()) ?? 0,
            'reference': _reference.text.trim(),
            if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
          },
        );
      case 'room_state':
        return (
          'set_room_state',
          <String, Object?>{
            'accommodationId': _text(widget.record['id']),
            'state': _roomState,
            if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
          },
        );
      case 'room_rate':
        return (
          'set_room_rate',
          <String, Object?>{
            'accommodationId': _text(widget.record['id']),
            'nightlyRatePhp': num.tryParse(_rate.text.trim()) ?? -1,
          },
        );
      case 'task_done':
        return (
          'update_task',
          <String, Object?>{
            'taskId': _text(widget.record['id']),
            'status': 'done',
          },
        );
      case 'resolve_conflict':
        return (
          'resolve_conflict',
          <String, Object?>{
            'conflictId': _text(widget.record['id']),
            'resolutionType': _resolutionType,
            if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
          },
        );
    }
    throw const PlpResortTransactionFailure('Unsupported resort action.');
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final tx = _transaction();
      await widget.action.execute(
        requestId:
            'plp-${widget.actionId}-${DateTime.now().microsecondsSinceEpoch}',
        action: tx.$1,
        payload: tx.$2,
      );
      widget.onChanged();
      if (!mounted) return;
      widget.onBack();
    } on PlpResortTransactionFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _actionConfig(widget.actionId);
    final fields = <Widget>[];
    switch (widget.actionId) {
      case 'edit_booking':
        fields.addAll([
          DropdownButtonFormField<String>(
            key: const ValueKey('plp-edit-booking-room'),
            value: _roomId,
            decoration: _decoration('Room'),
            items: [
              for (final room in _rooms)
                DropdownMenuItem<String>(
                  value: _text(room['id']),
                  child: Text(_text(room['name'], fallback: 'Room')),
                ),
            ],
            onChanged: (value) => setState(() => _roomId = value),
          ),
          _DateButton(label: 'Check-in', value: _checkIn, onTap: () => _pickDate(true)),
          _DateButton(label: 'Check-out', value: _checkOut, onTap: () => _pickDate(false)),
          _Field(controller: _guestCount, label: 'Guests', keyboardType: TextInputType.number),
          _Field(controller: _specialRequests, label: 'Special requests', maxLines: 3),
        ]);
        break;
      case 'update_guest':
        fields.addAll([
          _Field(controller: _guestName, label: 'Guest name'),
          _Field(
            controller: _guestEmail,
            label: 'New email (leave blank to keep current)',
            keyboardType: TextInputType.emailAddress,
          ),
          _Field(
            controller: _guestPhone,
            label: 'New phone (leave blank to keep current)',
            keyboardType: TextInputType.phone,
          ),
          _Field(controller: _specialRequests, label: 'Special requests', maxLines: 3),
        ]);
        break;
      case 'manual_payment':
        fields.addAll([
          _Field(
            fieldKey: const ValueKey('plp-payment-amount'),
            controller: _amount,
            label: 'Amount (PHP)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          _Field(controller: _reference, label: 'Receipt / reference'),
          _Field(controller: _note, label: 'Note', maxLines: 3),
        ]);
        break;
      case 'room_state':
        fields.addAll([
          DropdownButtonFormField<String>(
            key: const ValueKey('plp-room-state-select'),
            value: _roomState,
            decoration: _decoration('Operational state'),
            items: const [
              DropdownMenuItem(value: 'ready', child: Text('Ready')),
              DropdownMenuItem(value: 'cleaning', child: Text('Cleaning')),
              DropdownMenuItem(value: 'maintenance', child: Text('Maintenance')),
              DropdownMenuItem(value: 'out_of_order', child: Text('Out of order')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _roomState = value);
            },
          ),
          _Field(controller: _note, label: 'Operational note', maxLines: 3),
        ]);
        break;
      case 'room_rate':
        fields.add(
          _Field(
            controller: _rate,
            label: 'Nightly rate (PHP)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        );
        break;
      case 'resolve_conflict':
        fields.addAll([
          DropdownButtonFormField<String>(
            value: _resolutionType,
            decoration: _decoration('Resolution'),
            items: const [
              DropdownMenuItem(value: 'manual', child: Text('Manually reconciled')),
              DropdownMenuItem(value: 'inventory', child: Text('Inventory corrected')),
              DropdownMenuItem(value: 'channel', child: Text('Channel corrected')),
              DropdownMenuItem(value: 'booking', child: Text('Booking corrected')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _resolutionType = value);
            },
          ),
          _Field(controller: _note, label: 'Resolution note', maxLines: 3),
        ]);
        break;
      default:
        fields.add(
          Text(
            config.confirmation,
            style: const TextStyle(color: _muted, fontSize: 13, height: 1.45),
          ),
        );
    }

    return _TransactionScaffold(
      key: ValueKey<String>('plp-mutation-${widget.actionId}'),
      title: config.title,
      eyebrow: config.eyebrow,
      onBack: widget.onBack,
      error: _error,
      children: [
        ...fields,
        _SubmitButton(
          buttonKey: ValueKey<String>('plp-mutation-submit-${widget.actionId}'),
          label: config.button,
          busy: _saving,
          destructive: config.destructive,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _ActionConfig {
  const _ActionConfig({
    required this.title,
    required this.eyebrow,
    required this.button,
    required this.confirmation,
    this.destructive = false,
  });

  final String title;
  final String eyebrow;
  final String button;
  final String confirmation;
  final bool destructive;
}

_ActionConfig _actionConfig(String action) {
  switch (action) {
    case 'edit_booking':
      return const _ActionConfig(
        title: 'Edit reservation',
        eyebrow: 'STAY',
        button: 'Save reservation',
        confirmation: '',
      );
    case 'check_in':
      return const _ActionConfig(
        title: 'Check in guest',
        eyebrow: 'ARRIVAL',
        button: 'Confirm check-in',
        confirmation: 'Confirm that the guest has arrived and the stay should move to checked in.',
      );
    case 'check_out':
      return const _ActionConfig(
        title: 'Check out guest',
        eyebrow: 'DEPARTURE',
        button: 'Confirm check-out',
        confirmation: 'Confirm that the stay is complete and should move to checked out.',
      );
    case 'cancel_booking':
      return const _ActionConfig(
        title: 'Cancel reservation',
        eyebrow: 'STAY',
        button: 'Cancel reservation',
        confirmation: 'This closes the reservation. It does not issue a payment refund.',
        destructive: true,
      );
    case 'update_guest':
      return const _ActionConfig(
        title: 'Update guest',
        eyebrow: 'GUEST',
        button: 'Save guest',
        confirmation: '',
      );
    case 'manual_payment':
      return const _ActionConfig(
        title: 'Record payment',
        eyebrow: 'FINANCE',
        button: 'Record verified payment',
        confirmation: '',
      );
    case 'room_state':
      return const _ActionConfig(
        title: 'Room state',
        eyebrow: 'ROOM',
        button: 'Update room state',
        confirmation: '',
      );
    case 'room_rate':
      return const _ActionConfig(
        title: 'Nightly rate',
        eyebrow: 'REVENUE',
        button: 'Update rate',
        confirmation: '',
      );
    case 'task_done':
      return const _ActionConfig(
        title: 'Complete work',
        eyebrow: 'OPERATIONS',
        button: 'Mark done',
        confirmation: 'Confirm that this work item is complete.',
      );
    case 'resolve_conflict':
      return const _ActionConfig(
        title: 'Resolve channel exception',
        eyebrow: 'CHANNELS',
        button: 'Resolve exception',
        confirmation: '',
      );
  }
  return const _ActionConfig(
    title: 'Resort action',
    eyebrow: 'PLP',
    button: 'Continue',
    confirmation: '',
  );
}

class _TransactionScaffold extends StatelessWidget {
  const _TransactionScaffold({
    super.key,
    required this.title,
    required this.eyebrow,
    required this.onBack,
    required this.children,
    this.error,
  });

  final String title;
  final String eyebrow;
  final VoidCallback onBack;
  final List<Widget> children;
  final String? error;

  @override
  Widget build(BuildContext context) => Material(
        color: _canvas,
        child: SafeArea(
          bottom: false,
          child: ListView(
            key: const ValueKey('plp-transaction-scroll'),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 190),
            children: [
              Row(
                children: [
                  const SizedBox(width: 56),
                  Expanded(
                    child: Text(
                      eyebrow,
                      style: const TextStyle(
                        color: _accent,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('plp-transaction-back'),
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontFamily: 'serif',
                  fontSize: 38,
                  height: 1,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -1,
                ),
              ),
              if (error != null && error!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFF2EB),
                    border: Border.fromBorderSide(BorderSide(color: Color(0xFFE8C4AE))),
                  ),
                  child: Text(
                    error!,
                    style: const TextStyle(color: _ink, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              for (final child in children) ...[
                child,
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      );
}

class _Field extends StatelessWidget {
  const _Field({
    this.fieldKey,
    required this.controller,
    required this.label,
    this.keyboardType,
    this.maxLines = 1,
  });

  final Key? fieldKey;
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) => TextField(
        key: fieldKey,
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: _decoration(label),
      );
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    this.buttonKey,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final Key? buttonKey;
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        key: buttonKey,
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: _ink,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          shape: const RoundedRectangleBorder(),
          side: const BorderSide(color: _line),
          backgroundColor: _paper,
        ),
        child: Text(
          value == null ? label : '$label · ${_date(value!)}',
        ),
      );
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    this.buttonKey,
    required this.label,
    required this.busy,
    required this.onPressed,
    this.destructive = false,
  });

  final Key? buttonKey;
  final String label;
  final bool busy;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: buttonKey,
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: destructive ? const Color(0xFF7C3028) : _ink,
            foregroundColor: Colors.white,
            shape: const RoundedRectangleBorder(),
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          child: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(label),
        ),
      );
}

InputDecoration _decoration(String label) => InputDecoration(
      labelText: label,
      filled: true,
      fillColor: _paper,
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: _line),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: _accent),
      ),
    );

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

String _text(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

DateTime? _parseDate(Object? value) {
  final raw = _text(value);
  return raw.isEmpty ? null : DateTime.tryParse(raw);
}

String _date(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}
