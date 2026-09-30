"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");
const { PGlite } = require("@electric-sql/pglite");
const { pgcrypto } = require("@electric-sql/pglite/contrib/pgcrypto");

const migration = readFileSync(
  join(__dirname, "../supabase/migrations/20260930111000_pandora_capability_provider_activation_v1.sql"),
  "utf8",
);

const org = "70000000-0000-4000-8000-000000000001";
const owner = "71000000-0000-4000-8000-000000000001";

async function makeDb(t) {
  const db = new PGlite({ extensions: { pgcrypto } });
  t.after(() => db.close());

  await db.exec(
    "create role anon nologin;" +
    "create role authenticated nologin;" +
    "create role service_role nologin;" +
    "create schema auth;" +
    "create schema private;" +
    "create extension pgcrypto with schema public;" +
    "grant usage on schema public,auth,private to authenticated,service_role;" +
    "create function auth.uid() returns uuid language sql stable as $$" +
    "select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid" +
    "$$;" +
    "create table public.organizations(id uuid primary key);" +
    "create table public.memberships(" +
      "organization_id uuid not null," +
      "user_id uuid not null," +
      "status text not null," +
      "primary key(organization_id,user_id)" +
    ");" +
    "create table public.enterprise_entities(" +
      "id uuid primary key default gen_random_uuid()," +
      "organization_id uuid not null," +
      "entity_kind text not null," +
      "unique(id,organization_id)" +
    ");" +
    "create table public.pandora_provider_health(" +
      "organization_id uuid not null," +
      "provider text not null," +
      "status text not null," +
      "last_event_at timestamptz," +
      "last_success_at timestamptz," +
      "stale_after timestamptz" +
    ");" +
    "create table private.execution_dispatch_outbox(" +
      "organization_id uuid not null," +
      "worker_reported_at timestamptz," +
      "verified_at timestamptz," +
      "error_code text," +
      "verified_outcome text" +
    ");" +
    "grant select on table public.memberships to authenticated,service_role;" +
    "insert into public.organizations(id) values ('" + org + "');" +
    "insert into public.memberships values ('" + org + "','" + owner + "','active');"
  );

  await db.exec(migration);
  return db;
}

async function seedSyntheticProviders(db) {
  await db.exec(
    "insert into public.pandora_provider_manifests(" +
      "provider_key,manifest_version,display_name,lifecycle_state,auth_scheme,regions,data_residency," +
      "data_handling,deprecation_policy,runbook_ref,escalation_ref" +
    ") values " +
    "('test_ph','1.0.0','Test PH','active','test',array['global'],array['ph'],'{}'::jsonb,'{}'::jsonb,'runbook:test-ph','escalation:test-ph')," +
    "('test_us','1.0.0','Test US','active','test',array['global'],array['us'],'{}'::jsonb,'{}'::jsonb,'runbook:test-us','escalation:test-us');" +
    "insert into public.pandora_provider_capabilities(" +
      "provider_key,manifest_version,capability_key,capability_version,operation_mode,implementation_state," +
      "adapter_ref,regions,permissions,evidence_modes,constraints,idempotency_strategy" +
    ") values " +
    "('test_ph','1.0.0','ai.infer','1.0.0','write','native','test:test_ph',array['global'],'{}'::jsonb,array['provider_receipt'],'{}'::jsonb,'request_id')," +
    "('test_us','1.0.0','ai.infer','1.0.0','write','native','test:test_us',array['global'],'{}'::jsonb,array['provider_receipt'],'{}'::jsonb,'request_id');"
  );

  await db.query(
    "insert into public.pandora_provider_activations(" +
      "organization_id,provider_key,manifest_version,activation_state,granted_capabilities,granted_scopes," +
      "allowed_regions,health_state,activation_source,last_verified_at" +
    ") values " +
    "($1,'test_ph','1.0.0','authorized',array['ai.infer'],array['inference'],array['global'],'healthy','manual',now())," +
    "($1,'test_us','1.0.0','authorized',array['ai.infer'],array['inference'],array['global'],'healthy','manual',now())",
    [org],
  );

  await db.query(
    "insert into public.pandora_provider_capability_metrics(" +
      "organization_id,provider_key,capability_key,capability_version,region,window_start,window_end," +
      "accepted_count,verified_success_count,verified_failure_count,p95_latency_ms,cost_per_unit" +
    ") values " +
    "($1,'test_ph','ai.infer','1.0.0','global',now()-interval '1 hour',now(),100,95,5,400,0.02000000)," +
    "($1,'test_us','ai.infer','1.0.0','global',now()-interval '1 hour',now(),100,99,1,100,0.00100000)",
    [org],
  );
}

test("all seeded provider manifests pass the production conformance contract", async (t) => {
  const db = await makeDb(t);
  const result = await db.query(
    "select count(*)::int total," +
    "count(*) filter(where (public.pandora_provider_manifest_conformance_v1(provider_key,manifest_version)->>'pass')::boolean)::int passed " +
    "from public.pandora_provider_manifests"
  );
  assert.equal(result.rows[0].total, 18);
  assert.equal(result.rows[0].passed, 18);
});

test("provider selection is eligibility-first, explainable, and fail-closed", async (t) => {
  const db = await makeDb(t);
  await seedSyntheticProviders(db);

  await db.query(
    "insert into public.pandora_provider_selection_policies(" +
      "organization_id,capability_key,capability_version,selection_mode,preferred_providers,fallback_providers," +
      "required_data_residency,score_weights,approval_required" +
    ") values($1,'ai.infer','1.0.0','AUTO',array['test_us'],array['test_ph'],array['ph']," +
      "'{\"reliability\":0,\"latency\":0,\"cost\":1}'::jsonb,true)",
    [org],
  );

  const auto = (await db.query(
    "select public.pandora_select_provider_v1($1,'ai.infer','1.0.0','global','AUTO') payload",
    [org],
  )).rows[0].payload;
  assert.equal(auto.ok, true);
  assert.equal(auto.selectedProvider, "test_ph");
  assert.equal(auto.reason, "auto_highest_explainable_score");
  assert.equal(auto.approvalRequired, true);
  const excludedUs = auto.excludedProviders.find((p) => p.providerKey === "test_us");
  assert.ok(excludedUs);
  assert.ok(excludedUs.reasons.includes("data_residency_ineligible"));

  await db.query(
    "update public.pandora_provider_activations set health_state='down' " +
    "where organization_id=$1 and provider_key='test_ph'",
    [org],
  );
  await db.query(
    "update public.pandora_provider_selection_policies set " +
      "selection_mode='PREFERRED',preferred_providers=array['test_ph'],fallback_providers=array['test_us']," +
      "required_data_residency='{}'::text[] " +
    "where organization_id=$1 and capability_key='ai.infer' and capability_version='1.0.0'",
    [org],
  );

  const preferred = (await db.query(
    "select public.pandora_select_provider_v1($1,'ai.infer','1.0.0','global','PREFERRED') payload",
    [org],
  )).rows[0].payload;
  assert.equal(preferred.selectedProvider, "test_us");
  assert.equal(preferred.reason, "preferred_provider_unavailable_explicit_fallback");

  await db.query(
    "update public.pandora_provider_selection_policies set " +
      "selection_mode='REQUIRED',required_provider='test_ph',allow_required_fallback=false," +
      "fallback_providers=array['test_us'] " +
    "where organization_id=$1 and capability_key='ai.infer' and capability_version='1.0.0'",
    [org],
  );

  const requiredFailClosed = (await db.query(
    "select public.pandora_select_provider_v1($1,'ai.infer','1.0.0','global','REQUIRED') payload",
    [org],
  )).rows[0].payload;
  assert.equal(requiredFailClosed.ok, false);
  assert.equal(requiredFailClosed.selectedProvider, null);
  assert.equal(requiredFailClosed.reason, "required_provider_unavailable_fail_closed");

  await db.query(
    "update public.pandora_provider_selection_policies set allow_required_fallback=true " +
    "where organization_id=$1 and capability_key='ai.infer' and capability_version='1.0.0'",
    [org],
  );

  const requiredFallback = (await db.query(
    "select public.pandora_select_provider_v1($1,'ai.infer','1.0.0','global','REQUIRED') payload",
    [org],
  )).rows[0].payload;
  assert.equal(requiredFallback.ok, true);
  assert.equal(requiredFallback.selectedProvider, "test_us");
  assert.equal(requiredFallback.reason, "required_provider_unavailable_explicit_fallback");

  await assert.rejects(
    db.query(
      "update public.pandora_provider_selection_receipts set selection_reason='changed' where id=$1",
      [requiredFallback.selectionReceiptId],
    ),
    /provider_receipts_are_append_only/,
  );

  await assert.rejects(
    db.query(
      "update public.pandora_provider_manifests set data_handling='{\"changed\":true}'::jsonb " +
      "where provider_key='test_ph' and manifest_version='1.0.0'",
    ),
    /provider_manifest_version_is_immutable/,
  );
});
