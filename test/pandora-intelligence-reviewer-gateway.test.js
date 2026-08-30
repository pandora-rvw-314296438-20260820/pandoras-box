
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const migrationPath = new URL('../supabase/migrations/20260830220000_pandora_intelligence_reviewer_gateway_v1.sql', import.meta.url);
const edgePath = new URL('../supabase/functions/pandora-intelligence-review-attestation/index.ts', import.meta.url);
const [migration, edge] = await Promise.all([readFile(migrationPath, 'utf8'), readFile(edgePath, 'utf8')]);

test('reviewer enrollment is independent, fresh, canonical-repo bound, and grants no scope by default', () => {
  assert.match(migration, /create table if not exists private\.intelligence_reviewer_identities/i);
  assert.match(migration, /create table if not exists private\.intelligence_reviewer_scope_grants/i);
  assert.match(migration, /session_user<>'postgres'/i);
  assert.match(migration, /projectos\.intelligence\.verify/i);
  assert.match(migration, /pandora-rvw-314296438-20260820\/pandoras-box/i);
  assert.match(migration, /proof\.verified_by<>proof\.agent_key/i);
  assert.match(migration, /proof\.expires_at>now\(\)/i);
  assert.doesNotMatch(migration, /insert into private\.intelligence_reviewer_scope_grants[\s\S]{0,500}'global'/i);
});

test('global review requires an explicit short-lived grant and cannot outlive the reviewer proof', () => {
  assert.match(migration, /v_max_ttl := case when v_scope='global' then interval '30 minutes' else interval '2 hours' end/i);
  assert.match(migration, /review scope cannot outlive reviewer runtime proof/i);
  assert.match(migration, /explicit intelligence review scope grant required/i);
  assert.match(migration, /active explicit intelligence review grant required/i);
});

test('legacy direct Worker-E certification is retired from reviewer role', () => {
  assert.match(migration, /revoke execute on function public\.pandora_worker_e_certify_intelligence_asset[\s\S]*from projectos_reviewer_ingest/i);
  assert.match(migration, /grant execute on function public\.pandora_finalize_intelligence_review_attestation[\s\S]*to projectos_reviewer_ingest/i);
  assert.doesNotMatch(migration, /grant execute on function public\.pandora_worker_e_certify_intelligence_asset[\s\S]{0,200}to projectos_reviewer_ingest/i);
});

test('signed attestation is exact-digest, nonce, reviewer-key and JWT bound before TRUSTED', () => {
  assert.match(migration, /create table if not exists private\.intelligence_review_attestations/i);
  assert.match(migration, /unique \(reviewer_id,reviewer_nonce_sha256\)/i);
  assert.match(migration, /pandora-intelligence-review-v1/i);
  assert.match(migration, /pandora:intelligence-certify:v1/i);
  assert.match(migration, /key_fingerprint<>v_att\.key_fingerprint/i);
  assert.match(migration, /perform private\.pandora_assert_intelligence_certifier\(v_att\.scope_key,v_att\.reviewer_id,v_att\.request_sha256\)/i);
  assert.match(migration, /set_config\('pandora\.worker_e_certification',v_att\.asset_id::text,true\)/i);
  assert.match(migration, /verification_worker='E',verification_verdict='PASS'/i);
});

test('Edge gateway validates exact reviewer JWT and Ed25519 signature before recording attestation', () => {
  assert.match(edge, /projectos_reviewer_ingest/);
  assert.match(edge, /pandora-independent-review-authority/);
  assert.match(edge, /pandora-intelligence-certification/);
  assert.match(edge, /intelligence_asset_certification/);
  assert.match(edge, /crypto\.subtle\.importKey/[Symbol.match] ? /crypto\.subtle\.importKey/ : /crypto\.subtle\.importKey/);
  assert.match(edge, /name: "Ed25519"/);
  assert.match(edge, /REVIEW_SIGNATURE_INVALID/);
  assert.match(edge, /pandora_resolve_intelligence_review_target/);
  assert.match(edge, /pandora_record_intelligence_review_attestation/);
  assert.match(edge, /pandora_finalize_intelligence_review_attestation/);
  assert.doesNotMatch(edge, /eval\(|new Function\(/);
});

test('Edge gateway is bounded, rejects unknown fields, and caps trust expiry', () => {
  assert.match(edge, /MAX_BODY_BYTES = 24 \* 1024/);
  assert.match(edge, /UNKNOWN_FIELD/);
  assert.match(edge, /90 \* 24 \* 60 \* 60 \* 1000/);
  assert.match(edge, /Math\.abs\(Date\.now\(\) - signedAt\) > 300_000/);
});
