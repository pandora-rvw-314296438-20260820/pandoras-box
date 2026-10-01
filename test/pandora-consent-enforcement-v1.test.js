"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");
const { PGlite } = require("@electric-sql/pglite");
const { pgcrypto } = require("@electric-sql/pglite/contrib/pgcrypto");

const activation = readFileSync(
  join(__dirname, "../supabase/migrations/20260930111000_pandora_capability_provider_activation_v1.sql"),
  "utf8",
);
const consent = readFileSync(
  join(__dirname, "../supabase/migrations/20260930113000_pandora_consent_enforcement_v1.sql"),
  "utf8",
);

const org = "72000000-0000-4000-8000-000000000001";
const owner = "73000000-0000-4000-8000-000000000001";

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
      "organization_id uuid not null,user_id uuid not null,status text not null," +
      "primary key(organization_id,user_id));" +
    "create table public.enterprise_entities(" +
      "id uuid primary key default gen_random_uuid(),organization_id uuid not null," +
      "entity_kind text not null,unique(id,organization_id));" +
    "create table public.pandora_provider_health(" +
      "organization_id uuid not null,provider text not null,status text not null," +
      "last_event_at timestamptz,last_success_at timestamptz,stale_after timestamptz);" +
    "create table private.execution_dispatch_outbox(" +
      "organization_id uuid not null,worker_reported_at timestamptz,verified_at timestamptz," +
      "error_code text,verified_outcome text);" +
    "grant select on table public.memberships to authenticated,service_role;" +
    "insert into public.organizations(id) values ('" + org + "');" +
    "insert into public.memberships values ('" + org + "','" + owner + "','active');"
  );
  await db.exec(activation);
  await db.exec(consent);
  return db;
}

async function seedProvider(db) {
  await db.exec(
    "insert into public.pandora_provider_manifests(" +
      "provider_key,manifest_version,display_name,lifecycle_state,auth_scheme,regions,data_residency," +
      "data_handling,deprecation_policy,runbook_ref,escalation_ref" +
    ") values ('test_consent','1.0.0','Test Consent','active','test',array['global']," +
      "array['provider_managed'],'{}'::jsonb,'{}'::jsonb,'runbook:test','escalation:test');" +
    "insert into public.pandora_provider_capabilities(" +
      "provider_key,manifest_version,capability_key,capability_version,operation_mode,implementation_state," +
      "adapter_ref,regions,permissions,evidence_modes,constraints,idempotency_strategy" +
    ") values ('test_consent','1.0.0','message.send','1.0.0','write','native','test:consent'," +
      "array['global'],'{}'::jsonb,array['provider_receipt'],'{}'::jsonb,'request_id');"
  );
  await db.query(
    "insert into public.pandora_provider_activations(" +
      "organization_id,provider_key,manifest_version,activation_state,granted_capabilities," +
      "granted_scopes,allowed_regions,health_state,activation_source,last_verified_at" +
    ") values($1,'test_consent','1.0.0','authorized',array['message.send'],array['send']," +
      "array['global'],'healthy','manual',now())",
    [org],
  );
}

test("service role cannot bypass the consent-aware provider entry point", async (t) => {
  const db = await makeDb(t);
  await seedProvider(db);
  await db.query(
    "insert into public.pandora_provider_selection_policies(" +
      "organization_id,capability_key,capability_version,selection_mode,consent_required," +
      "consent_purpose,consent_subject_required" +
    ") values($1,'message.send','1.0.0','AUTO',true,'guest_notification',true)",
    [org],
  );

  await db.exec("set role service_role");
  await assert.rejects(
    db.query("select public.pandora_select_provider_v1($1,'message.send','1.0.0','global','AUTO')",[org]),
    /permission denied/,
  );
  await assert.rejects(
    db.query(
      "select public.pandora_select_provider_authorized_v1(" +
      "$1,'message.send','1.0.0','global','AUTO',null,'guest_notification',null)",
      [org],
    ),
    /consent_grant_required/,
  );
});

test("consent-bound selection requires exact purpose, subject, lifecycle and evidence", async (t) => {
  const db = await makeDb(t);
  await seedProvider(db);
  const subject = (await db.query(
    "insert into public.enterprise_entities(organization_id,entity_kind) values($1,'person') returning id",
    [org],
  )).rows[0].id;
  const otherSubject = (await db.query(
    "insert into public.enterprise_entities(organization_id,entity_kind) values($1,'person') returning id",
    [org],
  )).rows[0].id;

  await db.query(
    "insert into public.pandora_provider_selection_policies(" +
      "organization_id,capability_key,capability_version,selection_mode,consent_required," +
      "consent_purpose,consent_subject_required" +
    ") values($1,'message.send','1.0.0','AUTO',true,'guest_notification',true)",
    [org],
  );
  const grant = (await db.query(
    "insert into public.pandora_consent_grants(" +
      "organization_id,subject_entity_id,purpose,capability_key,capability_version,evidence_refs" +
    ") values($1,$2,'guest_notification','message.send','1.0.0'," +
      "'[{\"type\":\"consent_receipt\",\"ref\":\"fixture:consent:1\"}]'::jsonb) returning id",
    [org,subject],
  )).rows[0].id;

  await db.exec("set role service_role");
  await assert.rejects(
    db.query(
      "select public.pandora_select_provider_authorized_v1(" +
      "$1,'message.send','1.0.0','global','AUTO',$2,'marketing',$3)",
      [org,grant,subject],
    ),
    /consent_purpose_mismatch/,
  );
  await assert.rejects(
    db.query(
      "select public.pandora_select_provider_authorized_v1(" +
      "$1,'message.send','1.0.0','global','AUTO',$2,'guest_notification',$3)",
      [org,grant,otherSubject],
    ),
    /consent_subject_mismatch/,
  );

  const selected = (await db.query(
    "select public.pandora_select_provider_authorized_v1(" +
    "$1,'message.send','1.0.0','global','AUTO',$2,'guest_notification',$3) payload",
    [org,grant,subject],
  )).rows[0].payload;
  assert.equal(selected.ok,true);
  assert.equal(selected.selectedProvider,"test_consent");

  await db.query(
    "update public.pandora_consent_grants set revoked_at=clock_timestamp() where id=$1",
    [grant],
  );
  await assert.rejects(
    db.query(
      "select public.pandora_select_provider_authorized_v1(" +
      "$1,'message.send','1.0.0','global','AUTO',$2,'guest_notification',$3)",
      [org,grant,subject],
    ),
    /consent_revoked/,
  );
});

test("expired or evidence-free consent fails closed while non-consent policies still route", async (t) => {
  const db = await makeDb(t);
  await seedProvider(db);
  const subject = (await db.query(
    "insert into public.enterprise_entities(organization_id,entity_kind) values($1,'person') returning id",
    [org],
  )).rows[0].id;

  await db.query(
    "insert into public.pandora_provider_selection_policies(" +
      "organization_id,capability_key,capability_version,selection_mode,consent_required," +
      "consent_purpose,consent_subject_required" +
    ") values($1,'message.send','1.0.0','AUTO',true,'guest_notification',false)",
    [org],
  );
  const noEvidence = (await db.query(
    "insert into public.pandora_consent_grants(" +
      "organization_id,purpose,capability_key,capability_version,evidence_refs" +
    ") values($1,'guest_notification','message.send','1.0.0','[]'::jsonb) returning id",
    [org],
  )).rows[0].id;

  await db.exec("set role service_role");
  await assert.rejects(
    db.query(
      "select public.pandora_select_provider_authorized_v1(" +
      "$1,'message.send','1.0.0','global','AUTO',$2,'guest_notification',null)",
      [org,noEvidence],
    ),
    /consent_evidence_required/,
  );

  await db.exec("reset role");
  const expired = (await db.query(
    "insert into public.pandora_consent_grants(" +
      "organization_id,subject_entity_id,purpose,capability_key,capability_version," +
      "granted_at,expires_at,evidence_refs" +
    ") values($1,$2,'guest_notification','message.send','1.0.0'," +
      "clock_timestamp()-interval '2 hours',clock_timestamp()-interval '1 hour'," +
      "'[{\"type\":\"consent_receipt\",\"ref\":\"fixture:expired\"}]'::jsonb) returning id",
    [org,subject],
  )).rows[0].id;
  await db.exec("set role service_role");
  await assert.rejects(
    db.query(
      "select public.pandora_select_provider_authorized_v1(" +
      "$1,'message.send','1.0.0','global','AUTO',$2,'guest_notification',$3)",
      [org,expired,subject],
    ),
    /consent_expired/,
  );

  await db.exec("reset role");
  await db.query(
    "update public.pandora_provider_selection_policies set " +
      "consent_required=false,consent_subject_required=false,consent_purpose=null " +
      "where organization_id=$1 and capability_key='message.send' and capability_version='1.0.0'",
    [org],
  );
  await db.exec("set role service_role");
  const ordinary = (await db.query(
    "select public.pandora_select_provider_authorized_v1(" +
    "$1,'message.send','1.0.0','global','AUTO',null,null,null) payload",
    [org],
  )).rows[0].payload;
  assert.equal(ordinary.ok,true);
  assert.equal(ordinary.selectedProvider,"test_consent");
});
