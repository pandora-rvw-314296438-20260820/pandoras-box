'use strict';
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const migration = readFileSync(
  join(__dirname, '..', 'supabase', 'migrations', '20260831061500_pandora_worker_i_live_trust_verification_v1.sql'),
  'utf8',
);

test('Worker I TRUSTED promotion requires persisted exact Worker E evidence', () => {
  assert.match(migration, /create table if not exists public\.pandora_primitive_verification_runs/i);
  assert.match(migration, /pandora_guard_primitive_trust_promotion_20260831/i);
  assert.match(migration, /TRUSTED primitive promotion requires persisted Worker E evidence/);
  assert.match(migration, /status <> 'PASS'/);
  assert.match(migration, /source_digest <> new\.source_digest/);
  assert.match(migration, /verifier_identity <> 'worker-e-primitive-static-v1'/);
});

test('Worker E re-reads immutable GitHub source through the canonical integration transport', () => {
  assert.match(migration, /pandora_integration_github_api_20260825/g);
  assert.match(migration, /\?ref=' \|\| v_catalog\.source_commit/);
  assert.match(migration, /bundleDigest' <> v_catalog\.source_digest/);
  assert.match(migration, /primitive source file digest mismatch/);
  assert.match(migration, /security\.secret_scan/);
  assert.match(migration, /security\.static_policy/);
  assert.match(migration, /authoritative_issuer','pandora-verification-engine'/);
});

test('primitive trust verifier is service-role only and catalog remains fail closed', () => {
  assert.match(migration, /force row level security/i);
  assert.match(migration, /revoke all on public\.pandora_primitive_verification_runs from public, anon, authenticated, service_role/i);
  assert.match(migration, /revoke all on function public\.pandora_worker_e_verify_primitive_20260831\(text,text\) from public, anon, authenticated/i);
  assert.match(migration, /grant execute on function public\.pandora_worker_e_verify_primitive_20260831\(text,text\) to service_role/i);
});
