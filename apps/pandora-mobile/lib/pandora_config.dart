import 'core/config/pandora_runtime_binding.dart';

class PandoraConfig {
  PandoraConfig._();

  static const supabaseUrl = String.fromEnvironment(
    'PANDORA_SUPABASE_URL',
    defaultValue: 'https://jcyqixttuebxqqfkjonq.supabase.co',
  );

  // Public/publishable client key from the canonical operator config. Never put
  // service-role, PAT, Vercel, or other server credentials in this app.
  static const supabasePublishableKey = String.fromEnvironment(
    'PANDORA_SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_LGu6ncwUVEYI5THBjSV-3g_71AInQZt',
  );

  static const ownerApiBaseUrl = String.fromEnvironment(
    'PANDORA_OWNER_API_BASE_URL',
    defaultValue:
        'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-owner-api',
  );

  static const projectRuntimeApiBaseUrl = String.fromEnvironment(
    'PANDORA_PROJECT_RUNTIME_API_BASE_URL',
    defaultValue:
        'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-project-runtime',
  );

  static const organizationId = String.fromEnvironment(
    'PANDORA_ORGANIZATION_ID',
    defaultValue: '2270b266-59da-4c39-bfd9-9f8d08352af0',
  );

  static const plpOrganizationId = String.fromEnvironment(
    'PANDORA_PLP_ORGANIZATION_ID',
    defaultValue: '076a9306-5c4e-4d9d-98d3-e3a6fea968fb',
  );

  static const appVersion = String.fromEnvironment(
    'PANDORA_APP_VERSION',
    defaultValue: '0.4.0-rc.14+21',
  );
  static String get releaseLabel => '${appVersion.split('+').first} Owner Test';
  static const artifactClass = String.fromEnvironment(
    'PANDORA_ARTIFACT_CLASS',
    defaultValue: 'Owner Test — Android debug signed',
  );
  static const productionRelease = false;

  static const sourceRevision = String.fromEnvironment(
    'PANDORA_SOURCE_REVISION',
    defaultValue: 'local-development',
  );

  /// Validated before startup. Defined-but-empty fields remain visible so an
  /// orphan or partial acceptance build cannot fall back to production.
  static final runtimeBinding = PandoraRuntimeBinding.fromConfiguration(
    runtimeProfile: const String.fromEnvironment('PANDORA_RUNTIME_PROFILE',
        defaultValue: 'production'),
    acceptanceProjectRef:
        const bool.hasEnvironment('PANDORA_ACCEPTANCE_SUPABASE_PROJECT_REF')
            ? const String.fromEnvironment(
                'PANDORA_ACCEPTANCE_SUPABASE_PROJECT_REF')
            : null,
    acceptanceOrganizationId:
        const bool.hasEnvironment('PANDORA_ACCEPTANCE_ORGANIZATION_ID')
            ? const String.fromEnvironment('PANDORA_ACCEPTANCE_ORGANIZATION_ID')
            : null,
    acceptanceSourceSha:
        const bool.hasEnvironment('PANDORA_ACCEPTANCE_SOURCE_SHA')
            ? const String.fromEnvironment('PANDORA_ACCEPTANCE_SOURCE_SHA')
            : null,
    acceptancePublishableKeySha256:
        const bool.hasEnvironment('PANDORA_ACCEPTANCE_PUBLISHABLE_KEY_SHA256')
            ? const String.fromEnvironment(
                'PANDORA_ACCEPTANCE_PUBLISHABLE_KEY_SHA256')
            : null,
    acceptanceConfigSha256:
        const bool.hasEnvironment('PANDORA_ACCEPTANCE_CONFIG_SHA256')
            ? const String.fromEnvironment('PANDORA_ACCEPTANCE_CONFIG_SHA256')
            : null,
    supabaseUrl: supabaseUrl,
    publishableKey: supabasePublishableKey,
    organizationId: organizationId,
    sourceRevision: sourceRevision,
    ownerApiBaseUrl: ownerApiBaseUrl,
    projectRuntimeApiBaseUrl: projectRuntimeApiBaseUrl,
  );

  static const ownerApiEndpointLabel = 'Supabase owner API';
}
