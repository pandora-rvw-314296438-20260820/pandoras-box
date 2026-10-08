import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../pandora_config.dart';
import '../network/pandora_api_client.dart';
import '../network/pandora_api_error.dart';
import '../network/session_token_provider.dart';

/// Typed access to the owner API PayPal billing routes.
///
/// This is not a second HTTP client: it binds the shared [PandoraApiClient]
/// (session bearer token, X-Organization-Id, timeouts, bounded/sanitised
/// errors) to the PLP organization. No PayPal credential ever reaches the app;
/// responses carry subscription state and provider approval links only.
class PlpPaypalBillingApi {
  PlpPaypalBillingApi({required PandoraApiClient client}) : _client = client;

  factory PlpPaypalBillingApi.forOrganization(
    String organizationId, {
    SessionTokenProvider? tokenProvider,
    http.Client? httpClient,
    String environment = PandoraConfig.billingEnvironment,
  }) =>
      PlpPaypalBillingApi(
        client: PandoraApiClient(
          baseUri: Uri.parse(PandoraConfig.ownerApiBaseUrl),
          organizationId: organizationId,
          sessionTokenProvider: tokenProvider ??
              SupabaseSessionTokenProvider(Supabase.instance.client),
          httpClient: httpClient,
          timeout: const Duration(seconds: 30),
          defaultHeaders: <String, String>{
            'apikey': PandoraConfig.supabasePublishableKey,
            if (environment == 'sandbox')
              'x-pandora-billing-environment': 'sandbox',
          },
        ),
      );

  final PandoraApiClient _client;

  static final _random = Random.secure();

  /// `plp-checkout-<unique>` / `plp-plan-change-<unique>`.
  static String idempotencyKey(String prefix) {
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    final nonce = List<String>.generate(
      8,
      (_) => _random.nextInt(16).toRadixString(16),
    ).join();
    return '$prefix-$micros-$nonce';
  }

  Future<PlpBillingSnapshot> status() async {
    final response = await _client.getJson(
      pathSegments: const ['billing', 'paypal', 'status'],
      operation: 'billing.paypal.status',
      routeTemplate: '/billing/paypal/status',
    );
    return PlpBillingSnapshot.parse(response.data);
  }

  Future<PlpBillingApproval> checkout({
    required String planCode,
    required Uri returnUrl,
    required Uri cancelUrl,
  }) async {
    final response = await _client.postJson(
      pathSegments: const ['billing', 'paypal', 'checkout'],
      operation: 'billing.paypal.checkout',
      routeTemplate: '/billing/paypal/checkout',
      body: <String, Object?>{
        'planCode': planCode,
        'idempotencyKey': idempotencyKey('plp-checkout'),
        'returnUrl': returnUrl.toString(),
        'cancelUrl': cancelUrl.toString(),
      },
    );
    return PlpBillingApproval.parse(response.data);
  }

  Future<PlpBillingApproval> changePlan(
    String planCode, {
    Uri? returnUrl,
    Uri? cancelUrl,
  }) async {
    final response = await _client.postJson(
      pathSegments: const ['billing', 'paypal', 'change-plan'],
      operation: 'billing.paypal.changePlan',
      routeTemplate: '/billing/paypal/change-plan',
      body: <String, Object?>{
        'planCode': planCode,
        'idempotencyKey': idempotencyKey('plp-plan-change'),
        if (returnUrl != null) 'returnUrl': returnUrl.toString(),
        if (cancelUrl != null) 'cancelUrl': cancelUrl.toString(),
      },
    );
    return PlpBillingApproval.parse(response.data);
  }

  Future<void> reconcile() async {
    final response = await _client.postJson(
      pathSegments: const ['billing', 'paypal', 'reconcile'],
      operation: 'billing.paypal.reconcile',
      routeTemplate: '/billing/paypal/reconcile',
      body: const <String, Object?>{},
    );
    if (response.data is! Map) throw PlpBillingContractError();
  }

  /// The owner API decides the cancellation outcome from PayPal readbacks;
  /// the app only renders it (see [PlpBillingCancelOutcome]).
  Future<PlpBillingCancelOutcome> cancel() async {
    final response = await _client.postJson(
      pathSegments: const ['billing', 'paypal', 'cancel'],
      operation: 'billing.paypal.cancel',
      routeTemplate: '/billing/paypal/cancel',
      body: const <String, Object?>{'reason': 'Cancelled by Pandora owner'},
    );
    return PlpBillingCancelOutcome.parse(response.data);
  }

  void close() => _client.close();
}

class PlpBillingProblemException implements Exception {
  const PlpBillingProblemException(this.problem);
  final PlpBillingProblem problem;
}

class PlpBillingContractError implements Exception {
  @override
  String toString() => 'Billing response could not be read.';
}

Map<String, Object?> _map(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : const <String, Object?>{};

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty || text == 'null' ? null : text;
}

/// Only https links on paypal.com are opened.
Uri? plpTrustedApprovalUrl(Object? value) {
  final uri = Uri.tryParse(_text(value) ?? '');
  if (uri == null || uri.scheme != 'https') return null;
  final host = uri.host.toLowerCase();
  if (host != 'paypal.com' && !host.endsWith('.paypal.com')) return null;
  return uri;
}

class PlpBillingPlan {
  const PlpBillingPlan({
    required this.code,
    required this.name,
    required this.currency,
    required this.monthlyAmount,
    this.interval,
  });

  final String code;
  final String name;
  final String currency;
  final String monthlyAmount;

  /// Billing interval from the catalog (`month`); null when not reported.
  final String? interval;

  /// Amount in minor units, or null when the backend amount is not numeric.
  int? get amountCents {
    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(monthlyAmount);
    if (match == null) return null;
    final cents = (match.group(2) ?? '0').padRight(2, '0');
    return int.parse(match.group(1)!) * 100 + int.parse(cents);
  }

  /// `USD 49 / month` from the backend amount (`49.00`).
  String get priceLabel {
    final amount = monthlyAmount.endsWith('.00')
        ? monthlyAmount.substring(0, monthlyAmount.length - 3)
        : monthlyAmount;
    return '$currency $amount/mo';
  }
}

class PlpBillingSubscription {
  const PlpBillingSubscription({
    required this.state,
    required this.planCode,
    required this.renewsOn,
    required this.endsOn,
    this.startsOn,
    required this.providerVerified,
    required this.verifiedAt,
    required this.providerReference,
  });

  final String state;
  final String? planCode;
  final String? renewsOn;
  final String? endsOn;
  final String? startsOn;
  final bool providerVerified;
  final String? verifiedAt;
  final String? providerReference;

  bool get holdsPlan =>
      const {'trial', 'active', 'past_due', 'suspended'}.contains(state);
}

class PlpBillingCheckout {
  const PlpBillingCheckout({
    required this.status,
    required this.planCode,
    required this.approvalUrl,
    required this.expiresAt,
  });

  final String status;
  final String? planCode;
  final Uri? approvalUrl;
  final DateTime? expiresAt;

  bool pendingAt(DateTime now) =>
      status == 'approval_pending' &&
      approvalUrl != null &&
      (expiresAt == null || expiresAt!.isAfter(now));
}

class PlpBillingPlanChange {
  const PlpBillingPlanChange({
    required this.status,
    required this.toPlanCode,
    required this.approvalUrl,
  });

  final String status;
  final String? toPlanCode;
  final Uri? approvalUrl;

  bool get pending => status == 'approval_pending' && approvalUrl != null;
}

class PlpBillingSnapshot {
  const PlpBillingSnapshot({
    required this.environment,
    required this.plans,
    required this.subscription,
    required this.checkout,
    required this.planChange,
  });

  final String environment;
  final List<PlpBillingPlan> plans;
  final PlpBillingSubscription? subscription;
  final PlpBillingCheckout? checkout;
  final PlpBillingPlanChange? planChange;

  bool get sandbox => environment == 'sandbox';

  PlpBillingPlan? plan(String? code) {
    for (final plan in plans) {
      if (plan.code == code) return plan;
    }
    return null;
  }

  static PlpBillingSnapshot parse(Object? data) {
    if (data is! Map) throw PlpBillingContractError();
    final json = _map(data);
    final rawPlans = json['plans'];
    if (rawPlans is! List) throw PlpBillingContractError();
    final plans = <PlpBillingPlan>[];
    for (final raw in rawPlans) {
      final plan = _map(raw);
      final code = _text(plan['code']);
      final name = _text(plan['name']);
      final currency = _text(plan['currency']);
      final amount = _text(plan['monthlyAmount']);
      if (code == null || name == null || currency == null || amount == null) {
        throw PlpBillingContractError();
      }
      plans.add(PlpBillingPlan(
        code: code,
        name: name,
        currency: currency,
        monthlyAmount: amount,
        interval: _text(plan['interval']),
      ));
    }
    final sub = json['subscription'];
    final checkout = json['checkout'];
    final change = json['planChange'];
    if ((sub != null && sub is! Map) ||
        (checkout != null && checkout is! Map) ||
        (change != null && change is! Map)) {
      throw PlpBillingContractError();
    }
    PlpBillingSubscription? subscription;
    if (sub is Map) {
      final s = _map(sub);
      final state = _text(s['state']);
      if (state == null) throw PlpBillingContractError();
      subscription = PlpBillingSubscription(
        state: state,
        planCode: _text(s['plan_code']),
        renewsOn: _text(s['renews_on']),
        endsOn: _text(s['ends_on']),
        startsOn: _text(s['starts_on']),
        providerVerified: _text(s['source_kind']) == 'provider_verified' &&
            _text(s['provider_reference']) != null &&
            _text(s['verified_at']) != null,
        verifiedAt: _text(s['verified_at']),
        providerReference: _text(s['provider_reference']),
      );
    }
    PlpBillingCheckout? pendingCheckout;
    if (checkout is Map) {
      final c = _map(checkout);
      pendingCheckout = PlpBillingCheckout(
        status: _text(c['status']) ?? 'unknown',
        planCode: _text(c['plan_code']),
        approvalUrl: plpTrustedApprovalUrl(c['approval_url']),
        expiresAt: DateTime.tryParse(_text(c['expires_at']) ?? ''),
      );
    }
    PlpBillingPlanChange? planChange;
    if (change is Map) {
      final c = _map(change);
      planChange = PlpBillingPlanChange(
        status: _text(c['status']) ?? 'unknown',
        toPlanCode: _text(c['to_plan_code']),
        approvalUrl: plpTrustedApprovalUrl(c['approval_url']),
      );
    }
    return PlpBillingSnapshot(
      environment: _text(json['environment']) ?? 'live',
      plans: List<PlpBillingPlan>.unmodifiable(plans),
      subscription: subscription,
      checkout: pendingCheckout,
      planChange: planChange,
    );
  }
}

class PlpBillingApproval {
  const PlpBillingApproval({required this.approvalUrl, required this.status});

  /// Null when the backend returned no trusted PayPal approval link.
  final Uri? approvalUrl;
  final String? status;

  static PlpBillingApproval parse(Object? data) {
    if (data is! Map) throw PlpBillingContractError();
    final json = _map(data);
    return PlpBillingApproval(
      approvalUrl: plpTrustedApprovalUrl(json['approvalUrl']),
      status: _text(json['status']),
    );
  }
}

/// Server-decided result of `POST /billing/paypal/cancel`.
///
/// * `cancelled`: PayPal read back CANCELLED and Pandora recorded it.
/// * `blocked`: nothing was sent to PayPal (for example
///   `AWAITING_BUYER_APPROVAL` while the buyer has not approved yet).
/// * `cancel_unconfirmed`: PayPal accepted the request but did not read back
///   CANCELLED, so nothing was recorded as cancelled.
class PlpBillingCancelOutcome {
  const PlpBillingCancelOutcome({required this.status, this.reason});

  final String status;
  final String? reason;

  bool get cancelled => status == 'cancelled';
  bool get blocked => status == 'blocked';

  static PlpBillingCancelOutcome parse(Object? data) {
    if (data is! Map) throw PlpBillingContractError();
    final json = _map(data);
    final status = _text(json['status']);
    if (status == null) throw PlpBillingContractError();
    return PlpBillingCancelOutcome(status: status, reason: _text(json['reason']));
  }

  static const _blockedByReason = <String, String>{
    'AWAITING_BUYER_APPROVAL':
        'PayPal is still waiting for the buyer to approve this subscription. Nothing was sent to PayPal and nothing was cancelled.',
    'AWAITING_PROVIDER_ACTIVATION':
        'PayPal has not activated this subscription yet. Nothing was sent to PayPal and nothing was cancelled.',
    'RECONCILIATION_REQUIRED':
        'Pandora has not verified this subscription with PayPal yet. Refresh payment state first. Nothing was cancelled.',
    'SUBSCRIPTION_NOT_ACTIVE':
        'PayPal reports this subscription is not active. Nothing was cancelled.',
  };

  /// Owner-facing wording for a blocked cancellation.
  PlpBillingProblem get blockedProblem => PlpBillingProblem(
        'Cancellation blocked.',
        _blockedByReason[reason] ??
            'PayPal does not allow cancelling this subscription in its current state. Nothing was cancelled.',
      );
}

/// Concise owner-facing wording for billing failures. Raw exceptions are
/// never shown.
class PlpBillingProblem {
  const PlpBillingProblem(this.title, this.body, {this.needsIdentity = false});

  final String title;
  final String body;
  final bool needsIdentity;

  static const _byCode = <String, (String, String)>{
    'SIGN_IN_REQUIRED': (
      'Session expired.',
      'Your session has expired. Sign in again to manage billing.'
    ),
    'ORGANIZATION_ACCESS_REQUIRED': (
      'Billing is not available.',
      'Only owners and admins of this organization can manage billing.'
    ),
    'OWNER_ROLE_REQUIRED': (
      'Billing is not available.',
      'Only owners and admins of this organization can manage billing.'
    ),
    'ORGANIZATION_SELECTION_REQUIRED': (
      'Organization missing.',
      'Choose the organization whose billing you want to manage.'
    ),
    'BILLING_ORGANIZATION_REQUIRED': (
      'Organization missing.',
      'Choose the organization whose billing you want to manage.'
    ),
    'PLAN_NOT_FOUND': ('Plan unavailable.', 'That plan is not available.'),
    'PLAN_REQUIRED': ('Plan unavailable.', 'Choose a plan first.'),
    'PAYPAL_NOT_CONFIGURED': (
      'PayPal unavailable.',
      'PayPal is not configured for this workspace yet.'
    ),
    'PAYPAL_AUTH_FAILED': (
      'PayPal unavailable.',
      'PayPal is unavailable right now. Pandora could not authenticate with PayPal.'
    ),
    'PAYPAL_SECRET_ACCESS_UNAVAILABLE': (
      'PayPal unavailable.',
      'PayPal is unavailable right now.'
    ),
    'PAYPAL_SUBSCRIPTION_CREATE_FAILED': (
      'Checkout not started.',
      'PayPal could not start checkout. Nothing was charged.'
    ),
    'PAYPAL_APPROVAL_URL_MISSING': (
      'Approval link missing.',
      'PayPal did not return an approval link. Nothing was approved.'
    ),
    'PAYPAL_PLAN_CHANGE_APPROVAL_MISSING': (
      'Approval link missing.',
      'PayPal did not return an approval link for the plan change. The plan is unchanged.'
    ),
    'PAYPAL_PLAN_CHANGE_FAILED': (
      'Plan unchanged.',
      'PayPal could not change the plan. The current plan is unchanged.'
    ),
    'PAYPAL_PLAN_CHANGE_NOT_ALLOWED': (
      'Plan unchanged.',
      'PayPal does not allow that plan change for this subscription.'
    ),
    'PAYPAL_PLAN_SAME': (
      'Plan unchanged.',
      'The subscription is already on that plan.'
    ),
    'PAYPAL_CANCEL_FAILED': (
      'Cancellation not confirmed.',
      'PayPal could not cancel the subscription. Nothing was recorded as cancelled.'
    ),
    'PAYPAL_SUBSCRIPTION_READ_FAILED': (
      'Payment state not confirmed.',
      'PayPal could not confirm the subscription state. Try again shortly.'
    ),
    'PAYPAL_PLAN_MISMATCH': (
      'Billing needs review.',
      'PayPal reports a plan Pandora does not recognise.'
    ),
    'PAYPAL_PROVIDER_MISMATCH': (
      'Billing needs review.',
      'PayPal returned a subscription that does not match this checkout.'
    ),
    'SUBSCRIPTION_NOT_FOUND': (
      'No PayPal subscription yet.',
      'No PayPal subscription is linked to this organization yet.'
    ),
    'PROVIDER_SUBSCRIPTION_NOT_LINKED': (
      'No PayPal subscription yet.',
      'No PayPal subscription is linked to this organization yet.'
    ),
    'REQUEST_TIMEOUT': (
      'PayPal timed out.',
      'Billing took too long to respond. Refresh payment state before trying again.'
    ),
    'NETWORK_UNAVAILABLE': (
      'Billing unreachable.',
      'Pandora cannot reach the billing service. Check the connection and try again.'
    ),
    'RATE_LIMITED': (
      'Please wait.',
      'Too many billing requests. Wait a moment before trying again.'
    ),
  };

  static PlpBillingProblem from(Object error) {
    if (error is PlpBillingProblemException) return error.problem;
    if (error is PlpBillingContractError) {
      return const PlpBillingProblem(
        'Unreadable billing response.',
        'Pandora returned billing data this screen cannot read. Nothing was changed here.',
      );
    }
    if (error is PandoraApiError) {
      if (error.code == 'AAL2_REQUIRED') {
        return const PlpBillingProblem(
          'Confirm it is you.',
          'Billing changes need your authenticator code. PayPal is not contacted until you confirm.',
          needsIdentity: true,
        );
      }
      final known = _byCode[error.code];
      if (known != null) return PlpBillingProblem(known.$1, known.$2);
      if (error.kind == PandoraApiErrorKind.sessionExpired) {
        return PlpBillingProblem(
            _byCode['SIGN_IN_REQUIRED']!.$1, _byCode['SIGN_IN_REQUIRED']!.$2);
      }
      if (error.kind == PandoraApiErrorKind.contract) {
        return from(PlpBillingContractError());
      }
      if (error.kind == PandoraApiErrorKind.ambiguousMutation) {
        return const PlpBillingProblem(
          'Result not confirmed.',
          'Pandora could not confirm the result with PayPal. The billing state below was re-read from the server.',
        );
      }
      // Server plain messages are already bounded and sanitised by the
      // shared client; codes such as BILLING_ACCOUNT_REQUIRED or
      // RETURN_URL_NOT_ALLOWED arrive with owner-safe wording.
      return PlpBillingProblem('Billing needs attention.', error.message);
    }
    return const PlpBillingProblem(
      'Billing needs attention.',
      'Billing could not be updated. Refresh payment state to see the confirmed state.',
    );
  }
}
