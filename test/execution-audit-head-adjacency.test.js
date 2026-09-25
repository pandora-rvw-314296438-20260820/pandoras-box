const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");
const { PGlite } = require("@electric-sql/pglite");
const { pgcrypto } = require("@electric-sql/pglite/contrib/pgcrypto");

const root = join(__dirname, "..", "supabase", "migrations");
const original = readFileSync(
  join(root, "20260924195443_execution_audit_head_integrity_v1.sql"), "utf8",
);
const correction = readFileSync(
  join(root, "20260925091800_execution_audit_head_adjacency_v2.sql"), "utf8",
);
const receipt = readFileSync(
  join(root, "20260924192759_pandora_system_audit_repair_v1.sql"), "utf8",
);
const ORG = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const OTHER_ORG = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const FIRST = "11111111-1111-4111-8111-111111111111";
const SECOND = "22222222-2222-4222-8222-222222222222";
const THIRD = "33333333-3333-4333-8333-333333333333";
const ROOT = "44444444-4444-4444-8444-444444444444";
const ZERO = "0".repeat(64);

async function setup(db) {
  await db.exec([
    "create schema extensions;",
    "create extension pgcrypto with schema extensions;",
    "create schema private;",
    "create role anon nologin;",
    "create role authenticated nologin;",
    "create role service_role nologin;",
    "create table private.execution_audit_chain_state (organization_id uuid primary key, last_sequence bigint not null, last_hash text not null);",
    "create table private.execution_audit_events (id uuid primary key, organization_id uuid not null, sequence bigint not null, plan_id uuid, request_id uuid, event_type text not null, status text not null, tool text, risk text, payload_hash text, details jsonb not null, occurred_at timestamptz not null, previous_hash text not null, event_hash text not null, unique (organization_id, sequence));",
    "create function private.assert_control_service_role() returns void language plpgsql as $$ begin if coalesce(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '') <> 'service_role' then raise exception 'service role required' using errcode='42501'; end if; end $$;",
    "select set_config('request.jwt.claims', '{\"role\":\"service_role\"}', false);",
  ].join("\n"));
}

async function insertEvent(db, id, organizationId, sequence, previousHash) {
  await db.query(
    "insert into private.execution_audit_events (id,organization_id,sequence,event_type,status,details,occurred_at,previous_hash,event_hash) values ($1,$2,$3,'test','ok','{}'::jsonb,'2026-09-25T00:00:00Z',$4,$5)",
    [id, organizationId, sequence, previousHash, "f".repeat(63) + String(sequence)],
  );
  return rehash(db, id);
}

async function rehash(db, id) {
  const { rows } = await db.query(
    "select concat_ws('|',organization_id::text,sequence::text,coalesce(plan_id::text,''),coalesce(request_id::text,''),event_type,status,coalesce(tool,''),coalesce(risk,''),coalesce(payload_hash,''),details::text,occurred_at::text,previous_hash) as canonical from private.execution_audit_events where id=$1",
    [id],
  );
  const hash = createHash("sha256").update(rows[0].canonical, "utf8").digest("hex");
  await db.query("update private.execution_audit_events set event_hash=$1 where id=$2", [hash, id]);
  return hash;
}

async function setHead(db, organizationId, sequence, hash) {
  await db.query(
    "insert into private.execution_audit_chain_state(organization_id,last_sequence,last_hash) values($1,$2,$3) on conflict(organization_id) do update set last_sequence=excluded.last_sequence,last_hash=excluded.last_hash",
    [organizationId, sequence, hash],
  );
}

async function verify(db, organizationId) {
  const { rows } = await db.query(
    "select public.verify_execution_audit_head_v1($1::uuid) as verdict",
    [organizationId],
  );
  return rows[0].verdict;
}

test("head verification detects rewritten predecessor links while preserving indexed actual-tail safety", async () => {
  const db = new PGlite({ extensions: { pgcrypto } });
  try {
    await setup(db);
    await db.exec(original);
    const firstHash = await insertEvent(db, FIRST, ORG, 1, ZERO);
    await setHead(db, ORG, 1, firstHash);
    const secondHash = await insertEvent(db, SECOND, ORG, 2, firstHash);
    await setHead(db, ORG, 2, secondHash);
    assert.equal((await verify(db, ORG)).valid, true);

    // Model a rewritten tail and chain state: the old verifier hashes the
    // tail and matches state, yet never checks the link to event one.
    await db.query(
      "update private.execution_audit_events set previous_hash=$1 where id=$2",
      ["e".repeat(64), SECOND],
    );
    await setHead(db, ORG, 2, await rehash(db, SECOND));
    assert.equal((await verify(db, ORG)).valid, true);

    await db.exec(correction);
    assert.equal((await verify(db, ORG)).reason, "tail_previous_hash_mismatch");

    await db.query(
      "update private.execution_audit_events set previous_hash=$1 where id=$2",
      [firstHash, SECOND],
    );
    const restoredHash = await rehash(db, SECOND);
    await setHead(db, ORG, 2, restoredHash);
    assert.equal((await verify(db, ORG)).valid, true);

    await db.query("delete from private.execution_audit_events where id=$1", [FIRST]);
    assert.equal((await verify(db, ORG)).reason, "missing_previous_event");

    await insertEvent(db, THIRD, ORG, 3, restoredHash);
    assert.equal((await verify(db, ORG)).reason, "chain_head_mismatch");

    const corruptRoot = await insertEvent(db, ROOT, OTHER_ORG, 1, "d".repeat(64));
    await setHead(db, OTHER_ORG, 1, corruptRoot);
    assert.equal((await verify(db, OTHER_ORG)).reason, "tail_previous_hash_mismatch");

    await db.query(
      "select set_config('request.jwt.claims', '{\"role\":\"authenticated\"}', false)",
    );
    await assert.rejects(verify(db, OTHER_ORG), (error) => error.code === "42501");

    const { rows } = await db.query(
      "select has_function_privilege('anon','public.verify_execution_audit_head_v1(uuid)','EXECUTE') as anon, has_function_privilege('authenticated','public.verify_execution_audit_head_v1(uuid)','EXECUTE') as authenticated, has_function_privilege('service_role','public.verify_execution_audit_head_v1(uuid)','EXECUTE') as service",
    );
    assert.deepEqual(rows[0], { anon: false, authenticated: false, service: true });
  } finally {
    await db.close();
  }
});

test("provider receipt cannot rerun the already-applied activity repair", () => {
  assert.match(receipt, /Canonical executable authority: supabase\/migrations\/20260923183000_pandora_system_audit_repair_v1\.sql/);
  assert.match(receipt, /Replay mode: history_receipt_noop/);
  const executable = receipt.replace(/--[^\n]*/g, "").trim();
  assert.equal(executable, "select 1;");
});