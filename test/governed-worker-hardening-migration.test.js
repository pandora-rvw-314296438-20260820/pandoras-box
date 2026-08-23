"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

const root = path.join(__dirname, "..");
const migration = fs.readFileSync(
  path.join(
    root,
    "supabase",
    "migrations",
    "20260823153000_harden_governed_worker_lease_and_key_binding.sql",
  ),
  "utf8",
);

function sqlFunctionBody(name, parameterCountMarker) {
  const start = migration.indexOf(
    `create or replace function ${name}(${parameterCountMarker}`,
  );
  assert.notEqual(start, -1, `missing SQL function ${name}`);
  const end = migration.indexOf("\n$$;", start);
  assert.notEqual(end, -1, `unterminated SQL function ${name}`);
  return migration.slice(start, end + 4);
}

test("runtime-proof active leases are derived from durable unexpired dispatch rows", () => {
  assert.match(migration, /private\.projectos_worker_active_lease_count/);
  assert.match(
    migration,
    /dispatch\.status in \('claimed', 'envelope_ready'\)[\s\S]*dispatch\.lease_expires_at > now\(\)/,
  );
  assert.match(
    migration,
    /before insert or update on public\.projectos_agent_runtime_proofs[\s\S]*guard_projectos_runtime_proof_active_leases/,
  );
  assert.match(
    migration,
    /after insert or update or delete on private\.execution_dispatch_outbox[\s\S]*sync_projectos_worker_active_leases/,
  );
  assert.match(
    migration,
    /new\.active_leases := private\.projectos_worker_active_lease_count\(new\.id\)/,
  );
  assert.match(
    migration,
    /Repair any counter that was previously supplied by a runtime-proof refresh/,
  );
  assert.match(
    migration,
    /alter function public\.projectos_upsert_agent_runtime_proof\(uuid, text, jsonb\)[\s\S]*set schema private/,
  );
  assert.match(
    migration,
    /select proof\.active_leases into durable_active_leases[\s\S]*jsonb_set\([\s\S]*'\{activeLeases\}'/,
  );
});

test("nonce, claim, and completion lock the exact expected worker key", () => {
  const nonce = sqlFunctionBody(
    "public.consume_compute_worker_nonce",
    "\n  p_organization_id uuid,",
  );
  const claim = sqlFunctionBody(
    "public.claim_governed_worker_dispatch",
    "\n  p_organization_id uuid,",
  );
  const finish = sqlFunctionBody(
    "public.finish_governed_worker_dispatch",
    "\n  p_organization_id uuid,",
  );
  for (const body of [nonce, claim, finish]) {
    assert.match(body, /p_expected_key_fingerprint text/);
    assert.match(body, /worker\.key_fingerprint = p_expected_key_fingerprint/);
    assert.match(body, /for update/);
    assert.match(body, /worker key fingerprint changed/);
  }
  assert.match(
    finish,
    /dispatch\.worker_key_fingerprint = p_expected_key_fingerprint/,
  );
  assert.match(finish, /worker completion key binding mismatch/);
});

test("only key-bound RPC overloads remain exposed to service_role", () => {
  assert.match(
    migration,
    /revoke all on function public\.consume_compute_worker_nonce\(uuid, text, text\)[\s\S]*service_role/,
  );
  assert.match(
    migration,
    /revoke all on function public\.claim_governed_worker_dispatch\(uuid, text\)[\s\S]*service_role/,
  );
  assert.match(
    migration,
    /grant execute on function public\.consume_compute_worker_nonce\([\s\S]*uuid, text, text, text[\s\S]*\) to service_role/,
  );
  assert.match(
    migration,
    /grant execute on function public\.claim_governed_worker_dispatch\([\s\S]*uuid, text, text[\s\S]*\) to service_role/,
  );
});

test("Edge RPC calls carry the resolved key fingerprint through each mutation", () => {
  const source = fs.readFileSync(
    path.join(
      root,
      "supabase",
      "functions",
      "pandora-worker-dispatch",
      "index.ts",
    ),
    "utf8",
  );
  assert.match(source, /const keyFingerprint = String\(claims\.worker_key_fingerprint/);
  assert.equal(
    (source.match(/p_expected_key_fingerprint:/g) || []).length,
    3,
  );
  assert.doesNotMatch(source, /SUPABASE_SERVICE_ROLE_KEY/);
});
