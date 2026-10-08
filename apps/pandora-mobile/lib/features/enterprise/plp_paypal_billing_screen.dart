import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/plp_paypal_billing_api.dart';
import '../../core/security/pandora_identity_verification.dart';
import 'plp_billing_surfaces.dart';
import 'plp_editorial_surfaces.dart';
import 'plp_line_icons.dart';

typedef PlpBillingUrlLauncher = Future<bool> Function(Uri url);

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `YYYY-MM-DD` (optionally followed by a time) as a UTC calendar date.
DateTime? plpBillingDate(String? value) {
  if (value == null) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value.trim());
  if (m == null) return null;
  final year = int.parse(m[1]!);
  final month = int.parse(m[2]!);
  final day = int.parse(m[3]!);
  final date = DateTime.utc(year, month, day);
  if (date.month != month || date.day != day) return null;
  return date;
}

String plpBillingDateShort(DateTime d) => '${d.day} ${_months[d.month - 1]}';
String plpBillingDateLong(DateTime d) => '${plpBillingDateShort(d)} ${d.year}';

DateTime _oneMonthBefore(DateTime d) {
  final year = d.month == 1 ? d.year - 1 : d.year;
  final month = d.month == 1 ? 12 : d.month - 1;
  final lastDay = DateTime.utc(year, month + 1, 0).day;
  return DateTime.utc(year, month, math.min(d.day, lastDay));
}

String _ago(DateTime then, DateTime now) {
  final diff = now.difference(then);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}

String _money(int cents) => cents % 100 == 0
    ? '${cents ~/ 100}'
    : '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

/// Everything the workspace shows, derived only from the backend status.
class _BillingView {
  _BillingView(this.snapshot, this.now)
      : today = DateTime.utc(now.year, now.month, now.day) {
    final sub = snapshot.subscription;
    holds = sub != null && sub.holdsPlan;
    ghost = sub != null && sub.state == 'cancelled';
    final checkout = snapshot.checkout;
    final change = snapshot.planChange;
    pendingCheckout = !holds && checkout?.pendingAt(now) == true;
    pendingChange = holds && change?.pending == true;
    waitingUrl = pendingCheckout
        ? checkout!.approvalUrl
        : pendingChange
            ? change!.approvalUrl
            : null;
    pendingPlan = pendingCheckout
        ? checkout!.planCode
        : pendingChange
            ? change!.toPlanCode
            : null;
    cancelRequested = holds && checkout?.status == 'cancel_requested';
    plan = snapshot.plan(sub?.planCode);
    cycleEnd = holds
        ? plpBillingDate(sub!.renewsOn)
        : ghost
            ? plpBillingDate(sub!.endsOn)
            : null;
    final end = cycleEnd;
    if (end != null && plan?.interval == 'month') {
      var start = _oneMonthBefore(end);
      final started = plpBillingDate(sub!.startsOn);
      if (started != null && started.isAfter(start) && started.isBefore(end)) {
        start = started;
      }
      cycleStart = start;
    }
  }

  final PlpBillingSnapshot snapshot;
  final DateTime now;
  final DateTime today;
  late final bool holds;
  late final bool ghost;
  late final bool pendingCheckout;
  late final bool pendingChange;
  late final Uri? waitingUrl;
  late final String? pendingPlan;
  late final bool cancelRequested;
  late final PlpBillingPlan? plan;
  late final DateTime? cycleEnd;
  DateTime? cycleStart;

  PlpBillingSubscription? get sub => snapshot.subscription;
  bool get locked => waitingUrl != null;
  int? get daysLeft => cycleEnd?.difference(today).inDays;
  bool get ghostWithAccess => ghost && (daysLeft ?? -1) >= 0;
  String? get currentPlanCode => holds ? sub!.planCode : null;

  /// Timeline only when both ends are known and today sits inside the cycle.
  bool get hasPlayhead {
    final start = cycleStart;
    final end = cycleEnd;
    return start != null &&
        end != null &&
        start.isBefore(end) &&
        !now.isBefore(start) &&
        !now.isAfter(end.add(const Duration(days: 1)));
  }

  double _pos(DateTime t) {
    final start = cycleStart!.millisecondsSinceEpoch;
    final span = cycleEnd!.millisecondsSinceEpoch - start;
    return ((t.millisecondsSinceEpoch - start) / span).clamp(0.0, 1.0);
  }

  double get todayPos => _pos(now);

  double get sealPos {
    final verified = DateTime.tryParse(sub?.verifiedAt ?? '')?.toUtc();
    if (verified == null) return todayPos;
    return math.min(_pos(verified), todayPos);
  }

  (String, String) get entryText {
    if (locked) return ('Pandora billing', ' \u00b7 waiting for PayPal');
    final name = plan?.name ?? sub?.planCode;
    if (holds) {
      final end = cycleEnd;
      return (
        'Pandora',
        [
          if (name != null) name,
          if (end != null) 'renews ${plpBillingDateShort(end)}',
        ].map((part) => ' \u00b7 $part').join(),
      );
    }
    if (ghostWithAccess) {
      return (
        'Pandora',
        [
          if (name != null) name,
          'access until ${plpBillingDateShort(cycleEnd!)}',
        ].map((part) => ' \u00b7 $part').join(),
      );
    }
    return ('Pandora billing', ' \u00b7 not subscribed');
  }
}

/// Native PLP Enterprise billing workspace (approved concept).
///
/// Every value shown is read back from the owner API, which reads it from
/// PayPal or from Pandora's billing records. Nothing is assumed
/// optimistically: checkout, plan changes and cancellation only appear as
/// done after reconcile + status confirm them. Flutter never calls PayPal.
class PlpPaypalBillingScreen extends StatefulWidget {
  const PlpPaypalBillingScreen({
    super.key,
    required this.organizationId,
    required this.onOpenNavigation,
    this.api,
    this.launchApproval,
    this.clock,
    this.onBack,
  });

  /// The current PLP organization. Null/empty renders a missing-organization
  /// state and no request is sent.
  final String? organizationId;
  final VoidCallback onOpenNavigation;
  final PlpPaypalBillingApi? api;
  final PlpBillingUrlLauncher? launchApproval;
  final DateTime Function()? clock;

  /// Returns to the surface that opened billing (PLP routed-tool back).
  final VoidCallback? onBack;

  @override
  State<PlpPaypalBillingScreen> createState() => _PlpPaypalBillingScreenState();
}

enum _PendingAction { none, checkout, changePlan, reconcile, cancel }

class _PlpPaypalBillingScreenState extends State<PlpPaypalBillingScreen>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _diffKey = GlobalKey();
  PlpPaypalBillingApi? _api;
  PlpBillingSnapshot? _snapshot;
  PlpBillingProblem? _problem;
  String? _selectedPlan;
  bool _loading = true;
  bool _busy = false;
  bool _checking = false;
  bool _handoffOpen = false;
  bool _cancelOpen = false;
  bool _awaitingProviderReturn = false;
  _PendingAction _identityRetry = _PendingAction.none;
  String? _identityRetryPlan;
  Timer? _ticker;

  String? get _organizationId {
    final id = widget.organizationId?.trim();
    return id == null || id.isEmpty ? null : id;
  }

  DateTime get _now => (widget.clock ?? DateTime.now)().toUtc();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final organizationId = _organizationId;
    if (organizationId == null) {
      _loading = false;
      _problem = const PlpBillingProblem(
        'Organization missing.',
        'This workspace has no organization selected, so billing cannot load.',
      );
      return;
    }
    _api = widget.api ?? PlpPaypalBillingApi.forOrganization(organizationId);
    unawaited(_loadStatus());
    // Keeps "checked X ago" honest as time passes; the time itself is the
    // backend's last PayPal verification.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.api == null) _api?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the external PayPal approval: confirm with PayPal first,
    // then show what the server recorded.
    if (state == AppLifecycleState.resumed && _awaitingProviderReturn) {
      _awaitingProviderReturn = false;
      unawaited(_check());
    }
  }

  Future<void> _loadStatus() async {
    final api = _api;
    if (api == null) return;
    try {
      final snapshot = await api.status();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
        if (_selectedPlan != null && snapshot.plan(_selectedPlan) == null) {
          _selectedPlan = null;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _problem = PlpBillingProblem.from(error);
      });
    }
  }

  Future<void> _retry() async {
    if (_busy) return;
    setState(() {
      _loading = _snapshot == null;
      _problem = null;
    });
    await _loadStatus();
  }

  Future<void> _run(
    Future<void> Function() work, {
    _PendingAction retry = _PendingAction.none,
    String? retryPlan,
  }) async {
    if (_busy || _api == null) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await work();
    } catch (error) {
      final problem = PlpBillingProblem.from(error);
      if (mounted) {
        setState(() {
          _problem = problem;
          _identityRetry = problem.needsIdentity ? retry : _PendingAction.none;
          _identityRetryPlan = problem.needsIdentity ? retryPlan : null;
        });
      }
      // Never leave an unconfirmed outcome on screen: re-read server state.
      await _loadStatusQuietly();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadStatusQuietly() async {
    try {
      final snapshot = await _api!.status();
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (_) {
      // The primary problem is already on screen.
    }
  }

  Future<void> _reconcileAndReload() async {
    try {
      await _api!.reconcile();
    } finally {
      final snapshot = await _api!.status();
      if (mounted) setState(() => _snapshot = snapshot);
    }
  }

  Uri _returnUri(String outcome) {
    final base = kIsWeb && Uri.base.scheme == 'https'
        ? Uri.base.origin
        : 'https://pandoras-box-system.vercel.app';
    return Uri.parse('$base/?pandora_billing=paypal-$outcome');
  }

  Future<void> _checkout(String planCode) => _run(
        () async {
          final approval = await _api!.checkout(
            planCode: planCode,
            returnUrl: _returnUri('return'),
            cancelUrl: _returnUri('cancel'),
          );
          await _loadStatusQuietly();
          await _openApproval(approval.approvalUrl);
        },
        retry: _PendingAction.checkout,
        retryPlan: planCode,
      );

  Future<void> _changePlan(String planCode) => _run(
        () async {
          final approval = await _api!.changePlan(
            planCode,
            returnUrl: _returnUri('return'),
            cancelUrl: _returnUri('cancel'),
          );
          if (approval.approvalUrl != null) {
            await _loadStatusQuietly();
            await _openApproval(approval.approvalUrl);
          } else {
            await _reconcileAndReload();
          }
        },
        retry: _PendingAction.changePlan,
        retryPlan: planCode,
      );

  /// Reconcile with PayPal (server side), then read status.
  Future<void> _check() async {
    if (_busy) return;
    setState(() => _checking = true);
    try {
      await _run(_reconcileAndReload, retry: _PendingAction.reconcile);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _cancel() => _run(
        () async {
          await _api!.cancel();
          await _reconcileAndReload();
        },
        retry: _PendingAction.cancel,
      );

  Future<void> _openApproval(Uri? url) async {
    if (url == null) {
      throw const PlpBillingProblemException(PlpBillingProblem(
        'Approval link missing.',
        'PayPal did not return an approval link. Nothing was approved.',
      ));
    }
    final launcher = widget.launchApproval ??
        (Uri value) => launchUrl(value, mode: LaunchMode.externalApplication);
    var opened = false;
    try {
      opened = await launcher(url);
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      throw const PlpBillingProblemException(PlpBillingProblem(
        'PayPal did not open.',
        'Pandora could not open PayPal. Use \u201cOpen PayPal\u201d to try again.',
      ));
    }
    _awaitingProviderReturn = true;
  }

  Future<void> _reopenApproval(Uri url) async {
    if (_busy) return;
    try {
      await _openApproval(url);
    } catch (error) {
      if (mounted) setState(() => _problem = PlpBillingProblem.from(error));
    }
  }

  Future<void> _verifyIdentity() async {
    final retry = _identityRetry;
    final plan = _identityRetryPlan;
    final dependencies =
        context.getInheritedWidgetOfExactType<PandoraDependencies>();
    final verified = await verifyCoreIdentity(context, dependencies?.auth);
    if (!mounted) return;
    if (!verified) {
      setState(() => _problem = const PlpBillingProblem(
            'Identity not confirmed.',
            'The authenticator check was not completed, so nothing was sent to PayPal.',
            needsIdentity: true,
          ));
      return;
    }
    setState(() {
      _problem = null;
      _identityRetry = _PendingAction.none;
    });
    switch (retry) {
      case _PendingAction.checkout:
        if (plan != null) await _checkout(plan);
      case _PendingAction.changePlan:
        if (plan != null) await _changePlan(plan);
      case _PendingAction.reconcile:
        await _check();
      case _PendingAction.cancel:
        await _cancel();
      case _PendingAction.none:
        break;
    }
  }

  void _select(_BillingView view, String code) {
    setState(() {
      _selectedPlan =
          code == view.currentPlanCode || code == _selectedPlan ? null : code;
    });
  }

  double _panelHeight(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return (h * .4).clamp(330.0, math.max(330.0, h - 120));
  }

  void _openHandoff() {
    setState(() => _handoffOpen = true);
    // Lift the workspace so the chosen node and difference line stay
    // visible above the panel.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final box = _diffKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) return;
      final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
      final limit =
          MediaQuery.sizeOf(context).height - _panelHeight(context) - 16;
      final delta = bottom - limit;
      if (delta <= 0) return;
      final target =
          math.min(_scroll.offset + delta, _scroll.position.maxScrollExtent);
      if (plpReduceMotion(context)) {
        _scroll.jumpTo(target);
      } else {
        unawaited(_scroll.animateTo(target,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic));
      }
    });
  }

  Future<void> _continueHandoff(_BillingView view) async {
    final code = _selectedPlan;
    if (code == null) return;
    if (view.holds) {
      await _changePlan(code);
    } else {
      await _checkout(code);
    }
    if (mounted) {
      setState(() {
        _handoffOpen = false;
        _selectedPlan = null;
      });
    }
  }

  Future<void> _holdConfirmed() async {
    await _cancel();
    if (mounted) setState(() => _cancelOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final view = snapshot == null ? null : _BillingView(snapshot, _now);
    final locked = view?.locked ?? false;
    final open = (_handoffOpen || _cancelOpen) && view != null && !locked;
    final content = _content(context, view, locked: locked, open: open);

    final Widget page;
    if (locked) {
      page = Column(
        children: [
          PlpBillingWaitingBand(
            onOpenNavigation: widget.onOpenNavigation,
            onBack: widget.onBack,
            checking: _checking,
            onOpenPaypal:
                _busy ? null : () => _reopenApproval(view!.waitingUrl!),
            onCheckAgain: _busy ? null : _check,
            problem: _problem?.title,
          ),
          Expanded(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: .34,
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.matrix(<double>[
                      .2126, .7152, .0722, 0, 0, //
                      .2126, .7152, .0722, 0, 0, //
                      .2126, .7152, .0722, 0, 0, //
                      0, 0, 0, 1, 0,
                    ]),
                    child: content,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      page = SafeArea(bottom: false, child: content);
    }

    return Material(
      key: const ValueKey('plp-paypal-billing'),
      color: plpCanvas,
      child: Stack(
        children: [
          Positioned.fill(child: page),
          if (open) ...[
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('plp-billing-scrim'),
                behavior: HitTestBehavior.opaque,
                onTap: _busy
                    ? null
                    : () => setState(() {
                          _handoffOpen = false;
                          _cancelOpen = false;
                        }),
                child: const ColoredBox(color: Color(0x38171512)),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _Rise(
                child: _handoffOpen
                    ? _handoffPanel(context, view)
                    : _cancelPanel(view),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _handoffPanel(BuildContext context, _BillingView view) {
    final plan = view.snapshot.plan(_selectedPlan);
    return PlpBillingBlackPanel(
      height: _panelHeight(context),
      child: PlpBillingHandoffContent(
        planName: plan?.name ?? '',
        price: plan?.priceLabel ?? '',
        busy: _busy,
        onContinue: () => _continueHandoff(view),
        onNotNow: () => setState(() => _handoffOpen = false),
      ),
    );
  }

  Widget _cancelPanel(_BillingView view) {
    final end = view.cycleEnd;
    return PlpBillingBlackPanel(
      child: PlpBillingCancelContent(
        accessLine: end == null
            ? 'PayPal confirms when access ends.'
            : 'Access continues until ${plpBillingDateLong(end)}.',
        busy: _busy,
        onConfirmed: _holdConfirmed,
        onKeep: () => setState(() => _cancelOpen = false),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    _BillingView? view, {
    required bool locked,
    required bool open,
  }) {
    final children = <Widget>[
      if (!locked)
        PlpEditorialHeader(
          title: 'Subscription',
          onOpenNavigation: widget.onOpenNavigation,
          trailing: widget.onBack == null
              ? null
              : IconButton(
                  key: const ValueKey('plp-billing-back'),
                  onPressed: widget.onBack,
                  tooltip: 'Back',
                  color: plpInk,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
        ),
      SizedBox(height: locked ? 28 : 34),
      const PlpBillingTitle('Pandora billing'),
    ];

    if (view != null) {
      children
        ..add(const SizedBox(height: 14))
        ..add(_statusLine(view));
      if (view.snapshot.sandbox) {
        children.add(const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'PayPal sandbox \u00b7 test mode',
            key: ValueKey('plp-billing-sandbox'),
            style: TextStyle(color: plpWarn, fontSize: 11.5),
          ),
        ));
      }
    }

    final problem = _problem;
    if (problem != null && !locked) {
      final identity =
          problem.needsIdentity && _identityRetry != _PendingAction.none;
      children
        ..add(const SizedBox(height: 18))
        ..add(PlpBillingNotice(
          key: const ValueKey('plp-billing-problem'),
          title: problem.title,
          body: problem.body,
          action: identity
              ? 'Verify identity'
              : _api == null
                  ? null
                  : 'Try again',
          onAction: identity ? _verifyIdentity : (_busy ? null : _retry),
        ));
    }

    if (_loading) {
      children.add(const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Text('Loading\u2026',
            style: TextStyle(color: plpMuted, fontSize: 14.5)),
      ));
    } else if (view != null) {
      children.addAll(_workspace(view, open: open));
    }

    return ListView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(
          18, locked ? 0 : 14, 18, open ? _panelHeight(context) + 40 : 140),
      children: children,
    );
  }

  Widget _statusLine(_BillingView view) {
    final sub = view.sub;
    final name = view.plan?.name ?? sub?.planCode;
    if (view.holds) {
      final state = switch (sub!.state) {
        'active' => 'Active',
        'trial' => 'Trial',
        'past_due' => 'Past due',
        'suspended' => 'Suspended',
        _ => sub.state,
      };
      final rest = [
        if (name != null) name,
        if (view.plan != null) view.plan!.priceLabel,
        if (view.cancelRequested) 'cancellation sent',
      ];
      return PlpBillingStatusLine(
        key: const ValueKey('plp-billing-status'),
        lead: state,
        rest: rest.map((p) => '\u00b7 $p').join(' '),
        tone: sub.state == 'active' || sub.state == 'trial'
            ? PlpBillingTone.good
            : PlpBillingTone.warn,
      );
    }
    if (view.ghost) {
      return PlpBillingStatusLine(
        key: const ValueKey('plp-billing-status'),
        lead: 'Cancelled',
        rest: name == null ? '' : '\u00b7 $name',
        tone: PlpBillingTone.off,
      );
    }
    return const PlpBillingStatusLine(
      key: ValueKey('plp-billing-status'),
      lead: 'Not subscribed',
      rest: '',
      tone: PlpBillingTone.off,
    );
  }

  PlpBillingSeal _seal(_BillingView view) {
    final sub = view.sub!;
    final source = view.snapshot.sandbox ? 'PayPal sandbox' : 'PayPal';
    final verified = DateTime.tryParse(sub.verifiedAt ?? '')?.toUtc();
    final String label;
    if (_checking) {
      label = '$source \u00b7 checking\u2026';
    } else if (!sub.providerVerified || verified == null) {
      label = 'Account record \u00b7 not checked with PayPal';
    } else {
      label = '$source \u00b7 checked ${_ago(verified, view.now)}';
    }
    return PlpBillingSeal(
      label: label,
      verified: sub.providerVerified,
      checking: _checking,
      onTap: _busy ? null : _check,
    );
  }

  List<Widget> _workspace(_BillingView view, {required bool open}) {
    final sub = view.sub;
    final widgets = <Widget>[];

    if (sub != null && (sub.state == 'past_due' || sub.state == 'suspended')) {
      widgets.add(const Padding(
        padding: EdgeInsets.only(top: 14),
        child: PlpBillingNotice(title: 'Payment needs attention in PayPal.'),
      ));
    }
    if (view.cancelRequested) {
      widgets.add(const Padding(
        padding: EdgeInsets.only(top: 14),
        child: PlpBillingNotice(
          key: ValueKey('plp-billing-cancel-sent'),
          title: 'Cancellation sent \u00b7 waiting for PayPal',
        ),
      ));
    }
    if (sub == null && view.snapshot.checkout?.status == 'failed') {
      widgets.add(const Padding(
        padding: EdgeInsets.only(top: 14),
        child: PlpBillingNotice(
            title: 'Last checkout did not start \u00b7 nothing charged'),
      ));
    }

    // Temporal hero.
    final days = view.daysLeft;
    final end = view.cycleEnd;
    if (view.holds) {
      final known = days != null && days >= 0;
      widgets
        ..add(const SizedBox(height: 42))
        ..add(PlpBillingTemporalHero(
          value: known ? '$days' : '\u2014',
          unit: known ? (days == 1 ? 'day' : 'days') : '',
          caption: 'renews',
          date: end == null ? null : plpBillingDateLong(end),
        ));
    } else if (view.ghostWithAccess) {
      widgets
        ..add(const SizedBox(height: 42))
        ..add(PlpBillingTemporalHero(
          value: '$days',
          unit: days == 1 ? 'day left' : 'days left',
          caption: 'access until',
          date: view.hasPlayhead ? null : plpBillingDateLong(end!),
        ));
    }

    // Billing playhead (or the seal alone when dates are incomplete).
    if (sub != null && (view.holds || view.ghostWithAccess)) {
      if (view.hasPlayhead) {
        widgets
          ..add(const SizedBox(height: 38))
          ..add(PlpBillingPlayhead(
            today: view.todayPos,
            sealAt: view.sealPos,
            startLabel: plpBillingDateShort(view.cycleStart!),
            endLabel: view.ghost
                ? 'Access until ${plpBillingDateShort(end!)}'
                : plpBillingDateShort(end!),
            ghost: view.ghost,
            seal: _seal(view),
          ));
      } else {
        widgets
          ..add(const SizedBox(height: 18))
          ..add(Align(alignment: Alignment.centerLeft, child: _seal(view)));
      }
    } else if (sub != null) {
      widgets
        ..add(const SizedBox(height: 18))
        ..add(Align(alignment: Alignment.centerLeft, child: _seal(view)));
    }

    // Spatial plan axis.
    final axisEnabled = !_busy &&
        !view.locked &&
        !open &&
        !view.cancelRequested &&
        (!view.holds || sub!.state == 'active');
    final hero = !view.holds && !view.ghost;
    final label = view.ghost
        ? 'Restart'
        : view.holds
            ? 'Plan'
            : 'Choose a plan';
    widgets
      ..add(SizedBox(height: hero ? 72 : 50))
      ..add(PlpBillingLabel(
        label,
        icon: view.ghost ? PlpLineGlyph.rotateCcw : null,
      ))
      ..add(SizedBox(height: hero ? 30 : 22));
    if (view.snapshot.plans.isEmpty) {
      widgets.add(const PlpBillingNotice(title: 'No plans available'));
    } else {
      widgets.add(PlpPlanAxis(
        key: const ValueKey('plp-billing-axis'),
        hero: hero,
        nodes: [
          for (final plan in view.snapshot.plans)
            PlpPlanNode(
                code: plan.code, name: plan.name, price: plan.priceLabel),
        ],
        current: view.currentPlanCode,
        selected: _selectedPlan,
        pending: view.pendingPlan,
        onSelect: axisEnabled ? (code) => _select(view, code) : null,
      ));
    }

    final selected = view.snapshot.plan(_selectedPlan);
    if (selected != null && !view.locked) {
      final current = view.holds ? view.plan : null;
      String lead = selected.priceLabel;
      final from = current?.amountCents;
      final to = selected.amountCents;
      if (current != null && from != null && to != null) {
        final delta = to - from;
        lead = delta >= 0
            ? '+ ${selected.currency} ${_money(delta)}/mo'
            : '\u2212 ${selected.currency} ${_money(-delta)}/mo';
      }
      widgets
        ..add(const SizedBox(height: 26))
        ..add(PlpBillingRuledLine(
          key: _diffKey,
          lead: lead,
          rest: ' \u00b7 starts after PayPal approval',
          semanticsLabel:
              '${selected.name}, $lead, starts after PayPal approval. Continue.',
          onTap: _busy || open ? null : _openHandoff,
        ));
    } else if (hero && !view.locked) {
      widgets
        ..add(const SizedBox(height: 44))
        ..add(Container(
          padding: const EdgeInsets.only(top: 16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: plpLine)),
          ),
          child: const Text(
            'Billed monthly through PayPal.',
            style: TextStyle(color: plpMuted, fontSize: 12),
          ),
        ));
    }

    if (view.holds &&
        sub!.state == 'active' &&
        !view.cancelRequested &&
        _selectedPlan == null) {
      widgets
        ..add(const SizedBox(height: 46))
        ..add(PlpBillingRuledLine(
          key: const ValueKey('plp-billing-cancel'),
          lead: 'Cancel subscription',
          bottomRule: false,
          onTap: _busy || open || view.locked
              ? null
              : () => setState(() => _cancelOpen = true),
        ));
    }
    return widgets;
  }
}

/// Rises from the bottom on insertion (instant with reduced motion).
class _Rise extends StatelessWidget {
  const _Rise({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 1, end: 0),
        duration: plpReduceMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => FractionalTranslation(
          translation: Offset(0, value),
          child: child,
        ),
        child: child,
      );
}

/// Revenue entry: one thin-ruled ledger line read from the billing status.
class PlpBillingEntryLine extends StatefulWidget {
  const PlpBillingEntryLine({
    super.key,
    required this.organizationId,
    required this.onTap,
    this.api,
    this.clock,
  });

  final String? organizationId;
  final VoidCallback onTap;
  final PlpPaypalBillingApi? api;
  final DateTime Function()? clock;

  @override
  State<PlpBillingEntryLine> createState() => _PlpBillingEntryLineState();
}

class _PlpBillingEntryLineState extends State<PlpBillingEntryLine> {
  PlpPaypalBillingApi? _api;
  bool _ownsApi = false;
  PlpBillingSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    final org = widget.organizationId?.trim();
    if (org == null || org.isEmpty) return;
    try {
      _api = widget.api ?? PlpPaypalBillingApi.forOrganization(org);
      _ownsApi = widget.api == null;
    } catch (_) {
      // No session/runtime: the line stays a plain entry point.
      _api = null;
    }
    unawaited(_load());
  }

  Future<void> _load() async {
    final api = _api;
    if (api == null) return;
    try {
      final snapshot = await api.status();
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (_) {
      // Nothing is fabricated: on failure the line stays neutral.
    }
  }

  @override
  void dispose() {
    if (_ownsApi) _api?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final (lead, rest) = snapshot == null
        ? ('Pandora billing', '')
        : _BillingView(snapshot, (widget.clock ?? DateTime.now)().toUtc())
            .entryText;
    return PlpBillingRuledLine(
      key: const ValueKey('plp-billing-entry'),
      lead: lead,
      rest: rest,
      height: 58,
      semanticsLabel: '$lead$rest. Open billing.',
      onTap: widget.onTap,
    );
  }
}
