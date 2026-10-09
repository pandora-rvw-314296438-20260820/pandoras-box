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
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _clean(error));
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel PayPal subscription?'),
        content: const Text(
          'PayPal will receive the cancellation request. Pandora will then reconcile the provider state.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep subscription'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel subscription'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _cancel();
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
    final currentPrice = subscription['net_monthly_fee']?.toString().isNotEmpty == true
        ? 'USD ' + subscription['net_monthly_fee'].toString() + ' / month'
        : 'USD ' + (subscription['monthly_fee'] ?? '').toString() + ' / month';
    final approvalUrl =
        (pending['approval_url'] ?? checkout['approval_url'] ?? '').toString();

    Future<void> showPlanChooser() async {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: plpCanvas,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
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
                  'The new price takes effect on the next billing cycle after PayPal confirms the change.',
                  style: TextStyle(color: plpMuted, fontSize: 12.5, height: 1.45),
                ),
                const SizedBox(height: 18),
                for (final entry in _plans.entries)
                  PlpEditorialRow(
                    title: entry.value.$1,
                    detail: entry.value.$2 +
                        (entry.key == currentCode ? ' · Current plan.' : ''),
                    onTap: entry.key == currentCode || _busy
                        ? null
                        : () {
                            Navigator.pop(sheetContext);
                            _changePlan(entry.key);
                          },
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return PlpEditorialPage(
      pageKey: const ValueKey('plp-paypal-billing'),
      eyebrow: 'Billing',
      title: active ? 'Your subscription.' : 'Start your subscription.',
      intro: active
          ? 'One billing workspace for your plan, PayPal, renewal, payment history, and the few actions that matter.'
          : 'Choose a Pandora plan and complete secure recurring payment with PayPal.',
      onOpenNavigation: widget.onOpenNavigation,
      children: [
        const SizedBox(height: 22),
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
                      'Secure recurring billing',
                      style: TextStyle(color: plpMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Text(
                verified
                    ? 'Connected'
                    : provider['configured'] == true
                        ? 'Ready'
                        : 'Unavailable',
                style: TextStyle(
                  color: verified
                      ? plpGood
                      : provider['configured'] == true
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
                  'Renews ' +
                      (subscription['renews_on'] ?? 'pending').toString(),
                  style: const TextStyle(
                    color: Color(0xFFBDB7AE),
                    fontSize: 11,
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
            'Manage',
            detail: 'Stay on this page. Selection and confirmation open in context.',
          ),
          PlpEditorialRow(
            title: 'Change plan',
            detail: 'Switch Launch or Professional for the next billing cycle.',
            onTap: _busy ? null : showPlanChooser,
          ),
          PlpEditorialRow(
            title: 'Refresh PayPal state',
            detail: 'Reconcile this workspace against the live provider subscription.',
            onTap: _busy ? null : _reconcile,
          ),
          PlpEditorialRow(
            title: 'Cancel subscription',
            detail: 'Stop recurring PayPal billing after confirmation.',
            tone: plpWarn,
            onTap: _busy ? null : _confirmCancel,
          ),
        ] else ...[
          const PlpSectionTitle(
            'Plans',
            detail:
                'Pick a plan. PayPal handles secure approval; Pandora never receives the PayPal secret.',
          ),
          for (final entry in _plans.entries)
            PlpEditorialRow(
              title: entry.value.$1,
              detail: entry.value.$2,
              onTap: _busy ? null : () => _checkout(entry.key),
            ),
          if (approvalUrl.isNotEmpty)
            PlpBlackPanel(
              eyebrow: 'PayPal',
              title: 'Continue your payment.',
              body: 'A PayPal approval session already exists for this workspace.',
              action: 'Open PayPal',
              onTap: _busy ? null : () => _openApproval(approvalUrl),
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
              ? 'PayPal · provider verified'
              : provider['configured'] == true
                  ? 'PayPal · ready'
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
