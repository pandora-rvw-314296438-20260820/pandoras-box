"use strict";

const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");
const { PGlite } = require("@electric-sql/pglite");
const { pgcrypto } = require("@electric-sql/pglite/contrib/pgcrypto");
const {
  canonicalPlanMemoryContextJson,
  hashPlanMemoryContextEnvelope,
} = require("../src/runtime/plan-memory-context.js");

const root = join(__dirname, "..");
const migration = readFileSync(
  join(
    root,
    "supabase",
    "migrations",
    "20260823163000_harden_execution_plan_context_immutability.sql",
  ),
  "utf8",
);
const fullCapacityGateMigration = readFileSync(
  join(
    root,
    "supabase",
    "migrations",
    "20260817130000_projectos_memory_full_capacity_context_gate.sql",
  ),
  "utf8",
);
const workerValidationMigration = readFileSync(
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
    "20260823163000_disable_execution_plan_context_attachment.sql",
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

const attachmentSql = sqlFunction(
  migration,
  "public.attach_execution_plan_context",
);
const canonicalContextSql = sqlFunction(
  migration,
  "private.projectos_canonical_context_json",
);
const hashContractSql = sqlSection(
  migration,
  "-- BEGIN EXECUTION PLAN CONTEXT HASH CONTRACT",
  "-- END EXECUTION PLAN CONTEXT HASH CONTRACT",
);
const atomicHashContractSql = `begin;\n${hashContractSql}\ncommit;`;
const contextHashConstraintSql = sqlSection(
  workerValidationMigration,
  "-- Hash provenance is versioned in 20260823163000.",
  "-- SECURITY DEFINER callers run as their owner",
);

const FULL_CAPACITY_SECTIONS = [
  "adaptive_profile",
  "style_profile",
  "project_context",
  "people_context",
  "risk_warnings",
  "open_loops",
  "latest_context_pack",
  "daily_context_pack",
  "recent_events",
  "semantic_matches",
  "canonical_records",
  "approved_record_count",
  "requested_canon_statuses",
  "retrieval_mode",
  "retrieval_reasoning_summary",
  "warnings",
];

const APPROVED_MEMORY_CAPABILITY_SEMANTIC_HASH =
  "69cd91cb776249d22fa5050fa6826318748ea3b4d4fa68c96c509d9b51242dbd";

const SANITIZED_LIVE_HASH_FIXTURE = Object.freeze({
  totalRows: 3729,
  legacyNodeRows: 3728,
  legacyPostgresRows: 1,
});

function sha256(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function legacyV1Envelope() {
  return {
    schemaVersion: "1.0.0",
    status: "available",
    source: "pandora-memory",
    namespace: "real_life",
    retrievedAt: "2026-08-23T16:30:00.000Z",
    queryHash: "b".repeat(64),
    queryBasis: {
      tool: "projectos.worker.verify",
      identifiers: {
        branch: "main",
        repository: "banataosystems/Pandoras-box",
      },
    },
    counts: {
      projectContext: 1,
      riskWarnings: 0,
      openLoops: 1,
      recentEvents: 0,
      semanticMatches: 1,
    },
    highlights: {
      project: ["Canonical status pack"],
      risks: [],
      openLoops: ["Complete the physical Android journey"],
      recent: [],
      semantic: ["Return to customer interviews"],
    },
    warnings: [],
  };
}

function fullCapacityEnvelope({
  unavailable = false,
  status = "available",
  failure = { type: "MemoryCapabilityContractError", code: "MEMORY_CAPABILITY_CONTRACT_INVALID" },
} = {}) {
  const empty = !unavailable && status === "empty";
  const counts = {
    adaptiveProfile: unavailable || empty ? 0 : 1,
    styleProfile: 0,
    projectContext: unavailable || empty ? 0 : 1,
    peopleContext: 0,
    riskWarnings: 0,
    openLoops: 0,
    latestContextPack: 0,
    dailyContextPack: 0,
    recentEvents: 0,
    semanticMatches: 0,
    canonicalRecords: 0,
    approvedRecords: 0,
  };
  const highlights = {
    adaptive: [],
    style: [],
    project: unavailable || empty ? [] : ["Full-capacity project context"],
    people: [],
    risks: [],
    openLoops: [],
    latestContextPack: [],
    dailyContextPack: [],
    recent: [],
    semantic: [],
    canonical: [],
  };
  const base = {
    schemaVersion: "2.0.0",
    status: unavailable ? "unavailable" : status,
    source: "pandora-memory",
    namespace: "real_life",
    retrievedAt: "2026-08-23T16:30:00.000Z",
    queryHash: "d".repeat(64),
    queryBasis: {
      tool: "projectos.worker.verify",
      identifiers: { repository: "banataosystems/Pandoras-box" },
    },
    counts,
    highlights,
    retrieval: unavailable
      ? { requestedCanonStatuses: [], approvedRecordCount: 0 }
      : {
        mode: "hybrid",
        reasoningSummary: "Combined all governed context classes.",
        requestedCanonStatuses: ["approved"],
        approvedRecordCount: 0,
      },
    capabilityContract: unavailable
      ? {
        status: "unavailable",
        id: "pandora-projectos-memory-puzzle",
        path: "/.well-known/pandora-projectos-memory-contract-v1.json",
        compatible: false,
        requiredSections: [...FULL_CAPACITY_SECTIONS],
        observedSections: [],
        missingRequiredSections: [...FULL_CAPACITY_SECTIONS],
        utilizationPercentage: 0,
      }
      : {
        status: "verified",
        id: "pandora-projectos-memory-puzzle",
        version: "1.0.0",
        schemaVersion: "1.0.0",
        semanticHash: APPROVED_MEMORY_CAPABILITY_SEMANTIC_HASH,
        authorityRepository: "banataosystems/pandoras-box-memory",
        authorityOrigin: "https://pandorasbox-memory.vercel.app",
        path: "/.well-known/pandora-projectos-memory-contract-v1.json",
        compatible: true,
        requiredSections: [...FULL_CAPACITY_SECTIONS],
        observedSections: [...FULL_CAPACITY_SECTIONS],
        missingRequiredSections: [],
        utilizationPercentage: 100,
      },
    fallbackRequired: unavailable,
    warnings: unavailable ? ["memory_context_unavailable"] : [],
  };
  return unavailable
    ? { ...base, failure }
    : base;
}

function legacyV1UnavailableEnvelope() {
  const envelope = legacyV1Envelope();
  envelope.status = "unavailable";
  envelope.counts = Object.fromEntries(
    Object.keys(envelope.counts).map((key) => [key, 0]),
  );
  envelope.highlights = Object.fromEntries(
    Object.keys(envelope.highlights).map((key) => [key, []]),
  );
  envelope.warnings = ["memory_context_unavailable"];
  envelope.failure = { type: "PandoraMemoryError", status: 503 };
  return envelope;
}

function valueAtPath(value, path) {
  return path.reduce((current, key) => current[key], value);
}

function wrongJsonType(value) {
  if (Array.isArray(value)) return {};
  if (value !== null && typeof value === "object") return [];
  if (typeof value === "string") return 0;
  if (typeof value === "number") return "not-a-number";
  if (typeof value === "boolean") return "not-a-boolean";
  return "unexpected";
}

function requiredKeyMutationCases(base, parentPath, keys, family) {
  const cases = [];
  for (const key of keys) {
    const missing = structuredClone(base);
    delete valueAtPath(missing, parentPath)[key];
    cases.push({ name: `${family}.${key}:missing`, envelope: missing });

    const jsonNull = structuredClone(base);
    valueAtPath(jsonNull, parentPath)[key] = null;
    cases.push({ name: `${family}.${key}:json-null`, envelope: jsonNull });

    const unknown = structuredClone(base);
    const unknownParent = valueAtPath(unknown, parentPath);
    unknownParent[`__unexpected_${key}`] = unknownParent[key];
    delete unknownParent[key];
    cases.push({
      name: `${family}.${key}:unknown-equal-cardinality`,
      envelope: unknown,
    });

    const wrongType = structuredClone(base);
    const wrongTypeParent = valueAtPath(wrongType, parentPath);
    wrongTypeParent[key] = wrongJsonType(wrongTypeParent[key]);
    cases.push({ name: `${family}.${key}:wrong-type`, envelope: wrongType });
  }
  return cases;
}

function identifierMutationCases(base, identifiersPath, family) {
  const original = valueAtPath(base, identifiersPath);
  const key = Object.keys(original)[0];

  const unknown = structuredClone(base);
  const unknownIdentifiers = valueAtPath(unknown, identifiersPath);
  unknownIdentifiers.__unexpected_identifier = unknownIdentifiers[key];
  delete unknownIdentifiers[key];

  const jsonNull = structuredClone(base);
  valueAtPath(jsonNull, identifiersPath)[key] = null;

  const wrongType = structuredClone(base);
  valueAtPath(wrongType, identifiersPath)[key] = { nested: "value" };

  return [
    { name: `${family}:unknown-equal-cardinality`, envelope: unknown },
    { name: `${family}.${key}:json-null`, envelope: jsonNull },
    { name: `${family}.${key}:wrong-type`, envelope: wrongType },
  ];
}

async function createHashContractDb() {
  const db = new PGlite({ extensions: { pgcrypto } });
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create role service_role nologin;
    create schema private;
    create schema extensions;
    create extension if not exists pgcrypto with schema extensions;
    create table private.execution_plan_contexts (
      plan_id uuid primary key,
      context_hash text not null,
      context_envelope jsonb not null
    );
  `);
  await db.exec(canonicalContextSql);
  return db;
}

test("plan context replay requires the exact stored hash and envelope", () => {
  assert.match(
    attachmentSql,
    /if context_row\.plan_id is not null then[\s\S]*context_row\.context_hash = p_context_hash[\s\S]*and context_row\.context_envelope = p_context_envelope[\s\S]*projectos_context_hash_matches_contract[\s\S]*is true then[\s\S]*return jsonb_build_object/,
  );
  assert.match(
    attachmentSql,
    /raise exception 'execution plan context is immutable' using errcode = '55000'/,
  );

  const exactReplay = attachmentSql.indexOf(
    "context_row.context_hash = p_context_hash",
  );
  const immutableFailure = attachmentSql.indexOf(
    "execution plan context is immutable",
  );
  const firstAttachmentGate = attachmentSql.indexOf(
    "plan.status <> 'pending_approval'",
  );
  const insert = attachmentSql.indexOf(
    "insert into private.execution_plan_contexts",
  );
  assert.ok(exactReplay < immutableFailure);
  assert.ok(immutableFailure < firstAttachmentGate);
  assert.ok(firstAttachmentGate < insert);
});

test("first attachment is serialized and accepted only for an unexpired pending plan", () => {
  assert.match(
    attachmentSql,
    /from private\.execution_plans[\s\S]*where id = p_plan_id[\s\S]*and organization_id = p_organization_id[\s\S]*and request_id = p_request_id[\s\S]*for update/,
  );
  assert.match(
    attachmentSql,
    /from private\.execution_plan_contexts[\s\S]*where plan_id = plan\.id[\s\S]*for update/,
  );
  assert.match(
    attachmentSql,
    /if plan\.status <> 'pending_approval' or plan\.expires_at <= now\(\) then[\s\S]*execution plan context attachment is closed/,
  );
  assert.doesNotMatch(attachmentSql, /on conflict[\s\S]*do update/i);
  assert.doesNotMatch(
    attachmentSql,
    /update\s+private\.execution_plan_contexts/i,
  );
  assert.match(
    attachmentSql,
    /context_hash,\s*hash_contract,\s*canonical_context_hash,[\s\S]*p_context_hash,\s*'canonical-json-c-utf8-sha256-v1',\s*derived_context_hash/,
  );
});

test("the hardened function preserves its caller and response contracts", () => {
  assert.match(
    migration,
    /create or replace function public\.attach_execution_plan_context\(\s*p_organization_id uuid,\s*p_plan_id uuid,\s*p_request_id uuid,\s*p_context_hash text,\s*p_context_envelope jsonb\s*\)/,
  );
  assert.match(migration, /perform private\.assert_control_service_role\(\)/);
  assert.match(migration, /'plan_context_attached'/);
  assert.match(migration, /'contextHash', context_row\.context_hash/);
  assert.match(migration, /'recordedAt', context_row\.recorded_at/);
  assert.match(
    migration,
    /grant execute on function public\.attach_execution_plan_context\(uuid, uuid, uuid, text, jsonb\)[\s\S]*to service_role/,
  );
  assert.match(
    migration,
    /revoke all on table private\.execution_plan_contexts from service_role/,
  );
});

test("emergency rollback disables only new attachment and preserves evidence", () => {
  assert.match(
    rollback,
    /revoke execute on function public\.attach_execution_plan_context\([\s\S]*uuid, uuid, uuid, text, jsonb[\s\S]*\) from service_role/,
  );
  assert.doesNotMatch(rollback, /delete from|truncate|drop table|drop schema/i);
  assert.doesNotMatch(rollback, /update\s+private\.execution_plan_contexts/i);
});

test("hash classification is atomic and uses bounded production locks", () => {
  assert.match(migration, /^--[\s\S]*\nbegin;\nset local lock_timeout = '5s';\nset local statement_timeout = '5min';/);
  assert.match(
    migration,
    /lock table private\.execution_plan_contexts in share row exclusive mode;/,
  );
  const lock = migration.indexOf(
    "lock table private.execution_plan_contexts in share row exclusive mode;",
  );
  const classification = migration.indexOf(
    "update private.execution_plan_contexts",
  );
  const insertGuard = migration.indexOf(
    "create trigger execution_plan_contexts_canonical_insert",
  );
  const canonicalAttachment = migration.indexOf(
    "create or replace function public.attach_execution_plan_context",
  );
  const commit = migration.lastIndexOf("commit;");
  assert.ok(lock < classification);
  assert.ok(classification < insertGuard);
  assert.ok(insertGuard < canonicalAttachment);
  assert.ok(canonicalAttachment < commit);
  assert.match(migration, /revoke all on table private\.execution_plan_contexts from service_role;\n\ncommit;\s*$/);
});

test(`production-shaped legacy hashes classify ${SANITIZED_LIVE_HASH_FIXTURE.legacyNodeRows} plus ${SANITIZED_LIVE_HASH_FIXTURE.legacyPostgresRows} without rewriting evidence`, async () => {
  const db = await createHashContractDb();
  const envelope = legacyV1Envelope();
  const encodedEnvelope = JSON.stringify(envelope);
  const legacyNodeHash = sha256(encodedEnvelope);
  const fingerprintSql = `
    select encode(extensions.digest(convert_to(coalesce(string_agg(
      encode(extensions.digest(convert_to(
        plan_id::text || ':' || context_hash || ':' || context_envelope::text,
        'UTF8'
      ), 'sha256'), 'hex'), E'\\n' order by plan_id
    ), ''), 'UTF8'), 'sha256'), 'hex') as fingerprint
    from private.execution_plan_contexts
  `;

  try {
    await db.query(
      `insert into private.execution_plan_contexts
        (plan_id, context_hash, context_envelope)
       select extensions.gen_random_uuid(), $1::text, $2::jsonb
       from generate_series(1, ${SANITIZED_LIVE_HASH_FIXTURE.legacyNodeRows})`,
      [legacyNodeHash, encodedEnvelope],
    );
    const providerTextRow = await db.query(
      `insert into private.execution_plan_contexts
        (plan_id, context_hash, context_envelope)
       select
         extensions.gen_random_uuid(),
         encode(extensions.digest(convert_to($1::jsonb::text, 'UTF8'), 'sha256'), 'hex'),
         $1::jsonb
       returning context_hash`,
      [encodedEnvelope],
    );
    const providerTextHash = providerTextRow.rows[0].context_hash;
    assert.notEqual(providerTextHash, legacyNodeHash);
    const before = await db.query(fingerprintSql);
    const exactEvidenceBefore = await db.query(`
      select plan_id::text, context_hash, context_envelope::text as context_envelope
      from private.execution_plan_contexts
      order by plan_id
    `);
    assert.equal(
      exactEvidenceBefore.rows.length,
      SANITIZED_LIVE_HASH_FIXTURE.totalRows,
    );

    await db.exec(atomicHashContractSql);
    await db.exec(contextHashConstraintSql);

    const after = await db.query(fingerprintSql);
    assert.equal(after.rows[0].fingerprint, before.rows[0].fingerprint);
    const exactEvidenceAfter = await db.query(`
      select plan_id::text, context_hash, context_envelope::text as context_envelope
      from private.execution_plan_contexts
      order by plan_id
    `);
    assert.deepEqual(exactEvidenceAfter.rows, exactEvidenceBefore.rows);
    const classified = await db.query(`
      select hash_contract, count(*)::integer as count
      from private.execution_plan_contexts
      group by hash_contract
      order by hash_contract
    `);
    assert.deepEqual(classified.rows, [
      {
        hash_contract: "legacy-js-json-stringify-envelope-v1",
        count: SANITIZED_LIVE_HASH_FIXTURE.legacyNodeRows,
      },
      {
        hash_contract: "legacy-postgres-jsonb-text-sha256-v1",
        count: 1,
      },
    ]);
    const originalHashes = await db.query(`
      select
        count(*) filter (where context_hash = $1)::integer as node_rows,
        count(*) filter (where context_hash = $2)::integer as provider_text_rows,
        count(*) filter (
          where canonical_context_hash = private.projectos_context_json_sha256(
            private.projectos_canonical_context_json(context_envelope)
          )
        )::integer as canonical_derived_rows
      from private.execution_plan_contexts
    `, [legacyNodeHash, providerTextHash]);
    assert.deepEqual(originalHashes.rows, [{
      node_rows: SANITIZED_LIVE_HASH_FIXTURE.legacyNodeRows,
      provider_text_rows: SANITIZED_LIVE_HASH_FIXTURE.legacyPostgresRows,
      canonical_derived_rows: SANITIZED_LIVE_HASH_FIXTURE.totalRows,
    }]);
    const validatedConstraint = await db.query(`
      select convalidated
      from pg_constraint
      where conname = 'execution_plan_contexts_hash_matches_envelope'
    `);
    assert.deepEqual(validatedConstraint.rows, [{ convalidated: true }]);

    const canonicalHash = hashPlanMemoryContextEnvelope(envelope);
    await assert.rejects(
      db.query(
        `insert into private.execution_plan_contexts
          (plan_id, context_hash, hash_contract, canonical_context_hash, context_envelope)
         values (
           extensions.gen_random_uuid(), $1,
           'legacy-js-json-stringify-envelope-v1', $2, $3::jsonb
         )`,
        [legacyNodeHash, canonicalHash, encodedEnvelope],
      ),
      (error) => error.code === "23514",
    );

    const canonicalPlanId = "05f60218-9cb8-4c78-b533-0e328ee12887";
    await db.query(
      `insert into private.execution_plan_contexts
        (plan_id, context_hash, hash_contract, canonical_context_hash, context_envelope)
       values ($1, $2, 'canonical-json-c-utf8-sha256-v1', $2, $3::jsonb)`,
      [canonicalPlanId, canonicalHash, encodedEnvelope],
    );
    await assert.rejects(
      db.query(
        "update private.execution_plan_contexts set context_hash = context_hash where plan_id = $1",
        [canonicalPlanId],
      ),
      (error) => error.code === "55000",
    );
    await assert.rejects(
      db.query(
        "delete from private.execution_plan_contexts where plan_id = $1",
        [canonicalPlanId],
      ),
      (error) => error.code === "55000",
    );
  } finally {
    await db.close();
  }
});

test("an unclassified historical hash aborts the atomic migration", async () => {
  const db = await createHashContractDb();
  try {
    await db.query(
      `insert into private.execution_plan_contexts
        (plan_id, context_hash, context_envelope)
       values (extensions.gen_random_uuid(), $1, $2::jsonb)`,
      ["f".repeat(64), JSON.stringify(legacyV1Envelope())],
    );
    await assert.rejects(
      db.exec(atomicHashContractSql),
      (error) => {
        assert.equal(error.code, "23514");
        assert.match(error.message, /hash provenance is unclassified/);
        return true;
      },
    );
    await db.exec("rollback");
    const preserved = await db.query(`
      select
        count(*)::integer as row_count,
        bool_and(context_hash = $1) as hash_unchanged,
        bool_and(context_envelope = $2::jsonb) as envelope_unchanged
      from private.execution_plan_contexts
    `, ["f".repeat(64), JSON.stringify(legacyV1Envelope())]);
    assert.deepEqual(preserved.rows, [{
      row_count: 1,
      hash_unchanged: true,
      envelope_unchanged: true,
    }]);
    const columns = await db.query(`
      select column_name
      from information_schema.columns
      where table_schema = 'private'
        and table_name = 'execution_plan_contexts'
        and column_name in ('hash_contract', 'canonical_context_hash')
    `);
    assert.deepEqual(columns.rows, []);
  } finally {
    await db.close();
  }
});

test("database behavior permits only first pending attachment and exact replay", async () => {
  const db = new PGlite({ extensions: { pgcrypto } });
  const organizationId = "161cd8b0-6814-4208-b7bf-2b4f7ffb64f0";
  const pendingPlanId = "45a72e49-ec9c-441d-90da-35bd00fdaef1";
  const pendingRequestId = "46d8a81c-8db7-4244-a577-1bbba1e40291";
  const approvedPlanId = "e1f6c5f7-4280-48fa-befd-34a323f6a5c8";
  const approvedRequestId = "446b1be1-66d3-407f-916c-e635f9f0703e";
  const expiredPlanId = "e32a9969-5542-4939-bb33-5890beca3638";
  const expiredRequestId = "ba4e34b5-9114-439d-bc17-8db7d193d1bd";
  const fullAvailablePlanId = "83ad2ee3-3808-4bcf-92e5-a45d3af4d3d1";
  const fullAvailableRequestId = "7672a4ea-6aae-484d-8711-794c0e98538d";
  const fullEmptyPlanId = "8c6e20a6-7bb0-41fd-9a66-6d879ab401b4";
  const fullEmptyRequestId = "eaf4625e-c82f-48c4-8e3d-f6db8aac57d5";
  const fullUnavailablePlanId = "a799bdd2-8c80-4e82-829d-2864e0d7ed3e";
  const fullUnavailableRequestId = "e33b4fb9-203d-418f-8193-f7d2115cd016";
  const fullUnavailableStatusPlanId = "63240618-d306-45f7-8fcc-bc4fd9d53b26";
  const fullUnavailableStatusRequestId = "e64e43b4-c04c-4cf7-a01b-c11b081fe82a";
  const legacyReplayPlanId = "7d9e3357-1acf-4f5a-bd36-7b50abcfb028";
  const legacyReplayRequestId = "aef2c688-d1aa-420f-b8bc-44df08e44fb7";
  const v1EmptyPlanId = "c296d5ea-ab13-4cba-8f7f-c860c3d16013";
  const v1EmptyRequestId = "069ef3b5-f91d-46de-a1e0-3d798b9b5f3d";
  const v1UnavailablePlanId = "bb8b39c3-38a0-42eb-b7ec-caf46a0b06f9";
  const v1UnavailableRequestId = "75be82f8-d04e-45b0-a584-306710134e7a";
  const envelope = {
    schemaVersion: "1.0.0",
    source: "pandora-memory",
    queryBasis: {
      tool: "projectos.worker.verify",
      identifiers: {
        branch: "main",
        repository: "banataosystems/Pandoras-box",
      },
    },
    counts: {
      projectContext: 1,
      riskWarnings: 0,
      openLoops: 1,
      recentEvents: 0,
      semanticMatches: 1,
    },
    highlights: {
      project: ["Canonical status pack"],
      risks: [],
      openLoops: ["Complete the physical Android journey"],
      recent: [],
      semantic: ["Return to customer interviews"],
    },
    warnings: [],
    retrievedAt: "2026-08-23T16:30:00.000Z",
    status: "available",
    namespace: "real_life",
    queryHash: "b".repeat(64),
  };
  const reorderedEnvelope = {
    queryHash: envelope.queryHash,
    namespace: envelope.namespace,
    status: envelope.status,
    retrievedAt: envelope.retrievedAt,
    warnings: [],
    highlights: {
      semantic: ["Return to customer interviews"],
      recent: [],
      openLoops: ["Complete the physical Android journey"],
      risks: [],
      project: ["Canonical status pack"],
    },
    counts: {
      semanticMatches: 1,
      recentEvents: 0,
      openLoops: 1,
      riskWarnings: 0,
      projectContext: 1,
    },
    queryBasis: {
      identifiers: {
        repository: "banataosystems/Pandoras-box",
        branch: "main",
      },
      tool: "projectos.worker.verify",
    },
    source: envelope.source,
    schemaVersion: envelope.schemaVersion,
  };
  const canonicalContext = canonicalPlanMemoryContextJson(envelope);
  const contextHash = hashPlanMemoryContextEnvelope(envelope);
  const mismatchedContextHash = `${contextHash[0] === "0" ? "1" : "0"}${contextHash.slice(1)}`;

  const attach = (planId, requestId, hash, contextEnvelope) => db.query(
    `select public.attach_execution_plan_context(
      $1::uuid, $2::uuid, $3::uuid, $4::text, $5::jsonb
    ) as context`,
    [
      organizationId,
      planId,
      requestId,
      hash,
      JSON.stringify(contextEnvelope),
    ],
  );
  const expectDatabaseError = async (operation, code, message, description) => {
    await assert.rejects(operation, (error) => {
      assert.equal(error.code, code);
      assert.match(error.message, message);
      return true;
    }, description);
  };

  try {
    await db.exec(`
      create role anon nologin;
      create role authenticated nologin;
      create role service_role nologin;
      create schema private;
      create schema extensions;
      create extension if not exists pgcrypto with schema extensions;

      create table private.execution_plans (
        id uuid primary key,
        organization_id uuid not null,
        request_id uuid not null,
        tool text not null,
        risk text not null,
        payload_hash text not null,
        status text not null,
        expires_at timestamptz not null,
        created_at timestamptz not null default now()
      );

      create table private.execution_plan_contexts (
        plan_id uuid primary key,
        organization_id uuid not null,
        request_id uuid not null,
        context_hash text not null,
        context_status text not null,
        namespace text not null,
        context_envelope jsonb not null,
        recorded_at timestamptz not null default now(),
        updated_at timestamptz not null default now(),
        unique (organization_id, request_id)
      );

      create table private.test_execution_audit_events (
        plan_id uuid not null,
        event_type text not null
      );

      create function private.assert_control_service_role()
      returns void
      language plpgsql
      security definer
      set search_path = ''
      as $$ begin return; end $$;

      create function private.append_execution_audit(
        p_organization_id uuid,
        p_plan_id uuid,
        p_request_id uuid,
        p_event_type text,
        p_status text,
        p_tool text,
        p_risk text,
        p_payload_hash text,
        p_details jsonb default '{}'::jsonb
      )
      returns jsonb
      language plpgsql
      security definer
      set search_path = ''
      as $$
      begin
        insert into private.test_execution_audit_events (plan_id, event_type)
        values (p_plan_id, p_event_type);
        return '{}'::jsonb;
      end;
      $$;

      insert into private.execution_plans
        (id, organization_id, request_id, tool, risk, payload_hash, status, expires_at)
      values
        ('${pendingPlanId}', '${organizationId}', '${pendingRequestId}',
         'projectos.worker.verify', 'write', '${"c".repeat(64)}',
         'pending_approval', now() + interval '10 minutes'),
        ('${approvedPlanId}', '${organizationId}', '${approvedRequestId}',
         'projectos.worker.verify', 'write', '${"d".repeat(64)}',
         'approved', now() + interval '10 minutes'),
        ('${expiredPlanId}', '${organizationId}', '${expiredRequestId}',
         'projectos.worker.verify', 'write', '${"e".repeat(64)}',
         'pending_approval', now() - interval '1 second'),
        ('${fullAvailablePlanId}', '${organizationId}', '${fullAvailableRequestId}',
         'projectos.worker.verify', 'write', '${"1".repeat(64)}',
         'pending_approval', now() + interval '10 minutes'),
        ('${fullEmptyPlanId}', '${organizationId}', '${fullEmptyRequestId}',
         'projectos.worker.verify', 'read', '${"2".repeat(64)}',
         'pending_approval', now() + interval '10 minutes'),
        ('${fullUnavailablePlanId}', '${organizationId}', '${fullUnavailableRequestId}',
         'projectos.worker.verify', 'read', '${"3".repeat(64)}',
         'pending_approval', now() + interval '10 minutes'),
        ('${fullUnavailableStatusPlanId}', '${organizationId}', '${fullUnavailableStatusRequestId}',
         'projectos.worker.verify', 'read', '${"4".repeat(64)}',
         'pending_approval', now() + interval '10 minutes'),
        ('${v1EmptyPlanId}', '${organizationId}', '${v1EmptyRequestId}',
         'projectos.worker.verify', 'read', '${"6".repeat(64)}',
         'pending_approval', now() + interval '10 minutes'),
        ('${v1UnavailablePlanId}', '${organizationId}', '${v1UnavailableRequestId}',
         'projectos.worker.verify', 'read', '${"7".repeat(64)}',
         'pending_approval', now() + interval '10 minutes'),
        ('${legacyReplayPlanId}', '${organizationId}', '${legacyReplayRequestId}',
         'projectos.worker.verify', 'write', '${"5".repeat(64)}',
         'approved', now() + interval '10 minutes');
    `);

    const legacyReplayEnvelope = legacyV1Envelope();
    legacyReplayEnvelope.counts.projectContext = 51;
    const legacyReplayHash = sha256(JSON.stringify(legacyReplayEnvelope));
    await db.query(
      `insert into private.execution_plan_contexts (
        plan_id, organization_id, request_id, context_hash, context_status,
        namespace, context_envelope
      ) values ($1, $2, $3, $4, 'available', 'real_life', $5::jsonb)`,
      [
        legacyReplayPlanId,
        organizationId,
        legacyReplayRequestId,
        legacyReplayHash,
        JSON.stringify(legacyReplayEnvelope),
      ],
    );
    await db.exec(migration);
    await db.exec(fullCapacityGateMigration);
    await db.exec(`
      create trigger projectos_require_memory_context_before_execute
      before update of status on private.execution_plans
      for each row
      when (new.status = 'executing' and old.status is distinct from new.status)
      execute function private.enforce_execution_plan_memory_context();
    `);

    assert.equal(
      canonicalPlanMemoryContextJson(reorderedEnvelope),
      canonicalContext,
    );
    assert.equal(
      hashPlanMemoryContextEnvelope(reorderedEnvelope),
      contextHash,
    );
    const sqlCanonical = await db.query(
      `select
        private.projectos_canonical_context_json($1::jsonb) as canonical_json,
        encode(
          extensions.digest(
            convert_to(private.projectos_canonical_context_json($1::jsonb), 'UTF8'),
            'sha256'
          ),
          'hex'
        ) as context_hash`,
      [JSON.stringify(reorderedEnvelope)],
    );
    assert.equal(sqlCanonical.rows[0].canonical_json, canonicalContext);
    assert.equal(sqlCanonical.rows[0].context_hash, contextHash);

    const unicodeOrderingProbe = {
      nested: {
        "\u{1F600}": "supplementary-code-point",
        "\uE000": "bytewise-before-supplementary",
      },
    };
    const sqlOrderingProbe = await db.query(
      "select private.projectos_canonical_context_json($1::jsonb) as canonical_json",
      [JSON.stringify(unicodeOrderingProbe)],
    );
    assert.equal(
      sqlOrderingProbe.rows[0].canonical_json,
      canonicalPlanMemoryContextJson(unicodeOrderingProbe),
    );

    await db.exec("set role service_role");

    const historicalReplay = await attach(
      legacyReplayPlanId,
      legacyReplayRequestId,
      legacyReplayHash,
      legacyReplayEnvelope,
    );
    assert.equal(historicalReplay.rows[0].context.contextHash, legacyReplayHash);

    const v1UnavailableMatrixBase = legacyV1UnavailableEnvelope();
    const v1ShapeMatrix = [
      ...requiredKeyMutationCases(
        envelope,
        [],
        [
          "schemaVersion", "status", "source", "namespace", "retrievedAt",
          "queryHash", "queryBasis", "counts", "highlights", "warnings",
        ],
        "v1.top",
      ),
      ...requiredKeyMutationCases(
        envelope,
        ["queryBasis"],
        ["tool", "identifiers"],
        "v1.queryBasis",
      ),
      ...identifierMutationCases(
        envelope,
        ["queryBasis", "identifiers"],
        "v1.identifiers",
      ),
      ...requiredKeyMutationCases(
        envelope,
        ["counts"],
        Object.keys(envelope.counts),
        "v1.counts",
      ),
      ...requiredKeyMutationCases(
        envelope,
        ["highlights"],
        Object.keys(envelope.highlights),
        "v1.highlights",
      ),
      ...requiredKeyMutationCases(
        v1UnavailableMatrixBase,
        [],
        ["failure"],
        "v1.top",
      ),
      ...requiredKeyMutationCases(
        v1UnavailableMatrixBase,
        ["failure"],
        ["type"],
        "v1.failure",
      ),
    ];
    const v1NullWarning = structuredClone(envelope);
    v1NullWarning.warnings = [null];
    v1ShapeMatrix.push({
      name: "v1.warnings.element:json-null",
      envelope: v1NullWarning,
    });
    const v1WrongTypeWarning = structuredClone(envelope);
    v1WrongTypeWarning.warnings = [{ unexpected: true }];
    v1ShapeMatrix.push({
      name: "v1.warnings.element:wrong-type",
      envelope: v1WrongTypeWarning,
    });

    const v2AvailableMatrixBase = fullCapacityEnvelope();
    const v2UnavailableMatrixBase = fullCapacityEnvelope({
      unavailable: true,
    });
    const v2ShapeMatrix = [
      ...requiredKeyMutationCases(
        v2AvailableMatrixBase,
        [],
        [
          "schemaVersion", "status", "source", "namespace", "retrievedAt",
          "queryHash", "queryBasis", "counts", "highlights", "retrieval",
          "capabilityContract", "fallbackRequired", "warnings",
        ],
        "v2.available.top",
      ),
      ...requiredKeyMutationCases(
        v2AvailableMatrixBase,
        ["queryBasis"],
        ["tool", "identifiers"],
        "v2.queryBasis",
      ),
      ...identifierMutationCases(
        v2AvailableMatrixBase,
        ["queryBasis", "identifiers"],
        "v2.identifiers",
      ),
      ...requiredKeyMutationCases(
        v2AvailableMatrixBase,
        ["counts"],
        Object.keys(v2AvailableMatrixBase.counts),
        "v2.counts",
      ),
      ...requiredKeyMutationCases(
        v2AvailableMatrixBase,
        ["highlights"],
        Object.keys(v2AvailableMatrixBase.highlights),
        "v2.highlights",
      ),
      ...requiredKeyMutationCases(
        v2AvailableMatrixBase,
        ["retrieval"],
        Object.keys(v2AvailableMatrixBase.retrieval),
        "v2.available.retrieval",
      ),
      ...requiredKeyMutationCases(
        v2AvailableMatrixBase,
        ["capabilityContract"],
        Object.keys(v2AvailableMatrixBase.capabilityContract),
        "v2.verified.capabilityContract",
      ),
      ...requiredKeyMutationCases(
        v2UnavailableMatrixBase,
        [],
        ["failure"],
        "v2.unavailable.top",
      ),
      ...requiredKeyMutationCases(
        v2UnavailableMatrixBase,
        ["retrieval"],
        Object.keys(v2UnavailableMatrixBase.retrieval),
        "v2.unavailable.retrieval",
      ),
      ...requiredKeyMutationCases(
        v2UnavailableMatrixBase,
        ["capabilityContract"],
        Object.keys(v2UnavailableMatrixBase.capabilityContract),
        "v2.unavailable.capabilityContract",
      ),
      ...requiredKeyMutationCases(
        v2UnavailableMatrixBase,
        ["failure"],
        ["type"],
        "v2.failure",
      ),
    ];
    const v2NullWarning = structuredClone(v2AvailableMatrixBase);
    v2NullWarning.warnings = [null];
    v2ShapeMatrix.push({
      name: "v2.warnings.element:json-null",
      envelope: v2NullWarning,
    });
    const v2WrongTypeWarning = structuredClone(v2AvailableMatrixBase);
    v2WrongTypeWarning.warnings = [{ unexpected: true }];
    v2ShapeMatrix.push({
      name: "v2.warnings.element:wrong-type",
      envelope: v2WrongTypeWarning,
    });
    const v2UnknownFailureKey = structuredClone(v2UnavailableMatrixBase);
    v2UnknownFailureKey.failure.__unexpected_code =
      v2UnknownFailureKey.failure.code;
    delete v2UnknownFailureKey.failure.code;
    v2ShapeMatrix.push({
      name: "v2.failure.code:unknown-equal-cardinality",
      envelope: v2UnknownFailureKey,
    });
    const v2NullFailureCode = structuredClone(v2UnavailableMatrixBase);
    v2NullFailureCode.failure.code = null;
    v2ShapeMatrix.push({
      name: "v2.failure.code:json-null",
      envelope: v2NullFailureCode,
    });
    const v2WrongTypeFailureCode = structuredClone(v2UnavailableMatrixBase);
    v2WrongTypeFailureCode.failure.code = 503;
    v2ShapeMatrix.push({
      name: "v2.failure.code:wrong-type",
      envelope: v2WrongTypeFailureCode,
    });

    assert.equal(v1ShapeMatrix.length, 101);
    assert.equal(v2ShapeMatrix.length, 276);
    for (const shapeCase of [...v1ShapeMatrix, ...v2ShapeMatrix]) {
      await expectDatabaseError(
        attach(
          pendingPlanId,
          pendingRequestId,
          hashPlanMemoryContextEnvelope(shapeCase.envelope),
          shapeCase.envelope,
        ),
        "22023",
        /invalid/,
        shapeCase.name,
      );
    }

    const v1WithoutWarnings = { ...envelope };
    delete v1WithoutWarnings.warnings;
    const v1WithNullTool = {
      ...envelope,
      queryBasis: { ...envelope.queryBasis, tool: null },
    };
    const v1WithExtraHighlight = {
      ...envelope,
      highlights: { ...envelope.highlights, unexpected: [] },
    };
    const v1WithTooManyHighlights = {
      ...envelope,
      highlights: {
        ...envelope.highlights,
        project: ["one", "two", "three", "four"],
      },
    };
    const v1UnavailableWithoutFailure = {
      ...envelope,
      status: "unavailable",
    };
    const v1AvailableWithFailure = {
      ...envelope,
      failure: { type: "PandoraMemoryError", status: 503 },
    };
    const v1WithImpossibleRetrievedAt = {
      ...envelope,
      retrievedAt: "2026-02-30T00:00:00.000Z",
    };
    const v1AvailableWithoutSignal = structuredClone(envelope);
    v1AvailableWithoutSignal.counts = Object.fromEntries(
      Object.keys(v1AvailableWithoutSignal.counts).map((key) => [key, 0]),
    );
    v1AvailableWithoutSignal.highlights = Object.fromEntries(
      Object.keys(v1AvailableWithoutSignal.highlights).map((key) => [key, []]),
    );
    const v1EmptyWithSignal = {
      ...envelope,
      status: "empty",
    };
    const v1UnavailableWithSignal = {
      ...envelope,
      status: "unavailable",
      warnings: ["memory_context_unavailable"],
      failure: { type: "PandoraMemoryError", status: 503 },
    };
    const v1UnavailableWithExtraWarning = structuredClone(
      v1AvailableWithoutSignal,
    );
    v1UnavailableWithExtraWarning.status = "unavailable";
    v1UnavailableWithExtraWarning.warnings = [
      "memory_context_unavailable",
      "unexpected_warning",
    ];
    v1UnavailableWithExtraWarning.failure = {
      type: "PandoraMemoryError",
      status: 503,
    };
    for (const invalidV1 of [
      v1WithoutWarnings,
      v1WithNullTool,
      v1WithExtraHighlight,
      v1WithTooManyHighlights,
      v1UnavailableWithoutFailure,
      v1AvailableWithFailure,
      v1WithImpossibleRetrievedAt,
      v1AvailableWithoutSignal,
      v1EmptyWithSignal,
      v1UnavailableWithSignal,
      v1UnavailableWithExtraWarning,
    ]) {
      await expectDatabaseError(
        attach(
          pendingPlanId,
          pendingRequestId,
          hashPlanMemoryContextEnvelope(invalidV1),
          invalidV1,
        ),
        "22023",
        /invalid context envelope contract/,
      );
    }

    const validV1Empty = structuredClone(v1AvailableWithoutSignal);
    validV1Empty.status = "empty";
    await attach(
      v1EmptyPlanId,
      v1EmptyRequestId,
      hashPlanMemoryContextEnvelope(validV1Empty),
      validV1Empty,
    );
    const validV1Unavailable = legacyV1UnavailableEnvelope();
    await attach(
      v1UnavailablePlanId,
      v1UnavailableRequestId,
      hashPlanMemoryContextEnvelope(validV1Unavailable),
      validV1Unavailable,
    );
    const wrongPlanTool = {
      ...envelope,
      queryBasis: {
        ...envelope.queryBasis,
        tool: "github.get-repository",
      },
    };
    await expectDatabaseError(
      attach(
        pendingPlanId,
        pendingRequestId,
        hashPlanMemoryContextEnvelope(wrongPlanTool),
        wrongPlanTool,
      ),
      "22023",
      /context tool does not match execution plan/,
    );

    await expectDatabaseError(
      attach(
        pendingPlanId,
        pendingRequestId,
        hashPlanMemoryContextEnvelope({ ...envelope, unexpected: true }),
        { ...envelope, unexpected: true },
      ),
      "22023",
      /invalid context envelope contract/,
    );
    const malformedCountsEnvelope = {
      ...envelope,
      counts: { ...envelope.counts, unexpected: 0 },
    };
    await expectDatabaseError(
      attach(
        pendingPlanId,
        pendingRequestId,
        hashPlanMemoryContextEnvelope(malformedCountsEnvelope),
        malformedCountsEnvelope,
      ),
      "22023",
      /invalid context envelope contract/,
    );
    await expectDatabaseError(
      attach(
        pendingPlanId,
        pendingRequestId,
        mismatchedContextHash,
        envelope,
      ),
      "22023",
      /context hash does not match canonical envelope/,
    );

    const freshRetrievedAt = new Date().toISOString();
    const fixedFullAvailable = fullCapacityEnvelope();
    assert.equal(
      sha256(JSON.stringify(fixedFullAvailable)),
      "a72ae92697549876e9c6d6f94a3d35076ec230fde994e2784afbcc6da3bbf2b5",
    );
    assert.equal(
      hashPlanMemoryContextEnvelope(fixedFullAvailable),
      "586023c8fc81ce7bf6d201ee207db8696b172c5be9fb97f6ff1e48dceb99d075",
    );
    const fullAvailable = {
      ...fixedFullAvailable,
      retrievedAt: freshRetrievedAt,
    };
    const wrongBooleanFullCapacity = {
      ...fullAvailable,
      fallbackRequired: "false",
    };
    await expectDatabaseError(
      attach(
        fullAvailablePlanId,
        fullAvailableRequestId,
        hashPlanMemoryContextEnvelope(wrongBooleanFullCapacity),
        wrongBooleanFullCapacity,
      ),
      "22023",
      /invalid full-capacity context envelope/,
    );
    const unknownKeyFullCapacity = {
      ...fullAvailable,
      unexpected: true,
    };
    await expectDatabaseError(
      attach(
        fullAvailablePlanId,
        fullAvailableRequestId,
        hashPlanMemoryContextEnvelope(unknownKeyFullCapacity),
        unknownKeyFullCapacity,
      ),
      "22023",
      /invalid full-capacity context envelope/,
    );
    const missingCapabilityPath = structuredClone(fullAvailable);
    delete missingCapabilityPath.capabilityContract.path;
    const nullRetrievalMode = structuredClone(fullAvailable);
    nullRetrievalMode.retrieval.mode = null;
    const extraCapabilityKey = structuredClone(fullAvailable);
    extraCapabilityKey.capabilityContract.unexpected = true;
    const unapprovedCapabilityHash = structuredClone(fullAvailable);
    unapprovedCapabilityHash.capabilityContract.semanticHash = "e".repeat(64);
    const oversizedArrayBackedCount = structuredClone(fullAvailable);
    oversizedArrayBackedCount.counts.projectContext = 51;
    const wrongTypeQueryHash = {
      ...fullAvailable,
      queryHash: 1,
    };
    const impossibleRetrievedAt = {
      ...fullAvailable,
      retrievedAt: "2026-02-30T00:00:00.000Z",
    };
    for (const invalidFullCapacity of [
      missingCapabilityPath,
      nullRetrievalMode,
      extraCapabilityKey,
      unapprovedCapabilityHash,
      oversizedArrayBackedCount,
      wrongTypeQueryHash,
      impossibleRetrievedAt,
    ]) {
      await expectDatabaseError(
        attach(
          fullAvailablePlanId,
          fullAvailableRequestId,
          hashPlanMemoryContextEnvelope(invalidFullCapacity),
          invalidFullCapacity,
        ),
        "22023",
        /invalid (?:full-capacity )?context envelope/,
      );
    }
    const availableWithoutSignal = {
      ...fullCapacityEnvelope({ status: "empty" }),
      status: "available",
    };
    await expectDatabaseError(
      attach(
        fullAvailablePlanId,
        fullAvailableRequestId,
        hashPlanMemoryContextEnvelope(availableWithoutSignal),
        availableWithoutSignal,
      ),
      "22023",
      /invalid full-capacity context envelope/,
    );
    await attach(
      fullAvailablePlanId,
      fullAvailableRequestId,
      hashPlanMemoryContextEnvelope(fullAvailable),
      fullAvailable,
    );

    const fixedFullEmpty = fullCapacityEnvelope({ status: "empty" });
    assert.equal(
      sha256(JSON.stringify(fixedFullEmpty)),
      "317374404cb25fdbc1301bb5550f9f03b7b2b22d4499b449e860889b937f1713",
    );
    assert.equal(
      hashPlanMemoryContextEnvelope(fixedFullEmpty),
      "241d38b46d36816843a4905c1f6f717f22938efba35d97f01f0b5e35f2256338",
    );
    const fullEmpty = { ...fixedFullEmpty, retrievedAt: freshRetrievedAt };
    await attach(
      fullEmptyPlanId,
      fullEmptyRequestId,
      hashPlanMemoryContextEnvelope(fullEmpty),
      fullEmpty,
    );

    const fixedFullUnavailable = fullCapacityEnvelope({ unavailable: true });
    assert.equal(
      sha256(JSON.stringify(fixedFullUnavailable)),
      "e841adf5c0103efb5c9edb9c9d8ae1d45460a17d7807f93b7446c986776aedbf",
    );
    assert.equal(
      hashPlanMemoryContextEnvelope(fixedFullUnavailable),
      "a30165b5354cc80dd08bf6737134e4aa65ccb345b8fb9e0a22f26145a20b8717",
    );
    const fullUnavailable = {
      ...fixedFullUnavailable,
      retrievedAt: freshRetrievedAt,
    };
    const unavailableWithExtraRetrieval = structuredClone(fullUnavailable);
    unavailableWithExtraRetrieval.retrieval.mode = "unexpected";
    const unavailableWithExtraWarning = structuredClone(fullUnavailable);
    unavailableWithExtraWarning.warnings.push("unexpected_warning");
    await expectDatabaseError(
      attach(
        fullUnavailablePlanId,
        fullUnavailableRequestId,
        hashPlanMemoryContextEnvelope(unavailableWithExtraRetrieval),
        unavailableWithExtraRetrieval,
      ),
      "22023",
      /invalid full-capacity context envelope/,
    );
    await expectDatabaseError(
      attach(
        fullUnavailablePlanId,
        fullUnavailableRequestId,
        hashPlanMemoryContextEnvelope(unavailableWithExtraWarning),
        unavailableWithExtraWarning,
      ),
      "22023",
      /invalid full-capacity context envelope/,
    );
    await attach(
      fullUnavailablePlanId,
      fullUnavailableRequestId,
      hashPlanMemoryContextEnvelope(fullUnavailable),
      fullUnavailable,
    );

    const wrongStatusFailure = {
      ...fullCapacityEnvelope({
      unavailable: true,
      failure: { type: "MemoryCapabilityContractError", status: 503 },
      }),
      retrievedAt: freshRetrievedAt,
    };
    await expectDatabaseError(
      attach(
        fullUnavailableStatusPlanId,
        fullUnavailableStatusRequestId,
        hashPlanMemoryContextEnvelope(wrongStatusFailure),
        wrongStatusFailure,
      ),
      "22023",
      /invalid full-capacity context envelope/,
    );
    const fixedFullUnavailableStatus = fullCapacityEnvelope({
      unavailable: true,
      failure: { type: "PandoraMemoryError", status: 503 },
    });
    assert.equal(
      sha256(JSON.stringify(fixedFullUnavailableStatus)),
      "17909eb3b37f4584c7a14f63397912420ce330880c60276391fa55ea09610a1a",
    );
    assert.equal(
      hashPlanMemoryContextEnvelope(fixedFullUnavailableStatus),
      "cbb575b1402fc6fa3222f67a3c87123e836ea503c288eea9f341b7645e25906a",
    );
    const fullUnavailableStatus = {
      ...fixedFullUnavailableStatus,
      retrievedAt: freshRetrievedAt,
    };
    await attach(
      fullUnavailableStatusPlanId,
      fullUnavailableStatusRequestId,
      hashPlanMemoryContextEnvelope(fullUnavailableStatus),
      fullUnavailableStatus,
    );

    const first = await attach(
      pendingPlanId,
      pendingRequestId,
      contextHash,
      envelope,
    );

    await db.exec("reset role");
    await db.exec(`
      update private.execution_plans
      set status = 'approved'
      where id = '${pendingPlanId}'
    `);
    await db.exec("set role service_role");

    const replay = await attach(
      pendingPlanId,
      pendingRequestId,
      contextHash,
      reorderedEnvelope,
    );
    assert.equal(
      replay.rows[0].context.recordedAt,
      first.rows[0].context.recordedAt,
    );

    const changedEnvelope = {
      ...envelope,
      retrievedAt: "2026-08-23T16:31:00.000Z",
    };
    const changedContextHash = hashPlanMemoryContextEnvelope(changedEnvelope);
    assert.notEqual(changedContextHash, contextHash);
    await expectDatabaseError(
      attach(
        pendingPlanId,
        pendingRequestId,
        changedContextHash,
        changedEnvelope,
      ),
      "55000",
      /execution plan context is immutable/,
    );
    await expectDatabaseError(
      attach(approvedPlanId, approvedRequestId, contextHash, envelope),
      "55000",
      /execution plan context attachment is closed/,
    );
    await expectDatabaseError(
      attach(expiredPlanId, expiredRequestId, contextHash, envelope),
      "55000",
      /execution plan context attachment is closed/,
    );
    await assert.rejects(
      db.query("select * from private.execution_plan_contexts"),
      /permission denied/,
    );

    await db.exec("reset role");
    await db.query(
      "update private.execution_plans set status = 'executing' where id = $1",
      [fullAvailablePlanId],
    );
    await db.query(
      "update private.execution_plans set status = 'executing' where id = $1",
      [fullEmptyPlanId],
    );
    await expectDatabaseError(
      db.query(
        "update private.execution_plans set status = 'executing' where id = $1",
        [fullUnavailablePlanId],
      ),
      "55000",
      /projectos_memory_full_capacity_contract_invalid/,
    );
    const executionStatuses = await db.query(
      `select id, status from private.execution_plans
       where id in ($1, $2, $3)
       order by id`,
      [fullAvailablePlanId, fullEmptyPlanId, fullUnavailablePlanId],
    );
    assert.deepEqual(executionStatuses.rows, [
      { id: fullAvailablePlanId, status: "executing" },
      { id: fullEmptyPlanId, status: "executing" },
      { id: fullUnavailablePlanId, status: "pending_approval" },
    ].sort((left, right) => left.id.localeCompare(right.id)));
    const audit = await db.query(
      "select count(*)::integer as count from private.test_execution_audit_events",
    );
    assert.equal(audit.rows[0].count, 7);
  } finally {
    await db.close();
  }
});
