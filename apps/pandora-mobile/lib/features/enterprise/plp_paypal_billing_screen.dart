import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/plp_paypal_billing_api.dart';
import '../../core/network/pandora_api_error.dart';
import '../../core/security/pandora_identity_verification.dart';
import '../../pandora_config.dart';
import 'plp_billing_surfaces.dart';
import 'plp_resort_workspace.dart';

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

/// What the backend status says, reduced to the facts the page needs.
class _BillingView {
  _BillingView(this.snapshot, this.now) {
    final sub = snapshot.subscription;
    holds = sub != null && sub.holdsPlan;
    cancelled = sub != null && sub.state == 'cancelled';
    final checkout = snapshot.checkout;
    final change = snapshot.planChange;
    final pendingCheckout = !holds && checkout?.pendingAt(now) == true;
    final pendingChange = holds && change?.pending == true;
    waitingUrl = pendingCheckout
        ? checkout!.approvalUrl
        : pendingChange
            ? change!.approvalUrl
            : null;
    cancelRequested = holds && checkout?.status == 'cancel_requested';
    plan = snapshot.plan(sub?.planCode);
    cycleEnd = holds
        ? plpBillingDate(sub!.renewsOn)
        : cancelled
            ? plpBillingDate(sub!.endsOn)
            : null;
  }

  final PlpBillingSnapshot snapshot;
  final DateTime now;
  late final bool holds;
  late final bool cancelled;
  late final Uri? waitingUrl;
  late final bool cancelRequested;
  late final PlpBillingPlan? plan;
  late final DateTime? cycleEnd;

  PlpBillingSubscription? get sub => snapshot.subscription;

  /// A checkout or plan change is waiting for the buyer in PayPal.
  bool get locked => waitingUrl != null;

  String? get planName => plan?.name ?? sub?.planCode;

  /// ACTIVE in PayPal and read back by the server (provider_verified). Only
  /// this state may offer plan changes and cancellation.
  bool get activeVerified =>
      holds &&
      sub!.state == 'active' &&
      sub!.providerVerified &&
      !locked &&
      !cancelRequested;

  /// CANCELLED read back from PayPal and recorded by the server.
  bool get cancelledVerified => cancelled && sub!.providerVerified;

  (String, String) get entryText {
    if (locked) return ('Pandora billing', ' \u00b7 waiting for PayPal');
    final name = planName;
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
    final end = cycleEnd;
    if (cancelled &&
        end != null &&
        !end.isBefore(DateTime.utc(now.year, now.month, now.day))) {
      return (
        'Pandora',
        [
          if (name != null) name,
          'access until ${plpBillingDateShort(end)}',
        ].map((part) => ' \u00b7 $part').join(),
      );
    }
    return ('Pandora billing', ' \u00b7 not subscribed');
  }
}

/// Sub-pages of the active plan. Every one is the same tile page.
enum _Mode { home, changePlan, confirmCancel, choosePlan }

enum _Retry { none, checkout, changePlan, reconcile, cancel }

/// One rendered billing page: one notice sentence and its tiles.
class _Page {
  const _Page(this.notice, this.tiles);
  final String notice;
  final List<PlpCapability> tiles;
}

/// PLP billing, drawn as a Rooms & Housekeeping tile page: serif title,
/// one notice, capability tiles. The shell owns the menu button and the
/// Pandora logo; this page never draws either.
///
/// Every state comes from the owner API, which reads it from PayPal. Nothing
/// is assumed optimistically: checkout, plan changes and cancellation only
/// show as done after reconcile + status confirm them. Flutter never calls
/// PayPal and holds no PayPal credential.
class PlpPaypalBillingScreen extends StatefulWidget {
  const PlpPaypalBillingScreen({
    super.key,
    required this.organizationId,
    required this.onOpenNavigation,
    this.api,
    this.launchApproval,
    this.clock,
    this.onBack,
    this.billingEnvironment = PandoraConfig.billingEnvironment,
  });

  /// The current PLP organization. Null/empty renders a missing-organization
  /// notice and no request is sent.
  final String? organizationId;

  /// Kept for the shell contract; the shell draws the menu button.
  final VoidCallback onOpenNavigation;
  final PlpPaypalBillingApi? api;
  final PlpBillingUrlLauncher? launchApproval;
  final DateTime Function()? clock;

  /// Kept for the shell contract; the shell handles back.
  final VoidCallback? onBack;

  /// `sandbox` shows the sandbox header. Defaults to the build config.
  final String billingEnvironment;

  @override
  State<PlpPaypalBillingScreen> createState() => _PlpPaypalBillingScreenState();
}

class _PlpPaypalBillingScreenState extends State<PlpPaypalBillingScreen>
    with WidgetsBindingObserver {
  PlpPaypalBillingApi? _api;
  PlpBillingSnapshot? _snapshot;
  PlpBillingProblem? _problem;
  bool _loading = true;
  bool _busy = false;
  bool _awaitingProviderReturn = false;

  _Mode _mode = _Mode.home;

  /// Cancel was refused with AWAITING_BUYER_APPROVAL: stay on waiting until
  /// a refresh reads PayPal again.
  bool _awaitingBuyer = false;

  /// Change-plan refused with SANDBOX_PLAN_CHANGE_UNAVAILABLE.
  bool _sandboxChangeUnavailable = false;

  _Retry _identityRetry = _Retry.none;
  String? _identityRetryPlan;

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
      return;
    }
    _api = widget.api ?? PlpPaypalBillingApi.forOrganization(organizationId);
    unawaited(_loadStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.api == null) _api?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the PayPal approval: confirm with PayPal first, then show
    // what the server recorded.
    if (state == AppLifecycleState.resumed && _awaitingProviderReturn) {
      _awaitingProviderReturn = false;
      unawaited(_refresh());
    }
  }

  void _apply(PlpBillingSnapshot snapshot) {
    _snapshot = snapshot;
    final view = _BillingView(snapshot, _now);
    // Sub-pages only exist where their state still holds.
    if ((_mode == _Mode.changePlan || _mode == _Mode.confirmCancel) &&
        !view.activeVerified) {
      _mode = _Mode.home;
    }
    if (_mode == _Mode.choosePlan && (view.holds || view.locked)) {
      _mode = _Mode.home;
    }
  }

  Future<void> _loadStatus() async {
    final api = _api;
    if (api == null) return;
    try {
      final snapshot = await api.status();
      if (!mounted) return;
      setState(() {
        _apply(snapshot);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _problem = PlpBillingProblem.from(error);
      });
    }
  }

  Future<void> _retryLoad() async {
    if (_busy) return;
    setState(() {
      _loading = _snapshot == null;
      _problem = null;
    });
    await _loadStatus();
  }

  Future<void> _run(
    Future<void> Function() work, {
    _Retry retry = _Retry.none,
    String? retryPlan,
  }) async {
    if (_busy || _api == null) return;
    setState(() {
      _busy = true;
      _problem = null;
      _sandboxChangeUnavailable = false;
    });
    try {
      await work();
    } catch (error) {
      if (error is PandoraApiError &&
          error.code == 'SANDBOX_PLAN_CHANGE_UNAVAILABLE') {
        if (mounted) {
          setState(() {
            _sandboxChangeUnavailable = true;
            _mode = _Mode.home;
          });
        }
      } else {
        final problem = PlpBillingProblem.from(error);
        if (mounted) {
          setState(() {
            _problem = problem;
            _identityRetry = problem.needsIdentity ? retry : _Retry.none;
            _identityRetryPlan = problem.needsIdentity ? retryPlan : null;
          });
        }
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
      if (mounted) setState(() => _apply(snapshot));
    } catch (_) {
      // The primary problem is already on screen.
    }
  }

  Future<void> _reconcileAndReload() async {
    try {
      await _api!.reconcile();
    } finally {
      final snapshot = await _api!.status();
      if (mounted) setState(() => _apply(snapshot));
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
        retry: _Retry.checkout,
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
          if (mounted) setState(() => _mode = _Mode.home);
        },
        retry: _Retry.changePlan,
        retryPlan: planCode,
      );

  /// Reconcile with PayPal (server side), then read status.
  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _awaitingBuyer = false);
    await _run(_reconcileAndReload, retry: _Retry.reconcile);
  }

  /// The owner API decides the outcome from PayPal readbacks. Only a
  /// `cancelled` response followed by a CANCELLED status readback renders
  /// as Cancelled. AWAITING_BUYER_APPROVAL keeps the page on waiting.
  Future<void> _cancel() => _run(
        () async {
          final outcome = await _api!.cancel();
          if (outcome.blocked) {
            if (outcome.reason == 'AWAITING_BUYER_APPROVAL') {
              if (mounted) {
                setState(() {
                  _awaitingBuyer = true;
                  _mode = _Mode.home;
                });
              }
              await _loadStatusQuietly();
              return;
            }
            throw PlpBillingProblemException(outcome.blockedProblem);
          }
          await _reconcileAndReload();
          if (mounted) setState(() => _mode = _Mode.home);
        },
        retry: _Retry.cancel,
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
        'Pandora could not open PayPal. Try Open PayPal again.',
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
            'Identity not confirmed. Nothing was sent to PayPal.',
            needsIdentity: true,
          ));
      return;
    }
    setState(() {
      _problem = null;
      _identityRetry = _Retry.none;
    });
    switch (retry) {
      case _Retry.checkout:
        if (plan != null) await _checkout(plan);
      case _Retry.changePlan:
        if (plan != null) await _changePlan(plan);
      case _Retry.reconcile:
        await _refresh();
      case _Retry.cancel:
        await _cancel();
      case _Retry.none:
        break;
    }
  }

  void _go(_Mode mode) {
    if (_busy) return;
    setState(() {
      _mode = mode;
      _problem = null;
      _sandboxChangeUnavailable = false;
    });
  }

  VoidCallback? _tap(VoidCallback action) => _busy ? null : action;

  static IconData _planIcon(int index) => index == 0
      ? Icons.rocket_launch_outlined
      : Icons.workspace_premium_outlined;

  List<PlpCapability> _planTiles(
    List<PlpBillingPlan> plans,
    void Function(String code) onPick,
  ) {
    final all = _snapshot?.plans ?? const <PlpBillingPlan>[];
    return [
      for (final plan in plans)
        PlpCapability(
          plan.name,
          _planIcon(all.indexOf(plan)),
          _tap(() => onPick(plan.code)),
        ),
    ];
  }

  _Page _waiting(_BillingView view) {
    final url = view.waitingUrl;
    return _Page('Waiting for PayPal.', [
      if (url != null)
        PlpCapability(
          'Open PayPal',
          Icons.open_in_new_rounded,
          _tap(() => _reopenApproval(url)),
        ),
      PlpCapability('Refresh', Icons.refresh_rounded, _tap(_refresh)),
    ]);
  }

  _Page _page() {
    if (_organizationId == null) {
      return const _Page('No organization is selected.', []);
    }
    final snapshot = _snapshot;
    if (snapshot == null) {
      if (_loading) return const _Page('Loading\u2026', []);
      return _Page(_problem?.body ?? 'Billing could not load.', [
        if (_api != null)
          PlpCapability('Try again', Icons.refresh_rounded, _tap(_retryLoad)),
      ]);
    }

    final view = _BillingView(snapshot, _now);
    final sub = view.sub;
    final name = view.planName ?? 'Your plan';

    // Waiting: approval pending, cancel refused while the buyer approves,
    // cancellation sent but not read back, or a record PayPal has not
    // verified yet. Cancel is never offered here.
    if (_awaitingBuyer || view.locked) return _waiting(view);
    if (view.holds) {
      if (view.cancelRequested || !sub!.providerVerified) {
        return _waiting(view);
      }
      if (!view.activeVerified) {
        final refresh =
            PlpCapability('Refresh', Icons.refresh_rounded, _tap(_refresh));
        return switch (sub.state) {
          'trial' => _Page('$name is in trial, confirmed by PayPal.', [refresh]),
          _ => _Page('Payment needs attention in PayPal.', [refresh]),
        };
      }
      final others = [
        for (final plan in snapshot.plans)
          if (plan.code != sub.planCode) plan,
      ];
      switch (_mode) {
        case _Mode.changePlan:
          return _Page(
            others.isEmpty ? 'No other plan is available.' : 'Choose a plan.',
            _planTiles(others, _changePlan),
          );
        case _Mode.confirmCancel:
          return _Page('Cancel this plan. PayPal must confirm.', [
            PlpCapability(
              'Confirm cancel',
              Icons.check_circle_outline_rounded,
              _tap(_cancel),
            ),
          ]);
        case _Mode.home:
        case _Mode.choosePlan:
          return _Page(
            _sandboxChangeUnavailable
                ? 'Plan changes are not available in sandbox.'
                : '$name is active, confirmed by PayPal.',
            [
              if (others.isNotEmpty)
                PlpCapability(
                  'Change plan',
                  Icons.swap_horiz_rounded,
                  _tap(() => _go(_Mode.changePlan)),
                ),
              PlpCapability('Refresh', Icons.refresh_rounded, _tap(_refresh)),
              PlpCapability(
                'Cancel',
                Icons.cancel_outlined,
                _tap(() => _go(_Mode.confirmCancel)),
              ),
            ],
          );
      }
    }

    if (view.cancelled && _mode != _Mode.choosePlan) {
      if (!view.cancelledVerified) return _waiting(view);
      return _Page('Cancelled.', [
        PlpCapability(
          'Choose a plan',
          Icons.add_circle_outline_rounded,
          _tap(() => _go(_Mode.choosePlan)),
        ),
      ]);
    }

    return _Page(
      snapshot.plans.isEmpty
          ? 'No PayPal plan is available yet.'
          : 'No PayPal plan yet.',
      _planTiles(snapshot.plans, _checkout),
    );
  }

  @override
  Widget build(BuildContext context) {
    var page = _page();
    final problem = _problem;
    if (problem != null && _snapshot != null) {
      final identity =
          problem.needsIdentity && _identityRetry != _Retry.none;
      page = _Page(
        problem.body,
        identity
            ? [
                PlpCapability(
                  'Verify identity',
                  Icons.verified_user_outlined,
                  _tap(_verifyIdentity),
                ),
              ]
            : page.tiles,
      );
    }
    final sandbox = widget.billingEnvironment == 'sandbox';

    return Material(
      key: const ValueKey('plp-paypal-billing'),
      color: PlpResortWorkspaceScreen.canvas,
      child: SafeArea(
        bottom: false,
        child: ListView(
          key: const ValueKey('plp-billing-page'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            18,
            12,
            18,
            // Clear of the shell's bottom-right Pandora logo.
            120 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: const Align(
                alignment: Alignment.topLeft,
                heightFactor: 1,
                child: PlpPageTitle('BILLING'),
              ),
            ),
            if (sandbox)
              const Padding(
                padding: EdgeInsets.only(left: 56, top: 2),
                child: Text(
                  'PayPal sandbox',
                  key: ValueKey('plp-billing-sandbox'),
                  style: TextStyle(
                    color: PlpResortWorkspaceScreen.warn,
                    fontSize: 11,
                    letterSpacing: .4,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            PlpNoticeBox(
              page.notice,
              key: const ValueKey('plp-billing-notice'),
            ),
            if (page.tiles.isNotEmpty) ...[
              const SizedBox(height: 16),
              PlpCapabilityGrid(
                key: const ValueKey('plp-billing-tiles'),
                items: page.tiles,
              ),
            ],
          ],
        ),
      ),
    );
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
