'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const migration = fs.readFileSync(
  path.join(__dirname, '..', 'supabase', 'migrations', '20260831084000_pandora_worker_i_verification_run_lineage_v1.sql'),
  'utf8',
);

test('trusted project-version primitives bind the exact Worker E verification run', () => {
  assert.match(migration, /add column if not exists primitive_verification_run_id uuid/i);
  assert.match(migration, /foreign key \(primitive_verification_run_id\)[\s\S]*pandora_primitive_verification_runs\(id\)[\s\S]*on delete restrict/i);
  assert.match(migration, /trust_state = 'TRUSTED'[\s\S]*primitive_verification_run_id is null/i);
  assert.match(migration, /verifier_identity = 'worker-e-primitive-static-v1'/i);
  assert.match(migration, /r\.status = 'PASS'/i);
  assert.match(migration, /r\.primitive_name = p\.primitive_name/i);
  assert.match(migration, /r\.primitive_version = p\.primitive_version/i);
  assert.match(migration, /r\.source_digest = p\.source_digest/i);
  assert.match(migration, /r\.evidence_sha256 is not null/i);
});

test('database guard fails closed on missing or mismatched Worker E lineage', () => {
  assert.match(migration, /existing TRUSTED project-version primitive lacks exact Worker E verification-run lineage/i);
  assert.match(migration, /check \(trust_state <> 'TRUSTED' or primitive_verification_run_id is not null\)/i);
  assert.match(migration, /pandora_validate_primitive_verification_run_lineage_20260831/i);
  assert.match(migration, /v_run\.status <> 'PASS'/i);
  assert.match(migration, /v_run\.verifier_identity <> 'worker-e-primitive-static-v1'/i);
  assert.match(migration, /v_run\.primitive_name <> new\.primitive_name/i);
  assert.match(migration, /v_run\.primitive_version <> new\.primitive_version/i);
  assert.match(migration, /v_run\.source_digest <> new\.source_digest/i);
});
