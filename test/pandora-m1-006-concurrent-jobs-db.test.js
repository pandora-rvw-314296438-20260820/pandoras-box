"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");
const { PGlite } = require("@electric-sql/pglite");
const { pgcrypto } = require("@electric-sql/pglite/contrib/pgcrypto");

const migrations = join(__dirname, "..", "supabase", "migrations");
const transport = readFileSync(join(migrations, "20260914100000_pandora_activity_realtime_transport_v1.sql"), "utf8");
const controls = readFileSync(join(migrations, "20260915001000_pandora_activity_controls_v1.sql"), "utf8");
const recovery = readFileSync(join(migrations, "20260915013000_pandora_activity_recovery_v1.sql"), "utf8");
const nativeProjects = readFileSync(join(migrations, "20260918031500_pandora_native_project_registry_surface_v1.sql"), "utf8");
const ORG = "10000000-0000-4000-8000-000000000001";
const OWNER = "20000000-0000-4000-8000-000000000001";
const PEER = "20000000-0000-4000-8000-000000000002";
const CLAIM_A = "30000000-0000-4000-8000-000000000001";
const CLAIM_B = "30000000-0000-4000-8000-000000000002";
const THREAD = "40000000-0000-4000-8000-000000000001";
const PROJECT = "50000000-0000-4000-8000-000000000001";

async function setup(db) {
  await db.exec([
    "create schema extensions;",
    "create extension pgcrypto with schema extensions;",
    "create role anon nologin;",
    "create role authenticated nologin;",
    "create role service_role nologin;",
    "create schema auth;",
    "grant usage on schema public, auth to anon, authenticated, service_role;",
    "create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;",
    "create function auth.role() returns text language sql stable as $$ select nullif(current_setting('request.jwt.claim.role', true), '') $$;",
    "create table public.memberships (organization_id uuid not null, user_id uuid not null, status text not null);",
    "create table public.pandora_intelligence_threads (id uuid primary key, organization_id uuid not null, created_by uuid not null, status text not null);",
    "create table public.projectos_projects (id uuid primary key, organization_id uuid not null, project_key text, name text, repository text, workspace_path text, status text not null, objective text, roadmap_version text, current_phase_key text, current_task_key text, progress_percent integer, config jsonb, created_by uuid, last_reconciled_at timestamptz, created_at timestamptz, updated_at timestamptz);",
    "insert into public.pandora_intelligence_threads (id,organization_id,created_by,status) values ('" + THREAD + "','" + ORG + "','" + OWNER + "','active');",
    "insert into public.projectos_projects (id,organization_id,status) values ('" + PROJECT + "','" + ORG + "','active');",
    "insert into public.memberships (organization_id,user_id,status) values ('" + ORG + "','" + OWNER + "','active'),('" + ORG + "','" + PEER + "','active');",
  ].join("\n"));
  await db.exec(transport);
  await db.exec(controls);
  await db.exec(recovery);
  await db.exec(nativeProjects);
}

async function identity(db, role, userId) {
  await db.query("select set_config('request.jwt.claim.role', $1, false)", [role]);
  await db.query("select set_config('request.jwt.claim.sub', $1, false)", [userId || ""]);
}

async function begin(db, requestId) {
  const { rows } = await db.query(
    "select public.pandora_activity_job_begin_v1($1::uuid,$2::text,$3::uuid,$4::uuid) as job",
    [ORG, requestId, THREAD, PROJECT],
  );
  return rows[0].job;
}

async function claim(db, jobId, fingerprint, claimId) {
  const { rows } = await db.query(
    "select public.pandora_activity_execution_claim_v1($1::uuid,$2::text,$3::uuid) as claim",
    [jobId, fingerprint, claimId],
  );
  return rows[0].claim;
}

function event(job, sequence, state, eventId) {
  const at = new Date().toISOString();
  return {
    schemaVersion: 1,
    jobId: job.jobId,
    sequence,
    eventId,
    writerEpoch: job.writerEpoch,
    admittedBy: job.writerId,
    admissionMode: "online",
    state,
    message: "Evidence for " + job.requestId + " step " + sequence,
    occurredAt: at,
    admittedAt: at,
    provenance: {
      sourceType: "runtime",
      sourceId: "pandora-activity-runtime",
      sourceEventId: eventId,
      observedAt: at,
    },
    evidence: [{
      type: "runtime_event",
      relation: "source",
      ref: "activity-job:" + job.jobId + "/events/" + sequence,
    }],
    domain: "chat",
    capability: "intelligence.chat",
    executionId: job.jobId,
  };
}

async function admit(db, job, sequence, state, eventId) {
  const { rows } = await db.query(
    "select public.pandora_activity_admit_event_v1($1::uuid,$2::jsonb) as admitted",
    [job.jobId, JSON.stringify(event(job, sequence, state, eventId))],
  );
  return rows[0].admitted;
}

async function replay(db, jobId, afterSequence) {
  const { rows } = await db.query(
    "select public.pandora_activity_replay_v1($1::uuid,$2::uuid,$3::bigint,100) as replay",
    [ORG, jobId, afterSequence],
  );
  return rows[0].replay;
}

test("M1-006 keeps two live Activity jobs, controls and replay cursors independent", async () => {
  const db = new PGlite({ extensions: { pgcrypto } });
  try {
    await setup(db);
    await identity(db, "authenticated", OWNER);
    const alpha = await begin(db, "m1006-alpha-001");
    const beta = await begin(db, "m1006-beta-001");
    assert.notEqual(alpha.jobId, beta.jobId);
    assert.equal(alpha.lastSequence, 1);
    assert.equal(beta.lastSequence, 1);
    assert.equal(alpha.threadId, THREAD);
    assert.equal(beta.threadId, THREAD);
    assert.equal(alpha.projectId, PROJECT);
    assert.equal(beta.projectId, PROJECT);
    assert.equal((await begin(db, "m1006-alpha-001")).jobId, alpha.jobId);

    await identity(db, "service_role");
    const aClaim = await claim(db, alpha.jobId, "a".repeat(64), CLAIM_A);
    const bClaim = await claim(db, beta.jobId, "b".repeat(64), CLAIM_B);
    assert.equal(aClaim.mode, "execute");
    assert.equal(bClaim.mode, "execute");
    assert.equal((await claim(db, alpha.jobId, "a".repeat(64), CLAIM_B)).mode, "observe");
    const { rows: running } = await db.query(
      "select id,execution_state from public.pandora_activity_jobs where id in ($1::uuid,$2::uuid)",
      [alpha.jobId, beta.jobId],
    );
    assert.equal(running.length, 2);
    assert.ok(running.every((job) => job.execution_state === "running"));

    await admit(db, alpha, 2, "acting", "shared-step-2");
    await admit(db, beta, 2, "acting", "shared-step-2");
    await admit(db, alpha, 3, "checking", "alpha-step-3");
    await admit(db, beta, 3, "checking", "beta-step-3");
    await assert.rejects(
      db.query(
        "select public.pandora_activity_admit_event_v1($1::uuid,$2::jsonb)",
        [beta.jobId, JSON.stringify(event(alpha, 4, "acting", "wrong-job"))],
      ),
      (error) => error.code === "22023",
    );

    await identity(db, "authenticated", OWNER);
    const requested = await db.query(
      "select public.pandora_activity_control_request_v1($1::uuid,$2::uuid,$3::text,$4::text,$5::text) as control",
      [ORG, alpha.jobId, "alpha-control-001", "redirect", "Continue alpha separately"],
    );
    assert.equal(requested.rows[0].control.jobId, alpha.jobId);

    await identity(db, "service_role");
    const { rows: noBetaControl } = await db.query(
      "select public.pandora_activity_control_claim_v1($1::uuid) as control",
      [beta.jobId],
    );
    assert.equal(noBetaControl[0].control, null);
    const { rows: alphaControl } = await db.query(
      "select public.pandora_activity_control_claim_v1($1::uuid) as control",
      [alpha.jobId],
    );
    assert.equal(alphaControl[0].control.jobId, alpha.jobId);

    await admit(db, alpha, 4, "failed", "alpha-failed-4");
    await admit(db, beta, 4, "acting", "beta-still-running-4");

    await identity(db, "authenticated", OWNER);
    const aReplay = await replay(db, alpha.jobId, 1);
    const bReplay = await replay(db, beta.jobId, 2);
    assert.deepEqual(aReplay.events.map((item) => item.sequence), [2, 3, 4]);
    assert.deepEqual(bReplay.events.map((item) => item.sequence), [3, 4]);
    assert.ok(aReplay.events.every((item) => item.jobId === alpha.jobId));
    assert.ok(bReplay.events.every((item) => item.jobId === beta.jobId));
    assert.equal(aReplay.watermarkSequence, 4);
    assert.equal(bReplay.watermarkSequence, 4);
    assert.equal(aReplay.terminalState, "failed");
    assert.equal(aReplay.events[2].provenance.sourceEventId, "alpha-failed-4");
    assert.equal(aReplay.events[2].evidence[0].type, "runtime_event");
    assert.equal(aReplay.events[2].evidence[0].ref, "activity-job:" + alpha.jobId + "/events/4");
    assert.equal(bReplay.terminalState, null);
    assert.equal((await begin(db, "m1006-alpha-001")).lastSequence, 4);

    await identity(db, "authenticated", PEER);
    await assert.rejects(
      replay(db, alpha.jobId, 0),
      (error) => error.code === "22023" && /pandora_activity_job_not_found/.test(error.message),
    );
  } finally {
    await db.close();
  }
});
