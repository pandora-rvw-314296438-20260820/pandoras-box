'use strict';
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const migration = readFileSync(
  join(__dirname, '..', 'supabase', 'migrations', '20260910081625_pandora_worker_e_catalog_trust_bootstrap_v1.sql'),
  'utf8',
);
const worker = readFileSync(
  join(__dirname, '..', 'supabase', 'functions', 'pandora-source-convergence-worker', 'index.ts'),
  'utf8',
);

test('catalog bootstrap RPC loops EXPERIMENTAL/lacking TRUSTED+evidence via Worker E verify', () => {
  assert.match(migration, /pandora_worker_e_verify_catalog_experimental_20260910/);
  assert.match(migration, /private\.pandora_worker_e_verify_primitive_20260831/);
  assert.match(migration, /trust_state = 'TRUSTED'/);
  assert.match(migration, /worker_e_evidence_ref/);
  assert.match(migration, /passCount/);
  assert.match(migration, /failCount/);
  assert.match(migration, /results/);
  assert.doesNotMatch(migration, /perform pandora_worker_e_verify_catalog_experimental_20260910\(\)/i);
  assert.doesNotMatch(migration, /select public\.pandora_worker_e_verify_catalog_experimental_20260910\(\)/i);
});

test('catalog bootstrap RPC is service_role-only', () => {
  assert.match(
    migration,
    /revoke all on function public\.pandora_worker_e_verify_catalog_experimental_20260910\(\)\s+from public, anon, authenticated/i,
  );
  assert.match(
    migration,
    /grant execute on function public\.pandora_worker_e_verify_catalog_experimental_20260910\(\)\s+to service_role/i,
  );
});

test('source convergence self-heals once via bootstrap then re-resolves fail-closed', () => {
  assert.match(worker, /pandora_worker_e_verify_catalog_experimental_20260910/);
  assert.match(worker, /resolveTrustedPrimitives/);
  assert.match(worker, /p_require_trusted: true/);
  assert.match(worker, /Once-per-attempt self-heal/);
  assert.match(worker, /TRUSTED_PRIMITIVE_UNAVAILABLE/);
  assert.match(worker, /blockedPrimitives/);
  assert.match(worker, /public_error_summary/);
  assert.match(worker, /required building blocks are not available yet \(\$\{blocked\.join/);
  assert.doesNotMatch(worker, /p_require_trusted:\s*false/);
});

test('theatre surfaces blocked_names for TRUSTED_PRIMITIVE_UNAVAILABLE', () => {
  assert.match(migration, /pandora_trusted_primitive_unavailable_message_20260910/);
  assert.match(migration, /blocked_names/);
  assert.match(migration, /required building blocks are not available yet \(/);
  assert.match(migration, /pandora_sync_build_theatre_from_job/);
  assert.match(migration, /pandora_fail_preexecution_job_from_source_queue_v1/);
  assert.doesNotMatch(
    migration.match(/v_message := case[\s\S]*?end;/)?.[0] ?? '',
    /continuing this project in the background/,
  );
});
