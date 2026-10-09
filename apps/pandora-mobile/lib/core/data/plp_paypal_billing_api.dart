import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../pandora_config.dart';

/// Allowed origins for PLP checkout analytics and return navigation.
const plpCheckoutOrigins = <String>{
  'today',
  'stays',
  'guests',
  'operations',
  'revenue',
  'experiences',
  'team',
  'assistant',
};

/// A detected return from PayPal (approval or cancellation).
class PlpCheckoutReturn {
  const PlpCheckoutReturn({required this.cancelled, this.origin});
  final bool cancelled;
  final String? origin;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlpCheckoutReturn &&
          runtimeType == other.runtimeType &&
          cancelled == other.cancelled &&
          origin == other.origin;

  @override
  int get hashCode => Object.hash(cancelled, origin);
}

/// Detects a PayPal return or cancellation in [uri].
///
/// Origin is extracted from a `from` query parameter in the fragment query or
/// [Uri.queryParameters], retaining only values in [plpCheckoutOrigins].
/// NEVER treat a return as payment proof — it only selects the confirming view.
PlpCheckoutReturn? plpCheckoutReturnFromUri(Uri uri) {
  final hasReturn = uri.path.contains('/enterprise/paypal-return') ||
      uri.fragment.contains('/enterprise/paypal-return');
  final hasCancel = uri.path.contains('/enterprise/paypal-cancel') ||
      uri.fragment.contains('/enterprise/paypal-cancel');

  if (!hasReturn && !hasCancel) return null;

  String? fromParam = uri.queryParameters['from'];
  if (fromParam == null && uri.fragment.contains('?')) {
    final fragmentQuery = uri.fragment.substring(uri.fragment.indexOf('?') + 1);
    fromParam = Uri.splitQueryString(fragmentQuery)['from'];
  }

  final origin = (fromParam != null && plpCheckoutOrigins.contains(fromParam))
      ? fromParam
      : null;

  return PlpCheckoutReturn(
    cancelled: hasCancel,
    origin: origin,
  );
}

/// Owner API transport for PLP PayPal billing. Injectable so widget tests and
/// render harnesses can supply a fake.
typedef PlpBillingTransport = Future<Map<String, dynamic>> Function(
  String path, {
  String method,
  Map<String, dynamic>? body,
});

/// Returns true for transient network, timeout or rate-limit/server errors.
/// Compiles on web without dart:io.
bool plpBillingTransientError(Object error) {
  if (error is TimeoutException || error is http.ClientException) {
    return true;
  }
  if (error is PlpBillingRequestException) {
    return error.statusCode == 429 || error.statusCode >= 500;
  }
  return false;
}

/// The authenticated owner API (`/billing/paypal/*`) for one organization.
PlpBillingTransport plpOwnerBillingTransport(String organizationId) => (
      String path, {
      String method = 'GET',
      Map<String, dynamic>? body,
    }) async {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        throw Exception('Sign in again to manage billing.');
      }
      final headers = <String, String>{
        'Authorization': 'Bearer ${session.accessToken}',
        'apikey': PandoraConfig.supabasePublishableKey,
        'x-organization-id': organizationId,
        'Content-Type': 'application/json',
      };
      final uri = Uri.parse(PandoraConfig.ownerApiBaseUrl + path);
      final response = method == 'POST'
          ? await http
              .post(uri, headers: headers, body: jsonEncode(body ?? {}))
              .timeout(const Duration(seconds: 15))
          : await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw PlpBillingRequestException(
          statusCode: response.statusCode,
          code: (decoded['code'] ?? decoded['error'] ?? '').toString(),
          message: (decoded['error'] ??
                  decoded['message'] ??
                  decoded['plainMessage'] ??
                  'Billing request failed')
              .toString(),
        );
      }
      return decoded;
    };

/// A non-2xx owner API reply. Owner API failures carry a machine `code`
/// (e.g. OWNER_ROLE_REQUIRED, PAYPAL_NOT_CONFIGURED) beside a plain message.
class PlpBillingRequestException implements Exception {
  const PlpBillingRequestException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  /// The caller's membership may not read billing (owner/admin only).
  bool get isRoleDenied =>
      code == 'OWNER_ROLE_REQUIRED' ||
      code == 'ORGANIZATION_ACCESS_REQUIRED' ||
      (code.isEmpty && statusCode == 403);

  @override
  String toString() =>
      'Exception: ${code.isEmpty ? '' : '$code: '}$message';
}

/// The single truthful unlock rule, shared by the billing screen and the PLP
/// subscription gate: the subscription is active AND PayPal-verified
/// (provider-sourced, with a verification time). A PayPal return, a pending
/// checkout or an unconfirmed active row never unlocks.
bool plpBillingStatusUnlocked(Map<String, dynamic> status) {
  final raw = status['subscription'];
  if (raw is! Map) return false;
  final state = (raw['state'] ?? '').toString().toLowerCase();
  final verifiedAt = raw['verified_at'];
  return state == 'active' &&
      raw['source_kind'] == 'provider_verified' &&
      verifiedAt != null &&
      verifiedAt.toString().trim().isNotEmpty;
}

/// Reads only whether an organization is unlocked (active + PayPal-verified)
/// for any active member. Injectable for tests and render harnesses.
typedef PlpEntitlementReader = Future<bool> Function(String organizationId);

/// `public.pandora_plp_entitlement_v1(p_organization_id)`: a boolean, never
/// billing details. Throws when the caller is not an active member or the
/// function is unavailable, so callers fail closed.
Future<bool> plpSupabaseEntitlementReader(String organizationId) async {
  final result = await Supabase.instance.client
      .rpc(
        'pandora_plp_entitlement_v1',
        params: <String, Object?>{'p_organization_id': organizationId},
      )
      .timeout(const Duration(seconds: 12));
  if (result is bool) return result;
  throw StateError('PLP entitlement returned an invalid payload.');
}
