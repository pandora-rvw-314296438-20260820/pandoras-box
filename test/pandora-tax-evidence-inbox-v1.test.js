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

const org = "10000000-0000-4000-8000-000000000001";
const otherOrg = "10000000-0000-4000-8000-000000000002";
const owner = "20000000-0000-4000-8000-000000000001";
const viewer = "20000000-0000-4000-8000-000000000002";
const stranger = "20000000-0000-4000-8000-000000000003";
const shaA = "a".repeat(64);
const shaB = "b".repeat(64);

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
  await db.exec(foundation);
  await db.exec(evidence);
  return db;
}

async function actAs(db, user, role = "authenticated") {
  await db.exec("reset role");
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [user ?? ""]);
  await db.exec(`set role ${role}`);
}

async function registerEvidence(db, externalId, hash = shaA) {
  return (
    await db.query(
      `select public.pandora_tax_register_evidence_v1(
        $1,null,$2,'uploaded_receipt',clock_timestamp(),$3,1234,
        'application/pdf','official_receipt','2026-09-24',
        'tax-evidence','org/2026/receipt.pdf',
        '{"source":"test"}'::jsonb,null
      ) as payload`,
      [org, externalId, hash],
    )
  ).rows[0].payload;
}

test("sensitive tax read authorization fails closed to owner/admin until finance roles exist", async (t) => {
  const db = await makeDb(t);

  await actAs(db, owner);
  assert.equal(
    (await db.query("select public.pandora_tax_can_read_org_v1($1) as ok", [org])).rows[0].ok,
    true,
  );

  await actAs(db, viewer);
  assert.equal(
    (await db.query("select public.pandora_tax_can_read_org_v1($1) as ok", [org])).rows[0].ok,
    false,
  );
  await assert.rejects(
    db.query("select public.pandora_tax_evidence_inbox_v1($1)", [org]),
    /pandora_tax_membership_required/,
  );
});

test("service evidence registration is hash-bound, idempotent and duplicate-aware", async (t) => {
  const db = await makeDb(t);
  await actAs(db, null, "service_role");

  const first = await registerEvidence(db, "upload-1");
  assert.equal(first.canonical, true);
  assert.equal(first.duplicate, false);
  assert.equal(first.replayed, false);
  assert.equal(first.extractionState, "pending");

  const replay = await registerEvidence(db, "upload-1");
  assert.equal(replay.documentId, first.documentId);
  assert.equal(replay.sourceObjectId, first.sourceObjectId);
  assert.equal(replay.replayed, true);
  assert.equal(replay.duplicate, false);

  const duplicate = await registerEvidence(db, "upload-2");
  assert.equal(duplicate.documentId, first.documentId);
  assert.notEqual(duplicate.sourceObjectId, first.sourceObjectId);
  assert.equal(duplicate.canonical, false);
  assert.equal(duplicate.duplicate, true);
  assert.equal(duplicate.replayed, false);

  // PGlite's synthetic service_role does not carry Supabase's production
  // BYPASSRLS attribute. Switch to the authorized owner for readback.
  await actAs(db, owner);

  assert.equal(
    (await db.query("select count(*)::int as n from public.tax_documents where organization_id=$1", [org])).rows[0].n,
    1,
  );
  assert.equal(
    (await db.query("select count(*)::int as n from public.tax_source_objects where organization_id=$1", [org])).rows[0].n,
    2,
  );
  assert.equal(
    (await db.query("select count(*)::int as n from public.tax_evidence_hashes where organization_id=$1", [org])).rows[0].n,
    1,
  );
  assert.equal(
    (await db.query("select count(*)::int as n from public.tax_document_links where organization_id=$1 and link_type='duplicate_source'", [org])).rows[0].n,
    1,
  );
});

test("raw evidence registration and extraction commits are not callable by authenticated clients", async (t) => {
  const db = await makeDb(t);
  await actAs(db, owner);

  await assert.rejects(
    db.query(
      `select public.pandora_tax_register_evidence_v1(
        $1,null,'client-upload','receipt',clock_timestamp(),$2,10,
        'application/pdf','receipt',null,null,null,'{}'::jsonb,null
      )`,
      [org, shaA],
    ),
    /permission denied/,
  );

  const migration = foundation + "\n" + evidence;
  assert.match(
    migration,
    /grant execute on function public\.pandora_tax_register_evidence_v1[\s\S]*to service_role/i,
  );
  assert.doesNotMatch(
    migration,
    /grant execute on function public\.pandora_tax_register_evidence_v1[\s\S]{0,400}to authenticated/i,
  );
});

test("provider extraction never auto-verifies even at maximum confidence", async (t) => {
  const db = await makeDb(t);
  await actAs(db, null, "service_role");
  const registered = await registerEvidence(db, "extract-1");

  const extracted = (
    await db.query(
      `select public.pandora_tax_commit_document_extraction_v1(
        $1,$2,$3,'cloud_model','synthetic-provider','synthetic-model','extractor-v1',
        '{"invoice_number":"INV-001","gross_amount":"123.45"}'::jsonb,
        '{"invoice_number":1.0,"gross_amount":1.0}'::jsonb,
        1.0,$4,'{"providerRequestId":"synthetic"}'::jsonb
      ) as payload`,
      [org, registered.documentId, shaA, shaB],
    )
  ).rows[0].payload;

  assert.equal(extracted.status, "review_required");
  assert.equal(extracted.humanReviewRequired, true);
  assert.equal(extracted.autoVerified, false);

  // Verify through the same fail-closed owner read boundary used by clients.
  await actAs(db, owner);

  const row = (
    await db.query(
      "select status,reviewed_by,reviewed_at from public.tax_document_extractions where id=$1",
      [extracted.extractionId],
    )
  ).rows[0];
  assert.equal(row.status, "review_required");
  assert.equal(row.reviewed_by, null);
  assert.equal(row.reviewed_at, null);

  return { db, registered, extracted };
});

test("owner review is required to verify extraction and writes an audit-safe review record", async (t) => {
  const db = await makeDb(t);
  await actAs(db, null, "service_role");
  const registered = await registerEvidence(db, "review-1");
  const extracted = (
    await db.query(
      `select public.pandora_tax_commit_document_extraction_v1(
        $1,$2,$3,'provider_ocr','synthetic-ocr',null,'ocr-v1',
        '{"supplier":"Example Supplier","gross_amount":"500.00"}'::jsonb,
        '{"supplier":0.99,"gross_amount":0.99}'::jsonb,
        0.99,$4,'{}'::jsonb
      ) as payload`,
      [org, registered.documentId, shaA, shaB],
    )
  ).rows[0].payload;

  await actAs(db, viewer);
  await assert.rejects(
    db.query(
      "select public.pandora_tax_review_document_extraction_v1($1,$2,'verified',null,'{}'::jsonb)",
      [org, extracted.extractionId],
    ),
    /pandora_tax_manager_required/,
  );

  await actAs(db, owner);
  const reviewed = (
    await db.query(
      "select public.pandora_tax_review_document_extraction_v1($1,$2,'verified','Checked against original receipt','{}'::jsonb) as payload",
      [org, extracted.extractionId],
    )
  ).rows[0].payload;

  assert.equal(reviewed.decision, "verified");
  assert.equal(reviewed.replayed, false);

  const document = (
    await db.query(
      "select extraction_state,extraction_confidence from public.tax_documents where id=$1",
      [registered.documentId],
    )
  ).rows[0];
  assert.equal(document.extraction_state, "verified");
  assert.equal(Number(document.extraction_confidence), 0.99);

  assert.equal(
    (await db.query("select count(*)::int as n from public.tax_document_reviews where extraction_id=$1", [extracted.extractionId])).rows[0].n,
    1,
  );
  assert.equal(
    (await db.query("select count(*)::int as n from public.tax_audit_events where event_type='tax_document_extraction_reviewed' and source_ref=$1", [extracted.extractionId])).rows[0].n,
    1,
  );

  const replay = (
    await db.query(
      "select public.pandora_tax_review_document_extraction_v1($1,$2,'verified','Checked against original receipt','{}'::jsonb) as payload",
      [org, extracted.extractionId],
    )
  ).rows[0].payload;
  assert.equal(replay.replayed, true);
});

test("owner evidence inbox summarizes evidence without returning raw extracted fields", async (t) => {
  const db = await makeDb(t);
  await actAs(db, null, "service_role");
  const registered = await registerEvidence(db, "inbox-1");
  await registerEvidence(db, "inbox-2");
  const extracted = (
    await db.query(
      `select public.pandora_tax_commit_document_extraction_v1(
        $1,$2,$3,'deterministic_parser','pandora',null,'parser-v1',
        '{"sensitive_field":"must-not-appear-in-inbox"}'::jsonb,
        '{"sensitive_field":0.75}'::jsonb,0.75,$4,'{}'::jsonb
      ) as payload`,
      [org, registered.documentId, shaA, shaB],
    )
  ).rows[0].payload;

  await actAs(db, owner);
  const inbox = (
    await db.query("select public.pandora_tax_evidence_inbox_v1($1,25) as payload", [org])
  ).rows[0].payload;

  assert.equal(inbox.rawEvidenceIncluded, false);
  assert.equal(inbox.summary.needsReview, 1);
  assert.equal(inbox.summary.duplicateSources, 1);
  assert.equal(inbox.documents.length, 1);
  assert.equal(inbox.documents[0].content_sha256_prefix, shaA.slice(0,16));
  assert.doesNotMatch(JSON.stringify(inbox), /must-not-appear-in-inbox/);
  assert.ok(extracted.extractionId);
});

test("cross-tenant owner cannot inspect or review another organization's evidence", async (t) => {
  const db = await makeDb(t);
  await actAs(db, null, "service_role");
  const registered = await registerEvidence(db, "tenant-1");
  const extracted = (
    await db.query(
      `select public.pandora_tax_commit_document_extraction_v1(
        $1,$2,$3,'manual_import',null,null,'manual-v1',
        '{"amount":"1.00"}'::jsonb,'{}'::jsonb,1.0,$4,'{}'::jsonb
      ) as payload`,
      [org, registered.documentId, shaA, shaB],
    )
  ).rows[0].payload;

  await actAs(db, stranger);
  await assert.rejects(
    db.query("select public.pandora_tax_evidence_inbox_v1($1)", [org]),
    /pandora_tax_membership_required/,
  );
  await assert.rejects(
    db.query(
      "select public.pandora_tax_review_document_extraction_v1($1,$2,'verified',null,'{}'::jsonb)",
      [org, extracted.extractionId],
    ),
    /pandora_tax_manager_required/,
  );
});
