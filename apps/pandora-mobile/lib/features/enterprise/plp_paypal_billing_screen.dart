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
  bool _busy = false;
  String? _error;
  String? _theatre;
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
      throw Exception('Sign in again to read subscription truth.');
    }
    final headers = <String, String>{
      'Authorization': 'Bearer ${session.accessToken}',
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
        (decoded['plainMessage'] ?? decoded['message'] ?? decoded['error'] ?? 'Billing request failed')
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

  Future<void> _run(String theatre, Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _theatre = theatre;
    });
    try {
      await work();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _clean(error);
          _theatre = 'Provider verification failed';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _clean(Object error) => error.toString().replaceFirst('Exception: ', '');

  String _idempotency(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _checkout(String code) async {
    await _run('Requesting subscription', () async {
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
      if (mounted) setState(() => _theatre = 'Awaiting PayPal approval');
      await _openApproval(result['approvalUrl']?.toString());
      await _loadStatus();
    });
  }

  Future<void> _changePlan(String code) async {
    await _run('Requesting plan change', () async {
      final result = await _request(
        '/billing/paypal/change-plan',
        method: 'POST',
        body: {
          'planCode': code,
          'idempotencyKey': _idempotency('plp-plan-change'),
        },
      );
      if (mounted) setState(() => _theatre = 'Awaiting PayPal approval');
      await _openApproval(result['approvalUrl']?.toString());
      if (mounted) setState(() => _theatre = 'Verifying provider state');
      await _loadStatus();
    });
  }

  Future<void> _reconcile() async {
    await _run('Reconciling payment state', () async {
      final result = await _request('/billing/paypal/reconcile', method: 'POST');
      final reconciliation = _map(result['reconciliation']);
      if (mounted) {
        setState(() {
          _status = result;
          _theatre = reconciliation['verified'] == true
              ? 'Verified with PayPal'
              : (reconciliation['label'] ?? 'Provider verification failed').toString();
        });
      }
    });
  }

  Future<void> _cancel() async {
    await _run('Requesting cancellation', () async {
      final result = await _request(
        '/billing/paypal/cancel',
        method: 'POST',
        body: const {'reason': 'Cancelled by PLP owner'},
      );
      final cancellation = _map(result['cancellation']);
      if (mounted) {
        setState(() {
          _status = result;
          _theatre = cancellation['verified'] == true
              ? 'Cancellation verified with PayPal'
              : 'Awaiting provider confirmation';
        });
      }
    });
  }

  Future<void> _openApproval(String? value) async {
    if (value == null || value.isEmpty) return;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('PayPal approval could not be opened.');
    }
  }

  Future<void> _confirmCancel(String planName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this subscription?'),
        content: Text(
          '$planName will be sent to PayPal for cancellation. Pandora will not mark it cancelled until PayPal confirms the provider state.',
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
    final change = _map(_status['pendingPlanChange']);
    final plans = _list(_status['plans']);
    final activity = _list(_status['activity']);
    final subscribed = subscription.isNotEmpty && subscription['state'] != 'cancelled';
    final planName = _text(subscription['plan_name'], fallback: 'No subscription on file.');
    final verified = subscription['source_kind'] == 'provider_verified' &&
        _text(subscription['verified_at'], fallback: '').isNotEmpty;
    final verification = _text(
      subscription['verification_label'],
      fallback: provider['configured'] == false
          ? 'Provider state unavailable'
          : 'Awaiting provider confirmation',
    );
    final currentCode = _text(subscription['plan_code'], fallback: '');
    final currency = _text(subscription['currency'], fallback: _text(plans.isEmpty ? null : plans.first['currency'], fallback: ''));

    return PlpEditorialPage(
      pageKey: const ValueKey('plp-revenue-billing'),
      eyebrow: 'Revenue',
      title: planName,
      intro: subscribed
          ? 'Subscription truth for this PLP Enterprise account. Price, renewal, and PayPal evidence stay on one surface.'
          : 'No active subscription is on file. Plans below are the catalog Pandora can actually read. Checkout starts only after a PayPal plan link exists.',
      onOpenNavigation: widget.onOpenNavigation,
      children: [
        const SizedBox(height: 22),
        if (_error != null)
          PlpBlackPanel(
            eyebrow: 'Attention',
            title: 'Billing needs attention.',
            body: _error!,
          ),
        if (_theatre != null) ...[
          const SizedBox(height: 18),
          PlpEditorialRow(
            title: _theatre!,
            detail: _busy
                ? 'This step is in progress. The rest of the workspace stays readable.'
                : 'Latest governed billing action. Local request state is not provider confirmation.',
            tone: _theatre!.contains('failed') || _theatre!.contains('unavailable') ? plpWarn : plpAccent,
          ),
        ],
        const PlpSectionTitle(
          'Current subscription',
          detail: 'Provider-confirmed state outranks local request state.',
        ),
        PlpEditorialRow(
          title: subscribed ? planName : 'Not subscribed',
          detail: subscribed
              ? '${_text(subscription['state'])} · $verification'
              : verification,
          value: subscribed ? _money(subscription['net_monthly_fee'] ?? subscription['monthly_fee'], currency) : '—',
          tone: verified ? plpGood : plpWarn,
        ),
        PlpEditorialRow(
          title: 'Renewal',
          detail: subscribed ? 'Next renewal on the recorded subscription.' : 'No renewal until a subscription is verified.',
          value: _text(subscription['renews_on'], fallback: '—'),
        ),
        PlpEditorialRow(
          title: 'Provider',
          detail: verified
              ? 'Verified ${_text(subscription['verified_at'])}'
              : verification,
          value: _text(provider['label'], fallback: 'PayPal'),
        ),
        if (_text(subscription['provider_reference'], fallback: '').isNotEmpty)
          PlpEditorialRow(
            title: 'Provider reference',
            detail: 'PayPal subscription reference. Credentials remain server-side.',
            value: _short(_text(subscription['provider_reference'])),
          ),
        const PlpSectionTitle(
          'Plans',
          detail: 'A change shows the current plan, the requested plan, and the monthly price delta.',
        ),
        if (plans.isEmpty)
          const PlpEditorialRow(
            title: 'No plans on file',
            detail: 'Pandora did not return an active service plan. Nothing has been invented.',
          )
        else
          for (final plan in plans)
            _planRow(plan, currentCode, currency, subscribed),
        if (change.isNotEmpty) ...[
          const PlpSectionTitle(
            'Plan change',
            detail: 'Shown only while a request exists. Completion waits for PayPal.',
          ),
          PlpEditorialRow(
            title: '${_text(change['from_plan_name'], fallback: 'Current')} → ${_text(change['to_plan_name'])}',
            detail: '${_trustLabel(_text(change['trust']))} · ${_text(change['status'])}',
            value: _signedMoney(change['price_delta'], _text(change['currency'], fallback: currency)),
            tone: change['status'] == 'failed' ? plpWarn : plpAccent,
          ),
          if (_text(change['approval_url'], fallback: '').isNotEmpty)
            PlpBlackPanel(
              eyebrow: 'Approval required',
              title: 'Awaiting PayPal approval.',
              body: 'The workspace stays open. Opening PayPal does not by itself change the verified subscription.',
              action: 'Open PayPal approval',
              onTap: _busy ? null : () => _openApproval(change['approval_url']?.toString()),
            ),
        ],
        if (checkout.isNotEmpty && !subscribed) ...[
          const PlpSectionTitle(
            'Checkout',
            detail: 'Local checkout state until PayPal confirms the subscription.',
          ),
          PlpEditorialRow(
            title: _text(checkout['plan_name']),
            detail: '${_trustLabel(_text(checkout['trust']))} · ${_text(checkout['status'])}',
            tone: checkout['status'] == 'failed' ? plpWarn : plpAccent,
          ),
          if (_text(checkout['approval_url'], fallback: '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: PlpBlackPanel(
                eyebrow: 'Approval required',
                title: 'PayPal approval is waiting.',
                body: 'Reopen the existing approval link. Pandora does not store a PayPal secret in PLP.',
                action: 'Open PayPal approval',
                onTap: _busy ? null : () => _openApproval(checkout['approval_url']?.toString()),
              ),
            ),
        ],
        const PlpSectionTitle(
          'Activity',
          detail: 'Only recorded payments, verified PayPal events, and billing sessions. Nothing here is generated.',
        ),
        if (activity.isEmpty)
          const PlpEditorialRow(
            title: 'No billing evidence yet',
            detail: 'Payments and provider events will appear here after they are recorded.',
          )
        else
          for (final event in activity.take(8))
            PlpEditorialRow(
              title: _text(event['title']),
              detail: '${_trustLabel(_text(event['trust']))} · ${_text(event['detail'])}',
              value: event['amount'] == null
                  ? null
                  : _money(event['amount'], _text(event['currency'], fallback: currency)),
              tone: event['trust'] == 'provider' ? plpGood : plpWarn,
            ),
        const PlpSectionTitle(
          'Actions',
          detail: 'Reconcile reads PayPal. Cancel is destructive and stays subordinate.',
        ),
        PlpEditorialRow(
          title: 'Reconcile with PayPal',
          detail: 'Re-read provider state, persist what PayPal confirms, then reload this workspace.',
          onTap: _busy ? null : _reconcile,
        ),
        if (subscribed)
          PlpEditorialRow(
            title: 'Cancel subscription',
            detail: '$planName · PayPal · cancellation is pending until provider state confirms it.',
            tone: plpWarn,
            onTap: _busy ? null : () => _confirmCancel(planName),
          ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _planRow(
    Map<String, dynamic> plan,
    String currentCode,
    String currency,
    bool subscribed,
  ) {
    final code = _text(plan['code']);
    final current = code == currentCode && currentCode.isNotEmpty;
    final linked = plan['provider_linked'] == true;
    final price = plan['monthly_fee'];
    final delta = subscribed && !current ? _delta(price, _status) : null;
    return PlpEditorialRow(
      title: current ? '${_text(plan['name'])} · current' : _text(plan['name']),
      detail: linked
          ? '${_money(price, _text(plan['currency'], fallback: currency))} / month${delta == null ? '' : ' · $delta'}'
          : 'Provider link required before PayPal can price this plan.',
      value: current ? null : (linked ? 'Select' : null),
      onTap: _busy || current || !linked
          ? null
          : () => subscribed ? _changePlan(code) : _checkout(code),
      tone: current ? plpGood : null,
    );
  }

  String? _delta(Object? requested, Map<String, dynamic> status) {
    final subscription = _map(status['subscription']);
    final current = _number(subscription['net_monthly_fee'] ?? subscription['monthly_fee']);
    final next = _number(requested);
    if (current == null || next == null) return null;
    final delta = next - current;
    final sign = delta > 0 ? '+' : '';
    return '$sign${_money(delta, _text(subscription['currency']))} / month';
  }

  Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

  List<Map<String, dynamic>> _list(Object? value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList(growable: false);
  }

  String _text(Object? value, {String fallback = '—'}) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? fallback : normalized;
  }

  num? _number(Object? value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '');
  }

  String _money(Object? value, String currency) {
    final amount = _number(value);
    if (amount == null) return '—';
    final prefix = currency == 'PHP' ? '₱' : (currency.isEmpty ? '' : '$currency ');
    return '$prefix${amount.toStringAsFixed(2)}';
  }

  String _signedMoney(Object? value, String currency) {
    final amount = _number(value);
    if (amount == null) return '—';
    final sign = amount > 0 ? '+' : '';
    return '$sign${_money(amount, currency)}';
  }

  String _short(String value) => value.length <= 18 ? value : '${value.substring(0, 8)}…${value.substring(value.length - 4)}';

  String _trustLabel(String trust) {
    switch (trust) {
      case 'provider':
        return 'Verified';
      case 'pending_action':
        return 'Approval required';
      case 'failed':
        return 'Provider verification failed';
      case 'local_request':
        return 'Awaiting provider confirmation';
      default:
        return trust.isEmpty ? 'Reconciliation required' : trust;
    }
  }
}
