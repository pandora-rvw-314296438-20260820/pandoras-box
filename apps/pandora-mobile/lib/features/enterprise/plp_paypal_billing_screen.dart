import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../pandora_config.dart';
import 'plp_editorial_surfaces.dart';

class PlpPaypalBillingScreen extends StatefulWidget {
  const PlpPaypalBillingScreen({
    super.key,
    required this.organizationId,
    required this.onOpenNavigation,
  });

  final String organizationId;
  final VoidCallback onOpenNavigation;

  @override
  State<PlpPaypalBillingScreen> createState() => _PlpPaypalBillingScreenState();
}

class _PlpPaypalBillingScreenState extends State<PlpPaypalBillingScreen> {
  static const _plans = <String, (String, String)>{
    'launch': ('Launch', 'USD 49 / month'),
    'professional': ('Professional', 'USD 149 / month'),
  };

  bool _busy = false;
  bool _statusLoaded = false;
  String _selectedPlanCode = 'launch';
  String? _error;
  Map<String, dynamic> _status = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      throw Exception('Sign in again to manage billing.');
    }
    final headers = <String, String>{
      'Authorization': 'Bearer ' + session.accessToken,
      'apikey': PandoraConfig.supabasePublishableKey,
      'x-organization-id': widget.organizationId,
      'Content-Type': 'application/json',
    };
    final uri = Uri.parse(PandoraConfig.ownerApiBaseUrl + path);
    final response = method == 'POST'
        ? await http.post(uri, headers: headers, body: jsonEncode(body ?? {}))
        : await http.get(uri, headers: headers);
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        (decoded['error'] ?? decoded['message'] ?? 'Billing request failed')
            .toString(),
      );
    }
    return decoded;
  }

  Future<void> _loadStatus() async {
    try {
      final result = await _request('/billing/paypal/status');
      if (!mounted) return;
      setState(() {
        _status = result;
        _statusLoaded = true;
        final loadedSubscription = _map(result['subscription']);
        final loadedCheckout = _map(result['checkout']);
        final loadedPlanCode = (loadedSubscription['plan_code'] ??
                loadedCheckout['plan_code'] ??
                '')
            .toString();
        if (loadedSubscription['state']?.toString().toLowerCase() != 'active' &&
            _plans.containsKey(loadedPlanCode)) {
          _selectedPlanCode = loadedPlanCode;
        }
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusLoaded = true;
        _error = _clean(error);
      });
    }
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } catch (error) {
      if (mounted) setState(() => _error = _clean(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _clean(Object error) => error.toString().replaceFirst('Exception: ', '');

  String _idempotency(String prefix) =>
      prefix + '-' + DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> _checkout(String code) async {
    final checkout = _map(_status['checkout']);
    final pending = _map(_status['pendingPlanChange']);
    final existingApproval =
        (pending['approval_url'] ?? checkout['approval_url'] ?? '').toString().trim();
    if (existingApproval.isNotEmpty) {
      await _openApproval(existingApproval);
      return;
    }
    await _run(() async {
      final result = await _request(
        '/billing/paypal/checkout',
        method: 'POST',
        body: {
          'planCode': code,
          'idempotencyKey': _idempotency('plp-checkout'),
          'returnUrl': 'https://mcpmaster.vercel.app/#/enterprise/paypal-return',
          'cancelUrl': 'https://mcpmaster.vercel.app/#/enterprise/paypal-cancel',
        },
      );
      await _openApproval(result['approvalUrl']?.toString());
      await _loadStatus();
    });
  }

  Future<void> _changePlan(String code) async {
    await _run(() async {
      final result = await _request(
        '/billing/paypal/change-plan',
        method: 'POST',
        body: {
          'planCode': code,
          'idempotencyKey': _idempotency('plp-plan-change'),
        },
      );
      await _openApproval(result['approvalUrl']?.toString());
      await _loadStatus();
    });
  }

  Future<void> _reconcile() async {
    await _run(() async {
      await _request('/billing/paypal/reconcile', method: 'POST');
      await _loadStatus();
    });
  }

  Future<void> _cancel() async {
    await _run(() async {
      await _request(
        '/billing/paypal/cancel',
        method: 'POST',
        body: const {'reason': 'Cancelled by Pandora owner'},
      );
      await _loadStatus();
    });
  }

  Future<void> _openApproval(String? value) async {
    if (value == null || value.isEmpty) return;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('PayPal approval could not be opened.');
    }
  }

  Future<void> _confirmCancel() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: plpCanvas,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cancel subscription',
                style: TextStyle(
                  color: plpInk,
                  fontFamily: 'serif',
                  fontSize: 30,
                  height: 1,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'This sends a cancellation request to PayPal. Pandora will refresh the provider record before presenting the final status.',
                style: TextStyle(color: plpMuted, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 10),
              const Text(
                'The effective date and any change to access will be shown only when confirmed by the subscription terms. Until then, the current status is not treated as cancelled.',
                style: TextStyle(color: plpInk, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: const Text('Keep subscription'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : () => Navigator.pop(sheetContext, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: plpInk,
                    foregroundColor: plpPaper,
                  ),
                  child: const Text('Request cancellation'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true) await _cancel();
  }

  Future<void> _confirmPlanChange(String code) async {
    final plan = _plans[code];
    if (plan == null || code == _currentPlanCode()) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: plpCanvas,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Review plan change',
                style: TextStyle(
                  color: plpInk,
                  fontFamily: 'serif',
                  fontSize: 30,
                  height: 1,
                ),
              ),
              const SizedBox(height: 18),
              PlpEditorialRow(
                title: 'Current plan',
                detail: 'The plan currently displayed by Pandora.',
                value: _plans[_currentPlanCode()]?.$2 ?? 'Price unavailable',
              ),
              PlpEditorialRow(
                title: plan.$1,
                detail: 'Proposed recurring price · monthly',
                value: plan.$2,
                tone: plpAccent,
              ),
              const SizedBox(height: 12),
              const Text(
                'PayPal will show any required authorization and its applicable timing. Pandora will keep the current plan displayed until the updated provider state is confirmed.',
                style: TextStyle(color: plpMuted, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: const Text('Keep current plan'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : () => Navigator.pop(sheetContext, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: plpInk,
                    foregroundColor: plpPaper,
                  ),
                  child: const Text('Continue to PayPal'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true) await _changePlan(code);
  }

  String _currentPlanCode() {
    final subscription = _map(_status['subscription']);
    final checkout = _map(_status['checkout']);
    final code = (subscription['plan_code'] ?? checkout['plan_code'] ?? '').toString();
    return _plans.containsKey(code) ? code : '';
  }

  Widget _safeActionRow({
    required String title,
    required String detail,
    VoidCallback? onTap,
    Color? tone,
  }) =>
      Padding(
        padding: const EdgeInsets.only(right: 56),
        child: PlpEditorialRow(
          title: title,
          detail: detail,
          onTap: onTap,
          tone: tone,
        ),
      );

  Widget _planOption(String code) {
    final plan = _plans[code]!;
    final selected = _selectedPlanCode == code;
    return Padding(
      padding: const EdgeInsets.only(right: 56),
      child: Material(
        color: selected ? plpPaper : Colors.transparent,
        child: InkWell(
          onTap: _busy ? null : () => setState(() => _selectedPlanCode = code),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: selected ? plpInk : plpLine),
            ),
            padding: const EdgeInsets.fromLTRB(15, 17, 13, 17),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: selected ? plpInk : plpMuted,
                  size: 19,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.$1,
                        style: const TextStyle(
                          color: plpInk,
                          fontFamily: 'serif',
                          fontSize: 22,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        selected ? 'Selected · recurring monthly plan' : 'Select this recurring monthly plan',
                        style: const TextStyle(
                          color: plpMuted,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    plan.$2,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: plpInk,
                      fontFamily: 'serif',
                      fontSize: 18,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subscription = _map(_status['subscription']);
    final provider = _map(_status['provider']);
    final checkout = _map(_status['checkout']);
    final pending = _map(_status['pendingPlanChange']);
    final state = (subscription['state'] ?? '').toString().toLowerCase();
    final active = state == 'active';
    final verified = subscription['source_kind'] == 'provider_verified' &&
        subscription['verified_at'] != null;
    final currentCode =
        (subscription['plan_code'] ?? checkout['plan_code'] ?? '').toString();
    final currentPlan = _planName(currentCode);
    final fee = subscription['net_monthly_fee'] ?? subscription['monthly_fee'];
    final currentPrice = fee?.toString().trim().isNotEmpty == true
        ? 'USD ' + fee.toString() + ' / month'
        : 'Price unavailable';
    final approvalUrl =
        (pending['approval_url'] ?? checkout['approval_url'] ?? '').toString();
    final providerConfigured = provider['configured'] == true;
    final providerLabel = verified
        ? 'Verified'
        : active
            ? 'Unconfirmed'
            : providerConfigured
                ? 'Configured'
                : 'Unavailable';
    final renewalDate = (subscription['renews_on'] ?? '').toString().trim();
    final readableState = state.isEmpty
        ? 'Unknown'
        : state[0].toUpperCase() + state.substring(1);

    Future<void> showPlanChooser() async {
      String selectedCode = currentCode;
      final selection = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: plpCanvas,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setSheetState) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Change plan',
                    style: TextStyle(
                      color: plpInk,
                      fontFamily: 'serif',
                      fontSize: 30,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose a destination plan, then review the change before proceeding.',
                    style: TextStyle(color: plpMuted, fontSize: 12.5, height: 1.45),
                  ),
                  const SizedBox(height: 18),
                  for (final entry in _plans.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: selectedCode == entry.key ? plpPaper : Colors.transparent,
                        child: InkWell(
                          onTap: _busy ? null : () => setSheetState(() => selectedCode = entry.key),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: selectedCode == entry.key ? plpInk : plpLine,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  selectedCode == entry.key
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  color: selectedCode == entry.key ? plpInk : plpMuted,
                                  size: 18,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.value.$1,
                                        style: const TextStyle(
                                          color: plpInk,
                                          fontFamily: 'serif',
                                          fontSize: 21,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        entry.key == currentCode ? 'Current plan' : 'Recurring monthly plan',
                                        style: const TextStyle(color: plpMuted, fontSize: 11.5),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    entry.value.$2,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      color: plpInk,
                                      fontFamily: 'serif',
                                      fontSize: 17,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy || selectedCode == currentCode
                          ? null
                          : () => Navigator.pop(sheetContext, selectedCode),
                      style: FilledButton.styleFrom(
                        backgroundColor: plpInk,
                        foregroundColor: plpPaper,
                      ),
                      child: const Text('Review plan change'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (selection != null && selection != currentCode) {
        await _confirmPlanChange(selection);
      }
    }

    return PlpEditorialPage(
      pageKey: const ValueKey('plp-paypal-billing'),
      eyebrow: 'Billing',
      title: active ? 'Your subscription.' : 'Start your subscription.',
      intro: active
          ? 'Review the plan and billing information returned for this subscription, then manage it in one place.'
          : 'Choose Launch or Professional, review the recurring amount, then authorize payment through PayPal.',
      onOpenNavigation: widget.onOpenNavigation,
      children: [
        const SizedBox(height: 14),
        if (!_statusLoaded && _error == null)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: plpLine,
              color: plpAccent,
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: PlpBlackPanel(
              eyebrow: 'Attention',
              title: 'Billing needs attention.',
              body: _error!,
            ),
          ),
        Container(
          decoration: const BoxDecoration(
            color: plpPaper,
            border: Border.fromBorderSide(BorderSide(color: plpLine)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 17, 14, 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F7FC),
                  border: Border.all(color: const Color(0xFFD9E2EF)),
                ),
                child: const Text(
                  'P',
                  style: TextStyle(
                    color: Color(0xFF003087),
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PayPal',
                      style: TextStyle(
                        color: Color(0xFF003087),
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Payment authorization and recurring charges',
                      style: TextStyle(color: plpMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Text(
                providerLabel,
                style: TextStyle(
                  color: verified
                      ? plpGood
                      : providerConfigured
                          ? plpAccent
                          : plpWarn,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (active) ...[
          const SizedBox(height: 18),
          Container(
            color: plpInk,
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'CURRENT PLAN',
                        style: TextStyle(
                          color: Color(0xFFD5CCB7),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    if (verified)
                      const Text(
                        'VERIFIED',
                        style: TextStyle(
                          color: Color(0xFFB7C6B7),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  currentPlan,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'serif',
                    fontSize: 36,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  currentPrice,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'serif',
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 17),
                Text(
                  renewalDate.isNotEmpty
                      ? 'Next renewal · $renewalDate'
                      : 'Renewal date has not been confirmed by the provider.',
                  style: const TextStyle(
                    color: Color(0xFFBDB7AE),
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (approvalUrl.isNotEmpty) ...[
            const SizedBox(height: 18),
            PlpBlackPanel(
              eyebrow: 'PayPal',
              title: 'Approval is waiting.',
              body:
                  'Finish the change in PayPal, then return here. Pandora will verify the provider state before showing the new plan.',
              action: 'Open PayPal',
              onTap: _busy ? null : () => _openApproval(approvalUrl),
            ),
          ],
          const PlpSectionTitle(
            'Billing details',
            detail: 'What the provider does and what Pandora has actually confirmed.',
          ),
          const PlpEditorialRow(
            title: 'Payment processing',
            detail: 'PayPal handles payment authorization and recurring charges for the selected plan.',
          ),
          PlpEditorialRow(
            title: 'Subscription record',
            detail: verified
                ? 'The displayed subscription is marked provider-verified by the billing service.'
                : 'Provider verification is not confirmed. This workspace will not label the subscription as verified until the billing service returns that evidence.',
            value: readableState,
            tone: verified ? plpGood : plpAccent,
          ),
          const PlpSectionTitle(
            'Manage',
            detail: 'Review changes before proceeding. The displayed plan updates only after provider confirmation.',
          ),
          _safeActionRow(
            title: 'Change plan',
            detail: 'Compare the destination price, then review the change before opening PayPal.',
            onTap: _busy ? null : showPlanChooser,
          ),
          _safeActionRow(
            title: 'Refresh PayPal state',
            detail: 'Request reconciliation with the provider; the result may remain pending or unresolved.',
            onTap: _busy ? null : _reconcile,
          ),
          _safeActionRow(
            title: 'Cancel subscription',
            detail: 'Review the cancellation request and its confirmed outcome.',
            tone: plpWarn,
            onTap: _busy ? null : _confirmCancel,
          ),
        ] else if (approvalUrl.isNotEmpty) ...[
          const PlpSectionTitle(
            'Payment authorization',
            detail: 'An approval session already exists for this workspace. Finish it before starting another checkout.',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 56),
            child: PlpBlackPanel(
              eyebrow: 'PayPal approval',
              title: 'Continue your existing approval.',
              body: 'Open the existing PayPal session. Pandora will confirm the subscription from the provider response; returning here alone does not activate a plan.',
              action: 'Open PayPal',
              onTap: _busy ? null : () => _openApproval(approvalUrl),
            ),
          ),
        ] else ...[
          const PlpSectionTitle(
            'Choose a plan',
            detail: 'Select an option to review its recurring monthly price before you proceed.',
          ),
          for (final entry in _plans.entries) _planOption(entry.key),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.only(right: 56),
            child: PlpBlackPanel(
              eyebrow: 'Your billing commitment',
              title: _plans[_selectedPlanCode]?.$1 ?? 'Choose a plan',
              body: (_plans[_selectedPlanCode]?.$2 ?? 'Price unavailable') +
                  '. Recurring monthly subscription. PayPal will present the authorization terms; returning to Pandora alone does not confirm activation.',
              action: 'Continue with PayPal',
              onTap: _busy ? null : () => _checkout(_selectedPlanCode),
            ),
          ),
        ],
        if ((_status['activity'] as List?)?.isNotEmpty == true) ...[
          const PlpSectionTitle(
            'Recent billing',
            detail: 'Provider-backed events appear here as they are verified.',
          ),
          for (final item in (_status['activity'] as List).whereType<Map>())
            PlpEditorialRow(
              title: item['title']?.toString() ?? 'Billing event',
              detail: item['detail']?.toString() ?? '',
              tone: item['trust']?.toString() == 'provider'
                  ? plpGood
                  : plpAccent,
            ),
        ],
        const SizedBox(height: 24),
        Text(
          verified
              ? 'PayPal · subscription provider-verified'
              : active
                  ? 'PayPal · subscription not yet verified'
                  : providerConfigured
                      ? 'PayPal · configured; subscription not yet verified'
                      : 'PayPal · configuration needs attention',
          style: const TextStyle(color: plpMuted, fontSize: 11),
        ),
      ],
    );
  }

  Map<String, dynamic> _map(Object? value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};

  String _planName(String code) =>
      _plans[code]?.$1 ?? (code.isEmpty ? '—' : code);
}
