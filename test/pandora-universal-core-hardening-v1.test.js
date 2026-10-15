"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");
const { PGlite } = require("@electric-sql/pglite");
const { pgcrypto } = require("@electric-sql/pglite/contrib/pgcrypto");

const foundation = readFileSync(join(
  __dirname,
  "../supabase/migrations/20260930100000_pandora_universal_core_foundation_v1.sql",
), "utf8");
const hardening = readFileSync(join(
  __dirname,
  "../supabase/migrations/20260930101500_pandora_universal_core_hardening_v1.sql",
), "utf8");

const org = "10000000-0000-4000-8000-000000000001";
const owner = "20000000-0000-4000-8000-000000000001";

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
    "grant select on table public.memberships to authenticated,service_role;" +
    "insert into public.organizations values ('" + org + "');" +
    "insert into public.memberships values ('" + org + "','" + owner + "','owner','active');"
  );
  await db.exec(foundation);
  await db.exec(hardening);
  return db;
}

async function actAs(db,user,role="authenticated") {
  await db.exec("reset role");
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [user ?? ""]);
  await db.exec("set role " + role);
}

test("global registries have RLS and preserve authenticated-read/service-write boundaries", async (t) => {
  const db = await makeDb(t);
  const rls = await db.query(
    "select relname,relrowsecurity from pg_class " +
    "where relname in ('enterprise_entity_type_registry','enterprise_relationship_type_registry') " +
    "order by relname",
  );
  assert.deepEqual(
    rls.rows.map((row) => [row.relname,row.relrowsecurity]),
    [
      ["enterprise_entity_type_registry",true],
      ["enterprise_relationship_type_registry",true],
    ],
  );

  await actAs(db,owner);
  assert.equal(
    (await db.query("select count(*)::int n from public.enterprise_entity_type_registry")).rows[0].n,
    1,
  );
  await assert.rejects(
    db.query(
      "insert into public.enterprise_relationship_type_registry(" +
      "relation_type,namespace,display_name,schema_version" +
      ") values('client_write','core','Client write','1.0.0')",
    ),
    /permission denied/i,
  );

  await actAs(db,null,"anon");
  await assert.rejects(
    db.query("select * from public.enterprise_entity_type_registry"),
    /permission denied/i,
  );

  await actAs(db,null,"service_role");
  await db.query(
    "insert into public.enterprise_relationship_type_registry(" +
    "relation_type,namespace,display_name,schema_version" +
    ") values('associated_with','core','Associated with','1.0.0')",
  );
  assert.equal(
    (await db.query(
      "select count(*)::int n from public.enterprise_relationship_type_registry " +
      "where relation_type='associated_with'",
    )).rows[0].n,
    1,
  );
});

test("tenant RLS policies use init-plan-safe auth uid form", () => {
  assert.doesNotMatch(hardening, /m[.]user_id\s*=\s*auth[.]uid\(\)/i);
  const matches = hardening.match(/m[.]user_id=\(select auth[.]uid\(\)\)/g) || [];
  assert.equal(matches.length,10);
});

test("hardening adds targeted missing foreign-key indexes without deleting foundation indexes", async (t) => {
  const db = await makeDb(t);
  const expected = [
    "enterprise_entities_entity_kind_fk_idx",
    "enterprise_identity_signals_source_org_fk_idx",
    "enterprise_entity_bindings_source_org_fk_idx",
    "enterprise_relationships_binding_org_fk_idx",
    "enterprise_relationships_relation_type_fk_idx",
    "enterprise_authority_policies_connection_org_fk_idx",
    "enterprise_authority_policies_entity_kind_fk_idx",
    "enterprise_field_provenance_source_org_fk_idx",
    "enterprise_field_provenance_connection_org_fk_idx",
    "enterprise_field_provenance_authority_org_fk_idx",
    "enterprise_field_provenance_supersedes_org_fk_idx",
    "enterprise_identity_resolutions_source_b_org_fk_idx",
    "enterprise_identity_resolutions_entity_org_fk_idx",
  ];
  const rows = await db.query(
    "select indexname from pg_indexes where schemaname='public' and indexname = any($1::text[])",
    [expected],
  );
  assert.equal(rows.rows.length,expected.length);
  assert.match(hardening,/create index if not exists/i);
  assert.doesNotMatch(hardening,/drop\s+index/i);
});
