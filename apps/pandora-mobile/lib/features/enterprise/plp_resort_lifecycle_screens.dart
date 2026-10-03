import 'package:flutter/material.dart';

import '../../core/data/plp_resort_lifecycle_api.dart';

typedef PlpLifecycleChanged = void Function(Map<String, Object?> result);

const _canvas = Color(0xFFFAF7F1);
const _paper = Color(0xFFFFFDFC);
const _ink = Color(0xFF171512);
const _muted = Color(0xFF756F67);
const _line = Color(0xFFE4DCCF);
const _accent = Color(0xFF776A43);
const _good = Color(0xFF60745F);
const _warn = Color(0xFFA46C31);

class PlpReservationCreateScreen extends StatefulWidget {
  const PlpReservationCreateScreen({
    super.key,
    required this.bootstrap,
    required this.onBack,
    required this.onChanged,
    this.gateway = const SupabasePlpResortLifecycleGateway(),
    this.initialCheckIn,
    this.initialCheckOut,
  });

  final Map<String, Object?> bootstrap;
  final VoidCallback onBack;
  final PlpLifecycleChanged onChanged;
  final PlpResortLifecycleGateway gateway;
  final DateTime? initialCheckIn;
  final DateTime? initialCheckOut;

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
  final _requests = TextEditingController();
  late DateTime _checkIn;
  late DateTime _checkOut;
  String? _roomId;
  bool _busy = false;
  String? _error;

  List<Map<String, Object?>> get _rooms =>
      _maps(_map(widget.bootstrap['resortCommandCenter'])['rooms'])
          .where((room) => _text(room['id']).isNotEmpty)
          .toList(growable: false);

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _checkIn = _dateOnly(
      widget.initialCheckIn ?? today.add(const Duration(days: 1)),
    );
    _checkOut = _dateOnly(
      widget.initialCheckOut ?? today.add(const Duration(days: 2)),
    );
    if (_rooms.isNotEmpty) _roomId = _text(_rooms.first['id']);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _guestCount.dispose();
    _requests.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool checkIn) async {
    final current = checkIn ? _checkIn : _checkOut;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 1095)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (checkIn) {
        _checkIn = _dateOnly(picked);
        if (!_checkOut.isAfter(_checkIn)) {
          _checkOut = _checkIn.add(const Duration(days: 1));
        }
      } else {
        _checkOut = _dateOnly(picked);
      }
    });
  }

  Future<void> _submit() async {
    final count = int.tryParse(_guestCount.text.trim());
    if (_name.text.trim().length < 2 ||
        !_email.text.contains('@') ||
        _roomId == null ||
        count == null ||
        count <= 0 ||
        !_checkOut.isAfter(_checkIn)) {
      setState(() => _error = 'Complete the guest, room, dates and guest count.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.gateway.createReservation(
        requestId: _requestId('reservation-create'),
        guestName: _name.text.trim(),
        guestEmail: _email.text.trim(),
        guestPhone: _nullable(_phone.text),
        accommodationId: _roomId!,
        checkIn: _checkIn,
        checkOut: _checkOut,
        guestCount: count,
        specialRequests: _nullable(_requests.text),
      );
      if (!mounted) return;
      widget.onChanged(result);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reservation created and verified.')),
      );
      widget.onBack();
    } on PlpResortLifecycleFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _LifecycleScaffold(
        surfaceKey: const ValueKey('plp-reservation-create'),
        title: 'New reservation',
        eyebrow: 'RESERVATIONS',
        onBack: widget.onBack,
        children: [
          _TextField(
            fieldKey: const ValueKey('plp-reservation-guest-name'),
            controller: _name,
            label: 'Guest name',
            hint: 'Full name',
          ),
          _TextField(
            fieldKey: const ValueKey('plp-reservation-guest-email'),
            controller: _email,
            label: 'Email',
            hint: 'guest@example.com',
            keyboardType: TextInputType.emailAddress,
          ),
          _TextField(
            controller: _phone,
            label: 'Phone',
            hint: 'Optional',
            keyboardType: TextInputType.phone,
          ),
          _Section('ROOM'),
          if (_rooms.isEmpty)
            const _Notice(
              'No connected room can accept a reservation yet.',
              warning: true,
            )
          else
            DropdownButtonFormField<String>(
              key: const ValueKey('plp-reservation-room'),
              initialValue: _roomId,
              decoration: _inputDecoration('Room'),
              items: [
                for (final room in _rooms)
                  DropdownMenuItem(
                    value: _text(room['id']),
                    child: Text(
                      '${_text(room['name'], fallback: 'Room')} · '
                      '${_peso(room['nightlyRatePhp'])}',
                    ),
                  ),
              ],
              onChanged: _busy ? null : (value) => setState(() => _roomId = value),
            ),
          _Section('STAY'),
          _DateRow(
            label: 'Check-in',
            value: _checkIn,
            keyValue: 'plp-reservation-check-in',
            onTap: _busy ? null : () => _pickDate(true),
          ),
          _DateRow(
            label: 'Check-out',
            value: _checkOut,
            keyValue: 'plp-reservation-check-out',
            onTap: _busy ? null : () => _pickDate(false),
          ),
          _TextField(
            fieldKey: const ValueKey('plp-reservation-guest-count'),
            controller: _guestCount,
            label: 'Guests',
            hint: '1',
            keyboardType: TextInputType.number,
          ),
          _TextField(
            controller: _requests,
            label: 'Special requests',
            hint: 'Optional',
            maxLines: 3,
          ),
          if (_error != null) _ErrorText(_error!),
          _PrimaryAction(
            controlKey: const ValueKey('plp-reservation-submit'),
            label: 'Create reservation',
            busy: _busy,
            onPressed: _rooms.isEmpty ? null : _submit,
          ),
        ],
      );
}

class PlpStayLifecycleScreen extends StatefulWidget {
  const PlpStayLifecycleScreen({
    super.key,
    required this.record,
    required this.role,
    required this.onBack,
    required this.onChanged,
    this.gateway = const SupabasePlpResortLifecycleGateway(),
  });

  final Map<String, Object?> record;
  final String role;
  final VoidCallback onBack;
  final PlpLifecycleChanged onChanged;
  final PlpResortLifecycleGateway gateway;

  @override
  State<PlpStayLifecycleScreen> createState() => _PlpStayLifecycleScreenState();
}

class _PlpStayLifecycleScreenState extends State<PlpStayLifecycleScreen> {
  Map<String, Object?>? _detail;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  String get _bookingReference =>
      _text(widget.record['bookingReference'], fallback: '');
  bool get _canManage =>
      const {'owner', 'admin', 'operator'}.contains(widget.role.toLowerCase());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_bookingReference.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'This stay has no booking reference.';
      });
      return;
    }
    try {
      final detail = await widget.gateway.reservationDetail(_bookingReference);
      if (mounted) setState(() => _detail = detail);
    } on PlpResortLifecycleFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _transition(String action) async {
    if (_busy) return;
    if (action == 'cancel') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cancel reservation?'),
          content: const Text(
            'This removes the stay from active room inventory. '
            'The action is recorded in business activity.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep reservation'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel reservation'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.gateway.transitionReservation(
        requestId: _requestId('reservation-$action'),
        bookingReference: _bookingReference,
        action: action,
      );
      widget.onChanged(result);
      await _load();
    } on PlpResortLifecycleFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editStay() async {
    final detail = _detail;
    if (detail == null) return;
    final draft = await showModalBottomSheet<_StayEditDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _paper,
      builder: (_) => _StayEditSheet(detail: detail),
    );
    if (draft == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.gateway.updateReservation(
        requestId: _requestId('reservation-edit'),
        bookingReference: _bookingReference,
        patch: <String, Object?>{
          'checkIn': _isoDate(draft.checkIn),
          'checkOut': _isoDate(draft.checkOut),
          'guestCount': draft.guestCount,
          'specialRequests': draft.specialRequests,
        },
      );
      widget.onChanged(result);
      await _load();
    } on PlpResortLifecycleFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editGuest() async {
    final detail = _detail;
    if (detail == null) return;
    final draft = await showModalBottomSheet<_GuestEditDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _paper,
      builder: (_) => _GuestEditSheet(detail: detail),
    );
    if (draft == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.gateway.updateGuest(
        requestId: _requestId('guest-edit'),
        bookingReference: _bookingReference,
        patch: <String, Object?>{
          'fullName': draft.fullName,
          'email': draft.email,
          'phone': draft.phone,
          'specialRequests': draft.specialRequests,
        },
      );
      widget.onChanged(result);
      await _load();
    } on PlpResortLifecycleFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recordPayment() async {
    final detail = _detail;
    if (detail == null) return;
    final draft = await showModalBottomSheet<_PaymentDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _paper,
      builder: (_) => _PaymentSheet(
        balance: _number(detail['balanceAmountPhp']),
      ),
    );
    if (draft == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.gateway.recordPayment(
        requestId: _requestId('payment-record'),
        bookingReference: _bookingReference,
        amountPhp: draft.amount,
        method: draft.method,
        reference: draft.reference,
      );
      widget.onChanged(result);
      await _load();
    } on PlpResortLifecycleFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail ?? widget.record;
    final status = _text(detail['status']).toUpperCase();
    final paymentStatus = _text(detail['paymentStatus']);
    final balance = _number(detail['balanceAmountPhp']);
    final checkedIn = const {'CHECKED_IN', 'IN_HOUSE'}.contains(status);
    final finalized = const {
      'CHECKED_OUT',
      'CANCELLED',
      'CANCELED',
    }.contains(status);

    return _LifecycleScaffold(
      surfaceKey: const ValueKey('plp-stay-lifecycle'),
      title: _text(detail['fullName'], fallback: 'Guest stay'),
      eyebrow: 'STAY · $_bookingReference',
      onBack: widget.onBack,
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) _ErrorText(_error!),
        _Detail('Room', _text(detail['accommodationName'])),
        _Detail(
          'Stay',
          '${_text(detail['checkIn'])} → ${_text(detail['checkOut'])}',
        ),
        _Detail('Guests', _text(detail['guestCount'])),
        _Detail('Status', _humanStatus(status)),
        _Detail('Payment', _humanStatus(paymentStatus)),
        _Detail('Balance', _peso(balance)),
        if (_text(detail['specialRequests']).isNotEmpty)
          _Detail('Request', _text(detail['specialRequests'])),
        if (_canManage && !_loading) ...[
          const _Section('NORMAL SYSTEM ACTIONS'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SmallAction(
                controlKey: const ValueKey('plp-stay-edit'),
                label: 'Edit stay',
                icon: Icons.edit_calendar_outlined,
                onTap: finalized || _busy ? null : _editStay,
              ),
              _SmallAction(
                controlKey: const ValueKey('plp-guest-edit'),
                label: 'Edit guest',
                icon: Icons.person_outline,
                onTap: _busy ? null : _editGuest,
              ),
              _SmallAction(
                controlKey: const ValueKey('plp-payment-record'),
                label: 'Record payment',
                icon: Icons.payments_outlined,
                onTap: balance <= 0 || finalized || _busy ? null : _recordPayment,
              ),
              if (!checkedIn && !finalized)
                _SmallAction(
                  controlKey: const ValueKey('plp-stay-check-in'),
                  label: 'Check in',
                  icon: Icons.login_rounded,
                  onTap: _busy ? null : () => _transition('check_in'),
                ),
              if (checkedIn)
                _SmallAction(
                  controlKey: const ValueKey('plp-stay-check-out'),
                  label: 'Check out',
                  icon: Icons.logout_rounded,
                  onTap: _busy ? null : () => _transition('check_out'),
                ),
              if (!finalized)
                _SmallAction(
                  controlKey: const ValueKey('plp-stay-cancel'),
                  label: 'Cancel',
                  icon: Icons.cancel_outlined,
                  destructive: true,
                  onTap: _busy ? null : () => _transition('cancel'),
                ),
            ],
          ),
        ],
        if (!_canManage)
          const _Notice(
            'This account has read access. Owner, admin or operator access is required for stay changes.',
          ),
      ],
    );
  }
}

class PlpRoomLifecycleScreen extends StatefulWidget {
  const PlpRoomLifecycleScreen({
    super.key,
    required this.room,
    required this.role,
    required this.onBack,
    required this.onChanged,
    this.gateway = const SupabasePlpResortLifecycleGateway(),
  });

  final Map<String, Object?> room;
  final String role;
  final VoidCallback onBack;
  final PlpLifecycleChanged onChanged;
  final PlpResortLifecycleGateway gateway;

  @override
  State<PlpRoomLifecycleScreen> createState() => _PlpRoomLifecycleScreenState();
}

class _PlpRoomLifecycleScreenState extends State<PlpRoomLifecycleScreen> {
  bool _busy = false;
  String? _error;
  late Map<String, Object?> _room;

  bool get _canAdmin =>
      const {'owner', 'admin'}.contains(widget.role.toLowerCase());

  @override
  void initState() {
    super.initState();
    _room = Map<String, Object?>.from(widget.room);
  }

  Future<void> _edit() async {
    final draft = await showModalBottomSheet<_RoomEditDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _paper,
      builder: (_) => _RoomEditSheet(room: _room),
    );
    if (draft == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.gateway.updateRoom(
        requestId: _requestId('room-edit'),
        accommodationId: _text(_room['id']),
        patch: <String, Object?>{
          'nightlyRatePhp': draft.rate,
          'capacity': draft.capacity,
          'bedrooms': draft.bedrooms,
          'isActive': draft.active,
        },
      );
      setState(() {
        _room = <String, Object?>{
          ..._room,
          'nightlyRatePhp': result['nightlyRatePhp'],
          'capacity': result['capacity'],
          'bedrooms': result['bedrooms'],
          'isActive': result['isActive'],
        };
      });
      widget.onChanged(result);
    } on PlpResortLifecycleFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _LifecycleScaffold(
        surfaceKey: const ValueKey('plp-room-lifecycle'),
        title: _text(_room['name'], fallback: 'Room'),
        eyebrow: 'ROOM',
        onBack: widget.onBack,
        children: [
          if (_error != null) _ErrorText(_error!),
          _Detail('Current state', _humanStatus(_text(_room['state']))),
          _Detail('Nightly rate', _peso(_room['nightlyRatePhp'])),
          _Detail('Capacity', _text(_room['capacity'])),
          _Detail('Bedrooms', _text(_room['bedrooms'])),
          if (_canAdmin)
            _PrimaryAction(
              controlKey: const ValueKey('plp-room-edit'),
              label: 'Edit room settings',
              busy: _busy,
              onPressed: _edit,
            )
          else
            const _Notice(
              'Owner or admin access is required to change room configuration.',
            ),
        ],
      );
}

class _LifecycleScaffold extends StatelessWidget {
  const _LifecycleScaffold({
    this.surfaceKey,
    required this.title,
    required this.eyebrow,
    required this.onBack,
    required this.children,
  });

  final Key? surfaceKey;
  final String title;
  final String eyebrow;
  final VoidCallback onBack;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
        key: surfaceKey,
        color: _canvas,
        child: SafeArea(
          bottom: false,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 190),
            children: [
              Row(
                children: [
                  const SizedBox(width: 56),
                  Expanded(
                    child: Text(
                      eyebrow,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _accent,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('plp-lifecycle-back'),
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 28),
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
              const SizedBox(height: 26),
              ...children,
            ],
          ),
        ),
      );
}

class _StayEditDraft {
  const _StayEditDraft({
    required this.checkIn,
    required this.checkOut,
    required this.guestCount,
    required this.specialRequests,
  });
  final DateTime checkIn;
  final DateTime checkOut;
  final int guestCount;
  final String? specialRequests;
}

class _StayEditSheet extends StatefulWidget {
  const _StayEditSheet({required this.detail});
  final Map<String, Object?> detail;
  @override
  State<_StayEditSheet> createState() => _StayEditSheetState();
}

class _StayEditSheetState extends State<_StayEditSheet> {
  late DateTime _in;
  late DateTime _out;
  late final TextEditingController _count;
  late final TextEditingController _requests;

  @override
  void initState() {
    super.initState();
    _in = _parseDate(widget.detail['checkIn']) ?? DateTime.now();
    _out = _parseDate(widget.detail['checkOut']) ??
        _in.add(const Duration(days: 1));
    _count = TextEditingController(
      text: _text(widget.detail['guestCount'], fallback: '1'),
    );
    _requests = TextEditingController(
      text: _text(widget.detail['specialRequests']),
    );
  }

  @override
  void dispose() {
    _count.dispose();
    _requests.dispose();
    super.dispose();
  }

  Future<void> _pick(bool inbound) async {
    final value = inbound ? _in : _out;
    final picked = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 1095)),
    );
    if (picked == null) return;
    setState(() {
      if (inbound) {
        _in = _dateOnly(picked);
        if (!_out.isAfter(_in)) _out = _in.add(const Duration(days: 1));
      } else {
        _out = _dateOnly(picked);
      }
    });
  }

  @override
  Widget build(BuildContext context) => _Sheet(
        title: 'Edit stay',
        children: [
          _DateRow(label: 'Check-in', value: _in, onTap: () => _pick(true)),
          _DateRow(label: 'Check-out', value: _out, onTap: () => _pick(false)),
          _TextField(
            controller: _count,
            label: 'Guests',
            hint: '1',
            keyboardType: TextInputType.number,
          ),
          _TextField(
            controller: _requests,
            label: 'Special requests',
            hint: 'Optional',
            maxLines: 3,
          ),
          _PrimaryAction(
            label: 'Save stay',
            onPressed: () {
              final count = int.tryParse(_count.text.trim());
              if (count == null || count <= 0 || !_out.isAfter(_in)) return;
              Navigator.pop(
                context,
                _StayEditDraft(
                  checkIn: _in,
                  checkOut: _out,
                  guestCount: count,
                  specialRequests: _nullable(_requests.text),
                ),
              );
            },
          ),
        ],
      );
}

class _GuestEditDraft {
  const _GuestEditDraft({
    required this.fullName,
    required this.email,
    this.phone,
    this.specialRequests,
  });
  final String fullName;
  final String email;
  final String? phone;
  final String? specialRequests;
}

class _GuestEditSheet extends StatefulWidget {
  const _GuestEditSheet({required this.detail});
  final Map<String, Object?> detail;
  @override
  State<_GuestEditSheet> createState() => _GuestEditSheetState();
}

class _GuestEditSheetState extends State<_GuestEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _requests;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: _text(widget.detail['fullName']));
    _email = TextEditingController(text: _text(widget.detail['email']));
    _phone = TextEditingController(text: _text(widget.detail['phone']));
    _requests = TextEditingController(
      text: _text(widget.detail['specialRequests']),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _requests.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Sheet(
        title: 'Edit guest',
        children: [
          _TextField(controller: _name, label: 'Name', hint: 'Full name'),
          _TextField(
            controller: _email,
            label: 'Email',
            hint: 'guest@example.com',
            keyboardType: TextInputType.emailAddress,
          ),
          _TextField(
            controller: _phone,
            label: 'Phone',
            hint: 'Optional',
            keyboardType: TextInputType.phone,
          ),
          _TextField(
            controller: _requests,
            label: 'Special requests',
            hint: 'Optional',
            maxLines: 3,
          ),
          _PrimaryAction(
            label: 'Save guest',
            onPressed: () {
              if (_name.text.trim().length < 2 || !_email.text.contains('@')) {
                return;
              }
              Navigator.pop(
                context,
                _GuestEditDraft(
                  fullName: _name.text.trim(),
                  email: _email.text.trim(),
                  phone: _nullable(_phone.text),
                  specialRequests: _nullable(_requests.text),
                ),
              );
            },
          ),
        ],
      );
}

class _PaymentDraft {
  const _PaymentDraft({
    required this.amount,
    required this.method,
    this.reference,
  });
  final num amount;
  final String method;
  final String? reference;
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.balance});
  final num balance;
  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  late final TextEditingController _amount;
  final _reference = TextEditingController();
  String _method = 'cash';

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: widget.balance.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Sheet(
        title: 'Record payment',
        children: [
          _TextField(
            fieldKey: const ValueKey('plp-payment-amount'),
            controller: _amount,
            label: 'Amount',
            hint: '0.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: _inputDecoration('Method'),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
              DropdownMenuItem(value: 'card', child: Text('Card')),
              DropdownMenuItem(
                value: 'bank_transfer',
                child: Text('Bank transfer'),
              ),
              DropdownMenuItem(value: 'wallet', child: Text('Wallet')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: (value) => setState(() => _method = value ?? 'cash'),
          ),
          _TextField(
            controller: _reference,
            label: 'Reference',
            hint: 'Optional receipt / transaction reference',
          ),
          _Notice(
            'This records an already-received payment. It does not charge a card or wallet.',
          ),
          _PrimaryAction(
            controlKey: const ValueKey('plp-payment-submit'),
            label: 'Record verified payment',
            onPressed: () {
              final amount = num.tryParse(_amount.text.trim());
              if (amount == null || amount <= 0 || amount > widget.balance) {
                return;
              }
              Navigator.pop(
                context,
                _PaymentDraft(
                  amount: amount,
                  method: _method,
                  reference: _nullable(_reference.text),
                ),
              );
            },
          ),
        ],
      );
}

class _RoomEditDraft {
  const _RoomEditDraft({
    required this.rate,
    required this.capacity,
    required this.bedrooms,
    required this.active,
  });
  final num rate;
  final int capacity;
  final int bedrooms;
  final bool active;
}

class _RoomEditSheet extends StatefulWidget {
  const _RoomEditSheet({required this.room});
  final Map<String, Object?> room;
  @override
  State<_RoomEditSheet> createState() => _RoomEditSheetState();
}

class _RoomEditSheetState extends State<_RoomEditSheet> {
  late final TextEditingController _rate;
  late final TextEditingController _capacity;
  late final TextEditingController _bedrooms;
  late bool _active;

  @override
  void initState() {
    super.initState();
    _rate = TextEditingController(
      text: _number(widget.room['nightlyRatePhp']).toStringAsFixed(2),
    );
    _capacity = TextEditingController(
      text: _text(widget.room['capacity'], fallback: '1'),
    );
    _bedrooms = TextEditingController(
      text: _text(widget.room['bedrooms'], fallback: '0'),
    );
    _active = widget.room['isActive'] != false;
  }

  @override
  void dispose() {
    _rate.dispose();
    _capacity.dispose();
    _bedrooms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Sheet(
        title: 'Edit room settings',
        children: [
          _TextField(
            controller: _rate,
            label: 'Nightly rate',
            hint: '0.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          _TextField(
            controller: _capacity,
            label: 'Capacity',
            hint: '1',
            keyboardType: TextInputType.number,
          ),
          _TextField(
            controller: _bedrooms,
            label: 'Bedrooms',
            hint: '0',
            keyboardType: TextInputType.number,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active room'),
            value: _active,
            onChanged: (value) => setState(() => _active = value),
          ),
          _PrimaryAction(
            label: 'Save room',
            onPressed: () {
              final rate = num.tryParse(_rate.text.trim());
              final capacity = int.tryParse(_capacity.text.trim());
              final bedrooms = int.tryParse(_bedrooms.text.trim());
              if (rate == null ||
                  rate < 0 ||
                  capacity == null ||
                  capacity <= 0 ||
                  bedrooms == null ||
                  bedrooms < 0) {
                return;
              }
              Navigator.pop(
                context,
                _RoomEditDraft(
                  rate: rate,
                  capacity: capacity,
                  bedrooms: bedrooms,
                  active: _active,
                ),
              );
            },
          ),
        ],
      );
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontFamily: 'serif',
                  fontSize: 28,
                ),
              ),
              const SizedBox(height: 18),
              ...children.expand(
                (widget) => <Widget>[widget, const SizedBox(height: 10)],
              ),
            ],
          ),
        ),
      );
}

class _TextField extends StatelessWidget {
  const _TextField({
    this.fieldKey,
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
  });

  final Key? fieldKey;
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => TextField(
        key: fieldKey,
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: _inputDecoration(label).copyWith(hintText: hint),
      );
}

InputDecoration _inputDecoration(String label) => InputDecoration(
      labelText: label,
      filled: true,
      fillColor: _paper,
      border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: _line),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: _accent),
      ),
    );

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.keyValue,
  });
  final String label;
  final DateTime value;
  final VoidCallback? onTap;
  final String? keyValue;

  @override
  Widget build(BuildContext context) => InkWell(
        key: keyValue == null ? null : ValueKey<String>(keyValue!),
        onTap: onTap,
        child: Container(
          decoration: const BoxDecoration(
            color: _paper,
            border: Border.fromBorderSide(BorderSide(color: _line)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _isoDate(value),
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.calendar_today_outlined, size: 16),
            ],
          ),
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 2),
        child: Text(
          label,
          style: const TextStyle(
            color: _accent,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
          ),
        ),
      );
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _line)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 104,
              child: Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: _accent,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value.isEmpty ? '—' : value,
                style: const TextStyle(color: _ink, fontSize: 12.5),
              ),
            ),
          ],
        ),
      );
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    this.controlKey,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });
  final Key? controlKey;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: controlKey,
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: _ink,
            foregroundColor: Colors.white,
            shape: const RoundedRectangleBorder(),
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          child: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(label),
        ),
      );
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({
    this.controlKey,
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });
  final Key? controlKey;
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        key: controlKey,
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: destructive ? _warn : _ink,
          side: BorderSide(color: destructive ? _warn : _line),
          shape: const RoundedRectangleBorder(),
        ),
        icon: Icon(icon, size: 17),
        label: Text(label),
      );
}

class _Notice extends StatelessWidget {
  const _Notice(this.message, {this.warning = false});
  final String message;
  final bool warning;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: _paper,
          border: Border.all(color: warning ? _warn : _line),
        ),
        padding: const EdgeInsets.all(13),
        child: Text(
          message,
          style: TextStyle(
            color: warning ? _warn : _muted,
            fontSize: 11,
            height: 1.35,
          ),
        ),
      );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Text(
        message,
        key: const ValueKey('plp-lifecycle-error'),
        style: const TextStyle(color: _warn, fontSize: 11.5),
      );
}

String _requestId(String action) =>
    'plp-ui-$action-${DateTime.now().microsecondsSinceEpoch}';

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
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

String? _nullable(String value) {
  final text = value.trim();
  return text.isEmpty ? null : text;
}

num _number(Object? value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

DateTime? _parseDate(Object? value) {
  final parsed = DateTime.tryParse(_text(value));
  return parsed == null ? null : _dateOnly(parsed);
}

String _isoDate(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String _peso(Object? value) {
  final amount = _number(value).round();
  final raw = amount.abs().toString();
  final out = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 == 0) out.write(',');
    out.write(raw[i]);
  }
  return '${amount < 0 ? '-₱' : '₱'}$out';
}

String _humanStatus(String value) {
  if (value.isEmpty) return '—';
  return value
      .toLowerCase()
      .replaceAll('-', '_')
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
