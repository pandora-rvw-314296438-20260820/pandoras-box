'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { canContinueSourceBuilding } =
  require('../src/runtime/operations-source-release-policy.cjs');

const release = fs.readFileSync(
  'supabase/migrations/20260927020000_operations_source_release_fail_closed_v1.sql',
  'utf8',
);
const worker = fs.readFileSync('api/operations-native-worker.ts', 'utf8');

test('the replacement SQL release path cannot publish PASS, claim a merge, merge, or mark verified', () => {
  assert.match(release, /create or replace function public\.pandora_ops_generic_source_release_step_v1/);
  assert.match(release, /v_pr_body#>>'\{head,sha\}' is distinct from t\.head_sha/);
  assert.match(release, /commits\/'\|\|t\.head_sha\|\|'\/check-runs/);
  assert.match(release, /'state','release_authorization_required'/);
  assert.match(release, /'reviewStatus','unverified'/);
  assert.match(release, /'ownerReleaseAuthorization','unverified'/);
  assert.match(release, /different-vendor review for this exact PR and head SHA/);
  assert.match(release, /owner release authorization for this exact PR and head SHA/);
  assert.doesNotMatch(release, /pandora_coordinator_gate_invoke_v1|pandora_coordinator_vault_merge_v1/);
  assert.doesNotMatch(release, /pandora_ops_record_verification_v1|pandora_ops_verify_v1/);
  assert.doesNotMatch(release, /'decision','PASS'|'reviewId','not-required-by-ruleset'/);
});

test('a release awaiting human gates does not prevent the builder from handling another task', () => {
  assert.equal(canContinueSourceBuilding('release_authorization_required'), true);
  assert.equal(canContinueSourceBuilding('manual_reconciliation_required'), true);
  assert.equal(canContinueSourceBuilding('idle'), true);
  assert.match(worker, /if \(!canContinueSourceBuilding\(sourceRelease\?\.state\)\)/);
});

test('unknown or active coordinator states do not fall through to a new source build', () => {
  for (const state of [undefined, null, '', 'coordinator_publishing',
    'coordinator_claiming', 'checks_pending', 'checks_failed', 'complete']) {
    assert.equal(canContinueSourceBuilding(state), false, String(state));
  }
});
