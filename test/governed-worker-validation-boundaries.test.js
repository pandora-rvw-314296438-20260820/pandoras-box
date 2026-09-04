"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");
const { PGlite } = require("@electric-sql/pglite");
const { pgcrypto } = require("@electric-sql/pglite/contrib/pgcrypto");

const root = join(__dirname, "..");
const workerMigration = readFileSync(
  join(
    root,
    "supabase",
    "migrations",
    "20260823143000_add_governed_owner_worker_dispatch.sql",
  ),
  "utf8",
);
const contextMigration = readFileSync(
  join(
    root,
    "supabase",
    "migrations",
    "20260823163000_harden_execution_plan_context_immutability.sql",
  ),
  "utf8",
);
const hardeningMigration = readFileSync(
  join(
    root,
    "supabase",
    "migrations",
    "20260823164000_harden_governed_worker_validation_boundaries.sql",
  ),
  "utf8",
);
const rollback = readFileSync(
  join(
    root,
    "docs",
    "supabase",
    "recovery",
    "jcyqixttuebxqqfkjonq",
    "rollback",
    "20260823164000_restore_governed_worker_validation_boundaries.sql",
  ),
  "utf8",
);

function sqlSection(source, startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  assert.notEqual(start, -1, `missing SQL marker: ${startMarker}`);
  const end = source.indexOf(endMarker, start);
  assert.notEqual(end, -1, `missing SQL marker: ${endMarker}`);
  return source.slice(start, end);
}

function sqlFunction(source, qualifiedName) {
  const startMarker = `create or replace function ${qualifiedName}(`;
  const start = source.indexOf(startMarker);
  assert.notEqual(start, -1, `missing SQL function: ${qualifiedName}`);
  const end = source.indexOf("\n$$;", start);
  assert.notEqual(end, -1, `unterminated SQL function: ${qualifiedName}`);
  return source.slice(start, end + 4);
}

const workerValidatorSql = sqlSection(
  workerMigration,
  "create or replace function private.projectos_worker_plan_payload_hash",
  "create or replace function public.projectos_accept_governed_worker_intake",
);
const canonicalContextSql = sqlFunction(
  contextMigration,
  "private.projectos_canonical_context_json",
);
const contextHashContractSql = sqlSection(
  contextMigration,
  "-- BEGIN EXECUTION PLAN CONTEXT HASH CONTRACT",
  "-- END EXECUTION PLAN CONTEXT HASH CONTRACT",
);

const ids = {
  organization: "2270b266-59da-4c39-bfd9-9f8d08352af0",
  dispatch: "a6402a8a-4cbb-4812-80be-640028c81c5b",
  plan: "8ec3acda-4fb7-48b2-81f4-6885c005f561",
};

const validPlan = {
  schemaVersion: 1,
  repository: "banataosystems/Pandoras-box",
  exactSha: "1".repeat(40),
  jobClass: "node_regression",
  maxRuntimeSeconds: 300,
  productionMutationAllowed: false,
};

const validJob = {
  schemaVersion: 1,
  audience: "pandora-worker:worker-01",
  organizationId: ids.organization,
  dispatchId: ids.dispatch,
  planId: ids.plan,
  repository: validPlan.repository,
  exactSha: validPlan.exactSha,
  jobClass: validPlan.jobClass,
  maxRuntimeSeconds: validPlan.maxRuntimeSeconds,
  issuedAt: "2026-08-23T16:30:00.000Z",
  expiresAt: "2026-08-23T16:35:00.000Z",
  runnerPolicyHash: "2".repeat(64),
  runnerImageDigest: `sha256:${"3".repeat(64)}`,
  acquisitionImageDigest: `sha256:${"4".repeat(64)}`,
  networkPolicy: "none",
  isolation: "hyperv_container",
  productionMutationAllowed: false,
};

const validResult = {
  schemaVersion: 1,
  organizationId: ids.organization,
  dispatchId: ids.dispatch,
  planId: ids.plan,
  workerId: "worker-01",
  jobDigest: "5".repeat(64),
  repository: validPlan.repository,
  exactSha: validPlan.exactSha,
  jobClass: validPlan.jobClass,
  outcome: "completed",
  exitCode: 0,
  isolation: "hyperv_container",
  networkPolicy: "none",
  productionMutationAllowed: false,
  runnerPolicyHash: validJob.runnerPolicyHash,
  runnerImageDigest: validJob.runnerImageDigest,
  acquisitionImageDigest: validJob.acquisitionImageDigest,
  sourceTreeSha: "6".repeat(40),
  testsDiscovered: 12,
  startedAt: "2026-08-23T16:30:00.000Z",
  completedAt: "2026-08-23T16:31:00.000Z",
  stdoutSha256: "7".repeat(64),
  stderrSha256: "8".repeat(64),
};

function replaceKey(value, removedKey, substituteKey) {
  const copy = { ...value };
  delete copy[removedKey];
  copy[substituteKey] = "substitute";
  assert.equal(Object.keys(copy).length, Object.keys(value).length);
  return copy;
}

async function booleanQuery(db, sql, parameters) {
  const result = await db.query(sql, parameters);
  assert.equal(result.rows.length, 1);
  assert.equal(typeof result.rows[0].valid, "boolean");
  return result.rows[0].valid;
}

async function planIsValid(db, plan) {
  const encoded = JSON.stringify(plan);
  const hash = await db.query(
    "select private.projectos_worker_plan_payload_hash($1::jsonb) as hash",
    [encoded],
  );
  return booleanQuery(
    db,
    `select private.projectos_worker_plan_is_valid(
      'projectos.worker.verify', 'write', $1::jsonb, $2::text
    ) as valid`,
    [encoded, hash.rows[0].hash],
  );
}

function jobIsValid(db, payload) {
  return booleanQuery(
    db,
    "select private.projectos_worker_job_payload_is_valid($1::jsonb) as valid",
    [JSON.stringify(payload)],
  );
}

function resultIsValid(db, result) {
  return booleanQuery(
    db,
    "select private.projectos_worker_result_summary_is_valid($1::jsonb) as valid",
    [JSON.stringify(result)],
  );
}

test("real SQL replay keeps plan, job, and result validation total and fail-closed", async () => {
  const db = new PGlite({ extensions: { pgcrypto } });
  const missingJobKey = replaceKey(validJob, "runnerPolicyHash", "unexpectedJobKey");
  const missingResultKey = replaceKey(
    validResult,
    "testsDiscovered",
    "unexpectedResultKey",
  );
  const nullJobKey = { ...validJob, audience: null };
  const nullResultKey = { ...validResult, outcome: null };

  try {
    await db.exec(`
      create role anon nologin;
      create role authenticated nologin;
      create role service_role nologin;
      create role projectos_reviewer_ingest nologin noinherit;
      create schema private;
      create schema auth;
      create schema extensions;
      create extension pgcrypto with schema extensions;

      create function auth.jwt()
      returns jsonb
      language sql
      stable
      set search_path = ''
      as $$
        select coalesce(
          nullif(current_setting('request.jwt.claims', true), ''),
          '{}'
        )::jsonb
      $$;

      create table private.execution_dispatch_outbox (
        id uuid primary key default gen_random_uuid(),
        job_payload jsonb,
        result_summary jsonb
      );

      create table private.execution_plan_contexts (
        plan_id uuid primary key default gen_random_uuid(),
        context_hash text not null,
        context_envelope jsonb not null
      );

      create function private.projectos_upsert_agent_runtime_proof(
        uuid, text, jsonb
      ) returns jsonb
      language sql
      security definer
      set search_path = public, private, auth, pg_temp
      as $$ select '{}'::jsonb $$;

      create table private.governed_worker_review_attestations (
        id uuid primary key default gen_random_uuid(),
        payload jsonb not null default '{}'::jsonb
      );
    `);

    await db.exec(canonicalContextSql);
    await db.exec(contextHashContractSql);
    await db.exec(workerValidatorSql);
    await db.exec(hardeningMigration);

    assert.equal(await planIsValid(db, validPlan), true);
    for (const requiredKey of Object.keys(validPlan)) {
      assert.equal(
        await planIsValid(
          db,
          replaceKey(validPlan, requiredKey, `unexpected_${requiredKey}`),
        ),
        false,
        `plan validator accepted missing ${requiredKey}`,
      );
      assert.equal(
        await planIsValid(db, { ...validPlan, [requiredKey]: null }),
        false,
        `plan validator accepted JSON null ${requiredKey}`,
      );
    }
    assert.equal(await planIsValid(db, null), false);

    assert.equal(await jobIsValid(db, validJob), true);
    for (const requiredKey of Object.keys(validJob)) {
      assert.equal(
        await jobIsValid(
          db,
          replaceKey(validJob, requiredKey, `unexpected_${requiredKey}`),
        ),
        false,
        `job validator accepted missing ${requiredKey}`,
      );
      assert.equal(
        await jobIsValid(db, { ...validJob, [requiredKey]: null }),
        false,
        `job validator accepted JSON null ${requiredKey}`,
      );
    }
    assert.equal(await jobIsValid(db, null), false);

    assert.equal(await resultIsValid(db, validResult), true);
    for (const requiredKey of Object.keys(validResult)) {
      assert.equal(
        await resultIsValid(
          db,
          replaceKey(validResult, requiredKey, `unexpected_${requiredKey}`),
        ),
        false,
        `result validator accepted missing ${requiredKey}`,
      );
      assert.equal(
        await resultIsValid(db, { ...validResult, [requiredKey]: null }),
        false,
        `result validator accepted JSON null ${requiredKey}`,
      );
    }
    assert.equal(await resultIsValid(db, null), false);

    await db.query(
      `insert into private.execution_dispatch_outbox(job_payload, result_summary)
       values ($1::jsonb, $2::jsonb)`,
      [JSON.stringify(validJob), JSON.stringify(validResult)],
    );
    for (const [column, invalid] of [
      ["job_payload", missingJobKey],
      ["job_payload", nullJobKey],
      ["result_summary", missingResultKey],
      ["result_summary", nullResultKey],
    ]) {
      await assert.rejects(
        db.query(
          `insert into private.execution_dispatch_outbox(${column}) values ($1::jsonb)`,
          [JSON.stringify(invalid)],
        ),
        (error) => {
          assert.equal(error.code, "23514");
          return true;
        },
      );
    }
  } finally {
    await db.close();
  }
});

test("context hash validation is provenance-sensitive and always derives canonical bytes", () => {
  assert.match(
    hardeningMigration,
    /canonical_context_hash = private\.projectos_context_json_sha256\([\s\S]*private\.projectos_canonical_context_json\(context_envelope\)[\s\S]*and private\.projectos_context_hash_matches_contract\([\s\S]*context_hash, context_envelope, hash_contract/,
  );
  assert.doesNotMatch(
    hardeningMigration,
    /context_hash\s*=\s*encode\([\s\S]*projectos_canonical_context_json\(context_envelope\)/,
  );
});

test("privileged helper and immutable receipt boundaries are explicit", () => {
  const serviceGuard = sqlFunction(
    hardeningMigration,
    "private.assert_control_service_role",
  );
  assert.match(serviceGuard, /language plpgsql\s+security invoker/);
  assert.match(serviceGuard, /if session_user = 'postgres' then\s+return/);
  assert.match(
    serviceGuard,
    /if session_user <> 'authenticator'\s+or coalesce\(auth\.jwt\(\) ->> 'role', ''\) <> 'service_role' then/,
  );
  assert.doesNotMatch(serviceGuard, /current_user/);

  assert.match(
    hardeningMigration,
    /alter function private\.projectos_upsert_agent_runtime_proof\(uuid, text, jsonb\)\s+set search_path = '';/,
  );
  assert.match(
    hardeningMigration,
    /create trigger governed_worker_review_attestations_immutable\s+before update or delete on private\.governed_worker_review_attestations\s+for each row execute function\s+private\.reject_governed_worker_review_attestation_mutation\(\);/,
  );
});

test("service-role assertion uses the original authenticator session and signed JWT role", async () => {
  const db = new PGlite();
  const serviceGuard = sqlFunction(
    hardeningMigration,
    "private.assert_control_service_role",
  );

  try {
    await db.exec(`
      create role authenticator nologin noinherit;
      create role service_role nologin;
      create role authenticated nologin;
      grant service_role, authenticated to authenticator;
      create schema private;
      create schema auth;

      create function auth.jwt()
      returns jsonb
      language sql
      stable
      set search_path = ''
      as $$
        select coalesce(
          nullif(current_setting('request.jwt.claims', true), ''),
          '{}'
        )::jsonb
      $$;
    `);
    await db.exec(serviceGuard);
    await db.exec(`
      create function public.test_control_service_boundary()
      returns void
      language plpgsql
      security definer
      set search_path = ''
      as $$
      begin
        perform private.assert_control_service_role();
      end;
      $$;
      grant execute on function public.test_control_service_boundary()
        to authenticator, authenticated, service_role;
      set session authorization authenticator;
      select set_config(
        'request.jwt.claims',
        '{"role":"service_role"}',
        false
      );
      set role service_role;
      select public.test_control_service_boundary();
      reset role;
      select set_config(
        'request.jwt.claims',
        '{"role":"authenticated"}',
        false
      );
      set role authenticated;
    `);
    await assert.rejects(
      db.query("select public.test_control_service_boundary()"),
      (error) => {
        assert.equal(error.code, "42501");
        return true;
      },
    );
  } finally {
    await db.close();
  }
});

test("emergency rollback fails closed without restoring permissive validation", () => {
  for (const signature of [
    /revoke execute on function public\.projectos_create_or_get_worker_plan\([\s\S]*?\) from service_role;/,
    /revoke execute on function public\.record_governed_worker_job_envelope\([\s\S]*?\) from service_role;/,
    /revoke execute on function public\.finish_governed_worker_dispatch\([\s\S]*?\) from service_role;/,
    /revoke execute on function public\.attach_execution_plan_context\([\s\S]*?\) from service_role;/,
    /revoke execute on function public\.record_governed_worker_review_attestation\([\s\S]*?\) from projectos_reviewer_ingest;/,
  ]) {
    assert.match(rollback, signature);
  }
  assert.doesNotMatch(rollback, /\bgrant\s+execute\b/i);
  assert.doesNotMatch(rollback, /\bdrop\s+(?:table|function|trigger|schema)\b/i);
  assert.doesNotMatch(rollback, /\b(?:delete\s+from|truncate|update)\b/i);
  assert.doesNotMatch(rollback, /create\s+or\s+replace\s+function/i);
});
