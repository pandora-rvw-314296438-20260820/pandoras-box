'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const hardeningPath = path.join(
  __dirname,
  '..',
  'supabase',
  'migrations',
  '20260901194558_pandora_kimi_transport_security_hardening_v2.sql',
);
const hardening = fs.readFileSync(hardeningPath, 'utf8');
const {
  findCredentialMaterial,
} = require('../packages/pandora-intelligence/src/security/secret-boundary.js');

const FAKE = ['sk', 'moonshot-test-only', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ123456'].join('-');

test('Kimi transport v2 allowlists only the currently governed kimi-k3 model', () => {
  assert.match(hardening, /if v_model <> 'kimi-k3' then/);
  assert.match(hardening, /unsupported governed Moonshot model/);
  assert.doesNotMatch(hardening, /\^\(kimi-/);
});

test('Kimi transport v2 shares one bounded deadline across provider attempts', () => {
  assert.match(hardening, /v_provider_timeout_ms constant integer := 85000/);
  assert.match(hardening, /v_internal_deadline_ms constant integer := 89000/);
  assert.match(hardening, /v_deadline_at := clock_timestamp\(\) \+ interval '89 seconds'/);
  assert.match(hardening, /v_attempt_timeout_ms := least\(v_provider_timeout_ms, greatest\(1, v_remaining_ms - v_retry_guard_ms\)\)/);
  assert.match(hardening, /v_remaining_ms > \(v_sleep_ms \+ v_retry_guard_ms\)/);
  assert.match(hardening, /v_max_attempts constant integer := 2/);
  assert.match(hardening, /statement_timeout = '90s'/);
});

test('Kimi transport v2 preserves fixed host, Vault lookup and hard request/response consumption bounds', () => {
  assert.match(hardening, /where name='moonshot_api_key'/);
  assert.match(hardening, /https:\/\/api\.moonshot\.ai\/v1\/chat\/completions/);
  assert.match(hardening, /v_max_request_bytes constant integer := 1048576/);
  assert.match(hardening, /v_max_response_bytes constant integer := 2097152/);
  assert.doesNotMatch(hardening, /\bp_url\b|\bp_host\b|\bp_base_url\b/);
});

test('intelligence secret boundary rejects snake_case, camelCase and free-text Kimi/Moonshot credentials', () => {
  const findings = findCredentialMaterial({
    moonshot_api_key: FAKE,
    kimiApiKey: FAKE,
    text1: `moonshotApiKey=${FAKE}`,
    text2: `KIMI_API_KEY=${FAKE}`,
  });
  assert.ok(findings.length >= 4);
  assert.match(findings.join('\n'), /moonshot_api_key/);
  assert.match(findings.join('\n'), /kimiApiKey/);
});
