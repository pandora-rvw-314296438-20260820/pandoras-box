"use strict";

const test=require("node:test");
const assert=require("node:assert/strict");
const fs=require("node:fs");

const migration=fs.readFileSync("supabase/migrations/20260927111500_operations_rdp_artemis_verifier_v1.sql","utf8");
const worker=fs.readFileSync("scripts/operations/rdp-artemis-verifier.ps1","utf8");
const doc=fs.readFileSync("docs/operations/rdp-artemis-verifier-v1.md","utf8");

test("ARTEMIS is a distinct least-privilege RDP release verifier",()=>{
  assert.match(migration,/pandora-rdp-artemis-01/);
  assert.match(migration,/rdp:EC2AMAZ-SPAE2VG:artemis-verifier-v1/);
  assert.match(migration,/array\['release'\]::text\[\]/);
  assert.match(migration,/release\.verify/);
  assert.match(migration,/rdp\.release\.verify/);
  assert.doesNotMatch(migration,/source\.write|runtime\.deploy|memory\.integrate|spend\.authorized|owner\.meta_oauth/);
});

test("ARTEMIS registration is service-role-only and project-bound",()=>{
  assert.match(migration,/OPS_RDP_ARTEMIS_SERVICE_ROLE_REQUIRED/);
  assert.match(migration,/pandora_ops_project_bindings/);
  assert.match(migration,/state='active'/);
  assert.match(migration,/revoke all on function public\.pandora_ops_register_rdp_artemis_verifier_v1/);
  assert.match(migration,/grant execute on function public\.pandora_ops_register_rdp_artemis_verifier_v1[\s\S]*service_role/);
});

test("machine verifier binds exact Git state and emits hashed non-mutating evidence",()=>{
  assert.match(worker,/rev-parse","HEAD/);
  assert.match(worker,/status","--porcelain=v1/);
  assert.match(worker,/merge-base","--is-ancestor/);
  assert.match(worker,/diff","--check/);
  assert.match(worker,/node" @\("--test"/);
  assert.match(worker,/node" @\("--check"/);
  assert.match(worker,/diffSha256/);
  assert.match(worker,/stdoutSha256/);
  assert.match(worker,/sourceMutationPerformed=\$false/);
  assert.match(worker,/releaseMutationPerformed=\$false/);
  assert.doesNotMatch(worker,/\bgit\s+(push|commit|merge|rebase|cherry-pick)\b/i);
  assert.doesNotMatch(worker,/\bvercel\s+(deploy|promote|rollback)\b/i);
});

test("documentation keeps execution and verification identities separate",()=>{
  assert.match(doc,/pandora-rdp-windows-01/);
  assert.match(doc,/pandora-rdp-artemis-01/);
  assert.match(doc,/does not itself merge or release/i);
  assert.match(doc,/supplemental/i);
});
