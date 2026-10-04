import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/config/pandora_runtime_binding.dart';
import 'package:pandora_mobile/pandora_config.dart';

import '../../helpers/acceptance_profile_fixture.dart';

void main() {
  final args = acceptanceProfileArguments();
  final fixture = acceptanceProfileVector();
  final fields =
      args.keys.where((key) => key.startsWith('acceptance')).toList();
  final production = <String, String?>{
    'runtimeProfile': 'production',
    for (final field in fields) field: null,
  };
  Matcher code(String value) => throwsA(isA<PandoraRuntimeBindingException>()
      .having((error) => error.code, 'fixed code', value)
      .having((error) => error.toString(), 'private error text', value));

  test(
      'Dart uses the shared compact canonical UTF8 vector and immutable headers',
      () {
    final binding = acceptanceProfileBinding();
    expect(binding.canonical, fixture['canonical']);
    expect(binding.canonicalJson, fixture['canonicalJson']);
    expect(binding.configSha256, fixture['configSha256']);
    expect(binding.headers, {
      'x-pandora-runtime-profile': 'core_acceptance_v1',
      'x-pandora-config-sha256': fixture['configSha256'],
      'x-pandora-source-sha': args['sourceRevision'],
    });
    expect(binding.canonicalJson, isNot(contains(args['publishableKey']!)));
    expect(binding.memoryMode, 'unavailable');
    expect(binding.allowLandingAttribution, isFalse);
    expect(() => binding.canonical['sourceSha'] = 'changed',
        throwsUnsupportedError);
    expect(() => binding.headers.clear(), throwsUnsupportedError);
  });

  test(
      'production defaults and existing clients remain unchanged without markers',
      () {
    expect(
        PandoraConfig.runtimeBinding, same(PandoraRuntimeBinding.production));
    final binding = acceptanceProfileBinding(overrides: production);
    expect(binding, same(PandoraRuntimeBinding.production));
    expect(binding.headers, isEmpty);
    expect(binding.memoryMode, 'production');
    expect(binding.allowLandingAttribution, isTrue);
    binding.requireClient(
        restUrl: 'https://existing.invalid/rest/v1',
        organizationId: 'existing-scope',
        functionHeaders: const {'apikey': 'test'});
  });

  for (final field in fields) {
    for (final absent in [null, '']) {
      test('acceptance rejects $field ${absent == null ? 'missing' : 'empty'}',
          () {
        expect(() => acceptanceProfileBinding(overrides: {field: absent}),
            code('ACCEPTANCE_CONFIG_INCOMPLETE'));
      });
    }
    for (final orphan in ['', args[field]]) {
      test('production rejects defined orphan $field ${orphan?.isEmpty}', () {
        expect(
            () => acceptanceProfileBinding(
                overrides: {...production, field: orphan}),
            code('ACCEPTANCE_ORPHAN_CONFIG'));
      });
    }
  }

  for (final profile in ['', 'acceptance', 'CORE_ACCEPTANCE_V1']) {
    test('unknown profile cannot fall back to production: $profile', () {
      expect(
          () =>
              acceptanceProfileBinding(overrides: {'runtimeProfile': profile}),
          code('ACCEPTANCE_PROFILE_INVALID'));
    });
  }
  for (final ref in [
    'jcyqixttuebxqqfkjonq',
    'ivmvufhcsezyhczzondn',
    'not-a-project',
    'ABCDEFGHIJKLMNOPQRST',
    'jcyqixttuebxqqfkjonq\n',
    'abcdefghijklmnopqrst\n',
  ]) {
    test('rejects forbidden or malformed project $ref', () {
      expect(
          () => acceptanceProfileBinding(
              overrides: {'acceptanceProjectRef': ref}),
          code('ACCEPTANCE_PROJECT_INVALID'));
    });
  }
  test('UUID/source/digest validation rejects malformed identifiers privately',
      () {
    expect(
        () => acceptanceProfileBinding(
            overrides: {'acceptanceOrganizationId': 'raw-private-value'}),
        code('ACCEPTANCE_ORGANIZATION_INVALID'));
    for (final source in ['local-development', 'a' * 39, 'A' * 40]) {
      expect(
          () => acceptanceProfileBinding(
              overrides: {'acceptanceSourceSha': source}),
          code('ACCEPTANCE_SOURCE_MISMATCH'));
    }
    expect(
        () => acceptanceProfileBinding(overrides: {'sourceRevision': 'a' * 40}),
        code('ACCEPTANCE_SOURCE_MISMATCH'));
    for (final field in [
      'acceptancePublishableKeySha256',
      'acceptanceConfigSha256'
    ]) {
      expect(
          () => acceptanceProfileBinding(overrides: {field: 'INVALID-DIGEST'}),
          code('ACCEPTANCE_DIGEST_INVALID'));
    }
  });
  for (final field in [
    'supabaseUrl',
    'organizationId',
    'ownerApiBaseUrl',
    'projectRuntimeApiBaseUrl'
  ]) {
    test('effective $field cannot differ from the acceptance target', () {
      expect(() => acceptanceProfileBinding(overrides: {field: 'wrong-target'}),
          code('ACCEPTANCE_TARGET_MISMATCH'));
    });
  }
  test('key and canonical digests must both match without exposing key values',
      () {
    expect(
        () => acceptanceProfileBinding(overrides: {
              'publishableKey': 'sb_publishable_different_test_value'
            }),
        code('ACCEPTANCE_KEY_MISMATCH'));
    expect(
        () => acceptanceProfileBinding(
            overrides: {'acceptanceConfigSha256': '0' * 64}),
        code('ACCEPTANCE_CONFIG_MISMATCH'));
  });

  String jwt(Object payload) =>
      '${base64Url.encode(utf8.encode('{"alg":"HS256"}')).replaceAll('=', '')}.'
      '${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}.test_signature';
  test('only a public client key or target-bound anon JWT is accepted', () {
    final key = jwt({'role': 'anon', 'ref': args['acceptanceProjectRef']});
    final digest = sha256.convert(utf8.encode(key)).toString();
    final canonical = Map<String, dynamic>.from(fixture['canonical'] as Map)
      ..['publishableKeySha256'] = digest;
    final binding = acceptanceProfileBinding(overrides: {
      'publishableKey': key,
      'acceptancePublishableKeySha256': digest,
      'acceptanceConfigSha256':
          sha256.convert(utf8.encode(jsonEncode(canonical))).toString(),
    });
    expect(binding.isAcceptance, isTrue);
    for (final invalid in [
      'sb_secret_test_only',
      'sb_publishable_short',
      'raw-private-value',
      'x.malformed!.z',
      jwt({'role': 'service_role', 'ref': args['acceptanceProjectRef']}),
      jwt({'role': 'anon', 'ref': 'wrong-project'}),
      jwt(['not', 'claims']),
    ]) {
      expect(
          () =>
              acceptanceProfileBinding(overrides: {'publishableKey': invalid}),
          code('ACCEPTANCE_PUBLIC_KEY_REQUIRED'));
    }
  });

  test('canonical identifiers and keys reject trailing line terminators', () {
    for (final suffix in ['\n', '\r', '\r\n']) {
      for (final entry in {
        'acceptanceOrganizationId': 'ACCEPTANCE_ORGANIZATION_INVALID',
        'acceptanceSourceSha': 'ACCEPTANCE_SOURCE_MISMATCH',
        'acceptancePublishableKeySha256': 'ACCEPTANCE_DIGEST_INVALID',
        'acceptanceConfigSha256': 'ACCEPTANCE_DIGEST_INVALID',
        'publishableKey': 'ACCEPTANCE_PUBLIC_KEY_REQUIRED',
      }.entries) {
        expect(
          () => acceptanceProfileBinding(overrides: {
            entry.key: '${args[entry.key]}$suffix',
          }),
          code(entry.value),
        );
      }
    }
  });

  test('runtime client drift and forged inherited markers are rejected', () {
    final binding = acceptanceProfileBinding();
    void validate({String? url, String? org, Map<String, String>? headers}) =>
        binding.requireClient(
            restUrl: url ?? '${args['supabaseUrl']}/rest/v1',
            organizationId: org ?? args['organizationId']!,
            functionHeaders: headers ?? {'apikey': args['publishableKey']!});
    validate();
    expect(
        () => validate(url: 'https://jcyqixttuebxqqfkjonq.supabase.co/rest/v1'),
        code('ACCEPTANCE_CLIENT_MISMATCH'));
    expect(
        () => validate(org: 'another-org'), code('ACCEPTANCE_CLIENT_MISMATCH'));
    expect(
        () => validate(
            headers: {'apikey': 'sb_publishable_wrong_test_public_key'}),
        code('ACCEPTANCE_KEY_MISMATCH'));
    expect(
        () => validate(headers: {
              'apikey': args['publishableKey']!,
              'X-Pandora-Source-Sha': 'a' * 40
            }),
        code('ACCEPTANCE_HEADER_MISMATCH'));
    expect(
        () => PandoraRuntimeBinding.production.requireClient(
            restUrl: '',
            organizationId: '',
            functionHeaders: const {'X-Pandora-Runtime-Profile': ''}),
        code('ACCEPTANCE_ORPHAN_HEADERS'));
  });
}
