import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/data/plp_paypal_billing_api.dart';
import 'plp_resort_workspace.dart';

/// Billing renders through the same resort page frame, title, notice and
/// tile grid as Rooms & Housekeeping.
const plpBillingSection = PlpResortSection(
  id: 'billing',
  label: 'Billing',
  headerTitle: 'BILLING',
  icon: Icons.credit_card_outlined,
  commandHint: 'Ask about billing…',
);

typedef PlpBillingUrlLauncher = Future<bool> Function(Uri uri);

class PlpPaypalBillingScreen extends StatefulWidget {
  const PlpPaypalBillingScreen({
    super.key,
    required this.organizationId,
    required this.onOpenNavigation,
    this.transport,
    this.urlLauncher,
  });

  final String organizationId;
  final VoidCallback onOpenNavigation;
  final PlpBillingTransport? transport;
  final PlpBillingUrlLauncher? urlLauncher;

  @override
  State<PlpPaypalBillingScreen> createState() => _PlpPaypalBillingScreenState();
}

enum _BillingView { main, select, changeConfirm, cancelConfirm, history }

class _PlanOption {
  const _PlanOption(this.code, this.name, this.icon, this.fallbackMicros);
  final String code;
  final String name;
  final IconData icon;
  final int fallbackMicros;
}

class _HistoryRow {
  const _HistoryRow(this.amount, this.date, this.status);
  final String amount;
  final String date;
  final String status;
}

class _PlpPaypalBillingScreenState extends State<PlpPaypalBillingScreen> {
  static const _plans = <_PlanOption>[
    _PlanOption('launch', 'Launch', Icons.rocket_launch_outlined, 49000000),
    _PlanOption(
      'professional',
      'Professional',
      Icons.workspace_premium_outlined,
      149000000,
    ),
  ];

  bool _busy = false;
  bool _loaded = false;
  String? _pending;
  String? _error;
  Future<void> Function()? _retry;
  bool _unresolved = false;
  bool _cancelRequested = false;
  _BillingView _view = _BillingView.main;
  String? _target;

  /// Plan the owner picked (or the plan of an unfinished checkout). Kept when
  /// going back so the selection is never lost.
  String? _selectedPlanCode;
  final Map<String, String> _idempotencyKeys = <String, String>{};
  Map<String, dynamic> _status = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _initialLoad();
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) =>
      (widget.transport ?? plpOwnerBillingTransport(widget.organizationId))(
        path,
        method: method,
        body: body,
      );

  /// Replaces the shown state only with a successful backend read, so a
  /// failed read never overwrites the last confirmed state.
  Future<void> _fetchStatus() async {
    final result = await _request('/billing/paypal/status');
    if (!mounted) return;
    final state = _state(_map(result['subscription']));
    setState(() {
      _status = result;
      _loaded = true;
      final loadedSubscription = _map(result['subscription']);
      final loadedCheckout = _map(result['checkout']);
      final loadedPlanCode =
          (loadedSubscription['plan_code'] ?? loadedCheckout['plan_code'] ?? '')
              .toString();
      if (state != 'active' && _option(loadedPlanCode) != null) {
        _selectedPlanCode = loadedPlanCode;
      }
      if (state == 'cancelled' || state == 'canceled') {
        _cancelRequested = false;
      }
    });
  }

  Future<void> _initialLoad() async {
    try {
      await _fetchStatus();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _short(error);
        _retry = () => _run('Loading…', _fetchStatus);
      });
    }
  }

  Future<void> _run(String pending, Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _pending = pending;
      _error = null;
      _retry = null;
    });
    try {
      await work();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _short(error);
          _retry = () => _run(pending, work);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _pending = null;
        });
      }
    }
  }

  /// One short owner-facing line; raw provider errors never reach the page.
  String _short(Object error) {
    final raw = error.toString();
    if (raw.contains('Sign in again')) return 'Sign in again.';
    if (raw.contains('PAYPAL_NOT_CONFIGURED') ||
        raw.contains('PAYPAL_AUTH_FAILED')) {
      return 'PayPal is unavailable.';
    }
    if (raw.contains('could not be opened')) return 'PayPal didn’t open.';
    return _loaded ? 'PayPal didn’t respond.' : 'Couldn’t load.';
  }

  /// One key per intent, reused until it succeeds, so a retry after a
  /// network failure cannot start a second subscription or change.
  String _idempotency(String intent, String prefix) =>
      _idempotencyKeys.putIfAbsent(
        intent,
        () => '$prefix-${DateTime.now().microsecondsSinceEpoch}',
      );

  /// An unfinished PayPal approval (checkout or plan change) that can still
  /// be completed; '' when none.
  String _existingApprovalUrl() {
    final checkout = _map(_status['checkout']);
    final pending = _map(_status['pendingPlanChange']);
    final pendingStatus = (pending['status'] ?? '').toString().toLowerCase();
    final checkoutStatus = (checkout['status'] ?? '').toString().toLowerCase();
    final pendingUrl = _terminalApprovalStates.contains(pendingStatus)
        ? ''
        : (pending['approval_url'] ?? '').toString().trim();
    final checkoutUrl = _terminalApprovalStates.contains(checkoutStatus)
        ? ''
        : (checkout['approval_url'] ?? '').toString().trim();
    return pendingUrl.isNotEmpty ? pendingUrl : checkoutUrl;
  }

  static const _terminalApprovalStates = {
    'active',
    'completed',
    'cancelled',
    'canceled',
    'expired',
    'failed',
  };

  /// Resumes an existing PayPal approval session instead of creating a second
  /// checkout; only starts a new checkout when none is open.
  Future<void> _checkout(String code) => _run('Opening PayPal…', () async {
        final existingApproval = _existingApprovalUrl();
        if (existingApproval.isNotEmpty) {
          await _openApproval(existingApproval);
          return;
        }
        final intent = 'checkout:$code';
        final result = await _request(
          '/billing/paypal/checkout',
          method: 'POST',
          body: {
            'planCode': code,
            'idempotencyKey': _idempotency(intent, 'plp-checkout'),
            'returnUrl':
                'https://mcpmaster.vercel.app/#/enterprise/paypal-return',
            'cancelUrl':
                'https://mcpmaster.vercel.app/#/enterprise/paypal-cancel',
          },
        );
        _idempotencyKeys.remove(intent);
        _show(_BillingView.main);
        await _openApproval(result['approvalUrl']?.toString());
        await _fetchStatus();
      });

  Future<void> _changePlan(String code) => _run('Switching…', () async {
        final intent = 'change:$code';
        final result = await _request(
          '/billing/paypal/change-plan',
          method: 'POST',
          body: {
            'planCode': code,
            'idempotencyKey': _idempotency(intent, 'plp-plan-change'),
          },
        );
        _idempotencyKeys.remove(intent);
        _show(_BillingView.main);
        await _openApproval(result['approvalUrl']?.toString());
        await _fetchStatus();
      });

  /// Success is only what the reconciled status says; a provider failure
  /// keeps the last confirmed state and marks it unresolved.
  Future<void> _reconcile() => _run('Checking PayPal…', () async {
        try {
          await _request('/billing/paypal/reconcile', method: 'POST');
          await _fetchStatus();
          if (mounted) setState(() => _unresolved = false);
        } catch (_) {
          if (mounted) setState(() => _unresolved = true);
          rethrow;
        }
      });

  Future<void> _cancel() => _run('Cancelling…', () async {
        final result = await _request(
          '/billing/paypal/cancel',
          method: 'POST',
          body: const {'reason': 'Cancelled by Pandora owner'},
        );
        final outcome = _map(result['cancellation']);
        _show(_BillingView.main);
        await _fetchStatus();
        final state = _state(_map(_status['subscription']));
        if (mounted && state != 'cancelled' && state != 'canceled') {
          setState(() => _cancelRequested = outcome['cancelled'] != true);
        }
      });

  Future<void> _openApproval(String? value) async {
    if (value == null || value.isEmpty) return;
    final uri = Uri.tryParse(value);
    final launcher = widget.urlLauncher ??
        (Uri target) => launchUrl(target, mode: LaunchMode.externalApplication);
    if (uri == null || !await launcher(uri)) {
      throw Exception('PayPal approval could not be opened.');
    }
  }

  void _show(_BillingView view, [String? target]) {
    if (!mounted) return;
    setState(() {
      _error = null;
      _retry = null;
      _view = view;
      _target = target;
      if (view == _BillingView.select && target != null) {
        _selectedPlanCode = target;
      }
    });
  }

  VoidCallback? _tap(VoidCallback action) => _busy ? null : action;

  @override
  Widget build(BuildContext context) {
    final subscription = _map(_status['subscription']);
    final checkout = _map(_status['checkout']);
    final pending = _map(_status['pendingPlanChange']);
    final state = _state(subscription);
    final active = state == 'active';
    final cancelled = state == 'cancelled' || state == 'canceled';
    final cancelPending = _cancelRequested ||
        const {'cancel_requested', 'cancelling', 'pending_cancellation'}
            .contains(state);
    final currentCode =
        (subscription['plan_code'] ?? checkout['plan_code'] ?? '').toString();
    final pendingStatus = (pending['status'] ?? '').toString().toLowerCase();
    final pendingChange =
        pending.isNotEmpty && !_terminalApprovalStates.contains(pendingStatus);
    final pendingApproval =
        pendingChange ? (pending['approval_url'] ?? '').toString().trim() : '';
    final checkoutStatus = (checkout['status'] ?? '').toString().toLowerCase();
    final checkoutApproval = _terminalApprovalStates.contains(checkoutStatus)
        ? ''
        : (checkout['approval_url'] ?? '').toString().trim();
    // Verified only with provider evidence; a failed refresh keeps the last
    // confirmed data on screen but no longer calls it verified.
    final verified = !_unresolved &&
        subscription['source_kind'] == 'provider_verified' &&
        subscription['verified_at'] != null;
    final provider = _map(_status['provider']);
    final providerConfigured = provider['configured'] == true;
    final providerUnavailable = provider['configured'] == false;
    final providerLabel = verified
        ? 'Verified'
        : active
            ? 'Unconfirmed'
            : providerConfigured
                ? 'Configured'
                : 'Unavailable';
    // Renewal is shown only when the provider returned a date; never guessed.
    final renewalDate = plpBillingShortDate(subscription['renews_on']);
    final currentPrice = _monthlyPrice(subscription);
    final target = _option(_target);

    var notice = '';
    var tiles = <PlpCapability>[];

    final refreshTile = PlpCapability(
      'Refresh',
      Icons.sync_rounded,
      _tap(_reconcile),
      detail: active ? providerLabel : null,
      semanticLabel: active
          ? 'Refresh PayPal status, ${providerLabel.toLowerCase()}'
          : 'Check PayPal status',
    );
    final backTile = PlpCapability(
      'Back',
      Icons.arrow_back_rounded,
      _tap(() => _show(_BillingView.main)),
      showArrow: false,
    );
    final keepTile = PlpCapability(
      'Keep',
      Icons.check_circle_outline_rounded,
      _tap(() => _show(_BillingView.main)),
      showArrow: false,
    );
    PlpCapability openPaypal(String url) => PlpCapability(
          'Open PayPal',
          Icons.open_in_new_rounded,
          _tap(() => _run('Opening PayPal…', () => _openApproval(url))),
        );

    if (!_loaded) {
      notice = _error ?? 'Loading…';
      if (_error != null && _retry != null) {
        tiles = [PlpCapability('Retry', Icons.refresh_rounded, _tap(_retry!))];
      }
    } else if (!active && checkoutApproval.isNotEmpty) {
      notice = 'Finish in PayPal · not active yet';
      tiles = [openPaypal(checkoutApproval), refreshTile];
    } else if (active && pendingChange) {
      final to = _option((pending['to_plan_code'] ?? '').toString());
      notice =
          to == null ? 'Plan change pending' : 'Switch to ${to.name} pending';
      tiles = [
        if (pendingApproval.isNotEmpty) openPaypal(pendingApproval),
        refreshTile,
      ];
    } else if (active && cancelPending) {
      notice = 'Cancellation pending';
      tiles = [refreshTile];
    } else if (active &&
        _view == _BillingView.changeConfirm &&
        target != null) {
      final from = _option(currentCode)?.name ?? _planName(currentCode);
      final price = _planPrice(target);
      // Effective date only when the provider returned the renewal date.
      final when = renewalDate.isEmpty ? '' : ' from $renewalDate';
      notice = '$from to ${target.name} · $price$when';
      tiles = [
        PlpCapability(
          'Switch to ${target.name}',
          Icons.swap_horiz_rounded,
          _tap(() => _changePlan(target.code)),
          semanticLabel: 'Switch to ${target.name}, $price$when',
        ),
        keepTile,
      ];
    } else if (active && _view == _BillingView.cancelConfirm) {
      final plan = _option(currentCode)?.name ?? _planName(currentCode);
      notice = renewalDate.isEmpty
          ? 'Cancel $plan? No further charges.'
          : 'Cancel $plan? No charge on $renewalDate.';
      tiles = [
        keepTile,
        PlpCapability(
          'Cancel',
          Icons.do_not_disturb_on_outlined,
          _tap(_cancel),
          emphasis: true,
          semanticLabel: 'Cancel $plan subscription',
        ),
      ];
    } else if (active && _view == _BillingView.history) {
      final activity = _status['activity'];
      if (activity is! List) {
        notice = 'History unavailable.';
        tiles = [
          PlpCapability('Retry', Icons.refresh_rounded,
              _tap(() => _run('Loading…', _fetchStatus))),
          backTile,
        ];
      } else {
        final rows = _history(activity);
        notice = rows.isEmpty ? 'No payments yet.' : 'Recent payments';
        tiles = [
          // Two most recent real records keep the page to ~6 text items.
          for (final row in rows.take(2))
            PlpCapability(
              row.amount,
              Icons.receipt_long_outlined,
              null,
              detail: [row.date, row.status]
                  .where((part) => part.isNotEmpty)
                  .join(' · '),
            ),
          backTile,
        ];
      }
    } else if (active) {
      notice =
          _activeLine(subscription, currentCode, currentPrice, renewalDate);
      final others = _plans.where((plan) => plan.code != currentCode);
      tiles = [
        PlpCapability(
          'Change plan',
          Icons.swap_horiz_rounded,
          others.isEmpty
              ? null
              : _tap(
                  () => _show(_BillingView.changeConfirm, others.first.code)),
        ),
        refreshTile,
        PlpCapability(
          'History',
          Icons.receipt_long_outlined,
          _tap(() => _show(_BillingView.history)),
          semanticLabel: 'Payment history',
        ),
        PlpCapability(
          'Cancel',
          Icons.do_not_disturb_on_outlined,
          _tap(() => _show(_BillingView.cancelConfirm)),
          semanticLabel: 'Cancel subscription',
        ),
      ];
    } else if (_view == _BillingView.select && target != null) {
      notice = '${target.name} · ${_planPrice(target)}';
      tiles = [
        PlpCapability(
          'Pay with PayPal',
          Icons.open_in_new_rounded,
          _tap(() => _checkout(target.code)),
          semanticLabel:
              'Pay ${_planPrice(target)} for ${target.name} with PayPal',
        ),
        backTile,
      ];
    } else {
      final ends = plpBillingShortDate(subscription['ends_on']);
      // A cancelled subscription always says so; the end date only when known.
      notice = cancelled
          ? (ends.isEmpty ? 'Cancelled' : 'Cancelled · ends $ends')
          : providerUnavailable
              ? 'PayPal is unavailable.'
              : 'Pay monthly with PayPal.';
      tiles = [
        for (final plan in _plans)
          PlpCapability(
            plan.name,
            plan.icon,
            providerUnavailable
                ? null
                : _tap(() => _show(_BillingView.select, plan.code)),
            detail: _planPrice(plan),
            selected: !cancelled && _selectedPlanCode == plan.code,
            semanticLabel: '${plan.name}, ${_planPrice(plan)}'
                '${_selectedPlanCode == plan.code ? ', selected' : ''}',
          ),
      ];
    }

    if (_loaded && _pending != null) notice = _pending!;
    if (_loaded && _error != null) {
      notice = _error!;
      tiles = [
        if (_retry != null)
          PlpCapability('Retry', Icons.refresh_rounded, _tap(_retry!)),
        backTile,
      ];
    }

    return PlpResortPage(
      key: const ValueKey('plp-paypal-billing'),
      listKey: const ValueKey('plp-paypal-billing-list'),
      section: plpBillingSection,
      onRefresh: () {
        if (!_loaded) return _run('Loading…', _fetchStatus);
        if (active || checkoutApproval.isNotEmpty) return _reconcile();
        return _run('Loading…', _fetchStatus);
      },
      children: [
        if (notice.isNotEmpty) ...[
          Semantics(
            liveRegion: true,
            container: true,
            child: PlpResortNotice(
              notice,
              key: const ValueKey('plp-billing-notice'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (tiles.isNotEmpty) PlpCapabilityGrid(items: tiles),
        // Keeps the last tile clear of the floating PLP launcher.
        const SizedBox(height: 72),
      ],
    );
  }

  List<_HistoryRow> _history(List<dynamic> activity) {
    final rows = <_HistoryRow>[];
    for (final raw in activity.whereType<Map>()) {
      final item = Map<String, dynamic>.from(raw);
      final date = plpBillingShortDate(
        item['occurred_at'] ??
            item['paid_at'] ??
            item['created_at'] ??
            item['date'],
      );
      final currency = (item['currency'] ?? 'USD').toString();
      final micros = _plpNum(item['amount_micros']);
      final decimal = _plpNum(item['amount']);
      final amount = micros != null
          ? plpBillingFormatMicros(micros, currency)
          : decimal != null
              ? plpBillingFormatMicros(decimal * 1000000, currency)
              : '';
      if (date.isEmpty || amount.isEmpty) continue;
      final status = (item['status'] ?? item['state'] ?? '').toString();
      rows.add(_HistoryRow(
        amount,
        date,
        status.isEmpty
            ? ''
            : status[0].toUpperCase() +
                status.substring(1).toLowerCase().replaceAll('_', ' '),
      ));
    }
    return rows;
  }

  String _planPrice(_PlanOption plan) {
    for (final row
        in (_status['plans'] as List? ?? const []).whereType<Map>()) {
      if (row['code']?.toString() != plan.code) continue;
      final price = _monthlyPrice(Map<String, dynamic>.from(row));
      if (price != _priceUnavailable) return price;
    }
    return '${plpBillingFormatMicros(plan.fallbackMicros, 'USD')} / month';
  }

  String _activeLine(
    Map<String, dynamic> subscription,
    String code,
    String currentPrice,
    String renewalDate,
  ) {
    final name = (subscription['plan_name'] ?? '').toString().trim();
    final plan = name.isNotEmpty ? name : _planName(code);
    return [
      plan,
      currentPrice,
      if (renewalDate.isNotEmpty) 'renews $renewalDate',
    ].join(' · ');
  }

  static const _priceUnavailable = 'Price unavailable';

  /// Monthly price from a subscription (or plan) row returned by owner-api.
  /// The DB stores integer micros (monthly_fee_micros, discount_micros);
  /// decimal fields are accepted only as fallbacks. Never guessed.
  static String _monthlyPrice(Map<String, dynamic> subscription) {
    num? amount;
    final netMicros = _plpNum(subscription['net_monthly_fee_micros']);
    final feeMicros = _plpNum(subscription['monthly_fee_micros']);
    if (netMicros != null) {
      amount = netMicros / 1000000;
    } else if (feeMicros != null) {
      final discountMicros = _plpNum(subscription['discount_micros']) ?? 0;
      amount = (feeMicros - discountMicros) / 1000000;
    } else {
      amount = _plpNum(subscription['net_monthly_fee']) ??
          _plpNum(subscription['monthly_fee']);
    }
    if (amount == null || amount < 0) return 'Price unavailable';
    final currency = (subscription['currency'] ?? 'USD').toString();
    return '${plpBillingFormatMicros(amount * 1000000, currency)} / month';
  }

  String _state(Map<String, dynamic> subscription) =>
      (subscription['state'] ?? '').toString().toLowerCase();

  Map<String, dynamic> _map(Object? value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};

  _PlanOption? _option(String? code) {
    for (final plan in _plans) {
      if (plan.code == code) return plan;
    }
    return null;
  }

  String _planName(String code) =>
      _option(code)?.name ?? (code.isEmpty ? 'Plan' : code);
}

num? _plpNum(Object? value) {
  if (value is num) return value;
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : num.tryParse(text);
}

/// Monthly price for a subscription or plan row from the billing status,
/// e.g. 'USD 49 / month'; 'Price unavailable' when no price is known.
String plpBillingMonthlyPrice(Map<String, dynamic> row) =>
    _PlpPaypalBillingScreenState._monthlyPrice(row);

String plpBillingFormatMicros(num micros, String currency) {
  final cents = (micros / 10000).round();
  final whole = cents ~/ 100;
  final fraction = cents % 100;
  final digits = whole.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
  final amount =
      fraction == 0 ? digits : '$digits.${fraction.toString().padLeft(2, '0')}';
  final code = currency.trim().toUpperCase();
  return '${code.isEmpty ? 'USD' : code} $amount';
}

/// 'Nov 8' (or 'Nov 8, 2027' outside the current year); '' when unknown.
String plpBillingShortDate(Object? value, {DateTime? now}) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return '';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final date =
      parsed.isUtc && value.toString().length > 10 ? parsed.toLocal() : parsed;
  final label = '${months[date.month - 1]} ${date.day}';
  return date.year == (now ?? DateTime.now()).year
      ? label
      : '$label, ${date.year}';
}
