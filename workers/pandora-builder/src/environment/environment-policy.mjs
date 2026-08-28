const DEFAULT_HOST_ENV_ALLOWLIST = new Set([
  'PATH', 'SystemRoot', 'WINDIR', 'TEMP', 'TMP', 'TMPDIR', 'LANG', 'LC_ALL', 'CI', 'NODE_ENV',
]);
const FORBIDDEN_PATTERNS = [
  /TOKEN/i, /SECRET/i, /PASSWORD/i, /PASSWD/i, /PRIVATE[_-]?KEY/i, /SERVICE[_-]?ROLE/i,
  /^AWS_/i, /^AZURE_/i, /^GOOGLE_/i, /^GITHUB_/i, /^GITLAB_/i, /^VERCEL_/i,
  /^SUPABASE_/i, /^OPENAI_/i, /^GEMINI_/i, /^SSH_/i,
];

function assertSafeEnvironmentName(name) {
  if (!/^[A-Z_][A-Z0-9_]{0,127}$/i.test(name)) throw new Error('INVALID_ENVIRONMENT_NAME');
  if (FORBIDDEN_PATTERNS.some((pattern) => pattern.test(name))) throw new Error('STANDING_SECRET_ENV_FORBIDDEN');
}

function normalizedEnvironment({ hostEnv = process.env, explicit = {}, hostAllowlist = DEFAULT_HOST_ENV_ALLOWLIST, explicitAllowlist = [] } = {}) {
  const output = {};
  for (const key of hostAllowlist) {
    if (Object.prototype.hasOwnProperty.call(hostEnv, key) && typeof hostEnv[key] === 'string') output[key] = hostEnv[key];
  }
  const allowed = new Set(explicitAllowlist);
  for (const [key, value] of Object.entries(explicit)) {
    assertSafeEnvironmentName(key);
    if (!allowed.has(key)) throw new Error('ENVIRONMENT_KEY_NOT_ALLOWED');
    if (typeof value !== 'string' || value.length > 16_384) throw new Error('INVALID_ENVIRONMENT_VALUE');
    output[key] = value;
  }
  output.HOME = '/tmp/pandora-home';
  output.GIT_CONFIG_NOSYSTEM = '1';
  output.GIT_TERMINAL_PROMPT = '0';
  return Object.freeze(output);
}

export { DEFAULT_HOST_ENV_ALLOWLIST, assertSafeEnvironmentName, normalizedEnvironment };
