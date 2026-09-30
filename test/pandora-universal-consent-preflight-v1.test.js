"use strict";

const assert=require("node:assert/strict");
const {readFileSync}=require("node:fs");
const {join}=require("node:path");
const {test}=require("node:test");

const migration=readFileSync(
  join(__dirname,"../supabase/migrations/20260930121000_pandora_capability_consent_preflight_v1.sql"),
  "utf8"
);

test("universal capability consent is fail closed and separate from exact-action approval",()=>{
  assert.match(migration,/consent_required boolean not null default false/);
  assert.match(migration,/consent_purpose text/);
  assert.match(migration,/consent_subject_required boolean not null default true/);
  assert.match(migration,/pandora_capability_consent_preflight_v1/);
  assert.match(migration,/pandora_capability_execution_preflight_v1/);
  assert.match(migration,/g\.revoked_at is null/);
  assert.match(migration,/g\.expires_at is null or g\.expires_at>clock_timestamp\(\)/);
  assert.match(migration,/g\.subject_entity_id is not distinct from p_subject_entity_id/);
  assert.match(migration,/g\.purpose=v_expected_purpose/);
  assert.match(migration,/consent_revoked/);
  assert.match(migration,/consent_expired/);
  assert.match(migration,/consent_missing/);
  assert.match(migration,/approval_default='required'/);
  assert.match(migration,/authorizationBoundary','pandora_tool_gateway'/);
  assert.match(migration,/approvalBinding','exact_action_hash'/);
  assert.match(migration,/approvalAuthority','public\.approvals'/);
  assert.doesNotMatch(migration,/\bProjectOS\b/i);
  assert.doesNotMatch(migration,/vault\.decrypted_secrets|Github_supabase|vercel['"]/i);
});
