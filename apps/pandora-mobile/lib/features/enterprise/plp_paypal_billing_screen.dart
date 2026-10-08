import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/plp_paypal_billing_api.dart';
import '../../core/security/pandora_identity_verification.dart';
import 'plp_editorial_surfaces.dart';

typedef PlpBillingUrlLauncher = Future<bool> Function(Uri url);

/// Native PLP Enterprise billing workspace.
///
/// Every state shown here is read back from the owner API, which reads it
/// from PayPal or from Pandora's billing records. Nothing is assumed
/// optimistically: checkout, plan changes and cancellation only appear as
/// done after reconcile + status confirm them.
class PlpPaypalBillingScreen extends StatefulWidget {
  const PlpPaypalBillingScreen({
    super.key,
    required this.organizationId,
    required this.onOpenNavigation,
    this.api,
    this.launchApproval,
    this.clock,
  });

  /// The current PLP organization. Null/empty renders a missing-organization
  /// state and no request is sent.
  final String? organizationId;
  final VoidCallback onOpenNavigation;
  final PlpPaypalBillingApi? api;
  final PlpBillingUrlLauncher? launchApproval;
  final DateTime Function()? clock;

  @override
  State<PlpPaypalBillingScreen> createState() => _PlpPaypalBillingScreenState();
}

enum _PendingAction { none, checkout, changePlan, reconcile, cancel }

class _PlpPaypalBillingScreenState extends State<PlpPaypalBillingScreen>
    with WidgetsBindingObserver {
  PlpPaypalBillingApi? _api;
  PlpBillingSnapshot? _snapshot;
  PlpBillingProblem? _problem;
  String? _notice;
  String? _selectedPlan;
  bool _loading = true;
  bool _busy = false;
  bool _awaitingProviderReturn = false;
  _PendingAction _identityRetry = _PendingAction.none;
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
      _problem = const PlpBillingProblem(
        'Organization missing.',
        'This workspace has no organization selected, so billing cannot load.',
      );
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
    // Returning from the external PayPal approval: confirm with PayPal first,
    // then show what the server recorded.
    if (state == AppLifecycleState.resumed && _awaitingProviderReturn) {
      _awaitingProviderReturn = false;
      unawaited(
          _run(_reconcileAndReload, notice: 'Checked PayPal after return.'));
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

  Future<void> _retryStatus() async {
    setState(() {
      _loading = true;
      _problem = null;
    });
    await _loadStatus();
  }

  Future<void> _run(
    Future<void> Function() work, {
    String? notice,
    _PendingAction retry = _PendingAction.none,
    String? retryPlan,
  }) async {
    if (_busy || _api == null) return;
    setState(() {
      _busy = true;
      _problem = null;
      _notice = null;
    });
    try {
      await work();
      if (mounted && notice != null) setState(() => _notice = notice);
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
          if (mounted) setState(() => _selectedPlan = null);
          await _loadStatusQuietly();
          await _openApproval(approval.approvalUrl);
        },
        retry: _PendingAction.checkout,
        retryPlan: planCode,
        notice: 'PayPal opened. Come back here after approving.',
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
        notice: 'Approve the change in PayPal.',
      );

  Future<void> _refresh() => _run(
        _reconcileAndReload,
        retry: _PendingAction.reconcile,
        notice: 'Updated from PayPal.',
      );

  Future<void> _cancel() => _run(
        () async {
          await _api!.cancel();
          await _reconcileAndReload();
        },
        retry: _PendingAction.cancel,
        notice: 'Cancellation sent to PayPal.',
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
        'Pandora could not open PayPal. Use “Open PayPal approval” to try again.',
      ));
    }
    _awaitingProviderReturn = true;
  }

  Future<void> _reopenApproval(Uri url) async {
    if (_busy) return;
    try {
      await _openApproval(url);
      if (mounted) setState(() => _notice = 'PayPal approval reopened.');
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
        await _refresh();
      case _PendingAction.cancel:
        await _cancel();
      case _PendingAction.none:
        break;
    }
  }

  Future<void> _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x99171512),
      builder: (context) => const _PlpCancelDialog(),
    );
    if (confirmed == true) await _cancel();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final children = <Widget>[const SizedBox(height: 24)];
    final problem = _problem;
    if (problem != null) {
      children.add(PlpBlackPanel(
        key: const ValueKey('plp-billing-problem'),
        eyebrow: problem.needsIdentity ? 'Identity check' : 'Attention',
        title: problem.title,
        body: problem.body,
        action: problem.needsIdentity && _identityRetry != _PendingAction.none
            ? 'Verify identity'
            : null,
        onTap: problem.needsIdentity && _identityRetry != _PendingAction.none
            ? _verifyIdentity
            : null,
      ));
      children.add(const SizedBox(height: 18));
    }
    if (_loading) {
      children.add(const PlpEditorialRow(
        title: 'Loading…',
        detail: '',
        divider: false,
      ));
    } else if (snapshot != null) {
      children.addAll(_snapshotChildren(snapshot));
    } else if (_api != null) {
      children.add(PlpEditorialRow(
        key: const ValueKey('plp-billing-retry'),
        title: 'Try again',
        detail: '',
        divider: false,
        onTap: _busy ? null : _retryStatus,
      ));
    }
    if (_busy) {
      children.add(const Padding(
        padding: EdgeInsets.only(top: 14),
        child: Text(
          'Working with PayPal…',
          key: ValueKey('plp-billing-busy'),
          style: TextStyle(color: plpMuted, fontSize: 11.5),
        ),
      ));
    } else if (_notice != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Text(
          _notice!,
          key: const ValueKey('plp-billing-notice'),
          style: const TextStyle(color: plpMuted, fontSize: 11.5, height: 1.4),
        ),
      ));
    }
    return PlpEditorialPage(
      pageKey: const ValueKey('plp-paypal-billing'),
      eyebrow: 'Subscription',
      title: 'Pandora billing',
      intro: '',
      onOpenNavigation: widget.onOpenNavigation,
      children: children,
    );
  }

  List<Widget> _snapshotChildren(PlpBillingSnapshot snapshot) {
    final sub = snapshot.subscription;
    final checkout = snapshot.checkout;
    final change = snapshot.planChange;
    final now = _now;
    final pendingCheckout =
        (sub == null || !sub.holdsPlan) && checkout?.pendingAt(now) == true;
    final cancelRequested =
        sub != null && sub.holdsPlan && checkout?.status == 'cancel_requested';
    final status = _statusLabel(sub, pendingCheckout, cancelRequested);
    final currentPlan = snapshot.plan(sub?.planCode);
    final widgets = <Widget>[
      if (snapshot.sandbox)
        const PlpEditorialRow(
          key: ValueKey('plp-billing-sandbox'),
          title: 'PayPal sandbox',
          detail: 'Test mode. No real payments.',
          tone: plpWarn,
          divider: false,
        ),
      PlpMetricStrip(
        key: const ValueKey('plp-billing-metrics'),
        items: [
          ('Status', status.$1, status.$2),
          (
            'Plan',
            currentPlan?.name ?? (sub?.planCode ?? '—'),
            currentPlan?.priceLabel ?? '',
          ),
          (
            'Renewal',
            sub?.state == 'cancelled'
                ? (sub?.endsOn ?? '—')
                : (sub?.renewsOn ?? '—'),
            sub?.state == 'cancelled' ? 'ended' : '',
          ),
        ],
      ),
      if (sub != null)
        _PlpVerifiedMarker(
          key: const ValueKey('plp-billing-verification'),
          label: _verificationTitle(snapshot),
          verified: sub.providerVerified,
        ),
      if (sub != null && (sub.state == 'past_due' || sub.state == 'suspended'))
        const PlpEditorialRow(
          title: 'Payment needs attention',
          detail: 'Check PayPal, then refresh.',
          tone: plpWarn,
          divider: false,
        ),
      if (cancelRequested)
        const PlpEditorialRow(
          title: 'Cancellation sent',
          detail: 'Waiting for PayPal to confirm.',
          tone: plpWarn,
          divider: false,
        ),
      if (checkout != null && checkout.status == 'failed' && sub == null)
        const PlpEditorialRow(
          title: 'Last checkout did not start',
          detail: 'Nothing was charged.',
          tone: plpWarn,
          divider: false,
        ),
    ];

    final handoffUrl = pendingCheckout
        ? checkout!.approvalUrl
        : (change?.pending == true ? change!.approvalUrl : null);
    if (handoffUrl != null) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 28),
        child: PlpBlackPanel(
          key: const ValueKey('plp-billing-handoff'),
          eyebrow: 'Payment handoff',
          title: 'PayPal approval is waiting.',
          body: 'Reopen the existing provider approval link.',
          action: 'Open PayPal approval',
          onTap: _busy ? null : () => _reopenApproval(handoffUrl),
        ),
      ));
    }

    if (sub == null || !sub.holdsPlan) {
      widgets.add(const PlpSectionTitle('Choose a plan'));
      if (snapshot.plans.isEmpty) {
        widgets.add(const PlpEditorialRow(
          title: 'No plans available',
          detail: '',
          tone: plpWarn,
          divider: false,
        ));
      }
      for (final plan in snapshot.plans) {
        final selected = plan.code == _selectedPlan;
        widgets.add(PlpEditorialRow(
          key: ValueKey('plp-billing-plan-${plan.code}'),
          title: plan.name,
          detail: plan.priceLabel,
          tone: selected ? plpInk : null,
          divider: false,
          onTap: _busy ? null : () => setState(() => _selectedPlan = plan.code),
        ));
      }
      final selected = snapshot.plan(_selectedPlan);
      if (selected != null) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 18),
          child: PlpBlackPanel(
            key: const ValueKey('plp-billing-checkout'),
            eyebrow: 'Checkout',
            title: '${selected.name} · ${selected.priceLabel}',
            body: '',
            action: 'Continue to PayPal',
            onTap: _busy ? null : () => _checkout(selected.code),
          ),
        ));
      }
    }

    widgets.add(const PlpSectionTitle('Manage'));
    widgets.add(PlpEditorialRow(
      key: const ValueKey('plp-billing-refresh'),
      title: 'Refresh',
      detail: '',
      divider: false,
      onTap: _busy ? null : _refresh,
    ));
    if (sub != null && sub.state == 'active') {
      for (final plan in snapshot.plans) {
        if (plan.code == sub.planCode) continue;
        widgets.add(PlpEditorialRow(
          key: ValueKey('plp-billing-switch-${plan.code}'),
          title: 'Switch to ${plan.name} · ${plan.priceLabel}',
          detail: '',
          divider: false,
          onTap: _busy ? null : () => _changePlan(plan.code),
        ));
      }
      if (!cancelRequested) {
        widgets.add(PlpEditorialRow(
          key: const ValueKey('plp-billing-cancel'),
          title: 'Cancel subscription',
          detail: '',
          divider: false,
          onTap: _busy ? null : _confirmCancel,
        ));
      }
    }
    return widgets;
  }

  (String, String) _statusLabel(
    PlpBillingSubscription? sub,
    bool pendingCheckout,
    bool cancelRequested,
  ) {
    if (sub == null || !sub.holdsPlan) {
      if (pendingCheckout) return ('Pending', 'awaiting PayPal');
      if (sub?.state == 'cancelled') return ('Cancelled', 'ended');
      return ('Inactive', 'no subscription');
    }
    if (cancelRequested) return ('Active', 'cancellation pending');
    return switch (sub.state) {
      'active' => ('Active', 'monthly'),
      'trial' => ('Trial', 'trial period'),
      'past_due' => ('Past due', 'needs attention'),
      'suspended' => ('Suspended', 'needs attention'),
      _ => (sub.state, 'billing state'),
    };
  }

  String _verificationTitle(PlpBillingSnapshot snapshot) {
    final sub = snapshot.subscription;
    if (sub == null) return 'No subscription record';
    if (!sub.providerVerified) return 'Account record';
    return snapshot.sandbox
        ? 'Verified by PayPal sandbox'
        : 'Verified by PayPal';
  }
}

class _PlpVerifiedMarker extends StatelessWidget {
  const _PlpVerifiedMarker({
    super.key,
    required this.label,
    required this.verified,
  });

  final String label;
  final bool verified;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              color: verified ? plpGood : plpWarn,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: plpMuted, fontSize: 11),
            ),
          ],
        ),
      );
}

class _PlpCancelDialog extends StatelessWidget {
  const _PlpCancelDialog();

  @override
  Widget build(BuildContext context) => Dialog(
        key: const ValueKey('plp-billing-cancel-dialog'),
        backgroundColor: plpCanvas,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(),
        insetPadding: const EdgeInsets.symmetric(horizontal: 22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cancel subscription?',
                  style: TextStyle(
                    color: plpInk,
                    fontFamily: 'serif',
                    fontSize: 29,
                    height: 1.05,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'PayPal will stop billing after confirmation.',
                  style: TextStyle(color: plpMuted, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 26),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      key: const ValueKey('plp-billing-cancel-keep'),
                      style: TextButton.styleFrom(
                        foregroundColor: plpInk,
                        shape: const RoundedRectangleBorder(),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Keep subscription'),
                    ),
                    FilledButton(
                      key: const ValueKey('plp-billing-cancel-confirm'),
                      style: FilledButton.styleFrom(
                        backgroundColor: plpInk,
                        foregroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('YES, CANCEL'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}
