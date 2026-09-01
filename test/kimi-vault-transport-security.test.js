'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const { redactDeep, redactString } = require('../packages/pandora-tools/src/redaction.js');
const {
  findCredentialMaterial,
} = require('../packages/pandora-intelligence/src/security/secret-boundary.js');

const migrationPath = path.join(
  __dirname,
  '..',
  'supabase',
  'migrations',
  '20260902011500_pandora_kimi_vault_transport_v1.sql',
);
const migration = fs.readFileSync(migrationPath, 'utf8');

const FAKE_MOONSHOT_SECRET = ['sk', 'moonshot-test-only', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ123456'].join('-');

test('Kimi transport has one fixed HTTPS provider destination and rejects redirect following', () => {
  assert.match(migration, /https:\/\/api\.moonshot\.ai\/v1\/chat\/completions/);
  assert.match(migration, /redirects unless CURLOPT_FOLLOWLOCATION is enabled; Pandora never enables it/);
  assert.match(migration, /p_status in \(301,302,303,307,308\)/);
  assert.doesNotMatch(migration, /http_set_curlopt\('CURLOPT_FOLLOWLOCATION'/);
  assert.doesNotMatch(migration, /\bp_url\b|\bp_host\b|\bp_base_url\b/);
  assert.doesNotMatch(migration, /https?:\/\/['"]?\s*\|\|/);
});

test('Kimi transport is Vault-only and service-role-only', () => {
  const secretRead = migration.indexOf("where name='moonshot_api_key'");
  const outbound = migration.indexOf("'https://api.moonshot.ai/v1/chat/completions'");
  assert.ok(secretRead > 0);
  assert.ok(outbound > secretRead, 'Vault lookup must occur before any outbound provider call');
  assert.match(migration, /revoke all on function public\.pandora_kimi_chat_request_v1\(text,jsonb\) from public, anon, authenticated/);
  assert.match(migration, /grant execute on function public\.pandora_kimi_chat_request_v1\(text,jsonb\) to service_role/);
  assert.doesNotMatch(migration, /return\s+v_key/i);
});

test('Kimi transport bounds request, output, response, deadline, and attempts', () => {
  assert.match(migration, /v_max_request_bytes constant integer := 1048576/);
  assert.match(migration, /v_max_response_bytes constant integer := 2097152/);
  assert.match(migration, /v_max_output_tokens constant integer := 16384/);
  assert.match(migration, /CURLOPT_TIMEOUT_MS','85000'/);
  assert.match(migration, /statement_timeout = '90s'/);
  assert.match(migration, /v_max_attempts constant integer := 2/);
  assert.match(migration, /retry-after/);
  assert.match(migration, /v_retry_after_ms <= 2000/);
});

test('Kimi transport does not own or recurse into provider fallback', () => {
  assert.doesNotMatch(migration, /pandora_worker_b_gemini_request/i);
  assert.doesNotMatch(migration, /fallback\s*->|call\s+.*gemini/i);
  assert.match(migration, /'attempts', v_attempt/);
});

test('Kimi transport sanitizes provider errors and guards provider echo of Vault material', () => {
  assert.match(migration, /position\(v_key in v_response_text\) > 0/);
  assert.match(migration, /provider response failed secret-leak guard/);
  assert.match(migration, /providerCode', v_provider_type/);
  assert.doesNotMatch(migration, /'message',\s*v_provider_message/);
  assert.doesNotMatch(migration, /jsonb_build_object\('raw'/);
});

test('central redaction removes Kimi/Moonshot secret structures and inline forms', () => {
  const value = {
    moonshot_api_key: FAKE_MOONSHOT_SECRET,
    kimi_api_key: FAKE_MOONSHOT_SECRET,
    nested: {
      authorization: `Bearer ${FAKE_MOONSHOT_SECRET}`,
      text: `MOONSHOT_API_KEY=${FAKE_MOONSHOT_SECRET}`,
      url: `https://example.invalid/path?api_key=${FAKE_MOONSHOT_SECRET}&safe=1`,
    },
  };
  const redacted = JSON.stringify(redactDeep(value, { canaries: [FAKE_MOONSHOT_SECRET] }));
  assert.ok(!redacted.includes(FAKE_MOONSHOT_SECRET));
  assert.match(redacted, /\[REDACTED\]/);
  assert.equal(redactString(FAKE_MOONSHOT_SECRET), '[REDACTED]');
});

test('intelligence secret boundary rejects Kimi/Moonshot fields and raw bearer material', () => {
  const findings = findCredentialMaterial({
    moonshot_api_key: FAKE_MOONSHOT_SECRET,
    kimi_api_key: FAKE_MOONSHOT_SECRET,
    nested: `Bearer ${FAKE_MOONSHOT_SECRET}`,
  });
  assert.ok(findings.length >= 3);
  assert.match(findings.join('\n'), /moonshot_api_key/);
  assert.match(findings.join('\n'), /kimi_api_key/);
});

test('migration and regression fixtures contain no production credential value', () => {
  assert.ok(!migration.includes(FAKE_MOONSHOT_SECRET));
  assert.ok(!migration.includes('Kimi='), 'migration must not encode legacy secret assignments');
});
