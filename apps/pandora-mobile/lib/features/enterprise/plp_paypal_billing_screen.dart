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
    final checkout = _map(_status['checkout']);
    final state = (subscription['state'] ?? '').toString();
    final currentCode = (checkout['plan_code'] ?? '').toString();
    final renewsOn = (subscription['renews_on'] ?? '').toString();
    final verified =
        (subscription['source_kind'] ?? '').toString() == 'provider_verified';

    return PlpEditorialPage(
      pageKey: const ValueKey('plp-paypal-billing'),
      eyebrow: 'Subscription',
      title: 'Pandora billing.',
      intro:
          'Native PLP Enterprise billing. PayPal credentials stay server-side; this screen receives subscription state and provider approval links only.',
      onOpenNavigation: widget.onOpenNavigation,
      children: [
        const SizedBox(height: 24),
        if (_error != null)
          PlpBlackPanel(
            eyebrow: 'Attention',
            title: 'Billing needs attention.',
            body: _error!,
          ),
        PlpMetricStrip(
          items: [
            (
              'Status',
              state.isEmpty ? 'Not active' : state,
              verified ? 'provider verified' : 'account state',
            ),
            ('Plan', _planName(currentCode), 'monthly service'),
            ('Renewal', renewsOn.isEmpty ? '—' : renewsOn, 'next renewal'),
          ],
        ),
        const PlpSectionTitle(
          'Choose a plan',
          detail:
              'PayPal approval opens externally while Pandora keeps the credential boundary on the server.',
        ),
        for (final entry in _plans.entries)
          PlpEditorialRow(
            title: entry.value.$1,
            detail: entry.value.$2,
            onTap: _busy || state == 'active'
                ? null
                : () => _checkout(entry.key),
          ),
        if (state == 'active') ...[
          const PlpSectionTitle(
            'Manage subscription',
            detail: 'Provider state is re-read before consequential changes.',
          ),
          PlpEditorialRow(
            title: 'Refresh payment state',
            detail:
                'Reconcile this workspace against the live PayPal subscription.',
            onTap: _busy ? null : _reconcile,
          ),
          for (final entry in _plans.entries)
            if (entry.key != currentCode)
              PlpEditorialRow(
                title: 'Switch to ' + entry.value.$1,
                detail: entry.value.$2 + ' · PayPal approval required.',
                onTap: _busy ? null : () => _changePlan(entry.key),
              ),
          PlpEditorialRow(
            title: 'Cancel subscription',
            detail:
                'Cancel recurring PayPal billing and reconcile provider state.',
            tone: plpWarn,
            onTap: _busy ? null : _confirmCancel,
          ),
        ],
        if (checkout['approval_url']?.toString().isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 28),
            child: PlpBlackPanel(
              eyebrow: 'Payment handoff',
              title: 'PayPal approval is waiting.',
              body:
                  'Reopen the existing provider approval link. No PayPal secret is stored in PLP.',
              action: 'Open PayPal approval',
              onTap: _busy
                  ? null
                  : () => _openApproval(checkout['approval_url']?.toString()),
            ),
          ),
        const SizedBox(height: 18),
        Text(
          verified
              ? 'Provider state verified by PayPal.'
              : 'Provider verification is pending.',
          style: const TextStyle(
            color: plpMuted,
            fontSize: 11.5,
            height: 1.4,
          ),
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
