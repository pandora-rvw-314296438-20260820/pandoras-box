import 'dart:convert';
import 'dart:io';

import 'package:pandora_mobile/core/config/pandora_runtime_binding.dart';

Map<String, dynamic> acceptanceProfileVector() =>
    jsonDecode(File('test/fixtures/core_acceptance_profile_v1.json')
        .readAsStringSync()) as Map<String, dynamic>;

Map<String, String?> acceptanceProfileArguments() {
  final fixture = acceptanceProfileVector();
  final value = fixture['canonical'] as Map<String, dynamic>;
  return {
    'runtimeProfile': value['profile'] as String,
    'acceptanceProjectRef': value['supabaseProjectRef'] as String,
    'acceptanceOrganizationId': value['organizationId'] as String,
    'acceptanceSourceSha': value['sourceSha'] as String,
    'acceptancePublishableKeySha256': value['publishableKeySha256'] as String,
    'acceptanceConfigSha256': fixture['configSha256'] as String,
    'supabaseUrl': value['supabaseUrl'] as String,
    'publishableKey': fixture['publishableKeyTestInput'] as String,
    'organizationId': value['organizationId'] as String,
    'sourceRevision': value['sourceSha'] as String,
    'ownerApiBaseUrl': value['ownerApiBaseUrl'] as String,
    'projectRuntimeApiBaseUrl': value['projectRuntimeApiBaseUrl'] as String,
  };
}

PandoraRuntimeBinding acceptanceProfileBinding(
    {Map<String, String?> overrides = const {}}) {
  final args = {...acceptanceProfileArguments(), ...overrides};
  return PandoraRuntimeBinding.fromConfiguration(
    runtimeProfile: args['runtimeProfile']!,
    acceptanceProjectRef: args['acceptanceProjectRef'],
    acceptanceOrganizationId: args['acceptanceOrganizationId'],
    acceptanceSourceSha: args['acceptanceSourceSha'],
    acceptancePublishableKeySha256: args['acceptancePublishableKeySha256'],
    acceptanceConfigSha256: args['acceptanceConfigSha256'],
    supabaseUrl: args['supabaseUrl']!,
    publishableKey: args['publishableKey']!,
    organizationId: args['organizationId']!,
    sourceRevision: args['sourceRevision']!,
    ownerApiBaseUrl: args['ownerApiBaseUrl']!,
    projectRuntimeApiBaseUrl: args['projectRuntimeApiBaseUrl']!,
  );
}
