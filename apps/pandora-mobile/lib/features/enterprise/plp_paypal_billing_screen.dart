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

enum _PanelKind { none, handoff, cancel }

class _PlpPaypalBillingScreenState extends State<PlpPaypalBillingScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
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

  // Motion: waiting header + dim, and the bottom panels (handoff, cancel).
  late final AnimationController _lock =
      AnimationController(vsync: this, duration: plpMotionPanel);
  late final Animation<double> _lockCurve =
      CurvedAnimation(parent: _lock, curve: plpMotionIn);
  late final AnimationController _panel =
      AnimationController(vsync: this, duration: plpMotionPanel)
        ..addListener(_applyLift);
  late final Animation<double> _panelCurve =
      CurvedAnimation(parent: _panel, curve: plpMotionIn);
  _PanelKind _panelKind = _PanelKind.none;
  String? _handoffPlan;
  bool _lockSynced = false;
  double _liftBase = 0;
  double _liftDelta = 0;

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
    _lock.dispose();
    _panel.dispose();
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
      _syncLock();
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
      if (mounted) {
        setState(() => _snapshot = snapshot);
        _syncLock();
      }
    } catch (_) {
      // The primary problem is already on screen.
    }
  }

  Future<void> _reconcileAndReload() async {
    try {
      await _api!.reconcile();
    } finally {
      final snapshot = await _api!.status();
      if (mounted) {
        setState(() => _snapshot = snapshot);
        _syncLock();
      }
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

  /// The owner API decides the outcome from PayPal readbacks. A blocked
  /// cancel (e.g. buyer approval still pending) is shown as such; an
  /// unconfirmed one re-reads status, which keeps the plan and shows the
  /// "waiting for PayPal" note. Only a server-recorded cancellation renders
  /// as cancelled.
  Future<void> _cancel() => _run(
        () async {
          final outcome = await _api!.cancel();
          if (outcome.blocked) {
            throw PlpBillingProblemException(outcome.blockedProblem);
          }
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

  /// Eases the black "Waiting for PayPal" header (and the dim) in or out to
  /// match the server's state. The first status read applies instantly.
  void _syncLock() {
    final snapshot = _snapshot;
    if (snapshot == null || !mounted) return;
    final target = _BillingView(snapshot, _now).locked ? 1.0 : 0.0;
    if (!_lockSynced || plpReduceMotion(context)) {
      _lockSynced = true;
      _lock.value = target;
      return;
    }
    if (_lock.value == target && !_lock.isAnimating) return;
    if (target == 1) {
      unawaited(_lock.forward());
    } else {
      unawaited(_lock.reverse());
    }
  }

  /// Keeps the lifted content in step with the panel, so it rises and
  /// settles together with it instead of jumping.
  void _applyLift() {
    if (_liftDelta == 0 || !_scroll.hasClients) return;
    final position = _scroll.position;
    _scroll.jumpTo((_liftBase + _liftDelta * _panelCurve.value)
        .clamp(position.minScrollExtent, position.maxScrollExtent));
  }

  void _raisePanel({required bool lift}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _panelKind == _PanelKind.none) return;
      _liftBase = _scroll.hasClients ? _scroll.offset : 0;
      _liftDelta = 0;
      if (lift && _scroll.hasClients) {
        final box = _diffKey.currentContext?.findRenderObject() as RenderBox?;
        if (box != null && box.attached) {
          final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
          final limit =
              MediaQuery.sizeOf(context).height - _panelHeight(context) - 16;
          final delta = bottom - limit;
          if (delta > 0) {
            final target =
                math.min(_liftBase + delta, _scroll.position.maxScrollExtent);
            _liftDelta = target - _liftBase;
          }
        }
      }
      if (plpReduceMotion(context)) {
        _panel.value = 1;
      } else {
        unawaited(_panel.forward());
      }
    });
  }

  void _openHandoff() {
    setState(() {
      _handoffOpen = true;
      _cancelOpen = false;
      _panelKind = _PanelKind.handoff;
      _handoffPlan = _selectedPlan;
    });
    _raisePanel(lift: true);
  }

  void _openCancel() {
    setState(() {
      _cancelOpen = true;
      _handoffOpen = false;
      _panelKind = _PanelKind.cancel;
    });
    _raisePanel(lift: false);
  }

  /// Slides the open panel back down (same curve and duration it rose with).
  void _closePanel() {
    if (_panelKind == _PanelKind.none) return;
    setState(() {
      _handoffOpen = false;
      _cancelOpen = false;
    });
    void finish() {
      if (!mounted || _panel.value != 0) return;
      setState(() {
        _panelKind = _PanelKind.none;
        _liftDelta = 0;
      });
    }

    if (plpReduceMotion(context)) {
      _panel.value = 0;
      finish();
    } else {
      _panel.reverse().whenCompleteOrCancel(finish);
    }
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
      setState(() => _selectedPlan = null);
      _closePanel();
    }
  }

  Future<void> _holdConfirmed() async {
    await _cancel();
    if (mounted) _closePanel();
  }

  static const _identity = <double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0,
  ];
  static const _grey = <double>[
    .2126, .7152, .0722, 0, 0, //
    .2126, .7152, .0722, 0, 0, //
    .2126, .7152, .0722, 0, 0, //
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final view = snapshot == null ? null : _BillingView(snapshot, _now);
    final locked = view?.locked ?? false;
    final open = (_handoffOpen || _cancelOpen) && view != null && !locked;

    return Material(
      key: const ValueKey('plp-paypal-billing'),
      color: plpCanvas,
      child: AnimatedBuilder(
        animation: Listenable.merge([_lock, _panel]),
        builder: (context, _) {
          final t = _lockCurve.value;
          final p = _panelCurve.value;
          final panelShown =
              view != null && _panelKind != _PanelKind.none && _panel.value > 0;
          return Stack(
            children: [
              Positioned.fill(
                child: Column(
                  children: [
                    // Fixed: never scrolls or lifts with the content.
                    _topBar(view, locked, t),
                    Expanded(
                      child: IgnorePointer(
                        ignoring: locked,
                        child: ExcludeSemantics(
                          excluding: locked,
                          child: Opacity(
                            opacity: 1 - .66 * t,
                            child: ColorFiltered(
                              colorFilter: ColorFilter.matrix(<double>[
                                for (var i = 0; i < 20; i++)
                                  _identity[i] + (_grey[i] - _identity[i]) * t,
                              ]),
                              child: _content(context, view,
                                  locked: locked, open: open, lockT: t),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (panelShown) ...[
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('plp-billing-scrim'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _busy || !open ? null : _closePanel,
                    child: ColoredBox(
                      color: Color.fromRGBO(0x17, 0x15, 0x12, .22 * p),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionalTranslation(
                    translation: Offset(0, 1 - p),
                    child: _panelKind == _PanelKind.handoff
                        ? _handoffPanel(context, view)
                        : _cancelPanel(view),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Light header, with the black waiting header easing down over it from
  /// the top while a checkout or plan change waits for PayPal.
  Widget _topBar(_BillingView? view, bool locked, double t) {
    final back = widget.onBack;
    final url = locked ? view!.waitingUrl : null;
    return SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          if (t < 1)
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: PlpEditorialHeader(
                  title: 'Subscription',
                  onOpenNavigation: widget.onOpenNavigation,
                  trailing: back == null
                      ? null
                      : IconButton(
                          key: const ValueKey('plp-billing-back'),
                          onPressed: back,
                          tooltip: 'Back',
                          color: plpInk,
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                ),
              ),
            ),
          if (t > 0)
            ClipRect(
              child: Align(
                alignment: Alignment.bottomCenter,
                heightFactor: t,
                child: PlpBillingWaitingBand(
                  onOpenNavigation: widget.onOpenNavigation,
                  onBack: back,
                  checking: locked && _checking,
                  onOpenPaypal:
                      _busy || url == null ? null : () => _reopenApproval(url),
                  onCheckAgain: _busy || !locked ? null : _check,
                  problem: locked ? _problem?.title : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _handoffPanel(BuildContext context, _BillingView view) {
    final plan = view.snapshot.plan(_handoffPlan);
    return PlpBillingBlackPanel(
      height: _panelHeight(context),
      child: PlpBillingHandoffContent(
        planName: plan?.name ?? '',
        price: plan?.priceLabel ?? '',
        busy: _busy,
        onContinue: () => _continueHandoff(view),
        onNotNow: _closePanel,
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
        onKeep: _closePanel,
      ),
    );
  }

  Widget _content(
    BuildContext context,
    _BillingView? view, {
    required bool locked,
    required bool open,
    required double lockT,
  }) {
    final children = <Widget>[
      SizedBox(height: 34 + 16 * lockT),
      const PlpBillingTitle('Pandora billing'),
    ];

    if (view != null) {
      final sub = view.sub;
      children
        ..add(const SizedBox(height: 14))
        ..add(PlpMorph(
          key: const ValueKey('m-status'),
          signature: '${view.holds}|${view.ghost}|${sub?.state}|'
              '${view.plan?.code}|${view.cancelRequested}',
          child: _statusLine(view),
        ));
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

    final problem = locked ? null : _problem;
    final identity = problem != null &&
        problem.needsIdentity &&
        _identityRetry != _PendingAction.none;
    children.add(PlpMorph(
      key: const ValueKey('m-problem'),
      signature: problem?.title ?? 'none',
      child: problem == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 18),
              child: PlpBillingNotice(
                key: const ValueKey('plp-billing-problem'),
                title: problem.title,
                body: problem.body,
                action: identity
                    ? 'Verify identity'
                    : _api == null
                        ? null
                        : 'Try again',
                onAction: identity ? _verifyIdentity : (_busy ? null : _retry),
              ),
            ),
    ));

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
      padding: EdgeInsets.fromLTRB(18, 0, 18,
          _panelKind != _PanelKind.none ? _panelHeight(context) + 40 : 140),
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

    // Attention notices.
    final notices = <PlpBillingNotice>[
      if (sub != null && (sub.state == 'past_due' || sub.state == 'suspended'))
        const PlpBillingNotice(title: 'Payment needs attention in PayPal.'),
      if (view.cancelRequested)
        const PlpBillingNotice(
          key: ValueKey('plp-billing-cancel-sent'),
          title: 'Cancellation sent \u00b7 waiting for PayPal',
        ),
      if (sub == null && view.snapshot.checkout?.status == 'failed')
        const PlpBillingNotice(
            title: 'Last checkout did not start \u00b7 nothing charged'),
    ];
    widgets.add(PlpMorph(
      key: const ValueKey('m-notices'),
      signature: notices.map((n) => n.title).join('|'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final notice in notices)
            Padding(padding: const EdgeInsets.only(top: 14), child: notice),
        ],
      ),
    ));

    // Temporal hero. The number itself rolls when it changes.
    final days = view.daysLeft;
    final end = view.cycleEnd;
    var heroSignature = 'none';
    Widget hero = const SizedBox.shrink();
    if (view.holds) {
      final known = days != null && days >= 0;
      heroSignature = 'renews';
      hero = Padding(
        padding: const EdgeInsets.only(top: 42),
        child: PlpBillingTemporalHero(
          value: known ? '$days' : '\u2014',
          unit: known ? (days == 1 ? 'day' : 'days') : '',
          caption: 'renews',
          date: end == null ? null : plpBillingDateLong(end),
        ),
      );
    } else if (view.ghostWithAccess) {
      heroSignature = 'access';
      hero = Padding(
        padding: const EdgeInsets.only(top: 42),
        child: PlpBillingTemporalHero(
          value: '$days',
          unit: days == 1 ? 'day left' : 'days left',
          caption: 'access until',
          date: view.hasPlayhead ? null : plpBillingDateLong(end!),
        ),
      );
    }
    widgets.add(PlpMorph(
      key: const ValueKey('m-hero'),
      signature: heroSignature,
      child: hero,
    ));

    // Billing playhead (or the seal alone when dates are incomplete). The
    // playhead stays in place across active -> cancelled so its dashed
    // remainder can draw in.
    var cycleSignature = 'none';
    Widget cycle = const SizedBox.shrink();
    if (sub != null &&
        (view.holds || view.ghostWithAccess) &&
        view.hasPlayhead) {
      cycleSignature = 'playhead';
      cycle = Padding(
        padding: const EdgeInsets.only(top: 38),
        child: PlpBillingPlayhead(
          today: view.todayPos,
          sealAt: view.sealPos,
          startLabel: plpBillingDateShort(view.cycleStart!),
          endLabel: view.ghost
              ? 'Access until ${plpBillingDateShort(end!)}'
              : plpBillingDateShort(end!),
          ghost: view.ghost,
          seal: _seal(view),
        ),
      );
    } else if (sub != null) {
      cycleSignature = 'seal';
      cycle = Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Align(alignment: Alignment.centerLeft, child: _seal(view)),
      );
    }
    widgets.add(PlpMorph(
      key: const ValueKey('m-cycle'),
      signature: cycleSignature,
      child: cycle,
    ));

    // Spatial plan axis.
    final axisEnabled = !_busy &&
        !view.locked &&
        !open &&
        !view.cancelRequested &&
        (!view.holds || sub!.state == 'active');
    final heroAxis = !view.holds && !view.ghost;
    final label = view.ghost
        ? 'Restart'
        : view.holds
            ? 'Plan'
            : 'Choose a plan';
    widgets.add(PlpMorph(
      key: const ValueKey('m-axis-label'),
      signature: label,
      child: Padding(
        padding: EdgeInsets.only(
            top: heroAxis ? 92 : 50, bottom: heroAxis ? 30 : 22),
        child: PlpBillingLabel(
          label,
          icon: view.ghost ? PlpLineGlyph.rotateCcw : null,
        ),
      ),
    ));
    if (view.snapshot.plans.isEmpty) {
      widgets.add(const PlpBillingNotice(
          key: ValueKey('plp-billing-no-plans'), title: 'No plans available'));
    } else {
      widgets.add(PlpPlanAxis(
        key: const ValueKey('plp-billing-axis'),
        hero: heroAxis,
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

    // Difference line (or the billing hint when not subscribed).
    final selected = view.snapshot.plan(_selectedPlan);
    var tailSignature = 'none';
    Widget tail = const SizedBox.shrink();
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
      tailSignature = 'diff';
      tail = Padding(
        padding: const EdgeInsets.only(top: 20),
        child: PlpBillingRuledLine(
          key: const ValueKey('plp-billing-diff'),
          lead: lead,
          rest: ' \u00b7 starts after PayPal approval',
          chevron: true,
          semanticsLabel:
              '${selected.name}, $lead, starts after PayPal approval. Continue.',
          onTap: _busy || open ? null : _openHandoff,
        ),
      );
    } else if (heroAxis && !view.locked) {
      tailSignature = 'hint';
      tail = Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Container(
          padding: const EdgeInsets.only(top: 16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: plpLine)),
          ),
          child: const Text(
            'Billed monthly through PayPal.',
            style: TextStyle(color: plpMuted, fontSize: 12),
          ),
        ),
      );
    }
    widgets.add(KeyedSubtree(
      key: _diffKey,
      child: PlpMorph(signature: tailSignature, child: tail),
    ));

    final showCancel = view.holds &&
        sub!.state == 'active' &&
        !view.cancelRequested &&
        _selectedPlan == null;
    widgets.add(PlpMorph(
      key: const ValueKey('m-cancel'),
      signature: showCancel,
      child: showCancel
          ? Padding(
              padding: const EdgeInsets.only(top: 40),
              child: PlpBillingRuledLine(
                key: const ValueKey('plp-billing-cancel'),
                lead: 'Cancel subscription',
                bottomRule: false,
                chevron: true,
                onTap: _busy || open || view.locked ? null : _openCancel,
              ),
            )
          : const SizedBox.shrink(),
    ));
    return widgets;
  }
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
      restSize: 15,
      semanticsLabel: '$lead$rest. Open billing.',
      onTap: widget.onTap,
    );
  }
}
