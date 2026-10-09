import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../pandora_config.dart';

/// Owner API transport for PLP PayPal billing. Injectable so widget tests and
/// render harnesses can supply a fake.
typedef PlpBillingTransport = Future<Map<String, dynamic>> Function(
  String path, {
  String method,
  Map<String, dynamic>? body,
});

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
          ? await http.post(uri, headers: headers, body: jsonEncode(body ?? {}))
          : await http.get(uri, headers: headers);
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
