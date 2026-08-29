import 'pandora_models.dart';

class DomainQuote {
  const DomainQuote({
    required this.quoteId,
    required this.domain,
    required this.available,
    required this.currency,
    required this.contactSchema,
    this.years = 1,
    this.purchasePrice,
    this.renewalPrice,
    this.expiresAt,
  });

  final String quoteId;
  final String domain;
  final bool available;
  final int years;
  final double? purchasePrice;
  final double? renewalPrice;
  final String currency;
  final DateTime? expiresAt;
  final JsonMap contactSchema;

  String get formattedPurchasePrice =>
      purchasePrice == null ? 'Price unavailable' : '\$${purchasePrice!.toStringAsFixed(2)}';

  bool get hasUnsupportedAdditionalContactFields {
    if (contactSchema.isEmpty) return false;
    final required = asJsonList(contactSchema['required']).map(jsonText).where((value) => value.isNotEmpty).toSet();
    const supported = <String>{
      'firstName', 'lastName', 'email', 'phone', 'address1', 'address2',
      'city', 'state', 'zip', 'country', 'companyName',
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
      renewalPrice: _money(json['renewalPrice']),
      currency: jsonText(json['currency'], fallback: 'USD'),
      expiresAt: jsonDateTime(json['expiresAt']),
      contactSchema: asJsonMap(json['contactSchema']),
    );
  }
}

class DomainPurchaseReceipt {
  const DomainPurchaseReceipt({
    required this.ok,
    required this.domain,
    this.code,
    this.purchaseId,
    this.orderId,
    this.projectId,
    this.projectKey,
    this.projectName,
    this.status,
    this.connectionStatus,
    this.purchasePrice,
    this.currency = 'USD',
    this.years = 1,
    this.autoRenew = true,
    this.quoteId,
    this.expiresAt,
  });

  final bool ok;
  final String domain;
  final String? code;
  final String? purchaseId;
  final String? orderId;
  final String? projectId;
  final String? projectKey;
  final String? projectName;
  final String? status;
  final String? connectionStatus;
  final double? purchasePrice;
  final String currency;
  final int years;
  final bool autoRenew;
  final String? quoteId;
  final DateTime? expiresAt;

  factory DomainPurchaseReceipt.fromJson(Object? value) {
    final json = asJsonMap(value);
    return DomainPurchaseReceipt(
      ok: jsonBool(json['ok']),
      domain: jsonText(json['domain']),
      code: _optionalText(json['code']),
      purchaseId: _optionalText(json['purchaseId']),
      orderId: _optionalText(json['orderId']),
      projectId: _optionalText(json['projectId']),
      projectKey: _optionalText(json['projectKey']),
      projectName: _optionalText(json['projectName']),
      status: _optionalText(json['status']),
      connectionStatus: _optionalText(json['connectionStatus']),
      purchasePrice: _money(json['purchasePrice']),
      currency: jsonText(json['currency'], fallback: 'USD'),
      years: _intValue(json['years'], 1),
      autoRenew: json['autoRenew'] == null ? true : jsonBool(json['autoRenew']),
      quoteId: _optionalText(json['quoteId']),
      expiresAt: jsonDateTime(json['expiresAt']),
    );
  }
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
