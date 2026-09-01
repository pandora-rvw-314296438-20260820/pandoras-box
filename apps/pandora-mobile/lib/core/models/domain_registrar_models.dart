import 'pandora_models.dart';

enum DomainPaymentGateway {
  xendit('xendit', 'Xendit'),
  paypal('paypal', 'PayPal');

  const DomainPaymentGateway(this.wireValue, this.label);

  final String wireValue;
  final String label;
}

class DomainQuote {
  const DomainQuote({
    required this.quoteId,
    required this.domain,
    required this.available,
    required this.currency,
    required this.contactSchema,
    this.years = 1,
    this.purchasePrice,
    this.retailPrice,
    this.wholesalePurchasePrice,
    this.renewalPrice,
    this.markupBps = 0,
    this.expiresAt,
  });

  final String quoteId;
  final String domain;
  final bool available;
  final int years;
  final double? purchasePrice;
  final double? retailPrice;
  final double? wholesalePurchasePrice;
  final double? renewalPrice;
  final String currency;
  final int markupBps;
  final DateTime? expiresAt;
  final JsonMap contactSchema;

  double? get displayPrice => retailPrice ?? purchasePrice;

  String get formattedPurchasePrice => _formatMoney(displayPrice, currency);

  bool get hasUnsupportedAdditionalContactFields {
    if (contactSchema.isEmpty) return false;
    final required = asJsonList(contactSchema['required'])
        .map(jsonText)
        .where((value) => value.isNotEmpty)
        .toSet();
    const supported = <String>{
      'firstName',
      'lastName',
      'email',
      'phone',
      'address1',
      'address2',
      'city',
      'state',
      'zip',
      'country',
      'companyName',
    };
    return required.any((field) => !supported.contains(field));
  }

  factory DomainQuote.fromJson(Object? value) {
    final json = asJsonMap(value);
    return DomainQuote(
      quoteId: jsonText(json['quoteId']),
      domain: jsonText(json['domain']),
      available: jsonBool(json['available']),
      years: _intValue(json['years'], 1),
      purchasePrice: _money(json['purchasePrice']),
      retailPrice: _money(json['retailPrice']),
      wholesalePurchasePrice: _money(json['wholesalePurchasePrice']),
      renewalPrice: _money(json['renewalPrice']),
      currency: jsonText(json['currency'], fallback: 'USD'),
      markupBps: _intValue(json['markupBps'], 0),
      expiresAt: jsonDateTime(json['expiresAt']),
      contactSchema: asJsonMap(json['contactSchema']),
    );
  }
}

class DomainCheckout {
  const DomainCheckout({
    required this.checkoutId,
    required this.domain,
    required this.gateway,
    required this.status,
    required this.currency,
    this.checkoutUrl,
    this.amount,
    this.projectId,
    this.providerStatus,
    this.plainMessage,
    this.expiresAt,
    this.purchase = const <String, Object?>{},
  });

  final String checkoutId;
  final String domain;
  final DomainPaymentGateway gateway;
  final String status;
  final String currency;
  final String? checkoutUrl;
  final double? amount;
  final String? projectId;
  final String? providerStatus;
  final String? plainMessage;
  final DateTime? expiresAt;
  final JsonMap purchase;

  bool get isFulfilled => status == 'fulfilled';
  bool get isRefunded => status == 'refunded';
  bool get isRefundPending => status == 'refund_pending';
  bool get needsAttention => status == 'needs_attention';
  bool get canOpenPayment =>
      status == 'pending' && checkoutUrl != null && checkoutUrl!.isNotEmpty;
  bool get canReconcile => const <String>{
        'pending',
        'paid',
        'fulfilling',
        'needs_attention',
      }.contains(status);

  String get formattedAmount => _formatMoney(amount, currency);

  factory DomainCheckout.fromJson(Object? value) {
    final json = asJsonMap(value);
    final gatewayWire = jsonText(json['gateway']).toLowerCase();
    final gateway = DomainPaymentGateway.values.firstWhere(
      (item) => item.wireValue == gatewayWire,
      orElse: () => DomainPaymentGateway.xendit,
    );
    return DomainCheckout(
      checkoutId: jsonText(json['checkoutId']),
      domain: jsonText(json['domain']),
      gateway: gateway,
      status: jsonText(json['status'], fallback: 'pending'),
      currency: jsonText(json['currency'], fallback: 'USD'),
      checkoutUrl: _optionalText(json['checkoutUrl']),
      amount: _money(json['amount']),
      projectId: _optionalText(json['projectId']),
      providerStatus: _optionalText(json['providerStatus']),
      plainMessage: _optionalText(json['plainMessage']),
      expiresAt: jsonDateTime(json['expiresAt']),
      purchase: asJsonMap(json['purchase']),
    );
  }
}

String _formatMoney(double? value, String currency) {
  if (value == null) return 'Price unavailable';
  final amount = value.toStringAsFixed(2);
  return switch (currency.toUpperCase()) {
    'USD' => r'$' + amount,
    'PHP' => '₱$amount',
    _ => '$amount ${currency.toUpperCase()}',
  };
}

double? _money(Object? value) {
  if (value is num) return value.toDouble();
  final text = jsonText(value);
  return text.isEmpty ? null : double.tryParse(text);
}

int _intValue(Object? value, int fallback) {
  if (value is num) return value.toInt();
  return int.tryParse(jsonText(value)) ?? fallback;
}

String? _optionalText(Object? value) {
  final text = jsonText(value);
  return text.isEmpty ? null : text;
}
