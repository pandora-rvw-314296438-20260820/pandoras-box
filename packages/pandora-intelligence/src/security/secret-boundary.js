'use strict';

const FORBIDDEN_SECRET_KEYS = Object.freeze([
  'github_pat',
  'github_token',
  'github_supabase',
  'supabase_service_role',
  'service_role_key',
  'vercel_token',
  'gemini_api_key',
  'moonshot_api_key',
  'kimi_api_key',
  'openai_api_key',
  'anthropic_api_key',
  'database_password',
  'signing_key',
  'private_key',
  'authorization',
  'cookie',
  'set-cookie',
]);

const SECRET_VALUE_PATTERNS = Object.freeze([
  /gh[pousr]_[A-Za-z0-9_]{20,}/,
  /sk-[A-Za-z0-9_-]{20,}/,
  /AIza[0-9A-Za-z_-]{20,}/,
  /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,
  /(?:postgres(?:ql)?):\/\/[^\s:@]+:[^\s@]+@/i,
]);

/**
 * @param {unknown} value
 * @param {string} path
 * @param {string[]} findings
 * @param {WeakSet<object>} seen
 */
function scan(value, path, findings, seen) {
  if (typeof value === 'string') {
    if (SECRET_VALUE_PATTERNS.some((pattern) => pattern.test(value))) {
      findings.push(`${path}: credential-like value`);
    }
    return;
  }

  if (!value || typeof value !== 'object') return;
  if (seen.has(value)) return;
  seen.add(value);

  if (Array.isArray(value)) {
    value.forEach((item, index) => scan(item, `${path}[${index}]`, findings, seen));
    return;
  }

  for (const [key, nested] of Object.entries(value)) {
    const normalized = key
      .replace(/([a-z0-9])([A-Z])/g, '$1_$2')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '_');
    if (
      FORBIDDEN_SECRET_KEYS.includes(normalized) ||
      normalized.endsWith('_secret') ||
      normalized.endsWith('_password')
    ) {
      findings.push(`${path}.${key}: forbidden secret-bearing field`);
      continue;
    }
    scan(nested, `${path}.${key}`, findings, seen);
  }
}

/** @param {unknown} value */
function findCredentialMaterial(value) {
  /** @type {string[]} */
  const findings = [];
  scan(value, '$', findings, new WeakSet());
  return findings;
}

/** @param {unknown} value */
function assertNoCredentialMaterial(value) {
  const findings = findCredentialMaterial(value);
  if (findings.length) {
    throw new Error(`credential material rejected: ${findings.join('; ')}`);
  }
  return value;
}

module.exports = {
  FORBIDDEN_SECRET_KEYS,
  SECRET_VALUE_PATTERNS,
  assertNoCredentialMaterial,
  findCredentialMaterial,
};
