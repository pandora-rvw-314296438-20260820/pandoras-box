"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");
const { PGlite } = require("@electric-sql/pglite");
const { pgcrypto } = require("@electric-sql/pglite/contrib/pgcrypto");

const foundation = readFileSync(
  join(__dirname, "../supabase/migrations/20260925010000_pandora_tax_compliance_foundation_v1.sql"),
  "utf8",
);
const evidence = readFileSync(
  join(__dirname, "../supabase/migrations/20260925073000_pandora_tax_evidence_inbox_v1.sql"),
  "utf8",
);
const operating = readFileSync(
  join(__dirname, "../supabase/migrations/20260925090000_pandora_tax_operating_core_v1.sql"),
  "utf8",
);

const org = "10000000-0000-4000-8000-000000000001";
const otherOrg = "10000000-0000-4000-8000-000000000002";
const owner = "20000000-0000-4000-8000-000000000001";
const admin = "20000000-0000-4000-8000-000000000004";
const viewer = "20000000-0000-4000-8000-000000000002";
const stranger = "20000000-0000-4000-8000-000000000003";
const reviewer = "30000000-0000-4000-8000-000000000001";

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
    create table public.pandora_intelligence_threads(
      id uuid primary key default gen_random_uuid(),
      organization_id uuid not null,
      project_id uuid,
      created_by uuid not null,
      title text not null,
      status text not null default 'active',
      last_message_at timestamptz default clock_timestamp(),
      updated_at timestamptz default clock_timestamp()
    );
    create table public.pandora_intelligence_messages(
      id uuid primary key default gen_random_uuid(),
      thread_id uuid not null references public.pandora_intelligence_threads(id),
      organization_id uuid not null,
      project_id uuid,
      author_role text not null,
      content text not null,
      attachment_manifest jsonb not null default '[]'::jsonb,
      structured_response jsonb,
      provider text,
      model text,
      created_at timestamptz not null default clock_timestamp()
    );
    insert into public.organizations values ('${org}'),('${otherOrg}');
    insert into public.memberships values
      ('${org}','${owner}','owner','active'),
      ('${org}','${admin}','admin','active'),
      ('${org}','${viewer}','viewer','active'),
      ('${otherOrg}','${stranger}','owner','active');
  `);
  await db.exec(foundation);
  await db.exec(evidence);
  await db.exec(operating);
  return db;
}

async function actAs(db, user, role = "authenticated") {
  await db.exec("reset role");
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [user ?? ""]);
  await db.exec(`set role ${role}`);
}

async function insertPeriod(db, start = "2026-09-01", end = "2026-09-30") {
  return (
    await db.query(
      `insert into public.tax_periods(
        organization_id,jurisdiction_code,period_type,period_start,period_end,
        status,source_sync_state,created_by
      ) values($1,'PH','monthly',$2,$3,'review_required','complete',$4)
      returning id`,
      [org,start,end,owner],
    )
  ).rows[0].id;
}

async function postLedger(db, periodId, entryKey, overrides = {}) {
  const values = {
    sourceObjectId: null,
    documentId: null,
    date: "2026-09-10",
    kind: "sale",
    currency: "PHP",
    gross: 1120,
    net: 1000,
    tax: 120,
    accounting: "revenue",
    taxCategory: "vat_taxable_sale",
    purpose: "Synthetic test sale",
    confidence: 0.99,
    ...overrides,
  };
  return (
    await db.query(
      `select public.pandora_tax_post_ledger_entry_v1(
        $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,
        null,null,null,null,null,'{"test":true}'::jsonb
      ) as payload`,
      [
        org,entryKey,periodId,values.sourceObjectId,values.documentId,
        values.date,values.kind,values.currency,values.gross,values.net,
        values.tax,values.accounting,values.taxCategory,values.purpose,values.confidence,
      ],
    )
  ).rows[0].payload;
}

async function makeApprovedSyntheticPack(db, periodId) {
  await db.exec("reset role");
  const pack = (
    await db.query(
      `insert into public.tax_rule_packs(
        jurisdiction_code,version,status,effective_from,effective_to,
        official_sources,review_notes,reviewed_by,approved_at
      ) values(
        'PH','synthetic-approved-v1','draft','2026-01-01','2026-12-31',
        '[{"authority":"synthetic-test","ref":"test-only"}]'::jsonb,
        null,null,null
      ) returning id`,
    )
  ).rows[0];

  await db.query(
    `insert into public.tax_rules(
      rule_pack_id,rule_key,rule_type,deterministic_spec,official_source_ref
    ) values
    ($1,'synthetic.sales.base','formula',
      '{"operation":"sum","sequence":10,"lineKey":"sales_base","field":"net_amount","taxCategory":"vat_taxable_sale"}'::jsonb,
      '{"ref":"synthetic-test"}'::jsonb),
    ($1,'synthetic.output.tax','rate',
      '{"operation":"rate","sequence":20,"lineKey":"output_tax","baseLineKey":"sales_base","rate":0.12,"obligationKey":"synthetic_vat","deadlineDaysAfterPeriodEnd":25}'::jsonb,
      '{"ref":"synthetic-test"}'::jsonb)`,
    [pack.id],
  );

  await db.query(
    `update public.tax_rule_packs
     set status='approved',
         review_notes='Synthetic approved fixture only',
         reviewed_by=$2,
         approved_at=clock_timestamp()
     where id=$1`,
    [pack.id,reviewer],
  );
  await db.query(
    "update public.tax_periods set rule_pack_id=$2 where id=$1 and organization_id=$3",
    [periodId,pack.id,org],
  );
  return pack.id;
}

test("operating core migration replays and PH pack is deliberately not approved", async (t) => {
  const db = await makeDb(t);
  await db.exec("reset role");

  const pack = (
    await db.query(
      "select status,version,official_sources from public.tax_rule_packs where jurisdiction_code='PH' and version='ph-2026-authoritative-draft-v1'",
    )
  ).rows[0];

  assert.equal(pack.status, "in_review");
  assert.equal(pack.version, "ph-2026-authoritative-draft-v1");
  assert.ok(Array.isArray(pack.official_sources));
  assert.ok(pack.official_sources.length >= 4);

  const jurisdiction = (
    await db.query("select source_policy from public.tax_jurisdictions where code='PH'")
  ).rows[0].source_policy;
  assert.equal(jurisdiction.liveCalculationEnabled, false);
  assert.equal(jurisdiction.embeddedPackStatus, "in_review");

  const functions = [
    "pandora_tax_post_ledger_entry_v1",
    "pandora_tax_run_reconciliation_v1",
    "pandora_tax_calculate_period_v1",
    "pandora_tax_build_filing_package_v1",
    "pandora_tax_command_center_v1",
  ];
  for (const name of functions) {
    const result = await db.query(
      "select count(*)::int as n from pg_proc where proname=$1",
      [name],
    );
    assert.equal(result.rows[0].n, 1);
  }
});

test("service-role ledger posting is idempotent and authenticated clients cannot post directly", async (t) => {
  const db = await makeDb(t);
  await db.exec("reset role");
  const periodId = await insertPeriod(db);

  await actAs(db, null, "service_role");
  const first = await postLedger(db, periodId, "sale-001");
  assert.equal(first.replayed, false);
  assert.equal(first.treatmentState, "suggested");

  const replay = await postLedger(db, periodId, "sale-001");
  assert.equal(replay.replayed, true);
  assert.equal(replay.ledgerEntryId, first.ledgerEntryId);

  await assert.rejects(
    postLedger(db, periodId, "sale-001", { gross: 9999 }),
    /pandora_tax_ledger_idempotency_conflict/,
  );

  await actAs(db, owner);
  await assert.rejects(
    db.query(
      `select public.pandora_tax_post_ledger_entry_v1(
        $1,'client-write',$2,null,null,'2026-09-10','sale','PHP',
        100,100,0,'revenue','vat_taxable_sale','client',1,
        null,null,null,null,null,'{}'::jsonb
      )`,
      [org,periodId],
    ),
    /permission denied/,
  );
});

test("owner review verifies ledger treatment but cross-tenant and viewer access fail closed", async (t) => {
  const db = await makeDb(t);
  await db.exec("reset role");
  const periodId = await insertPeriod(db);

  await actAs(db, null, "service_role");
  const posted = await postLedger(db, periodId, "sale-review");

  await actAs(db, viewer);
  await assert.rejects(
    db.query(
      "select public.pandora_tax_review_ledger_entry_v1($1,$2,'verified','revenue','vat_taxable_sale','sale','viewer')",
      [org,posted.ledgerEntryId],
    ),
    /pandora_tax_manager_required/,
  );

  await actAs(db, stranger);
  await assert.rejects(
    db.query(
      "select public.pandora_tax_review_ledger_entry_v1($1,$2,'verified','revenue','vat_taxable_sale','sale','stranger')",
      [org,posted.ledgerEntryId],
    ),
    /pandora_tax_manager_required/,
  );

  await actAs(db, owner);
  const reviewed = (
    await db.query(
      "select public.pandora_tax_review_ledger_entry_v1($1,$2,'verified','revenue','vat_taxable_sale','sale','checked') as payload",
      [org,posted.ledgerEntryId],
    )
  ).rows[0].payload;
  assert.equal(reviewed.decision, "verified");
  assert.equal(reviewed.classificationVersion, 2);

  const row = (
    await db.query(
      "select treatment_state,reviewed_by from public.tax_ledger_entries where id=$1",
      [posted.ledgerEntryId],
    )
  ).rows[0];
  assert.equal(row.treatment_state, "verified");
  assert.equal(row.reviewed_by, owner);
});

test("reconciliation creates explicit exceptions and calculation refuses an unapproved PH pack", async (t) => {
  const db = await makeDb(t);
  await db.exec("reset role");
  const periodId = await insertPeriod(db);

  await actAs(db, null, "service_role");
  const posted = await postLedger(db, periodId, "sale-reconcile");
  await actAs(db, owner);
  await db.query(
    "select public.pandora_tax_review_ledger_entry_v1($1,$2,'verified','revenue','vat_taxable_sale','sale','checked')",
    [org,posted.ledgerEntryId],
  );

  const recon = (
    await db.query(
      "select public.pandora_tax_run_reconciliation_v1($1,$2) as payload",
      [org,periodId],
    )
  ).rows[0].payload;

  assert.equal(recon.status, "complete");
  assert.ok(recon.exceptionCount >= 1);

  await assert.rejects(
    db.query("select public.pandora_tax_calculate_period_v1($1,$2)", [org,periodId]),
    /pandora_tax_approved_rule_pack_required/,
  );
});

test("deterministic calculation uses only an approved pack and produces reproducible checksums", async (t) => {
  const db = await makeDb(t);
  await db.exec("reset role");
  const periodId = await insertPeriod(db);
  await makeApprovedSyntheticPack(db, periodId);

  await actAs(db, null, "service_role");
  const posted = await postLedger(db, periodId, "sale-calc");

  await actAs(db, owner);
  await db.query(
    "select public.pandora_tax_review_ledger_entry_v1($1,$2,'verified','revenue','vat_taxable_sale','sale','checked')",
    [org,posted.ledgerEntryId],
  );
  await db.query(
    "select public.pandora_tax_run_reconciliation_v1($1,$2)",
    [org,periodId],
  );

  const first = (
    await db.query(
      "select public.pandora_tax_calculate_period_v1($1,$2) as payload",
      [org,periodId],
    )
  ).rows[0].payload;

  assert.equal(first.status, "complete");
  assert.equal(first.lineCount, 2);
  assert.match(first.inputChecksum, /^[0-9a-f]{64}$/);
  assert.match(first.outputChecksum, /^[0-9a-f]{64}$/);

  const lines = await db.query(
    "select line_key,amount from public.tax_calculation_lines where calculation_run_id=$1 order by line_key",
    [first.calculationRunId],
  );
  const byKey = Object.fromEntries(lines.rows.map((row) => [row.line_key, Number(row.amount)]));
  assert.equal(byKey.sales_base, 1000);
  assert.equal(byKey.output_tax, 120);

  const obligation = (
    await db.query(
      "select obligation_key,amount_due,due_date from public.tax_obligations where organization_id=$1 and tax_period_id=$2",
      [org,periodId],
    )
  ).rows[0];
  assert.equal(obligation.obligation_key, "synthetic_vat");
  assert.equal(Number(obligation.amount_due), 120);
  assert.equal(String(obligation.due_date), "2026-10-25");
});

test("filing package requires completed deterministic calculation and remains submission-disabled after review and owner approval", async (t) => {
  const db = await makeDb(t);
  await db.exec("reset role");
  const periodId = await insertPeriod(db);
  await makeApprovedSyntheticPack(db, periodId);

  await actAs(db, null, "service_role");
  const posted = await postLedger(db, periodId, "sale-package");

  await actAs(db, owner);
  await db.query(
    "select public.pandora_tax_review_ledger_entry_v1($1,$2,'verified','revenue','vat_taxable_sale','sale','checked')",
    [org,posted.ledgerEntryId],
  );
  await db.query("select public.pandora_tax_run_reconciliation_v1($1,$2)", [org,periodId]);
  await db.query("select public.pandora_tax_calculate_period_v1($1,$2)", [org,periodId]);

  const pkg = (
    await db.query(
      "select public.pandora_tax_build_filing_package_v1($1,$2,'SYNTHETIC-RETURN') as payload",
      [org,periodId],
    )
  ).rows[0].payload;
  assert.equal(pkg.status, "review_required");
  assert.equal(pkg.filingEnabled, false);
  assert.equal(pkg.paymentEnabled, false);

  await actAs(db, null, "service_role");
  const professional = (
    await db.query(
      `select public.pandora_tax_record_filing_package_review_v1(
        $1,$2,$3,'cpa','synthetic-credential','approved','Synthetic review only'
      ) as payload`,
      [org,pkg.filingPackageId,reviewer],
    )
  ).rows[0].payload;
  assert.equal(professional.status, "accountant_approved");

  await actAs(db, owner);
  const approved = (
    await db.query(
      "select public.pandora_tax_approve_filing_package_v1($1,$2) as payload",
      [org,pkg.filingPackageId],
    )
  ).rows[0].payload;
  assert.equal(approved.status, "submission_disabled");
  assert.equal(approved.filingEnabled, false);
  assert.equal(approved.paymentEnabled, false);
});

test("command center exposes operational truth without claiming filing or payment capability", async (t) => {
  const db = await makeDb(t);
  await actAs(db, owner);
  const center = (
    await db.query(
      "select public.pandora_tax_command_center_v1($1) as payload",
      [org],
    )
  ).rows[0].payload;

  assert.equal(center.capabilities.preparePeriod, true);
  assert.equal(center.capabilities.evidenceInbox, true);
  assert.equal(center.capabilities.canonicalLedger, true);
  assert.equal(center.capabilities.reconciliation, true);
  assert.equal(center.capabilities.filingSubmission, false);
  assert.equal(center.capabilities.paymentExecution, false);
  assert.equal(center.rules.liveCalculationEnabled, false);
  assert.doesNotMatch(JSON.stringify(center), /service_role|access_token|refresh_token/i);
});

test("PH draft rule tests execute deterministically but do not self-approve the pack", async (t) => {
  const db = await makeDb(t);
  await db.exec("reset role");
  const pack = (
    await db.query(
      "select id,status from public.tax_rule_packs where jurisdiction_code='PH' and version='ph-2026-authoritative-draft-v1'",
    )
  ).rows[0];

  await actAs(db, null, "service_role");
  const result = (
    await db.query(
      "select public.pandora_tax_run_rule_tests_v1($1) as payload",
      [pack.id],
    )
  ).rows[0].payload;

  assert.equal(result.total, 6);
  assert.equal(result.passed, 6);
  assert.equal(result.failed, 0);
  assert.equal(result.allPassed, true);

  await db.exec("reset role");
  const state = (
    await db.query(
      "select status from public.tax_rule_packs where id=$1",
      [pack.id],
    )
  ).rows[0];
  assert.equal(state.status, "in_review");

  const tests = await db.query(
    "select test_key,status,last_result from public.tax_rule_tests where rule_pack_id=$1 order by test_key",
    [pack.id],
  );
  assert.equal(tests.rows.length, 6);
  assert.ok(tests.rows.every((row) => row.status === "passed"));
});

test("draft PH source pack cannot be approved without passing tests and professional source review", async (t) => {
  const db = await makeDb(t);
  await db.exec("reset role");
  const pack = (
    await db.query(
      "select id from public.tax_rule_packs where jurisdiction_code='PH' and version='ph-2026-authoritative-draft-v1'",
    )
  ).rows[0];

  await actAs(db, null, "service_role");
  await assert.rejects(
    db.query(
      `select public.pandora_tax_record_rule_review_v1(
        $1,$2,'cpa','synthetic-credential','approve',
        'Attempted approval before rule tests were independently passed',
        true,true,'{}'::jsonb
      )`,
      [pack.id,reviewer],
    ),
    /pandora_tax_rule_pack_not_approvable/,
  );
});

test("universal chat gives deterministic tax status and refuses filing or payment claims", async (t) => {
  const db = await makeDb(t);
  await actAs(db, owner);

  const status = (
    await db.query(
      "select public.pandora_chat_universal_dispatch_v9($1,'tax status',null,null) as payload",
      [org],
    )
  ).rows[0].payload;
  assert.equal(status.handled, true);
  assert.equal(status.conversationLane, "tax_compliance");
  assert.equal(status.providerReadback.capability, "tax.command-center.read");
  assert.match(status.reply, /rule pack|tax command center/i);

  const guarded = (
    await db.query(
      "select public.pandora_chat_universal_dispatch_v9($1,'pay our taxes now',null,null) as payload",
      [org],
    )
  ).rows[0].payload;
  assert.equal(guarded.handled, true);
  assert.equal(guarded.providerReadback.capability, "tax.legal_action.guardrail");
  assert.equal(guarded.providerReadback.filingEnabled, false);
  assert.equal(guarded.providerReadback.paymentEnabled, false);
  assert.match(guarded.reply, /not submitted or paid|disabled/i);

  const messages = await db.query(
    "select author_role,content from public.pandora_intelligence_messages order by created_at,id",
  );
  assert.equal(messages.rows.length, 4);
});

test("operating core grants keep privileged writes out of authenticated clients", () => {
  assert.doesNotMatch(
    operating,
    /grant\s+(?:insert|update|delete|all)[^;]*public\.tax_(?:counterparties|accounts|entry_classifications|entry_adjustments|reconciliation_matches|exception_resolutions|rule_sources|rule_tests|rule_reviews|return_versions|return_schedules|filing_packages)[^;]*to authenticated/i,
  );
  assert.match(
    operating,
    /grant execute on function public\.pandora_tax_post_ledger_entry_v1[\s\S]*to service_role/i,
  );
  assert.doesNotMatch(
    operating,
    /grant execute on function public\.pandora_tax_post_ledger_entry_v1[\s\S]{0,500}to authenticated/i,
  );
  assert.match(
    operating,
    /grant execute on function public\.pandora_tax_run_rule_tests_v1\(uuid\)[\s\S]*to service_role/i,
  );
  assert.doesNotMatch(
    operating,
    /grant execute on function public\.pandora_tax_run_rule_tests_v1\(uuid\)[\s\S]{0,300}to authenticated/i,
  );
  assert.match(
    operating,
    /status,'in_review'/i,
  );
  assert.doesNotMatch(
    operating,
    /filingAdapterState','verified_submit'/i,
  );
});
