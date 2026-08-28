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

  // The installed APK proved the currently deployed Vercel compatibility route
  // returns HTTP 404 for owner screens. The original Pandora client contract
  // targets this Supabase Edge Function, using the signed-in user's JWT.
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

  static const appVersion = String.fromEnvironment(
    'PANDORA_APP_VERSION',
    defaultValue: '0.3.0-rc.3+6',
  );
  static String get releaseLabel => '${appVersion.split('+').first} Owner Test';
  static const artifactClass = 'Owner Test — Android debug signed';
  static const productionRelease = false;

  static const sourceRevision = String.fromEnvironment(
    'PANDORA_SOURCE_REVISION',
    defaultValue: 'local-development',
  );

  // A fallback is intentionally absent. The Vercel operator route implements
  // a different contract, and retrying a mutation after an ambiguous outcome
  // could duplicate work. Contract parity must be proven before another base
  // can be offered explicitly.
  static const ownerApiEndpointLabel = 'Supabase owner API';
}
