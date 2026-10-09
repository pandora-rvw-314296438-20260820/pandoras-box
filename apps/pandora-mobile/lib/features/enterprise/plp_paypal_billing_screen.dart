import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
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
}) {
  var origin = _plpPaypalDefaultReturnOrigin;
  if (isWeb && base.scheme == 'https' && base.host.isNotEmpty) {
    final candidate = base.origin;
    if (plpPaypalReturnOrigins.contains(candidate)) origin = candidate;
  }
  return (
    returnUrl: '$origin/#/enterprise/paypal-return',
    cancelUrl: '$origin/#/enterprise/paypal-cancel',
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

  @override
  State<PlpPaypalBillingScreen> createState() => _PlpPaypalBillingScreenState();
}

enum _BillingView { main, select, handoff, changeConfirm, cancelConfirm, history, error }

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
  bool _statusRefreshFailed = false;
  bool _comparePlans = false;
  String? _pendingApprovalUrl;
  _BillingView _view = _BillingView.main;
  String? _target;

  /// Plan the owner picked (or the plan of an unfinished checkout). Kept when
  /// going back so the selection is never lost.
  String? _selectedPlanCode = 'launch';
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
      _error = null;
      _retry = null;
      _statusRefreshFailed = false;
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
      final loadedPending = _map(result['pendingPlanChange']);
      final loadedPendingStatus = (loadedPending['status'] ?? '').toString().toLowerCase();
      final loadedCheckoutStatus = (loadedCheckout['status'] ?? '').toString().toLowerCase();
      final pendingUrl = _terminalApprovalStates.contains(loadedPendingStatus)
          ? ''
          : (loadedPending['approval_url'] ?? '').toString().trim();
      final checkoutUrl = _terminalApprovalStates.contains(loadedCheckoutStatus)
          ? ''
          : (loadedCheckout['approval_url'] ?? '').toString().trim();
      if (pendingUrl.isNotEmpty || checkoutUrl.isNotEmpty) {
        _pendingApprovalUrl = pendingUrl.isNotEmpty ? pendingUrl : checkoutUrl;
      } else if (state == 'active') {
        _pendingApprovalUrl = null;
      }
    });
    widget.onStatus?.call(result);
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

  /// Resume the same PayPal approval on retry instead of opening a second checkout.
  Future<void> _checkout(String code) => _run('Opening PayPal…', () async {
        final intent = 'checkout:$code';
        final existingApproval = _pendingApprovalUrl ?? _existingApprovalUrl();
        if (existingApproval.isNotEmpty) {
          _pendingApprovalUrl = existingApproval;
          _show(_BillingView.handoff, code);
          await _openApproval(existingApproval);
          await _refreshAfterHandoff();
          return;
        }
        final returnUrls = plpPaypalReturnUrls(
          isWeb: widget.isWeb ?? kIsWeb,
          base: widget.appBaseUri ?? Uri.base,
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
        final approval = (result['approvalUrl'] ?? '').toString().trim();
        if (approval.isEmpty) throw Exception('PayPal approval could not be opened.');
        _pendingApprovalUrl = approval;
        _show(_BillingView.handoff, code);
        await _openApproval(approval);
        _idempotencyKeys.remove(intent);
        await _refreshAfterHandoff();
      });

  Future<void> _changePlan(String code) => _run('Switching plan…', () async {
        final intent = 'change:$code';
        final result = await _request(
          '/billing/paypal/change-plan',
          method: 'POST',
          body: {
            'planCode': code,
            'idempotencyKey': _idempotency(intent, 'plp-plan-change'),
          },
        );
        final approval = (result['approvalUrl'] ?? '').toString().trim();
        if (approval.isNotEmpty) {
          _pendingApprovalUrl = approval;
          _show(_BillingView.handoff, code);
          await _openApproval(approval);
          _idempotencyKeys.remove(intent);
          await _refreshAfterHandoff();
          return;
        }
        _idempotencyKeys.remove(intent);
        _show(_BillingView.main);
        await _fetchStatus();
      });

  /// Separate successful PayPal launch from a failed post-launch status read.
  Future<void> _refreshAfterHandoff() async {
    try {
      await _fetchStatus();
      if (!mounted) return;
      final active = _state(_map(_status['subscription'])) == 'active';
      setState(() {
        _statusRefreshFailed = false;
        _error = null;
        _retry = null;
        _view = active ? _BillingView.main : _BillingView.handoff;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusRefreshFailed = true;
        _error = 'PayPal opened, but billing status could not be refreshed.';
        _retry = () => _run('Refreshing status…', _refreshAfterHandoff);
        _view = _BillingView.handoff;
      });
    }
  }
  /// Reconciliation remains the provider-truth checkpoint for refresh/cancel flows.
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
    final candidate = value?.trim() ?? '';
    final uri = Uri.tryParse(candidate);
    final host = uri?.host.toLowerCase() ?? '';
    final trustedHost = host == 'paypal.com' || host.endsWith('.paypal.com');
    if (uri == null || uri.scheme != 'https' || !trustedHost) {
      throw Exception('PayPal approval could not be opened.');
    }
    final launcher = widget.urlLauncher ??
        (Uri target) => launchUrl(target, mode: LaunchMode.externalApplication);
    if (!await launcher(uri)) {
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


  static const Color _canvas = Color(0xFFFAF7F1);
  static const Color _paper = Color(0xFFFFFDFC);
  static const Color _ink = Color(0xFF171512);
  static const Color _muted = Color(0xFF756F67);
  static const Color _line = Color(0xFFE4DCCF);
  static const Color _gold = Color(0xFF776A43);
  static const Color _softGold = Color(0xFFF0E8D8);
  static const Color _danger = Color(0xFF9E1823);
  static const Color _paypalBlue = Color(0xFF1769AA);

  @override
  Widget build(BuildContext context) {
    final subscription = _map(_status['subscription']);
    final active = _state(subscription) == 'active';
    final approval = _pendingApprovalUrl ?? _existingApprovalUrl();
    if (_statusRefreshFailed && _view == _BillingView.handoff) return _handoffPage();
    if (!_loaded || _error != null || _view == _BillingView.error) {
      if (_statusRefreshFailed && _view == _BillingView.handoff) return _handoffPage();
      return _errorPage(active: active);
    }
    if (!active && approval.isNotEmpty && _view == _BillingView.main) {
      return _pendingCheckoutPage(approval);
    }
    switch (_view) {
      case _BillingView.select: return _planSelectionPage();
      case _BillingView.handoff: return _handoffPage();
      case _BillingView.history: return _historyPage();
      case _BillingView.main:
      case _BillingView.changeConfirm:
      case _BillingView.cancelConfirm:
      case _BillingView.error:
        return active ? _activeSubscriptionPage() : _setupPage();
    }
  }

  Widget _billingHeader({bool canGoBack = false, VoidCallback? onBack}) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
    child: Row(children: [
      const SizedBox(width: 40),
      Expanded(child: Center(child: Text('PLP ENTERPRISE',
        key: const ValueKey('plp-billing-brand'),
        style: const TextStyle(color: _ink, fontFamily: 'serif', fontSize: 11,
          letterSpacing: 2.5, fontWeight: FontWeight.w400)))),
      SizedBox(width: 44, child: canGoBack
        ? IconButton(key: const ValueKey('plp-billing-back'), tooltip: 'Go back',
            onPressed: onBack ?? () => _show(_BillingView.main),
            icon: const Icon(Icons.arrow_back_rounded, size: 20))
        : IconButton(tooltip: 'Open navigation', onPressed: widget.onOpenNavigation,
            icon: const Icon(Icons.menu_rounded, size: 20))),
    ]),
  );

  Widget _billingPage({required List<Widget> children, bool canGoBack = false, VoidCallback? onBack}) => Material(
    key: const ValueKey('plp-paypal-billing'),
    color: _canvas,
    child: SafeArea(bottom: false, child: Column(children: [
      _billingHeader(canGoBack: canGoBack, onBack: onBack),
      Expanded(child: RefreshIndicator(
        color: _ink, backgroundColor: _paper,
        onRefresh: () async {
          if (_state(_map(_status['subscription'])) == 'active') { await _reconcile(); }
          else { await _run('Refreshing…', _fetchStatus); }
        },
        child: ListView(
          key: const ValueKey('plp-paypal-billing-list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20, 8, 20, 104 + MediaQuery.viewPaddingOf(context).bottom),
          children: children,
        ),
      )),
    ])),
  );

  Widget _primaryButton({required String label, required VoidCallback? onPressed, Key? key, IconData? icon, bool danger = false}) => SizedBox(
    width: double.infinity, height: 52,
    child: ElevatedButton(
      key: key, onPressed: _busy ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: danger ? _danger : _ink, foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFF77716A), elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: 'serif', fontSize: 14, fontWeight: FontWeight.w400))),
        if (icon != null) ...[const SizedBox(width: 9), Icon(icon, size: 17)],
      ]),
    ),
  );

  Widget _secondaryButton({required String label, required VoidCallback? onPressed, Key? key}) => SizedBox(
    width: double.infinity, height: 46,
    child: OutlinedButton(key: key, onPressed: _busy ? null : onPressed,
      style: OutlinedButton.styleFrom(foregroundColor: _ink, side: const BorderSide(color: _line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400))),
  );

  Widget _paypalMark({double size = 44}) => Container(
    width: size, height: size, alignment: Alignment.center,
    decoration: BoxDecoration(color: const Color(0xFFF7F9FC),
      border: Border.all(color: const Color(0xFFE7E8EC)), borderRadius: BorderRadius.circular(8)),
    child: Text('P', style: TextStyle(color: _paypalBlue, fontSize: size * .72,
      fontWeight: FontWeight.w800, fontStyle: FontStyle.italic, height: 1)),
  );

  Widget _resortHero({required double height, required bool dark, Widget? child}) => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: SizedBox(width: double.infinity, height: height,
      child: Stack(fit: StackFit.expand, children: [
        Image.asset('assets/workspaces/plp.webp', fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF7C897D),
            child: Icon(Icons.waves_rounded, color: Colors.white54, size: 72))),
        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: dark ? [const Color(0x33000000), const Color(0xDD121512)]
            : [const Color(0x08FFFFFF), const Color(0x00000000)]))),
        if (child != null) child,
      ]),
    ),
  );

  Widget _setupPage() => _billingPage(children: [
    const SizedBox(height: 8),
    const Text('Grow\nwhat’s next.', key: ValueKey('plp-billing-setup-title'),
      style: TextStyle(color: _ink, fontFamily: 'serif', fontSize: 39, height: 1.02,
        fontWeight: FontWeight.w400, letterSpacing: -.7)),
    const SizedBox(height: 14),
    const Text('Choose a plan and start your PLP Enterprise workspace.',
      style: TextStyle(color: _ink, fontSize: 14, height: 1.45)),
    const SizedBox(height: 18),
    _resortHero(height: 242, dark: false),
    const SizedBox(height: 18),
    Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _paper, border: Border.all(color: _line), borderRadius: BorderRadius.circular(7)),
      child: Row(children: [
        _paypalMark(), const SizedBox(width: 13),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('PayPal', style: TextStyle(fontFamily: 'serif', fontSize: 17, color: _ink)),
          SizedBox(height: 3), Text('Ready to connect', style: TextStyle(color: _muted, fontSize: 12)),
        ])),
        const Icon(Icons.chevron_right_rounded, color: _ink),
      ]),
    ),
    const SizedBox(height: 14),
    _primaryButton(label: 'Choose a plan', icon: Icons.arrow_forward_rounded,
      key: const ValueKey('plp-billing-choose-plan'),
      onPressed: () => _show(_BillingView.select, _selectedPlanCode ?? 'launch')),
    const SizedBox(height: 10),
    const Text('Secure recurring payments through PayPal.', textAlign: TextAlign.center,
      style: TextStyle(color: _muted, fontSize: 11.5)),
  ]);

  Widget _planCard(_PlanOption plan) {
    final selected = _selectedPlanCode == plan.code;
    final description = plan.code == 'launch' ? 'Everything you need to begin.' : 'More capacity for growing businesses.';
    return Semantics(button: true, selected: selected,
      label: plan.name + ', ' + _planPrice(plan) + (selected ? ', selected' : ''),
      child: InkWell(key: ValueKey('plp-capability-' + plan.code),
        onTap: _tap(() => _show(_BillingView.select, plan.code)),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: selected ? const Color(0xFFFCF8EF) : _paper,
            border: Border.all(color: selected ? _gold : _line, width: selected ? 1.3 : 1),
            borderRadius: BorderRadius.circular(8)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 48, height: 54, alignment: Alignment.center,
              decoration: BoxDecoration(color: _softGold, borderRadius: BorderRadius.circular(5)),
              child: Icon(plan.icon, size: 27, color: _gold)),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(plan.name, style: const TextStyle(color: _ink, fontFamily: 'serif', fontSize: 20)),
              const SizedBox(height: 4),
              Text(_planPrice(plan), style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 7),
              Text(_comparePlans ? description + ' Monthly billing.' : description,
                style: const TextStyle(color: _muted, fontSize: 11, height: 1.35)),
            ])),
            const SizedBox(width: 10),
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              color: selected ? _ink : const Color(0xFF9A938A), size: 21),
          ]),
        ),
      ),
    );
  }

  Widget _planSelectionPage() => _billingPage(canGoBack: true, onBack: () => _show(_BillingView.main), children: [
    const SizedBox(height: 8),
    const Text('Choose your plan.', key: ValueKey('plp-billing-plan-title'),
      style: TextStyle(color: _ink, fontFamily: 'serif', fontSize: 32, height: 1.1,
        fontWeight: FontWeight.w400, letterSpacing: -.45)),
    const SizedBox(height: 8),
    const Text('Simple, transparent pricing. Change anytime.',
      style: TextStyle(color: _muted, fontSize: 13, height: 1.4)),
    const SizedBox(height: 18),
    Container(padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: const Color(0xFFF0ECE4), borderRadius: BorderRadius.circular(28)),
      child: Row(children: [
        Expanded(child: _segment('Monthly', selected: !_comparePlans, onTap: () => setState(() => _comparePlans = false))),
        Expanded(child: _segment('Compare', selected: _comparePlans, onTap: () => setState(() => _comparePlans = true))),
      ]),
    ),
    const SizedBox(height: 18),
    for (final plan in _plans) _planCard(plan),
    const SizedBox(height: 8),
    _primaryButton(label: 'Continue with PayPal', icon: Icons.arrow_forward_rounded,
      key: const ValueKey('plp-capability-pay-with-paypal'),
      onPressed: _selectedPlanCode == null ? null : () => _show(_BillingView.handoff, _selectedPlanCode)),
    const SizedBox(height: 11),
    const Text('No payment is taken until you approve the plan in PayPal.', textAlign: TextAlign.center,
      style: TextStyle(color: _muted, fontSize: 11, height: 1.35)),
  ]);


  Widget _pendingCheckoutPage(String approval) => _billingPage(
    canGoBack: true,
    onBack: () => _show(_BillingView.main),
    children: [
      const SizedBox(height: 16),
      const Text('Finish in PayPal · not active yet',
        style: TextStyle(color: _ink, fontFamily: 'serif', fontSize: 27, height: 1.12)),
      const SizedBox(height: 12),
      const Text('Your subscription is not active yet. Continue the existing approval in PayPal, then refresh to confirm the result.',
        style: TextStyle(color: _muted, fontSize: 13, height: 1.5)),
      const SizedBox(height: 26),
      Center(child: _paypalMark(size: 64)),
      const SizedBox(height: 22),
      _primaryButton(
        label: 'Open PayPal',
        icon: Icons.north_east_rounded,
        key: const ValueKey('plp-capability-open-paypal'),
        onPressed: () => _run('Opening PayPal…', () async {
          await _openApproval(approval);
          await _refreshAfterHandoff();
        }),
      ),
      const SizedBox(height: 10),
      _secondaryButton(
        label: 'Refresh PayPal state',
        key: const ValueKey('plp-billing-refresh-pending'),
        onPressed: () => _run('Checking PayPal…', _fetchStatus),
      ),
    ],
  );

  Widget _segment(String label, {required bool selected, required VoidCallback onTap}) => Material(
    color: selected ? _ink : Colors.transparent, borderRadius: BorderRadius.circular(24),
    child: InkWell(borderRadius: BorderRadius.circular(24), onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
        child: Center(child: Text(label, style: TextStyle(color: selected ? Colors.white : _ink,
          fontSize: 11.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w400))))),
  );

  Widget _handoffPage() {
    final plan = _option(_target ?? _selectedPlanCode) ?? _plans.first;
    return _billingPage(canGoBack: true, onBack: () => _show(_BillingView.select, plan.code), children: [
      const SizedBox(height: 18),
      const Text('Continue with PayPal.', key: ValueKey('plp-billing-handoff-title'),
        style: TextStyle(color: _ink, fontFamily: 'serif', fontSize: 32, height: 1.1)),
      const SizedBox(height: 12),
      const Text('You’ll be redirected to PayPal to authorize your recurring payments.',
        style: TextStyle(color: _muted, fontSize: 13, height: 1.5)),
      const SizedBox(height: 28), Center(child: _paypalMark(size: 72)),
      const SizedBox(height: 18),
      Center(child: Text(plan.name, style: const TextStyle(color: _ink, fontFamily: 'serif', fontSize: 22))),
      const SizedBox(height: 5),
      Center(child: Text(_planPrice(plan), style: const TextStyle(color: _ink, fontSize: 15))),
      const SizedBox(height: 28),
      _infoLine(Icons.lock_outline_rounded, 'Secure checkout with PayPal.'),
      const SizedBox(height: 13),
      _infoLine(Icons.person_outline_rounded, 'You’ll be returned to PLP Enterprise after approval.'),
      if (_statusRefreshFailed) ...[
        const SizedBox(height: 22),
        Container(padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: const Color(0xFFF8EFE9), border: Border.all(color: const Color(0xFFE4CBB9)),
            borderRadius: BorderRadius.circular(7)),
          child: const Text('PayPal opened, but billing status could not be refreshed.',
            style: TextStyle(color: _ink, fontSize: 12, height: 1.4))),
        const SizedBox(height: 10),
        _secondaryButton(label: 'Refresh billing status', key: const ValueKey('plp-billing-refresh-status'), onPressed: _retry),
      ],
      const SizedBox(height: 26),
      _primaryButton(label: _busy ? 'Opening PayPal…' : 'Continue to PayPal', icon: Icons.north_east_rounded,
        key: const ValueKey('plp-capability-continue-to-paypal'), onPressed: () => _checkout(plan.code)),
      const SizedBox(height: 7),
      TextButton(key: const ValueKey('plp-billing-cancel-handoff'),
        onPressed: _busy ? null : () => _show(_BillingView.select, plan.code),
        child: const Text('Cancel', style: TextStyle(color: _ink, fontSize: 12))),
    ]);
  }

  Widget _infoLine(IconData icon, String label) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, size: 18, color: _gold), const SizedBox(width: 10),
    Expanded(child: Text(label, style: const TextStyle(color: _muted, fontSize: 12, height: 1.4))),
  ]);

  Widget _activeSubscriptionPage() {
    final subscription = _map(_status['subscription']);
    final pending = _map(_status['pendingPlanChange']);
    final pendingStatus = (pending['status'] ?? '').toString().toLowerCase();
    final pendingChange = pending.isNotEmpty && !_terminalApprovalStates.contains(pendingStatus);
    final currentCode = (subscription['plan_code'] ?? '').toString();
    final planName = (subscription['plan_name'] ?? '').toString().trim().isNotEmpty
      ? subscription['plan_name'].toString().trim() : _planName(currentCode);
    final renewalDate = plpBillingShortDate(subscription['renews_on']);
    final verified = !_unresolved && subscription['source_kind'] == 'provider_verified' && subscription['verified_at'] != null;
    final cancelPending = _cancelRequested || const {'cancel_requested', 'cancelling', 'pending_cancellation'}.contains(_state(subscription));
    final others = _plans.where((option) => option.code != currentCode).toList();
    return _billingPage(children: [
      _resortHero(height: 300, dark: true, child: Padding(
        padding: const EdgeInsets.fromLTRB(19, 20, 19, 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('CURRENT PLAN', style: TextStyle(color: Color(0xFFF2E9D4),
              fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.w600))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
              decoration: BoxDecoration(color: verified ? const Color(0xFF526E58) : const Color(0xFF8A6C42),
                borderRadius: BorderRadius.circular(18)),
              child: Text(verified ? 'Active' : 'Unconfirmed', style: const TextStyle(color: Colors.white, fontSize: 10))),
          ]),
          const Spacer(),
          Text(planName, style: const TextStyle(color: Colors.white, fontFamily: 'serif', fontSize: 36, height: 1.05)),
          const SizedBox(height: 8),
          Text(_monthlyPrice(subscription), style: const TextStyle(color: Colors.white, fontFamily: 'serif', fontSize: 24, height: 1.15)),
          if (renewalDate.isNotEmpty) ...[const SizedBox(height: 10), Text('Renews ' + renewalDate, style: const TextStyle(color: Colors.white, fontSize: 13))],
        ]),
      )),
      const SizedBox(height: 17),
      if (pendingChange || cancelPending) ...[
        Container(width: double.infinity, padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: _paper, border: Border.all(color: _line), borderRadius: BorderRadius.circular(7)),
          child: Text(pendingChange ? 'Plan change awaiting PayPal confirmation.' : 'Cancellation pending confirmation from PayPal.',
            style: const TextStyle(color: _ink, fontSize: 12, height: 1.4))),
        const SizedBox(height: 12),
      ],
      _connectionRow(title: 'PayPal', detail: verified ? 'Subscription connected' : 'Subscription status unconfirmed', leading: _paypalMark(size: 42)),
      const SizedBox(height: 5),
      _actionRow(keyName: 'change-plan', title: 'Change plan', subtitle: 'Review the plan and effective date',
        icon: Icons.sync_alt_rounded, onTap: others.isEmpty ? null : () => _openChangePlanSheet(others.first)),
      _actionRow(keyName: 'history', title: 'Payment history', subtitle: 'View recorded payments',
        icon: Icons.calendar_month_outlined, onTap: () => _show(_BillingView.history)),
      _actionRow(keyName: 'refresh', title: 'Refresh PayPal state', subtitle: 'Check the latest subscription details',
        icon: Icons.refresh_rounded, onTap: _openRefreshSheet),
      _actionRow(keyName: 'cancel', title: 'Cancel subscription',
        subtitle: renewalDate.isEmpty ? 'Review cancellation details' : 'Access currently renews ' + renewalDate,
        icon: Icons.delete_outline_rounded, danger: true, onTap: cancelPending ? null : _openCancelSheet),
    ]);
  }

  Widget _connectionRow({required String title, required String detail, required Widget leading}) => Container(
    margin: const EdgeInsets.only(bottom: 5), padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(color: _paper, border: Border.all(color: _line), borderRadius: BorderRadius.circular(8)),
    child: Row(children: [
      leading, const SizedBox(width: 13),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: _ink, fontFamily: 'serif', fontSize: 16)),
        const SizedBox(height: 3), Text(detail, style: const TextStyle(color: _muted, fontSize: 11)),
      ])),
      const Icon(Icons.chevron_right_rounded, color: _ink, size: 21),
    ]),
  );

  Widget _actionRow({required String keyName, required String title, required String subtitle,
    required IconData icon, required VoidCallback? onTap, bool danger = false}) => Column(children: [
    InkWell(key: ValueKey('plp-capability-' + keyName), onTap: _busy || onTap == null ? null : onTap,
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 2),
        child: Row(children: [
          Icon(icon, size: 21, color: danger ? _danger : _muted), const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: danger ? _danger : _ink, fontFamily: 'serif', fontSize: 15)),
            const SizedBox(height: 3), Text(subtitle, style: const TextStyle(color: _muted, fontSize: 10.5)),
          ])),
          const Icon(Icons.chevron_right_rounded, size: 20, color: _muted),
        ]),
      )),
    const Divider(height: 1, color: _line),
  ]);

  Widget _historyPage() {
    final activity = _status['activity'];
    final rows = activity is List ? _history(activity) : const <_HistoryRow>[];
    return _billingPage(canGoBack: true, onBack: () => _show(_BillingView.main), children: [
      const SizedBox(height: 9),
      const Text('Payment history.', style: TextStyle(color: _ink, fontFamily: 'serif', fontSize: 31, height: 1.1)),
      const SizedBox(height: 13), const Divider(height: 1, color: _line),
      if (activity is! List) ...[
        const SizedBox(height: 20),
        const Text('Payment history is not available right now.', style: TextStyle(color: _muted, fontSize: 13, height: 1.45)),
        const SizedBox(height: 13),
        _secondaryButton(label: 'Try again', key: const ValueKey('plp-billing-retry-history'), onPressed: () => _run('Refreshing…', _fetchStatus)),
      ] else if (rows.isEmpty) ...[
        const SizedBox(height: 20), const Text('No payments recorded yet.', style: TextStyle(color: _muted, fontSize: 13)),
      ] else ...[for (final row in rows.take(20)) _historyTile(row)],
    ]);
  }

  Widget _historyTile(_HistoryRow row) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 1),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
    child: Row(children: [
      const Icon(Icons.receipt_long_outlined, color: _muted, size: 20), const SizedBox(width: 13),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(row.date, style: const TextStyle(color: _ink, fontSize: 12)),
        const SizedBox(height: 4), Text(row.amount, style: const TextStyle(color: _ink, fontWeight: FontWeight.w600, fontSize: 13)),
      ])),
      if (row.status.isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: const Color(0xFFE7EEE4), borderRadius: BorderRadius.circular(20)),
        child: Text(row.status, style: const TextStyle(color: Color(0xFF45614A), fontSize: 10))),
      const SizedBox(width: 7), const Icon(Icons.chevron_right_rounded, size: 19, color: _muted),
    ]),
  );

  Widget _errorPage({required bool active}) => Material(key: const ValueKey('plp-paypal-billing'), color: _canvas,
    child: SafeArea(bottom: false, child: Column(children: [
      _billingHeader(canGoBack: true, onBack: () => _show(active ? _BillingView.main : _BillingView.select)),
      Expanded(child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, 60, 20, 104 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          const SizedBox(height: 60),
          Container(padding: const EdgeInsets.fromLTRB(19, 28, 19, 22),
            decoration: BoxDecoration(color: _paper, border: Border.all(color: _line), borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              const Icon(Icons.warning_amber_rounded, color: _danger, size: 46), const SizedBox(height: 16),
              const Text('We couldn’t reach PayPal.', textAlign: TextAlign.center,
                style: TextStyle(color: _danger, fontFamily: 'serif', fontSize: 23)),
              const SizedBox(height: 10),
              Text(_error ?? 'Please check your connection and try again.', textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 12, height: 1.5)),
              const SizedBox(height: 25),
              _primaryButton(label: _busy ? 'Trying again…' : 'Try again', key: const ValueKey('plp-billing-retry'),
                icon: Icons.refresh_rounded, onPressed: _retry),
              const SizedBox(height: 9),
              _secondaryButton(label: 'Go back', key: const ValueKey('plp-billing-go-back'),
                onPressed: () => _show(active ? _BillingView.main : _BillingView.select)),
            ]),
          ),
        ],
      )),
    ])),
  );

  Widget _billingSheet(BuildContext sheetContext, {required String title, required List<Widget> children}) => SafeArea(
    top: false,
    child: Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * .84),
      decoration: const BoxDecoration(color: _paper, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 9),
        Container(width: 38, height: 4, decoration: BoxDecoration(color: const Color(0xFF7A756E), borderRadius: BorderRadius.circular(5))),
        Padding(padding: const EdgeInsets.fromLTRB(20, 10, 12, 7),
          child: Row(children: [
            Expanded(child: Text(title, style: const TextStyle(color: _ink, fontFamily: 'serif', fontSize: 23))),
            IconButton(key: const ValueKey('plp-billing-sheet-close'), tooltip: 'Close',
              onPressed: () => Navigator.of(sheetContext).pop(), icon: const Icon(Icons.close_rounded, size: 20)),
          ])),
        Flexible(child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 22 + MediaQuery.viewPaddingOf(sheetContext).bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))),
      ]),
    ),
  );

  void _openChangePlanSheet(_PlanOption target) {
    final subscription = _map(_status['subscription']);
    final currentCode = (subscription['plan_code'] ?? '').toString();
    final current = _option(currentCode);
    final renewalDate = plpBillingShortDate(subscription['renews_on']);
    unawaited(showModalBottomSheet<void>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (sheetContext) => _billingSheet(sheetContext, title: 'Change plan.', children: [
        const SizedBox(height: 6),
        _planSummaryCard(label: 'Current plan', name: current?.name ?? _planName(currentCode), price: _monthlyPrice(subscription)),
        const Padding(padding: EdgeInsets.symmetric(vertical: 11), child: Icon(Icons.arrow_downward_rounded, color: _ink, size: 22)),
        _planSummaryCard(label: 'New plan', name: target.name, price: _planPrice(target)),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: const Color(0xFFF2ECE1), borderRadius: BorderRadius.circular(7)),
          child: Row(children: [
            const Icon(Icons.calendar_month_outlined, color: _gold, size: 20), const SizedBox(width: 10),
            Expanded(child: Text(renewalDate.isEmpty
              ? 'The effective date will follow the provider-confirmed subscription state.'
              : 'The change is based on your current renewal date: ' + renewalDate + '.',
              style: const TextStyle(color: _ink, fontSize: 11, height: 1.4))),
          ])),
        const SizedBox(height: 17),
        _primaryButton(label: 'Confirm plan change', key: ValueKey('plp-capability-switch-to-' + target.code),
          onPressed: () { Navigator.of(sheetContext).pop(); unawaited(_changePlan(target.code)); }),
        const SizedBox(height: 8),
        _secondaryButton(label: 'Keep current plan', key: const ValueKey('plp-billing-keep-plan'),
          onPressed: () => Navigator.of(sheetContext).pop()),
      ]),
    ));
  }

  Widget _planSummaryCard({required String label, required String name, required String price}) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(color: _paper, border: Border.all(color: _line), borderRadius: BorderRadius.circular(7)),
    child: Row(children: [
      Container(width: 43, height: 47, alignment: Alignment.center,
        decoration: BoxDecoration(color: _softGold, borderRadius: BorderRadius.circular(5)),
        child: const Icon(Icons.apartment_rounded, color: _gold, size: 24)),
      const SizedBox(width: 11),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: _muted, fontSize: 10)), const SizedBox(height: 3),
        Text(name, style: const TextStyle(color: _ink, fontFamily: 'serif', fontSize: 18)),
        const SizedBox(height: 3), Text(price, style: const TextStyle(color: _ink, fontSize: 12)),
      ])),
    ]),
  );

  void _openCancelSheet() {
    final subscription = _map(_status['subscription']);
    final renewalDate = plpBillingShortDate(subscription['renews_on']);
    unawaited(showModalBottomSheet<void>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (sheetContext) => _billingSheet(sheetContext, title: 'Cancel subscription?', children: [
        const Text('This will stop your recurring billing with PayPal.', style: TextStyle(color: _muted, fontSize: 12, height: 1.45)),
        const SizedBox(height: 15),
        Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFF2ECE1), borderRadius: BorderRadius.circular(7)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.calendar_month_outlined, color: _gold, size: 21), const SizedBox(width: 10),
            Expanded(child: Text(renewalDate.isEmpty
              ? 'Your access end date depends on PayPal’s confirmed subscription state.'
              : 'You’ll keep access until ' + renewalDate + '. No further charges are expected after cancellation is confirmed.',
              style: const TextStyle(color: _ink, fontSize: 12, height: 1.4))),
          ])),
        const SizedBox(height: 17),
        _primaryButton(label: 'Cancel subscription', danger: true, key: const ValueKey('plp-billing-confirm-cancel'),
          onPressed: () { Navigator.of(sheetContext).pop(); unawaited(_cancel()); }),
        const SizedBox(height: 8),
        _secondaryButton(label: 'Keep subscription', key: const ValueKey('plp-billing-keep-subscription'),
          onPressed: () => Navigator.of(sheetContext).pop()),
      ]),
    ));
  }

  void _openRefreshSheet() {
    unawaited(showModalBottomSheet<void>(
      context: context, isScrollControlled: true, isDismissible: false, enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _billingSheet(sheetContext, title: 'Refresh PayPal state.', children: const [
        SizedBox(height: 18),
        Text('We’ll check the latest subscription details with PayPal and update your workspace.',
          style: TextStyle(color: _muted, fontSize: 12, height: 1.45)),
        SizedBox(height: 28),
        Center(child: SizedBox(width: 44, height: 44, child: CircularProgressIndicator(color: _gold, strokeWidth: 2.5))),
        SizedBox(height: 18),
        Center(child: Text('Checking with PayPal…', style: TextStyle(color: _ink, fontFamily: 'serif', fontSize: 18))),
        SizedBox(height: 6),
        Center(child: Text('This may take a few moments.', style: TextStyle(color: _muted, fontSize: 11))),
        SizedBox(height: 25),
      ]),
    ));
    unawaited(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await _reconcile();
      if (!mounted) return;
      Navigator.of(context).maybePop();
      if (_unresolved) setState(() => _view = _BillingView.error);
    }());
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
