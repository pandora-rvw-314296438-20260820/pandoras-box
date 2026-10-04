import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Fixed codes only: malformed inputs, URLs and key material never enter errors.
class PandoraRuntimeBindingException implements Exception {
  const PandoraRuntimeBindingException(this.code);
  final String code;

  @override
  String toString() => code;
}

/// Validated build provenance, not permission to change the configured backend.
/// No client key or authentication credential is retained in this value.
class PandoraRuntimeBinding {
  const PandoraRuntimeBinding._({
    required this.profile,
    this.canonical = const {},
    this.configSha256,
  });

  static const production = PandoraRuntimeBinding._(profile: 'production');
  static const acceptanceProfile = 'core_acceptance_v1';
  static const metadataHeaders = {
    'x-pandora-runtime-profile',
    'x-pandora-config-sha256',
    'x-pandora-source-sha',
  };
  static final _ref = RegExp(r'^[a-z0-9]{20}$');
  static final _source = RegExp(r'^[0-9a-f]{40}$');
  static final _digest = RegExp(r'^[0-9a-f]{64}$');
  static final _organization = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

  final String profile;
  final Map<String, String> canonical;
  final String? configSha256;
  bool get isAcceptance => profile == acceptanceProfile;
  bool get allowLandingAttribution => !isAcceptance;
  String get memoryMode => isAcceptance ? 'unavailable' : 'production';
  String get canonicalJson => jsonEncode(canonical);

  factory PandoraRuntimeBinding.fromConfiguration({
    String runtimeProfile = 'production',
    String? acceptanceProjectRef,
    String? acceptanceOrganizationId,
    String? acceptanceSourceSha,
    String? acceptancePublishableKeySha256,
    String? acceptanceConfigSha256,
    required String supabaseUrl,
    required String publishableKey,
    required String organizationId,
    required String sourceRevision,
    required String ownerApiBaseUrl,
    required String projectRuntimeApiBaseUrl,
  }) {
    final acceptanceFields = [
      acceptanceProjectRef,
      acceptanceOrganizationId,
      acceptanceSourceSha,
      acceptancePublishableKeySha256,
      acceptanceConfigSha256,
    ];
    if (runtimeProfile == 'production') {
      if (acceptanceFields.any((field) => field != null)) {
        throw const PandoraRuntimeBindingException('ACCEPTANCE_ORPHAN_CONFIG');
      }
      return production;
    }
    if (runtimeProfile != acceptanceProfile) {
      throw const PandoraRuntimeBindingException('ACCEPTANCE_PROFILE_INVALID');
    }
    if (acceptanceFields.any((field) => field == null || field.isEmpty)) {
      throw const PandoraRuntimeBindingException(
          'ACCEPTANCE_CONFIG_INCOMPLETE');
    }
    final ref = acceptanceProjectRef!;
    if (!_matches(_ref, ref) ||
        const {'jcyqixttuebxqqfkjonq', 'ivmvufhcsezyhczzondn'}.contains(ref)) {
      throw const PandoraRuntimeBindingException('ACCEPTANCE_PROJECT_INVALID');
    }
    if (!_matches(_organization, acceptanceOrganizationId!)) {
      throw const PandoraRuntimeBindingException(
          'ACCEPTANCE_ORGANIZATION_INVALID');
    }
    if (!_matches(_source, acceptanceSourceSha!) ||
        sourceRevision != acceptanceSourceSha) {
      throw const PandoraRuntimeBindingException('ACCEPTANCE_SOURCE_MISMATCH');
    }
    if (!_matches(_digest, acceptancePublishableKeySha256!) ||
        !_matches(_digest, acceptanceConfigSha256!)) {
      throw const PandoraRuntimeBindingException('ACCEPTANCE_DIGEST_INVALID');
    }
    final expectedUrl = 'https://$ref.supabase.co';
    if (supabaseUrl != expectedUrl ||
        ownerApiBaseUrl != '$expectedUrl/functions/v1/pandora-owner-api' ||
        projectRuntimeApiBaseUrl !=
            '$expectedUrl/functions/v1/pandora-project-runtime' ||
        organizationId != acceptanceOrganizationId) {
      throw const PandoraRuntimeBindingException('ACCEPTANCE_TARGET_MISMATCH');
    }
    _requirePublicKey(publishableKey, ref);
    if (_sha(publishableKey) != acceptancePublishableKeySha256) {
      throw const PandoraRuntimeBindingException('ACCEPTANCE_KEY_MISMATCH');
    }
    // This insertion order is shared with the producer and server validator.
    final canonical = <String, String>{
      'profile': acceptanceProfile,
      'sourceSha': acceptanceSourceSha,
      'supabaseProjectRef': ref,
      'supabaseUrl': expectedUrl,
      'publishableKeySha256': acceptancePublishableKeySha256,
      'organizationId': acceptanceOrganizationId,
      'ownerApiBaseUrl': ownerApiBaseUrl,
      'projectRuntimeApiBaseUrl': projectRuntimeApiBaseUrl,
      'memoryMode': 'unavailable',
    };
    if (_sha(jsonEncode(canonical)) != acceptanceConfigSha256) {
      throw const PandoraRuntimeBindingException('ACCEPTANCE_CONFIG_MISMATCH');
    }
    return PandoraRuntimeBinding._(
      profile: acceptanceProfile,
      canonical: Map.unmodifiable(canonical),
      configSha256: acceptanceConfigSha256,
    );
  }

  /// Check the actual SDK target and key before use; never reconfigure a client.
  /// The Supabase SDK exposes its constructed base through rest.url.
  void requireClient({
    required String restUrl,
    required String organizationId,
    required Map<String, String> functionHeaders,
  }) {
    if (!isAcceptance) {
      if (functionHeaders.keys
          .any((key) => metadataHeaders.contains(key.toLowerCase()))) {
        throw const PandoraRuntimeBindingException('ACCEPTANCE_ORPHAN_HEADERS');
      }
      return;
    }
    if (restUrl != '${canonical['supabaseUrl']}/rest/v1' ||
        organizationId != canonical['organizationId']) {
      throw const PandoraRuntimeBindingException('ACCEPTANCE_CLIENT_MISMATCH');
    }
    final key = functionHeaders['apikey'] ?? '';
    _requirePublicKey(key, canonical['supabaseProjectRef']!);
    if (_sha(key) != canonical['publishableKeySha256']) {
      throw const PandoraRuntimeBindingException('ACCEPTANCE_KEY_MISMATCH');
    }
    for (final entry in functionHeaders.entries) {
      final name = entry.key.toLowerCase();
      if (metadataHeaders.contains(name) && entry.value != headers[name]) {
        throw const PandoraRuntimeBindingException(
            'ACCEPTANCE_HEADER_MISMATCH');
      }
    }
  }

  Map<String, String> get headers => isAcceptance
      ? Map.unmodifiable({
          'x-pandora-runtime-profile': profile,
          'x-pandora-config-sha256': configSha256!,
          'x-pandora-source-sha': canonical['sourceSha']!,
        })
      : const {};

  /// A correctly configured client must not accept another runtime's reply.
  void requireResponseHeaders(Map<String, String> received) {
    if (!isAcceptance) return;
    for (final expected in headers.entries) {
      final values = received.entries
          .where((entry) => entry.key.toLowerCase() == expected.key)
          .map((entry) => entry.value)
          .toList();
      if (values.length != 1 || values.single != expected.value) {
        throw const PandoraRuntimeBindingException(
            'ACCEPTANCE_RESPONSE_MISMATCH');
      }
    }
  }

  // In Dart/JavaScript, $ may match before a final line terminator. Every
  // canonical identifier must consume the complete value, like Python fullmatch.
  static bool _matches(RegExp expression, String value) {
    final match = expression.firstMatch(value);
    return match != null && match.start == 0 && match.end == value.length;
  }

  static String _sha(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static void _requirePublicKey(String key, String ref) {
    if (_matches(RegExp(r'^sb_publishable_[A-Za-z0-9_-]{16,}$'), key)) return;
    try {
      final parts = key.split('.');
      if (parts.length == 3 &&
          parts.every((part) => _matches(RegExp(r'^[A-Za-z0-9_-]+$'), part))) {
        final payload = jsonDecode(
            utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
        if (payload is Map &&
            payload['role'] == 'anon' &&
            payload['ref'] == ref) {
          return;
        }
      }
    } catch (_) {
      // Never expose parser input or errors containing credential material.
    }
    throw const PandoraRuntimeBindingException(
        'ACCEPTANCE_PUBLIC_KEY_REQUIRED');
  }
}
