import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/domain_registrar_models.dart';
import '../network/idempotency_key.dart';

class DomainRegistrarApi {
  DomainRegistrarApi({
    required SupabaseClient client,
    required String organizationId,
    IdempotencyKeyFactory? idempotencyKeys,
  })  : _client = client,
        _organizationId = organizationId,
        _keys = idempotencyKeys ?? IdempotencyKeyFactory();

  final SupabaseClient _client;
  final String _organizationId;
  final IdempotencyKeyFactory _keys;

  Future<DomainQuote> quoteDomain(String domain) async {
    _requireUser();
    try {
      final result = await _client.rpc(
        'pandora_quote_domain_checkout',
        params: <String, Object?>{
          'p_organization_id': _organizationId,
          'p_domain': domain.trim(),
        },
      );
      return DomainQuote.fromJson(result);
    } on PostgrestException catch (error) {
      throw DomainRegistrarException(_plainMessage(error.message));
    }
  }

  Future<DomainCheckout> createCheckout({
    required String projectIdentifier,
    required DomainQuote quote,
    required DomainPaymentGateway gateway,
    required Map<String, Object?> contactInformation,
    bool autoRenewRequested = false,
    String? idempotencyKey,
  }) async {
    _requireUser();
    if (!quote.available ||
        quote.displayPrice == null ||
        quote.quoteId.isEmpty) {
      throw const DomainRegistrarException(
        'Get a fresh domain price before continuing.',
      );
    }
    try {
      final result = await _client.rpc(
        'pandora_create_domain_checkout',
        params: <String, Object?>{
          'p_organization_id': _organizationId,
          'p_project_identifier': projectIdentifier.trim(),
          'p_quote_id': quote.quoteId,
          'p_gateway': gateway.wireValue,
          'p_contact_information': contactInformation,
          'p_auto_renew_requested': autoRenewRequested,
          'p_idempotency_key':
              idempotencyKey ?? _keys.create('domain-checkout'),
        },
      );
      return DomainCheckout.fromJson(result);
    } on PostgrestException catch (error) {
      throw DomainRegistrarException(_plainMessage(error.message));
    }
  }

  Future<DomainCheckout> reconcileCheckout(String checkoutId) async {
    _requireUser();
    try {
      final result = await _client.rpc(
        'pandora_reconcile_domain_checkout',
        params: <String, Object?>{
          'p_organization_id': _organizationId,
          'p_checkout_id': checkoutId.trim(),
        },
      );
      return DomainCheckout.fromJson(result);
    } on PostgrestException catch (error) {
      throw DomainRegistrarException(_plainMessage(error.message));
    }
  }

  void _requireUser() {
    if (_client.auth.currentUser == null) {
      throw const DomainRegistrarException(
        'Please sign in again before buying a domain.',
      );
    }
  }

  String _plainMessage(String providerMessage) {
    final message = providerMessage.toUpperCase();
    if (message.contains('XENDIT_NOT_CONFIGURED')) {
      return 'Xendit is not connected to Pandora’s Box yet.';
    }
    if (message.contains('PAYPAL_NOT_CONFIGURED')) {
      return 'PayPal is not connected to Pandora’s Box yet.';
    }
    if (message.contains('QUOTE_EXPIRED')) {
      return 'That price expired. Search again for a fresh price.';
    }
    if (message.contains('PRICE_CONFIRMATION')) {
      return 'The price changed. Search again before continuing.';
    }
    if (message.contains('CONTACT')) {
      return 'Check the registration contact details and try again.';
    }
    if (message.contains('OWNER_ROLE') || message.contains('PERMISSION')) {
      return 'You do not have permission to buy a domain for this account.';
    }
    if (message.contains('PROJECT_NOT_FOUND')) {
      return 'Choose a project before buying this domain.';
    }
    if (message.contains('PAYMENT_GATEWAY')) {
      return 'Choose Xendit or PayPal to continue.';
    }
    if (message.contains('CHECKOUT')) {
      return 'Pandora’s Box could not start that payment checkout.';
    }
    return 'Pandora could not complete the domain request right now.';
  }
}

class DomainRegistrarException implements Exception {
  const DomainRegistrarException(this.message);
  final String message;
  @override
  String toString() => message;
}
