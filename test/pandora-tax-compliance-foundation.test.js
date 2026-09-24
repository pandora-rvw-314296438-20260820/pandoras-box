"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");
const { PGlite } = require("@electric-sql/pglite");
const { pgcrypto } = require("@electric-sql/pglite/contrib/pgcrypto");

const migrationPath = join(
  __dirname,
  "../supabase/migrations/20260925010000_pandora_tax_compliance_foundation_v1.sql",
);
const migration = readFileSync(migrationPath, "utf8");

const org = "10000000-0000-4000-8000-000000000001";
const otherOrg = "10000000-0000-4000-8000-000000000002";
const owner = "20000000-0000-4000-8000-000000000001";
const viewer = "20000000-0000-4000-8000-000000000002";
const stranger = "20000000-0000-4000-8000-000000000003";

async function makeDb(t) {
  const db = new PGlite({ extensions: { pgcrypto } });
  t.after(() => db.close());
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create role service_role nologin;
    create schema auth;
    create schema private;
    create extension pgcrypto with schema public;
    grant usage on schema public,auth,private to authenticated,service_role;
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    $$;
    create table public.organizations(id uuid primary key);
    create table public.memberships(
      organization_id uuid not null,
      user_id uuid not null,
      role text not null,
      status text not null,
      primary key(organization_id,user_id)
    );
    insert into public.organizations values ('${org}'),('${otherOrg}');
    insert into public.memberships values
      ('${org}','${owner}','owner','active'),
      ('${org}','${viewer}','viewer','active'),
      ('${otherOrg}','${stranger}','owner','active');
  `);
  await db.exec(migration);
  return db;
}

async function actAs(db, user, role = "authenticated") {
  await db.exec("reset role");
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [user ?? ""]);
  await db.exec(`set role ${role}`);
}

test("foundation contains no hard-coded tax rates and starts Philippines rules fail-closed", async (t) => {
  assert.doesNotMatch(
    migration,
    /(?:vat|withholding|income)[^\n]{0,80}(?:0\.12|12%|0\.05|5%)/i,
  );
  const db = await makeDb(t);
  const jurisdiction = await db.query(
    "select code,status,source_policy from public.tax_jurisdictions where code='PH'",
  );
  assert.equal(jurisdiction.rows[0].status, "draft");
  assert.equal(jurisdiction.rows[0].source_policy.ratesEmbedded, false);
  assert.equal(
    (await db.query("select count(*)::int as n from public.tax_rule_packs")).rows[0].n,
    0,
  );
});

test("owner can open a tax preparation period but calculation remains blocked without an approved rule pack", async (t) => {
  const db = await makeDb(t);
  await actAs(db, owner);
  const result = (
    await db.query(
      "select public.pandora_tax_prepare_period_v1($1,$2,$3,$4,$5) as payload",
      [org, "2026-09-01", "2026-09-30", "PH", "monthly"],
    )
  ).rows[0].payload;

  assert.equal(result.status, "review_required");
  assert.equal(result.rulesReady, false);
  assert.equal(result.calculationEnabled, false);
  assert.equal(result.filingEnabled, false);
  assert.equal(result.paymentEnabled, false);
  assert.equal(result.nextAction, "approve_current_rule_pack_before_calculation");

  const audit = await db.query(
    "select event_type,event_payload_redacted from public.tax_audit_events where organization_id=$1",
    [org],
  );
  assert.equal(audit.rows.length, 1);
  assert.equal(audit.rows[0].event_type, "tax_period_preparation_requested");
  assert.equal(audit.rows[0].event_payload_redacted.rulesReady, false);
});

test("viewer, stranger and anonymous callers cannot create periods", async (t) => {
  const db = await makeDb(t);

  await actAs(db, viewer);
  await assert.rejects(
    db.query(
      "select public.pandora_tax_prepare_period_v1($1,$2,$3,$4,$5)",
      [org, "2026-09-01", "2026-09-30", "PH", "monthly"],
    ),
    /pandora_tax_manager_required/,
  );

  await actAs(db, stranger);
  await assert.rejects(
    db.query(
      "select public.pandora_tax_prepare_period_v1($1,$2,$3,$4,$5)",
      [org, "2026-09-01", "2026-09-30", "PH", "monthly"],
    ),
    /pandora_tax_manager_required/,
  );

  await actAs(db, null, "anon");
  await assert.rejects(
    db.query(
      "select public.pandora_tax_prepare_period_v1($1,$2,$3,$4,$5)",
      [org, "2026-09-01", "2026-09-30", "PH", "monthly"],
    ),
    /permission denied/,
  );
});

test("organization RLS prevents cross-tenant tax reads and direct client writes", async (t) => {
  const db = await makeDb(t);
  await actAs(db, owner);
  await db.query(
    "select public.pandora_tax_prepare_period_v1($1,$2,$3,$4,$5)",
    [org, "2026-09-01", "2026-09-30", "PH", "monthly"],
  );

  assert.equal(
    (await db.query("select count(*)::int as n from public.tax_periods")).rows[0].n,
    1,
  );

  await actAs(db, stranger);
  assert.equal(
    (await db.query("select count(*)::int as n from public.tax_periods")).rows[0].n,
    0,
  );
  await assert.rejects(
    db.query(
      "insert into public.tax_periods(organization_id,jurisdiction_code,period_type,period_start,period_end) values($1,'PH','monthly','2026-10-01','2026-10-31')",
      [otherOrg],
    ),
    /permission denied/,
  );
});

test("tax workspace is organization-scoped and does not claim filing or payment capability", async (t) => {
  const db = await makeDb(t);
  await actAs(db, owner);
  await db.query(
    "select public.pandora_tax_prepare_period_v1($1,$2,$3,$4,$5)",
    [org, "2026-09-01", "2026-09-30", "PH", "monthly"],
  );
  const payload = (
    await db.query("select public.pandora_tax_workspace_v1($1) as payload", [org])
  ).rows[0].payload;

  assert.equal(payload.rules.philippinesApproved, false);
  assert.equal(payload.rules.calculationEnabled, false);
  assert.equal(payload.filing.enabled, false);
  assert.equal(payload.payments.enabled, false);
  assert.equal(payload.latestPeriod.status, "review_required");

  await actAs(db, stranger);
  await assert.rejects(
    db.query("select public.pandora_tax_workspace_v1($1)", [org]),
    /pandora_tax_membership_required/,
  );
});

test("tax audit trail is append-only even for service role", async (t) => {
  const db = await makeDb(t);
  await actAs(db, owner);
  await db.query(
    "select public.pandora_tax_prepare_period_v1($1,$2,$3,$4,$5)",
    [org, "2026-09-01", "2026-09-30", "PH", "monthly"],
  );

  await actAs(db, null, "service_role");
  await assert.rejects(
    db.query("update public.tax_audit_events set event_type='tampered'"),
    /permission denied|tax audit events are append-only/,
  );
  await assert.rejects(
    db.query("delete from public.tax_audit_events"),
    /permission denied|tax audit events are append-only/,
  );
  assert.match(
    migration,
    /grant select,insert on table public\.tax_audit_events to service_role/i,
  );
  assert.doesNotMatch(
    migration,
    /grant[^;]*(?:update|delete|truncate)[^;]*public\.tax_audit_events[^;]*to service_role/i,
  );
});


test("approved deterministic rule pack is bound to a newly prepared period", async (t) => {
  const db = await makeDb(t);
  const pack = (
    await db.query(
      `insert into public.tax_rule_packs(
        jurisdiction_code,version,status,effective_from,effective_to,
        official_sources,review_notes,reviewed_by,approved_at
      ) values(
        'PH','ph-foundation-test-v1','approved','2026-01-01','2026-12-31',
        '[{"type":"official_bir_source","ref":"synthetic-test-only"}]'::jsonb,
        'Synthetic contract fixture only','30000000-0000-4000-8000-000000000001',now()
      ) returning id`,
    )
  ).rows[0];

  await actAs(db, owner);
  const result = (
    await db.query(
      "select public.pandora_tax_prepare_period_v1($1,$2,$3,$4,$5) as payload",
      [org, "2026-10-01", "2026-10-31", "PH", "monthly"],
    )
  ).rows[0].payload;

  assert.equal(result.status, "draft");
  assert.equal(result.rulesReady, true);
  assert.equal(result.calculationEnabled, true);
  assert.equal(result.rulePackId, pack.id);

  const period = (
    await db.query(
      "select rule_pack_id,status from public.tax_periods where organization_id=$1 and period_start='2026-10-01'",
      [org],
    )
  ).rows[0];
  assert.equal(period.rule_pack_id, pack.id);
  assert.equal(period.status, "draft");
});


test("approved tax rule history becomes immutable and can only be superseded by reference", async (t) => {
  const db = await makeDb(t);

  const approved = (
    await db.query(
      `insert into public.tax_rule_packs(
        jurisdiction_code,version,status,effective_from,effective_to,
        official_sources,review_notes,reviewed_by,approved_at
      ) values(
        'PH','immutable-v1','approved','2026-01-01','2026-12-31',
        '[{"type":"official_bir_source","ref":"synthetic-immutable-test"}]'::jsonb,
        'Synthetic immutable-history fixture','30000000-0000-4000-8000-000000000001',now()
      ) returning id`,
    )
  ).rows[0];

  await assert.rejects(
    db.query(
      "insert into public.tax_rules(rule_pack_id,rule_key,rule_type,deterministic_spec,official_source_ref) values($1,'late-rule','rate','{}'::jsonb,'{}'::jsonb)",
      [approved.id],
    ),
    /tax rules in approved or superseded packs are immutable/,
  );

  await assert.rejects(
    db.query(
      "update public.tax_rule_packs set review_notes='mutated' where id=$1",
      [approved.id],
    ),
    /approved tax rule packs may only transition immutably to a verified approved replacement/,
  );

  const replacement = (
    await db.query(
      `insert into public.tax_rule_packs(
        jurisdiction_code,version,status,effective_from,effective_to,
        official_sources,review_notes,reviewed_by,approved_at
      ) values(
        'PH','immutable-v2','approved','2027-01-01',null,
        '[{"type":"official_bir_source","ref":"synthetic-replacement-test"}]'::jsonb,
        'Synthetic replacement fixture','30000000-0000-4000-8000-000000000002',now()
      ) returning id`,
    )
  ).rows[0];

  await db.query(
    "update public.tax_rule_packs set status='superseded',superseded_by=$2,updated_at=clock_timestamp() where id=$1",
    [approved.id,replacement.id],
  );

  const state = (
    await db.query("select status,superseded_by from public.tax_rule_packs where id=$1", [approved.id])
  ).rows[0];
  assert.equal(state.status, "superseded");
  assert.equal(state.superseded_by, replacement.id);

  await assert.rejects(
    db.query("delete from public.tax_rule_packs where id=$1", [approved.id]),
    /approved tax rule packs are immutable history/,
  );
});

test("approved packs require non-empty authoritative source provenance", async (t) => {
  const db = await makeDb(t);
  await assert.rejects(
    db.query(
      `insert into public.tax_rule_packs(
        jurisdiction_code,version,status,official_sources,review_notes,reviewed_by,approved_at
      ) values('PH','invalid-approved','approved','[]'::jsonb,'Synthetic invalid fixture','30000000-0000-4000-8000-000000000003',now())`,
    ),
    /check constraint/,
  );
});


test("draft rules require non-empty deterministic specification and source provenance", async (t) => {
  const db = await makeDb(t);
  const draft = (
    await db.query(
      `insert into public.tax_rule_packs(
        jurisdiction_code,version,status,official_sources
      ) values(
        'PH','draft-source-check','draft',
        '[{"type":"official_bir_source","ref":"synthetic-draft-test"}]'::jsonb
      ) returning id`,
    )
  ).rows[0];

  await assert.rejects(
    db.query(
      "insert into public.tax_rules(rule_pack_id,rule_key,rule_type,deterministic_spec,official_source_ref) values($1,'empty-spec','rate','{}'::jsonb,'{\"ref\":\"x\"}'::jsonb)",
      [draft.id],
    ),
    /check constraint/,
  );
  await assert.rejects(
    db.query(
      "insert into public.tax_rules(rule_pack_id,rule_key,rule_type,deterministic_spec,official_source_ref) values($1,'empty-source','rate','{\"formula\":\"synthetic\"}'::jsonb,'{}'::jsonb)",
      [draft.id],
    ),
    /check constraint/,
  );
});

test("approved packs cannot be superseded by a draft or cross-jurisdiction replacement", async (t) => {
  const db = await makeDb(t);
  await db.exec(
    "insert into public.tax_jurisdictions(code,display_name,currency_code,status) values('XX','Synthetic Other','XXX','draft')",
  );
  const approved = (
    await db.query(
      `insert into public.tax_rule_packs(
        jurisdiction_code,version,status,official_sources,review_notes,reviewed_by,approved_at
      ) values(
        'PH','supersession-source','approved',
        '[{"type":"official_bir_source","ref":"synthetic-source"}]'::jsonb,
        'Synthetic approved source','30000000-0000-4000-8000-000000000004',now()
      ) returning id`,
    )
  ).rows[0];
  const draft = (
    await db.query(
      "insert into public.tax_rule_packs(jurisdiction_code,version,status) values('PH','supersession-draft','draft') returning id",
    )
  ).rows[0];
  const other = (
    await db.query(
      `insert into public.tax_rule_packs(
        jurisdiction_code,version,status,official_sources,review_notes,reviewed_by,approved_at
      ) values(
        'XX','cross-jurisdiction','approved',
        '[{"type":"official_source","ref":"synthetic-other"}]'::jsonb,
        'Synthetic cross-jurisdiction','30000000-0000-4000-8000-000000000005',now()
      ) returning id`,
    )
  ).rows[0];

  await assert.rejects(
    db.query(
      "update public.tax_rule_packs set status='superseded',superseded_by=$2 where id=$1",
      [approved.id,draft.id],
    ),
    /verified approved replacement/,
  );
  await assert.rejects(
    db.query(
      "update public.tax_rule_packs set status='superseded',superseded_by=$2 where id=$1",
      [approved.id,other.id],
    ),
    /verified approved replacement/,
  );
});

test("foundation preserves evidence lineage and avoids service-role truncate authority", () => {
  assert.doesNotMatch(migration, /on delete set null/i);
  assert.doesNotMatch(
    migration,
    /grant\s+all\s+on\s+table\s+public\.tax_/i,
  );
  assert.doesNotMatch(
    migration,
    /grant[^;]*truncate[^;]*public\.tax_/i,
  );
  assert.match(
    migration,
    /organization_id uuid not null references public\.organizations\(id\) on delete restrict,\s+tax_period_id uuid,\s+event_type text not null/is,
  );
});

test("authenticated clients cannot mutate deterministic rule authority", async (t) => {
  const db = await makeDb(t);
  await actAs(db, owner);
  await assert.rejects(
    db.query(
      "insert into public.tax_rule_packs(jurisdiction_code,version,status) values('PH','fake','approved')",
    ),
    /permission denied/,
  );
  assert.equal(
    (await db.query("select count(*)::int as n from public.tax_rule_packs")).rows[0].n,
    0,
  );
});
