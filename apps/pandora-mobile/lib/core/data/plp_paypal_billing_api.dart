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
        throw Exception(
          (decoded['error'] ?? decoded['message'] ?? 'Billing request failed')
              .toString(),
        );
      }
      return decoded;
    };
