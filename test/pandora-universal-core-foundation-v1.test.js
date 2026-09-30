"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");
const { PGlite } = require("@electric-sql/pglite");
const { pgcrypto } = require("@electric-sql/pglite/contrib/pgcrypto");

const migrationPath = join(
  __dirname,
  "../supabase/migrations/20260930100000_pandora_universal_core_foundation_v1.sql",
);
const migration = readFileSync(migrationPath, "utf8");

const org = "10000000-0000-4000-8000-000000000001";
const otherOrg = "10000000-0000-4000-8000-000000000002";
const owner = "20000000-0000-4000-8000-000000000001";
const stranger = "20000000-0000-4000-8000-000000000002";

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
    "role text not null," +
    "status text not null," +
    "primary key(organization_id,user_id)" +
    ");" +
    "insert into public.organizations values ('" + org + "'),('" + otherOrg + "');" +
    "insert into public.memberships values " +
    "('" + org + "','" + owner + "','owner','active')," +
    "('" + otherOrg + "','" + stranger + "','owner','active');"
  );
  await db.exec(migration);
  return db;
}

async function actAs(db,user,role="authenticated") {
  await db.exec("reset role");
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [user ?? ""]);
  await db.exec("set role " + role);
}

async function seedSources(db,{sharedSignal=true}={}) {
  const connA = (await db.query(
    "insert into public.enterprise_integration_connections(" +
    "organization_id,source_system_key,display_name,connection_key,capability_state" +
    ") values($1,'pms','PMS','primary','healthy') returning id",
    [org],
  )).rows[0].id;
  const connB = (await db.query(
    "insert into public.enterprise_integration_connections(" +
    "organization_id,source_system_key,display_name,connection_key,capability_state" +
    ") values($1,'booking','Booking','primary','healthy') returning id",
    [org],
  )).rows[0].id;

  const recA = (await db.query(
    "insert into public.enterprise_source_records(" +
    "organization_id,source_connection_id,source_object_id,object_type,source_observed_at,content_sha256" +
    ") values($1,$2,'88372','person',now(),$3) returning id",
    [org,connA,"a".repeat(64)],
  )).rows[0].id;
  const recB = (await db.query(
    "insert into public.enterprise_source_records(" +
    "organization_id,source_connection_id,source_object_id,object_type,source_observed_at,content_sha256" +
    ") values($1,$2,'9911','person',now(),$3) returning id",
    [org,connB,"b".repeat(64)],
  )).rows[0].id;

  if (sharedSignal) {
    const identityHash = "c".repeat(64);
    await db.query(
      "insert into public.enterprise_identity_signals(" +
      "organization_id,source_record_id,signal_type,normalized_value_hmac_sha256,verification_state,evidence_refs,observed_at" +
      ") values($1,$2,'verified_email',$3,'verified','[{\"type\":\"synthetic\",\"ref\":\"pms-email-proof\"}]'::jsonb,now())," +
      "($1,$4,'verified_email',$3,'verified','[{\"type\":\"synthetic\",\"ref\":\"booking-email-proof\"}]'::jsonb,now())",
      [org,recA,identityHash,recB],
    );
  }
  return { connA,connB,recA,recB };
}

async function seedPerson(db) {
  const entity = (await db.query(
    "insert into public.enterprise_entities(organization_id,entity_kind) values($1,'person') returning id",
    [org],
  )).rows[0].id;
  await db.query(
    "insert into public.enterprise_people(entity_id,organization_id,display_name) values($1,$2,'Maria Santos')",
    [entity,org],
  );
  return entity;
}

test("foundation does not repurpose hospitality enterprise_source_connections or create a generic entity payload", () => {
  assert.doesNotMatch(
    migration,
    /create table if not exists public[.]enterprise_source_connections/i,
  );
  assert.match(
    migration,
    /create table if not exists public[.]enterprise_integration_connections/i,
  );
  const entityBlock = migration.match(
    /create table if not exists public[.]enterprise_entities[\s\S]*?\n\);/i,
  )?.[0] ?? "";
  assert.doesNotMatch(entityBlock, /\b(?:data|payload|attributes)\s+jsonb\b/i);
  assert.doesNotMatch(
    migration,
    /\b(?:positive_evidence|negative_evidence)\s+text\[\]/i,
  );
  assert.match(entityBlock, /entity_kind text not null/i);
  assert.doesNotMatch(migration, /grant\s+all\s+on\s+table\s+public[.]enterprise_/i);
  assert.doesNotMatch(migration, /grant[^;]*truncate[^;]*public[.]enterprise_/i);
});

test("typed Person rows are organization-bound and authenticated clients are read-only", async (t) => {
  const db = await makeDb(t);
  const entity = await seedPerson(db);

  await actAs(db, owner);
  assert.equal(
    (await db.query("select count(*)::int as n from public.enterprise_people")).rows[0].n,
    1,
  );
  await assert.rejects(
    db.query(
      "insert into public.enterprise_entities(organization_id,entity_kind) values($1,'person')",
      [org],
    ),
    /permission denied/,
  );

  await actAs(db, stranger);
  assert.equal(
    (await db.query("select count(*)::int as n from public.enterprise_people")).rows[0].n,
    0,
  );

  await db.exec("reset role");
  await assert.rejects(
    db.query(
      "insert into public.enterprise_people(entity_id,organization_id,display_name) values($1,$2,'Cross Tenant')",
      [entity,otherOrg],
    ),
    /foreign key|violates/i,
  );
});

test("MERGE requires a shared verified keyed-HMAC identity signal and creates two confirmed bindings", async (t) => {
  const db = await makeDb(t);
  const { recA,recB } = await seedSources(db,{sharedSignal:true});
  const entity = await seedPerson(db);

  await actAs(db,null,"service_role");
  const payload = (await db.query(
    "select public.pandora_enterprise_resolve_identity_v1(" +
    "$1,$2,$3,'merge',$4,$5,$6,$7,'shared_verified_signal',$8,$9::jsonb" +
    ") as payload",
    [
      org,recA,recB,
      "identity:merge:maria:0001",
      "d".repeat(64),
      "service:identity-resolver",
      entity,
      ["SHARED_VERIFIED_EMAIL"],
      JSON.stringify([{type:"synthetic",ref:"identity-match-proof"}]),
    ],
  )).rows[0].payload;

  assert.equal(payload.decision,"merge");
  assert.equal(payload.canonicalEntityId,entity);
  assert.equal(
    (await db.query(
      "select count(*)::int as n from public.enterprise_entity_bindings " +
      "where organization_id=$1 and pandora_entity_id=$2 and binding_state='confirmed'",
      [org,entity],
    )).rows[0].n,
    2,
  );

  const replay = (await db.query(
    "select public.pandora_enterprise_resolve_identity_v1(" +
    "$1,$2,$3,'merge',$4,$5,$6,$7,'shared_verified_signal',$8,$9::jsonb" +
    ") as payload",
    [
      org,recA,recB,
      "identity:merge:maria:0001",
      "d".repeat(64),
      "service:identity-resolver",
      entity,
      ["SHARED_VERIFIED_EMAIL"],
      JSON.stringify([{type:"synthetic",ref:"identity-match-proof"}]),
    ],
  )).rows[0].payload;
  assert.equal(replay.mode,"replay");
});

test("weak name similarity cannot be accepted as MERGE and SEPARATE creates no confirmed binding", async (t) => {
  const db = await makeDb(t);
  const { recA,recB } = await seedSources(db,{sharedSignal:false});
  const entity = await seedPerson(db);

  await actAs(db,null,"service_role");
  await assert.rejects(
    db.query(
      "select public.pandora_enterprise_resolve_identity_v1(" +
      "$1,$2,$3,'merge',$4,$5,$6,$7,'manual_review',$8,$9::jsonb" +
      ")",
      [
        org,recA,recB,
        "identity:merge:weak:0001",
        "e".repeat(64),
        "service:identity-resolver",
        entity,
        ["NAME_SIMILARITY_ONLY"],
        JSON.stringify([{type:"synthetic",ref:"weak-name-proof"}]),
      ],
    ),
    /enterprise_identity_merge_requires_shared_verified_signal/,
  );

  const separate = (await db.query(
    "select public.pandora_enterprise_resolve_identity_v1(" +
    "$1,$2,$3,'separate',$4,$5,$6,null,'manual_review',$7,$8::jsonb" +
    ") as payload",
    [
      org,recA,recB,
      "identity:separate:weak:0001",
      "f".repeat(64),
      "service:identity-resolver",
      ["INSUFFICIENT_IDENTITY_SIGNAL"],
      JSON.stringify([{type:"synthetic",ref:"manual-separate-proof"}]),
    ],
  )).rows[0].payload;

  assert.equal(separate.decision,"separate");
  assert.equal(
    (await db.query(
      "select count(*)::int as n from public.enterprise_entity_bindings " +
      "where organization_id=$1 and source_record_id in ($2,$3) and binding_state='confirmed'",
      [org,recA,recB],
    )).rows[0].n,
    0,
  );
});

test("source replay is deduplicated by connection, external identity and content hash", async (t) => {
  const db = await makeDb(t);
  const conn = (await db.query(
    "insert into public.enterprise_integration_connections(" +
    "organization_id,source_system_key,display_name,connection_key" +
    ") values($1,'erp','ERP','primary') returning id",
    [org],
  )).rows[0].id;
  const hash = "1".repeat(64);
  await db.query(
    "insert into public.enterprise_source_records(" +
    "organization_id,source_connection_id,source_object_id,object_type,source_observed_at,content_sha256" +
    ") values($1,$2,'customer-17','person',now(),$3)",
    [org,conn,hash],
  );
  await assert.rejects(
    db.query(
      "insert into public.enterprise_source_records(" +
      "organization_id,source_connection_id,source_object_id,object_type,source_observed_at,content_sha256" +
      ") values($1,$2,'customer-17','person',now(),$3)",
      [org,conn,hash],
    ),
    /unique|duplicate/i,
  );
});

test("source authority vocabulary is independent from provider routing and provenance requires valid hashes", async (t) => {
  const db = await makeDb(t);
  const { connA,recA } = await seedSources(db,{sharedSignal:false});
  const entity = await seedPerson(db);

  await assert.rejects(
    db.query(
      "insert into public.enterprise_authority_policies(" +
      "organization_id,entity_kind,field_path,authority_kind,source_connection_id,policy_version" +
      ") values($1,'person','primary_email','preferred',$2,'1.0.0')",
      [org,connA],
    ),
    /check constraint/i,
  );

  const policy = (await db.query(
    "insert into public.enterprise_authority_policies(" +
    "organization_id,entity_kind,field_path,authority_kind,source_connection_id,policy_version,conflict_action" +
    ") values($1,'person','primary_email','source_of_record',$2,'1.0.0','manual_review') returning id",
    [org,connA],
  )).rows[0].id;

  await db.query(
    "insert into public.enterprise_field_provenance(" +
    "organization_id,entity_id,field_path,source_record_id,source_connection_id," +
    "observed_at,effective_at,verified_at,evidence_refs,value_hmac_sha256,confidence_state,authority_policy_id" +
    ") values($1,$2,'primary_email',$3,$4,now(),now(),now()," +
    "'[{\"type\":\"synthetic\",\"ref\":\"email-readback\"}]'::jsonb,$5,'verified',$6)",
    [org,entity,recA,connA,"2".repeat(64),policy],
  );

  await assert.rejects(
    db.query(
      "insert into public.enterprise_field_provenance(" +
      "organization_id,entity_id,field_path,source_record_id,source_connection_id," +
      "observed_at,effective_at,value_hmac_sha256,authority_policy_id" +
      ") values($1,$2,'display_name',$3,$4,now(),now(),'not-a-hash',$5)",
      [org,entity,recA,connA,policy],
    ),
    /check constraint/i,
  );
});

test("relationships use governed types and composite tenant foreign keys", async (t) => {
  const db = await makeDb(t);
  await db.query(
    "insert into public.enterprise_relationship_type_registry(" +
    "relation_type,namespace,display_name,schema_version" +
    ") values('associated_with','core','Associated with','1.0.0')",
  );
  const a = (await db.query(
    "insert into public.enterprise_entities(organization_id,entity_kind) values($1,'person') returning id",
    [org],
  )).rows[0].id;
  const b = (await db.query(
    "insert into public.enterprise_entities(organization_id,entity_kind) values($1,'person') returning id",
    [org],
  )).rows[0].id;
  await db.query(
    "insert into public.enterprise_relationships(" +
    "organization_id,subject_entity_id,relation_type,object_entity_id" +
    ") values($1,$2,'associated_with',$3)",
    [org,a,b],
  );
  await assert.rejects(
    db.query(
      "insert into public.enterprise_relationships(" +
      "organization_id,subject_entity_id,relation_type,object_entity_id" +
      ") values($1,$2,'associated_with',$3)",
      [otherOrg,a,b],
    ),
    /foreign key|violates/i,
  );
});

test("revoked connections remain historical source parents rather than deleting source records", async (t) => {
  const db = await makeDb(t);
  const { connA,recA } = await seedSources(db,{sharedSignal:false});
  await db.query(
    "update public.enterprise_integration_connections " +
    "set capability_state='revoked',revoked_at=now() where id=$1",
    [connA],
  );
  const row = (await db.query(
    "select c.capability_state,s.id as source_id " +
    "from public.enterprise_integration_connections c " +
    "join public.enterprise_source_records s on s.source_connection_id=c.id and s.organization_id=c.organization_id " +
    "where c.id=$1 and s.id=$2",
    [connA,recA],
  )).rows[0];
  assert.equal(row.capability_state,"revoked");
  assert.equal(row.source_id,recA);
});
