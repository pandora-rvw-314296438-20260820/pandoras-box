"use strict";

const assert = require("node:assert/strict");
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

test("plan context replay requires the exact stored hash and envelope", () => {
  assert.match(
    migration,
    /if context_row\.plan_id is not null then[\s\S]*context_row\.context_hash = p_context_hash[\s\S]*and context_row\.context_envelope = p_context_envelope then[\s\S]*return jsonb_build_object/,
  );
  assert.match(
    migration,
    /raise exception 'execution plan context is immutable' using errcode = '55000'/,
  );

  const exactReplay = migration.indexOf(
    "context_row.context_hash = p_context_hash",
  );
  const immutableFailure = migration.indexOf(
    "execution plan context is immutable",
  );
  const firstAttachmentGate = migration.indexOf(
    "plan.status <> 'pending_approval'",
  );
  const insert = migration.indexOf(
    "insert into private.execution_plan_contexts",
  );
  assert.ok(exactReplay < immutableFailure);
  assert.ok(immutableFailure < firstAttachmentGate);
  assert.ok(firstAttachmentGate < insert);
});

test("first attachment is serialized and accepted only for an unexpired pending plan", () => {
  assert.match(
    migration,
    /from private\.execution_plans[\s\S]*where id = p_plan_id[\s\S]*and organization_id = p_organization_id[\s\S]*and request_id = p_request_id[\s\S]*for update/,
  );
  assert.match(
    migration,
    /from private\.execution_plan_contexts[\s\S]*where plan_id = plan\.id[\s\S]*for update/,
  );
  assert.match(
    migration,
    /if plan\.status <> 'pending_approval' or plan\.expires_at <= now\(\) then[\s\S]*execution plan context attachment is closed/,
  );
  assert.doesNotMatch(migration, /on conflict[\s\S]*do update/i);
  assert.doesNotMatch(
    migration,
    /update\s+private\.execution_plan_contexts/i,
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

test("database behavior permits only first pending attachment and exact replay", async () => {
  const db = new PGlite({ extensions: { pgcrypto } });
  const organizationId = "161cd8b0-6814-4208-b7bf-2b4f7ffb64f0";
  const pendingPlanId = "45a72e49-ec9c-441d-90da-35bd00fdaef1";
  const pendingRequestId = "46d8a81c-8db7-4244-a577-1bbba1e40291";
  const approvedPlanId = "e1f6c5f7-4280-48fa-befd-34a323f6a5c8";
  const approvedRequestId = "446b1be1-66d3-407f-916c-e635f9f0703e";
  const expiredPlanId = "e32a9969-5542-4939-bb33-5890beca3638";
  const expiredRequestId = "ba4e34b5-9114-439d-bc17-8db7d193d1bd";
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
      "\uE000": ["bytewise-before-supplementary"],
      "\u{1F600}": ["supplementary-code-point"],
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
      "\u{1F600}": ["supplementary-code-point"],
      semantic: ["Return to customer interviews"],
      recent: [],
      openLoops: ["Complete the physical Android journey"],
      risks: [],
      project: ["Canonical status pack"],
      "\uE000": ["bytewise-before-supplementary"],
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
  const expectDatabaseError = async (operation, code, message) => {
    await assert.rejects(operation, (error) => {
      assert.equal(error.code, code);
      assert.match(error.message, message);
      return true;
    });
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
        expires_at timestamptz not null
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
         'pending_approval', now() - interval '1 second');
    `);
    await db.exec(migration);

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

    await db.exec("set role service_role");

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
      /invalid context counts/,
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
    const audit = await db.query(
      "select count(*)::integer as count from private.test_execution_audit_events",
    );
    assert.equal(audit.rows[0].count, 1);
  } finally {
    await db.close();
  }
});
