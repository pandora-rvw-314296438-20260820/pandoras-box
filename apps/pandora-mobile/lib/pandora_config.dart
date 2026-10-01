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
  static const productionRelease = bool.fromEnvironment(
    'PANDORA_PRODUCTION_RELEASE',
    defaultValue: false,
  );

  static String get releaseLabel => productionRelease
      ? appVersion.split('+').first
      : '${appVersion.split('+').first} Owner Test';

  static String get artifactClass => productionRelease
      ? 'Production Release — Android release signed'
      : 'Owner Test — Android debug signed';

  static String get releaseStateLabel =>
      productionRelease ? 'Production release' : 'Not a production release';

  static const sourceRevision = String.fromEnvironment(
    'PANDORA_SOURCE_REVISION',
    defaultValue: 'local-development',
  );

  static const ownerApiEndpointLabel = 'Supabase owner API';
}