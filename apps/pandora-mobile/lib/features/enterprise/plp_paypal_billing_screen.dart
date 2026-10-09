import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/analytics/owner_analytics.dart';
import '../../core/data/plp_paypal_billing_api.dart';
import 'plp_checkout_analytics.dart';
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

/// Web origins PayPal may send the owner back to. Keep in sync with the
/// pandora-owner-api CORS allowlist (DEFAULT_ALLOWED_ORIGINS in contract.ts).
const plpPaypalReturnOrigins = <String>{
  'https://mcpmaster.vercel.app',
  'https://pandoras-box-system.vercel.app',
  'https://mcpmaster-hazel.vercel.app',
  'https://mcpmaster-mbanatao-dc676069.vercel.app',
  'https://enterprise-omega-five.vercel.app',
};

const _plpPaypalDefaultReturnOrigin = 'https://mcpmaster.vercel.app';

/// PayPal return/cancel URLs. On web the owner comes back to the site they
/// started on when it is an allowed origin; everywhere else (Android, or an
/// unknown web origin) keeps the mcpmaster return page.
({String returnUrl, String cancelUrl}) plpPaypalReturnUrls({
  required bool isWeb,
  required Uri base,
  String? origin,
}) {
  var targetOrigin = _plpPaypalDefaultReturnOrigin;
  if (isWeb && base.scheme == 'https' && base.host.isNotEmpty) {
    final candidate = base.origin;
    if (plpPaypalReturnOrigins.contains(candidate)) targetOrigin = candidate;
  }
  final query = (origin != null && plpCheckoutOrigins.contains(origin))
      ? '?from=$origin'
      : '';
  return (
    returnUrl: '$targetOrigin/#/enterprise/paypal-return$query',
    cancelUrl: '$targetOrigin/#/enterprise/paypal-cancel$query',
  );
}

class PlpPaypalBillingScreen extends StatefulWidget {
  const PlpPaypalBillingScreen({
    super.key,
    required this.organizationId,
    required this.onOpenNavigation,
    this.transport,
    this.urlLauncher,
    this.isWeb,
    this.appBaseUri,
    this.onStatus,
    this.origin,
    this.originLabel,
    this.initialStatus,
    this.paypalReturn,
    this.onEvent,
    this.onActivated,
    this.confirmPollInterval = const Duration(seconds: 4),
    this.confirmPollAttempts = 5,
    this.successHold = const Duration(milliseconds: 1600),
  });

  final String organizationId;
  final VoidCallback onOpenNavigation;
  final PlpBillingTransport? transport;
  final PlpBillingUrlLauncher? urlLauncher;

  /// Test seams; default to the running platform and [Uri.base].
  final bool? isWeb;
  final Uri? appBaseUri;

  /// Every successful status read, so the PLP subscription gate follows the
  /// same confirmed state the owner sees here (never a PayPal return alone).
  final ValueChanged<Map<String, dynamic>>? onStatus;

  final String? origin;
  final String? originLabel;
  final Map<String, dynamic>? initialStatus;
  final PlpCheckoutReturn? paypalReturn;
  final PlpCheckoutEventSink? onEvent;
  final VoidCallback? onActivated;
  final Duration confirmPollInterval;
  final int confirmPollAttempts;
  final Duration successHold;

  @override
  State<PlpPaypalBillingScreen> createState() => _PlpPaypalBillingScreenState();
}

enum _BillingView {
  landing,
  review,
  handedOff,
  confirming,
  pending,
  success,
  cancelledReturn,
  failed,
  changeConfirm,
  cancelConfirm,
  history,
}

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

class _UnlockRow {
  const _UnlockRow(this.icon, this.label, this.originKey);
  final IconData icon;
  final String label;
  final String originKey;
}

class _PlpPaypalBillingScreenState extends State<PlpPaypalBillingScreen>
    with WidgetsBindingObserver {
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
  _BillingView _view = _BillingView.landing;
  String? _target;
  String? _errorMessage;

  /// Plan the owner picked (or the plan of an unfinished checkout). Kept when
  /// going back so the selection is never lost.
  String _selectedPlanCode = 'launch';
  final Map<String, String> _idempotencyKeys = <String, String>{};
  Map<String, dynamic> _status = const <String, dynamic>{};

  DateTime? _viewStartTime;
  bool _paywallViewedEmitted = false;
  bool _activationVerifiedEmitted = false;
  bool _onActivatedCalled = false;
  Timer? _successTimer;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _viewStartTime = DateTime.now();

    final ret = widget.paypalReturn;
    if (ret != null) {
      if (ret.cancelled) {
        _view = _BillingView.cancelledReturn;
        _emitEvent(
          OwnerAnalyticsEvent.checkoutAbandoned,
          reason: 'paypal_cancel',
        );
      } else {
        _view = _BillingView.confirming;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startConfirming();
        });
      }
    } else {
      _view = _BillingView.landing;
    }

    _initialLoad();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _successTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _view == _BillingView.handedOff) {
      _startConfirming();
    }
  }

  void _emitEvent(
    OwnerAnalyticsEvent event, {
    String? plan,
    String? reason,
    int? attempt,
    Duration? sinceView,
  }) {
    final sink = widget.onEvent ?? plpCheckoutAnalytics;
    sink(
      event,
      origin: widget.origin,
      plan: plan ?? _selectedPlanCode,
      reason: reason,
      attempt: attempt,
      sinceView: sinceView,
    );
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

  void _applyStatus(Map<String, dynamic> result) {
    _status = result;
    final state = _state(_map(result['subscription']));
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
  }

  Future<void> _fetchStatus() async {
    final result = await _request('/billing/paypal/status');
    if (!mounted) return;
    setState(() {
      _applyStatus(result);
      _loaded = true;
    });
    widget.onStatus?.call(result);
  }

  Future<void> _initialLoad() async {
    if (widget.initialStatus != null) {
      setState(() {
        _applyStatus(widget.initialStatus!);
        _loaded = true;
      });
      widget.onStatus?.call(widget.initialStatus!);
      // Refresh status silently in background; failed silent refresh changes nothing.
      try {
        final result = await _request('/billing/paypal/status');
        if (mounted) {
          setState(() {
            _applyStatus(result);
          });
          widget.onStatus?.call(result);
        }
      } catch (_) {}
      return;
    }

    var attempts = 0;
    while (true) {
      attempts++;
      try {
        await _fetchStatus();
        return;
      } catch (error) {
        if (!mounted) return;
        if (plpBillingTransientError(error) && attempts < 3) {
          final delay = attempts == 1
              ? const Duration(milliseconds: 600)
              : const Duration(milliseconds: 1500);
          await Future<void>.delayed(delay);
          if (!mounted) return;
          continue;
        }
        setState(() {
          _error = 'Couldn’t load billing.';
          _retry = () => _run('Loading…', _initialLoad);
        });
        return;
      }
    }
  }

  Future<void> _startConfirming() async {
    if (!mounted) return;
    setState(() {
      _view = _BillingView.confirming;
      _error = null;
      _retry = null;
    });

    for (var attempt = 0; attempt < widget.confirmPollAttempts; attempt++) {
      try {
        await _request('/billing/paypal/reconcile', method: 'POST');
      } catch (_) {}
      try {
        final result = await _request('/billing/paypal/status');
        if (!mounted) return;
        setState(() {
          _applyStatus(result);
          _loaded = true;
        });
        widget.onStatus?.call(result);

        if (plpBillingStatusUnlocked(result)) {
          _goToSuccess();
          return;
        }
      } catch (_) {}

      if (attempt < widget.confirmPollAttempts - 1) {
        final completer = Completer<void>();
        _pollTimer = Timer(widget.confirmPollInterval, () {
          if (!completer.isCompleted) completer.complete();
        });
        await completer.future;
        _pollTimer = null;
        if (!mounted) return;
      }
    }

    if (!mounted) return;
    final checkout = _map(_status['checkout']);
    final checkoutStatus = (checkout['status'] ?? '').toString().toLowerCase();
    if (checkoutStatus == 'failed' || checkoutStatus == 'expired') {
      _showFailed(
        'Checkout couldn’t start. Nothing was charged.',
        'server_error',
      );
    } else {
      setState(() {
        _view = _BillingView.pending;
      });
      _emitEvent(
        OwnerAnalyticsEvent.checkoutAbandoned,
        reason: 'pending_timeout',
      );
    }
  }

  void _goToSuccess() {
    if (!mounted) return;
    setState(() {
      _view = _BillingView.success;
      _error = null;
      _retry = null;
    });
    if (!_activationVerifiedEmitted) {
      _activationVerifiedEmitted = true;
      _emitEvent(
        OwnerAnalyticsEvent.activationVerified,
        sinceView: _viewStartTime != null
            ? DateTime.now().difference(_viewStartTime!)
            : null,
      );
    }
    if (widget.originLabel != null && !_onActivatedCalled) {
      _successTimer?.cancel();
      _successTimer = Timer(widget.successHold, () {
        if (mounted) _triggerActivated();
      });
    }
  }

  void _triggerActivated() {
    if (_onActivatedCalled) return;
    _onActivatedCalled = true;
    _successTimer?.cancel();
    widget.onActivated?.call();
  }

  void _showFailed(String message, String reason) {
    if (!mounted) return;
    setState(() {
      _view = _BillingView.failed;
      _errorMessage = message;
    });
    _emitEvent(
      OwnerAnalyticsEvent.checkoutFailed,
      reason: reason,
    );
  }

  void _handleCheckoutError(Object error) {
    final raw = error.toString();
    if (raw.contains('SUBSCRIPTION_ALREADY_ACTIVE') ||
        raw.contains('ACTIVE_SUBSCRIPTION_EXISTS')) {
      _startConfirming();
      return;
    }
    String message;
    String reason;
    final isPlpReq = error is PlpBillingRequestException;
    final isPaypalCheckoutFailed =
        (isPlpReq && error.code == 'PAYPAL_CHECKOUT_FAILED') ||
        raw.contains('PAYPAL_CHECKOUT_FAILED');
    final is503 = isPlpReq && error.statusCode == 503;
    final is429 = (isPlpReq && error.statusCode == 429) || raw.contains('429');

    if (isPaypalCheckoutFailed) {
      message = 'PayPal didn’t start checkout. Nothing was charged.';
      reason = 'paypal_unavailable';
    } else if (raw.contains('PAYPAL_NOT_CONFIGURED') ||
        raw.contains('PAYPAL_AUTH_FAILED') ||
        is503) {
      message = 'PayPal is unavailable right now. Nothing was charged.';
      reason = 'paypal_unavailable';
    } else if (raw.contains('AAL2_REQUIRED')) {
      message = 'Checkout needs an extra sign-in check on this account.';
      reason = 'identity_required';
    } else if (raw.contains('could not be opened')) {
      message = 'PayPal didn’t open. Nothing was charged.';
      reason = 'open_failed';
    } else if (is429) {
      message = 'Too many attempts. Wait a moment, then try again.';
      reason = 'server_error';
    } else if (error is TimeoutException || error is http.ClientException) {
      message = 'No connection to PLP. Nothing was charged.';
      reason = 'network';
    } else {
      message = 'Checkout couldn’t start. Nothing was charged.';
      reason = 'server_error';
    }

    _showFailed(message, reason);
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
        final active = _state(_map(_status['subscription'])) == 'active';
        if (!active &&
            (_view == _BillingView.review || _view == _BillingView.landing)) {
          _handleCheckoutError(error);
        } else {
          setState(() {
            _error = _short(error);
            _retry = () => _run(pending, work);
          });
        }
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
        final returnUrls = plpPaypalReturnUrls(
          isWeb: widget.isWeb ?? kIsWeb,
          base: widget.appBaseUri ?? Uri.base,
          origin: widget.origin,
        );
        final result = await _request(
          '/billing/paypal/checkout',
          method: 'POST',
          body: {
            'planCode': code,
            'idempotencyKey': _idempotency(intent, 'plp-checkout'),
            'returnUrl': returnUrls.returnUrl,
            'cancelUrl': returnUrls.cancelUrl,
          },
        );
        _idempotencyKeys.remove(intent);
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
        _show(_BillingView.landing);
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
        _show(_BillingView.landing);
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
    final active = _state(_map(_status['subscription'])) == 'active';
    if (!active &&
        (_view == _BillingView.landing ||
            _view == _BillingView.review ||
            _view == _BillingView.failed)) {
      _emitEvent(
        OwnerAnalyticsEvent.paypalHandoff,
        plan: _selectedPlanCode,
        sinceView: _viewStartTime != null
            ? DateTime.now().difference(_viewStartTime!)
            : null,
      );
      _show(_BillingView.handedOff);
    }
  }

  void _show(_BillingView view, [String? target]) {
    if (!mounted) return;
    setState(() {
      _error = null;
      _retry = null;
      _view = view;
      _target = target;
    });
  }

  VoidCallback? _tap(VoidCallback action) => _busy ? null : action;

  Widget _primaryCta({
    required Key key,
    required String label,
    VoidCallback? onTap,
    bool disabled = false,
    IconData? icon,
  }) {
    final enabled = !disabled && onTap != null && !_busy;
    return Material(
      color: enabled ? const Color(0xFF151515) : const Color(0xFFE4DCCF),
      borderRadius: BorderRadius.circular(2),
      child: InkWell(
        key: key,
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          height: 48,
          width: double.infinity,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: enabled ? Colors.white : const Color(0xFF756F67),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .3,
                      ),
                    ),
                  ),
                  if (icon != null) ...[
                    const SizedBox(width: 8),
                    Icon(
                      icon,
                      size: 16,
                      color: enabled ? Colors.white : const Color(0xFF756F67),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

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
    // Verified only with provider evidence; a failed refresh keeps the last
    // confirmed data on screen but no longer calls it verified.
    final verified = !_unresolved &&
        subscription['source_kind'] == 'provider_verified' &&
        subscription['verified_at'] != null;
    final provider = _map(_status['provider']);
    final providerConfigured = provider['configured'] == true;
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

    // Active management views
    if (active &&
        (_view == _BillingView.landing ||
            _view == _BillingView.changeConfirm ||
            _view == _BillingView.cancelConfirm ||
            _view == _BillingView.history)) {
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
        _tap(() => _show(_BillingView.landing)),
        showArrow: false,
      );
      final keepTile = PlpCapability(
        'Keep',
        Icons.check_circle_outline_rounded,
        _tap(() => _show(_BillingView.landing)),
        showArrow: false,
      );
      PlpCapability openPaypal(String url) => PlpCapability(
            'Open PayPal',
            Icons.open_in_new_rounded,
            _tap(() => _run('Opening PayPal…', () => _openApproval(url))),
          );

      if (pendingChange) {
        final to = _option((pending['to_plan_code'] ?? '').toString());
        notice =
            to == null ? 'Plan change pending' : 'Switch to ${to.name} pending';
        tiles = [
          if (pendingApproval.isNotEmpty) openPaypal(pendingApproval),
          refreshTile,
        ];
      } else if (cancelPending) {
        notice = 'Cancellation pending';
        tiles = [refreshTile];
      } else if (_view == _BillingView.changeConfirm && target != null) {
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
      } else if (_view == _BillingView.cancelConfirm) {
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
      } else if (_view == _BillingView.history) {
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
      } else {
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
      }

      if (_pending != null) notice = _pending!;
      if (_error != null) {
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
          return _reconcile();
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

    // Loading / error state if not loaded yet
    if (!_loaded) {
      final notice = _error ?? 'Loading…';
      return PlpResortPage(
        key: const ValueKey('plp-paypal-billing'),
        listKey: const ValueKey('plp-paypal-billing-list'),
        section: plpBillingSection,
        onRefresh: () => _run('Loading…', _fetchStatus),
        children: [
          Semantics(
            liveRegion: true,
            container: true,
            child: PlpResortNotice(
              notice,
              key: const ValueKey('plp-billing-notice'),
            ),
          ),
          if (_error != null && _retry != null) ...[
            const SizedBox(height: 12),
            PlpCapabilityGrid(
              items: [
                PlpCapability('Retry', Icons.refresh_rounded, _tap(_retry!)),
              ],
            ),
          ],
          // Keeps the last tile clear of the floating PLP launcher.
          const SizedBox(height: 72),
        ],
      );
    }

    // Unpaid journeys
    switch (_view) {
      case _BillingView.review:
        return _buildReview(context);
      case _BillingView.handedOff:
        return _buildHandedOff(context);
      case _BillingView.confirming:
        return _buildConfirming(context);
      case _BillingView.pending:
        return _buildPending(context);
      case _BillingView.success:
        return _buildSuccess(context);
      case _BillingView.cancelledReturn:
        return _buildCancelledReturn(context);
      case _BillingView.failed:
        return _buildFailed(context);
      default:
        return _buildLanding(context, state: state, cancelled: cancelled);
    }
  }

  Widget _buildLanding(
    BuildContext context, {
    required String state,
    required bool cancelled,
  }) {
    if (!_paywallViewedEmitted) {
      _paywallViewedEmitted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _emitEvent(OwnerAnalyticsEvent.paywallViewed);
      });
    }

    final selectedCode = _selectedPlanCode;
    final selectedOption = _option(selectedCode) ?? _plans.first;
    final selectedPrice = _planPriceText(selectedCode, selectedOption.fallbackMicros);

    final provider = _map(_status['provider']);
    final providerUnavailable = provider['configured'] == false;

    final checkout = _map(_status['checkout']);
    final checkoutStatus = (checkout['status'] ?? '').toString().toLowerCase();
    final openCheckout = checkout.isNotEmpty &&
        !_terminalApprovalStates.contains(checkoutStatus) &&
        (checkout['approval_url'] ?? '').toString().trim().isNotEmpty;
    final openPlanCode = (checkout['plan_code'] ?? '').toString();
    final openPlanName = _option(openPlanCode)?.name ?? 'Launch';

    final ends = plpBillingShortDate(_map(_status['subscription'])['ends_on']);
    final endedLine = cancelled
        ? (ends.isEmpty ? 'Cancelled' : 'Cancelled · ends $ends')
        : '';

    // Unlock items ordering
    final unlockRows = <_UnlockRow>[
      const _UnlockRow(
        Icons.event_available_outlined,
        'Stays & Guests',
        'stays_guests',
      ),
      const _UnlockRow(
        Icons.room_service_outlined,
        'Operations & Experiences',
        'ops_exp',
      ),
      const _UnlockRow(
        Icons.insights_outlined,
        'Revenue',
        'revenue',
      ),
      const _UnlockRow(
        Icons.groups_outlined,
        'Team & the PLP assistant',
        'team_assistant',
      ),
    ];

    String? matchKey;
    final orig = widget.origin;
    if (orig == 'stays' || orig == 'guests') {
      matchKey = 'stays_guests';
    } else if (orig == 'operations' || orig == 'experiences') {
      matchKey = 'ops_exp';
    } else if (orig == 'revenue') {
      matchKey = 'revenue';
    } else if (orig == 'team' || orig == 'assistant') {
      matchKey = 'team_assistant';
    }

    if (matchKey != null) {
      final index = unlockRows.indexWhere((r) => r.originKey == matchKey);
      if (index > 0) {
        final row = unlockRows.removeAt(index);
        unlockRows.insert(0, row);
      }
    }

    return PlpResortPage(
      key: const ValueKey('plp-paypal-billing'),
      listKey: const ValueKey('plp-paypal-billing-list'),
      section: plpBillingSection,
      onRefresh: () => _run('Loading…', _fetchStatus),
      children: [
        if (openCheckout) ...[
          PlpResortNotice(
            'You started checkout for $openPlanName. Finish in PayPal or choose again.',
            key: const ValueKey('plp-billing-open-checkout-notice'),
          ),
          const SizedBox(height: 12),
        ] else if (providerUnavailable) ...[
          const PlpResortNotice(
            'PayPal is unavailable right now. Nothing was charged.',
            key: ValueKey('plp-billing-notice'),
          ),
          const SizedBox(height: 12),
        ],
        if (endedLine.isNotEmpty) ...[
          Text(
            endedLine,
            style: const TextStyle(
              fontSize: 12,
              color: PlpResortWorkspaceScreen.muted,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          widget.originLabel != null
              ? '${widget.originLabel} is part of PLP Enterprise'
              : 'Run the whole resort from PLP',
          style: const TextStyle(
            fontFamily: 'serif',
            fontSize: 24,
            color: PlpResortWorkspaceScreen.ink,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'One subscription unlocks every workspace for your team.',
          style: TextStyle(
            fontSize: 13,
            color: PlpResortWorkspaceScreen.muted,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'WHAT UNLOCKS',
          style: TextStyle(
            color: PlpResortWorkspaceScreen.accent,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        for (final row in unlockRows) ...[
          Row(
            children: [
              Icon(
                row.icon,
                size: 18,
                color: PlpResortWorkspaceScreen.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  row.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: PlpResortWorkspaceScreen.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
        const SizedBox(height: 4),
        _buildPlanCard(
          code: 'launch',
          name: 'Launch',
          detail: 'Everything in PLP · 1,000 assistant requests/mo',
          isLaunch: true,
          isSelected: selectedCode == 'launch',
          priceText: _planPriceText('launch', 49000000),
        ),
        const SizedBox(height: 6),
        _buildPlanCard(
          code: 'professional',
          name: 'Professional',
          detail: '5,000 assistant requests/mo · priority support',
          isLaunch: false,
          isSelected: selectedCode == 'professional',
          priceText: _planPriceText('professional', 149000000),
        ),
        const SizedBox(height: 8),
        const Text(
          'Billed monthly by PayPal. Renews until you cancel — cancel anytime in Billing.',
          style: TextStyle(
            fontSize: 11.5,
            color: PlpResortWorkspaceScreen.muted,
          ),
        ),
        const SizedBox(height: 10),
        if (providerUnavailable) ...[
          _primaryCta(
            key: const ValueKey('plp-checkout-continue'),
            label: 'Continue with ${selectedOption.name} · $selectedPrice/mo',
            disabled: true,
          ),
          const SizedBox(height: 12),
          PlpCapabilityGrid(
            items: [
              PlpCapability(
                'Retry',
                Icons.refresh_rounded,
                _tap(() => _run('Loading…', _fetchStatus)),
              ),
            ],
          ),
        ] else if (openCheckout) ...[
          _primaryCta(
            key: const ValueKey('plp-checkout-continue'),
            label: 'Finish in PayPal',
            onTap: () => _checkout(selectedCode),
          ),
        ] else ...[
          _primaryCta(
            key: const ValueKey('plp-checkout-continue'),
            label: 'Continue with ${selectedOption.name} · $selectedPrice/mo',
            onTap: () {
              _emitEvent(
                OwnerAnalyticsEvent.checkoutStarted,
                plan: selectedCode,
              );
              _show(_BillingView.review);
            },
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          'Free without a plan: Today, Rooms & Housekeeping, Activity.',
          style: TextStyle(
            fontSize: 11.5,
            color: PlpResortWorkspaceScreen.muted,
          ),
        ),
        // Keeps the last tile clear of the floating PLP launcher.
        const SizedBox(height: 72),
      ],
    );
  }

  Widget _buildPlanCard({
    required String code,
    required String name,
    required String detail,
    required bool isLaunch,
    required bool isSelected,
    required String priceText,
  }) {
    final semanticLabel =
        '$name, $priceText per month${isLaunch ? ', recommended' : ''}${isSelected ? ', selected' : ''}';
    return Semantics(
      selected: isSelected,
      button: true,
      label: semanticLabel,
      child: Material(
        color: PlpResortWorkspaceScreen.paper,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: isSelected
                ? PlpResortWorkspaceScreen.accent
                : PlpResortWorkspaceScreen.line,
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: InkWell(
          key: ValueKey('plp-plan-$code'),
          onTap: () {
            setState(() {
              _selectedPlanCode = code;
            });
            _emitEvent(OwnerAnalyticsEvent.planSelected, plan: code);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isLaunch) ...[
                  const Text(
                    'RECOMMENDED',
                    style: TextStyle(
                      color: PlpResortWorkspaceScreen.accent,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'serif',
                          fontSize: 19,
                          color: PlpResortWorkspaceScreen.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      priceText,
                      style: const TextStyle(
                        fontFamily: 'serif',
                        fontSize: 22,
                        color: PlpResortWorkspaceScreen.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Text(
                      ' / month',
                      style: TextStyle(
                        fontSize: 12,
                        color: PlpResortWorkspaceScreen.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: PlpResortWorkspaceScreen.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReview(BuildContext context) {
    final selectedCode = _selectedPlanCode;
    final selectedOption = _option(selectedCode) ?? _plans.first;
    final selectedPrice = _planPriceText(selectedCode, selectedOption.fallbackMicros);

    return PlpResortPage(
      key: const ValueKey('plp-paypal-billing'),
      listKey: const ValueKey('plp-paypal-billing-list'),
      section: plpBillingSection,
      onRefresh: () => _run('Loading…', _fetchStatus),
      children: [
        const Text(
          'REVIEW',
          style: TextStyle(
            color: PlpResortWorkspaceScreen.accent,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          selectedOption.name,
          style: const TextStyle(
            fontFamily: 'serif',
            fontSize: 24,
            color: PlpResortWorkspaceScreen.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$selectedPrice per month',
          style: const TextStyle(
            fontSize: 15,
            color: PlpResortWorkspaceScreen.ink,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 20),
        _reviewStepRow(
          Icons.open_in_new_rounded,
          'PayPal opens so you can approve the subscription.',
        ),
        const SizedBox(height: 12),
        _reviewStepRow(
          Icons.verified_outlined,
          'Come back here — PLP checks with PayPal.',
        ),
        const SizedBox(height: 12),
        _reviewStepRow(
          Icons.lock_open_outlined,
          widget.originLabel != null
              ? 'Everything unlocks once PayPal confirms, then we take you back to ${widget.originLabel}.'
              : 'Everything unlocks once PayPal confirms.',
        ),
        const SizedBox(height: 22),
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: PlpResortWorkspaceScreen.paper,
            border: Border.fromBorderSide(
              BorderSide(color: PlpResortWorkspaceScreen.line),
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$selectedPrice every month until you cancel.',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: PlpResortWorkspaceScreen.ink,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Cancel anytime in Billing — no further charges. Access ends when the cancellation is confirmed.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: PlpResortWorkspaceScreen.ink,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Charges and receipts come from PayPal.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: PlpResortWorkspaceScreen.ink,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _primaryCta(
          key: const ValueKey('plp-checkout-paypal'),
          label: 'Continue to PayPal',
          icon: Icons.open_in_new_rounded,
          onTap: () => _checkout(selectedCode),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => _show(_BillingView.landing),
            child: const Text(
              'Back',
              style: TextStyle(color: PlpResortWorkspaceScreen.muted),
            ),
          ),
        ),
        // Keeps the last tile clear of the floating PLP launcher.
        const SizedBox(height: 72),
      ],
    );
  }

  Widget _reviewStepRow(IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: PlpResortWorkspaceScreen.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                color: PlpResortWorkspaceScreen.ink,
              ),
            ),
          ),
        ],
      );

  Widget _buildHandedOff(BuildContext context) {
    final approvalUrl = _existingApprovalUrl();
    return PlpResortPage(
      key: const ValueKey('plp-paypal-billing'),
      listKey: const ValueKey('plp-paypal-billing-list'),
      section: plpBillingSection,
      onRefresh: _reconcile,
      children: [
        const PlpResortNotice(
          'Approve in PayPal, then come back here.',
          key: ValueKey('plp-billing-notice'),
        ),
        const SizedBox(height: 12),
        PlpCapabilityGrid(
          items: [
            PlpCapability(
              'I’ve approved',
              Icons.check_circle_outline_rounded,
              _startConfirming,
            ),
            PlpCapability(
              'Open PayPal again',
              Icons.open_in_new_rounded,
              approvalUrl.isNotEmpty ? () => _openApproval(approvalUrl) : null,
            ),
            PlpCapability(
              'Choose another plan',
              Icons.arrow_back_rounded,
              () => _show(_BillingView.landing),
              showArrow: false,
            ),
          ],
        ),
        // Keeps the last tile clear of the floating PLP launcher.
        const SizedBox(height: 72),
      ],
    );
  }

  Widget _buildConfirming(BuildContext context) => PlpResortPage(
        key: const ValueKey('plp-paypal-billing'),
        listKey: const ValueKey('plp-paypal-billing-list'),
        section: plpBillingSection,
        onRefresh: _reconcile,
        children: [
          const PlpResortNotice(
            'Confirming with PayPal…',
            key: ValueKey('plp-billing-notice'),
          ),
          const SizedBox(height: 6),
          const Text(
            'This usually takes a few seconds.',
            style: TextStyle(
              fontSize: 13,
              color: PlpResortWorkspaceScreen.muted,
            ),
          ),
          const SizedBox(height: 14),
          const LinearProgressIndicator(
            minHeight: 2,
            color: PlpResortWorkspaceScreen.accent,
            backgroundColor: PlpResortWorkspaceScreen.line,
          ),
          // Keeps the last tile clear of the floating PLP launcher.
          const SizedBox(height: 72),
        ],
      );

  Widget _buildPending(BuildContext context) {
    final approvalUrl = _existingApprovalUrl();
    return PlpResortPage(
      key: const ValueKey('plp-paypal-billing'),
      listKey: const ValueKey('plp-paypal-billing-list'),
      section: plpBillingSection,
      onRefresh: _reconcile,
      children: [
        const PlpResortNotice(
          'PayPal hasn’t confirmed yet.',
          key: ValueKey('plp-billing-notice'),
        ),
        const SizedBox(height: 6),
        const Text(
          'If you approved, it can take a minute. Nothing unlocks until PayPal confirms.',
          style: TextStyle(
            fontSize: 13,
            color: PlpResortWorkspaceScreen.muted,
          ),
        ),
        const SizedBox(height: 14),
        PlpCapabilityGrid(
          items: [
            PlpCapability(
              'Check again',
              Icons.refresh_rounded,
              _startConfirming,
            ),
            if (approvalUrl.isNotEmpty)
              PlpCapability(
                'Open PayPal',
                Icons.open_in_new_rounded,
                () => _openApproval(approvalUrl),
              ),
            PlpCapability(
              'Choose another plan',
              Icons.arrow_back_rounded,
              () => _show(_BillingView.landing),
              showArrow: false,
            ),
          ],
        ),
        // Keeps the last tile clear of the floating PLP launcher.
        const SizedBox(height: 72),
      ],
    );
  }

  Widget _buildSuccess(BuildContext context) {
    final selectedCode = _selectedPlanCode;
    final selectedOption = _option(selectedCode) ?? _plans.first;
    final selectedPrice = _planPriceText(selectedCode, selectedOption.fallbackMicros);

    final subscription = _map(_status['subscription']);
    final renewalDate = plpBillingShortDate(subscription['renews_on']);
    final renewsPart = renewalDate.isNotEmpty ? ' · renews $renewalDate' : '';

    final ctaLabel = widget.originLabel != null
        ? 'Open ${widget.originLabel}'
        : 'Go to Today';

    return PlpResortPage(
      key: const ValueKey('plp-paypal-billing'),
      listKey: const ValueKey('plp-paypal-billing-list'),
      section: plpBillingSection,
      onRefresh: _reconcile,
      children: [
        const Text(
          'PLP Enterprise is unlocked',
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: 26,
            color: PlpResortWorkspaceScreen.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${selectedOption.name} · $selectedPrice / month$renewsPart',
          style: const TextStyle(
            fontSize: 14,
            color: PlpResortWorkspaceScreen.ink,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Verified with PayPal.',
          style: TextStyle(
            fontSize: 12,
            color: PlpResortWorkspaceScreen.muted,
          ),
        ),
        const SizedBox(height: 24),
        _primaryCta(
          key: const ValueKey('plp-checkout-done'),
          label: ctaLabel,
          onTap: _triggerActivated,
        ),
        // Keeps the last tile clear of the floating PLP launcher.
        const SizedBox(height: 72),
      ],
    );
  }

  Widget _buildCancelledReturn(BuildContext context) => PlpResortPage(
        key: const ValueKey('plp-paypal-billing'),
        listKey: const ValueKey('plp-paypal-billing-list'),
        section: plpBillingSection,
        onRefresh: () => _run('Loading…', _fetchStatus),
        children: [
          const PlpResortNotice(
            'You left PayPal before approving. Nothing was charged.',
            key: ValueKey('plp-billing-notice'),
          ),
          const SizedBox(height: 18),
          _primaryCta(
            key: const ValueKey('plp-checkout-retry'),
            label: 'Try again',
            onTap: () => _show(_BillingView.review),
          ),
          const SizedBox(height: 12),
          PlpCapabilityGrid(
            items: [
              PlpCapability(
                'Choose another plan',
                Icons.arrow_back_rounded,
                () => _show(_BillingView.landing),
                showArrow: false,
              ),
            ],
          ),
          // Keeps the last tile clear of the floating PLP launcher.
          const SizedBox(height: 72),
        ],
      );

  Widget _buildFailed(BuildContext context) => PlpResortPage(
        key: const ValueKey('plp-paypal-billing'),
        listKey: const ValueKey('plp-paypal-billing-list'),
        section: plpBillingSection,
        onRefresh: () => _run('Loading…', _fetchStatus),
        children: [
          PlpResortNotice(
            _errorMessage ?? 'Checkout couldn’t start. Nothing was charged.',
            key: const ValueKey('plp-billing-notice'),
          ),
          const SizedBox(height: 14),
          PlpCapabilityGrid(
            items: [
              PlpCapability(
                'Try again',
                Icons.refresh_rounded,
                () => _checkout(_selectedPlanCode),
              ),
              PlpCapability(
                'Back',
                Icons.arrow_back_rounded,
                () => _show(_BillingView.landing),
                showArrow: false,
              ),
            ],
          ),
          // Keeps the last tile clear of the floating PLP launcher.
          const SizedBox(height: 72),
        ],
      );

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

  String _planPriceText(String code, int fallbackMicros) {
    for (final row
        in (_status['plans'] as List? ?? const []).whereType<Map>()) {
      if (row['code']?.toString() != code) continue;
      final micros = _monthlyPriceMicros(Map<String, dynamic>.from(row));
      if (micros != null) {
        final currency = (row['currency'] ?? 'USD').toString();
        return plpBillingFormatMicros(micros, currency);
      }
    }
    return plpBillingFormatMicros(fallbackMicros, 'USD');
  }

  static num? _monthlyPriceMicros(Map<String, dynamic> row) {
    final netMicros = _plpNum(row['net_monthly_fee_micros']);
    final feeMicros = _plpNum(row['monthly_fee_micros']);
    if (netMicros != null) return netMicros;
    if (feeMicros != null) {
      final discountMicros = _plpNum(row['discount_micros']) ?? 0;
      return feeMicros - discountMicros;
    }
    final decimal = _plpNum(row['monthlyAmount']) ??
        _plpNum(row['net_monthly_fee']) ??
        _plpNum(row['monthly_fee']);
    if (decimal != null) return decimal * 1000000;
    return null;
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
