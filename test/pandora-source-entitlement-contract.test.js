
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const test = require("node:test");

const migration = fs.readFileSync(path.join(process.cwd(),"supabase/migrations/20260902013000_pandora_source_entitlements_v1.sql"),"utf8");
const preview = fs.readFileSync(path.join(process.cwd(),"supabase/functions/pandora-preview-content/index.ts"),"utf8");

test("durable source entitlement is explicit and never implied by membership",()=>{
  assert.match(migration,/pandora_source_entitlements/);
  assert.match(migration,/NO_SOURCE_ENTITLEMENT/);
  assert.match(migration,/SOURCE_ENTITLEMENT_EXPIRED/);
  assert.match(migration,/SOURCE_ENTITLEMENT_REVOKED/);
  assert.match(migration,/capabilities <@ array\['read','search','diff','export'\]/);
  assert.doesNotMatch(migration,/role::text\s*=\s*'owner'.*allowed.*true/is);
  assert.match(migration,/revoke all on public\.pandora_source_entitlements from public, anon, authenticated/);
});

test("preview content withholds durable source by default and uses exact hosted identity",()=>{
  const decision = preview.indexOf('pandora_get_source_entitlement_v1');
  const hosted = preview.indexOf('preview.source_withheld');
  const download = preview.indexOf('.download(text(artifactVersion.storage_path))');
  assert.ok(decision > 0 && hosted > decision && download > hosted);
  assert.match(preview,/sourceIncluded:false/);
  assert.match(preview,/sourceEntitled:false/);
  assert.match(preview,/verification_state","live_verified/);
  assert.match(preview,/source_sha256/);
  assert.match(preview,/artifact_digest/);
  assert.match(preview,/HOSTED_PREVIEW_IDENTITY_MISMATCH/);
  assert.doesNotMatch(preview,/createSignedUrl|signedURL|signedUrl/);
});

test("raw preview bundle requires an auditable active source entitlement",()=>{
  assert.match(preview,/if\(!sourceAllowed\)/);
  assert.match(preview,/p_action:"preview\.source_bundle"/);
  assert.match(preview,/p_allowed:true/);
  assert.match(preview,/SOURCE_ENTITLEMENT_ACTIVE/);
  assert.match(preview,/SOURCE_ACCESS_AUDIT_FAILED/);
  assert.match(preview,/sourceIncluded:true/);
  assert.match(preview,/sourceEntitled:true/);
});
