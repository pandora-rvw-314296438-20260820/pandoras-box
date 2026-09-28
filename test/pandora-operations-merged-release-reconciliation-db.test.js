"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { PGlite } = require("@electric-sql/pglite");
const { normalizeTask, REPOSITORIES } = require("../packages/pandora-operations-room/contracts");
const REPO = REPOSITORIES[0], ROOT = "/repos/" + REPO;
const BASE = "a".repeat(40);
const OLD = "5448f61715b139dff7bbedf9d3056ca80cadb585";
const HEAD = "3e38b571ae963cc663e622fc1a75d5578b6fb7a2";
const MERGE = "d".repeat(40), MAIN = "e".repeat(40);
const RELEASE_KEY = "pandora-native-release-v1";
const RELEASE_PRINCIPAL = "vercel:mcpmaster:operations-native-release-v1";
const FB025_SPEC = "a9cebabf19bbac53eaab1d27b4394efc8d1d943549bdbb1fc1ecda486ee7aefc";
const FB025_BASE = "f4675344f99a3d2cc23a9c360c9512826e921c5c";
const FB025_ACCEPTANCE = ["Schema distinguishes verified fact, user decision, provider evidence, inference, assumption, and superseded information."];
let db;
const migration = name => fs.readFileSync(path.join(__dirname, "../supabase/migrations", name), "utf8");
async function rpc(name, args) {
  const entries = Object.entries(args);
  const values = entries.map(([, value]) => typeof value === "object" && value !== null && !Array.isArray(value) ? JSON.stringify(value) : value);
  return (await db.query("select public." + name + "(" +
    entries.map(([key], i) => key + " => $" + (i + 1)).join(",") + ") value", values)).rows[0].value;
}
async function fixture({ risk = "source", status = "verifying", taskId = "FB-025" } = {}) {
  const org = randomUUID(), project = randomUUID();
  await db.query("insert into organizations(id) values($1)", [org]);
  const scope = { p_organization_id: org, p_project_id: project };
  await rpc("pandora_ops_project_binding_v1", { ...scope, p_state: "active", p_evidence_ref: "fixture:binding" });
  await rpc("pandora_ops_initialize_v1", { ...scope, p_budget_micros: 0, p_max_concurrency: 2 });
  await db.query("update private.pandora_ops_workspaces set paused=false where organization_id=$1", [org]);
  for (const worker of [
    { key: "builder", principal: "builder-principal", lanes: ["backend"] },
    { key: "release", principal: "release-principal", lanes: ["release"] },
    { key: RELEASE_KEY, principal: RELEASE_PRINCIPAL, lanes: ["release"] },
  ]) await rpc("pandora_ops_register_worker_v1", {
    ...scope, p_worker_key: worker.key, p_principal_key: worker.principal,
    p_lanes: worker.lanes, p_capabilities: ["source.write", "provider.readback", "release.verify"],
    p_capacity: 1, p_receipt_ref: "fixture:" + worker.key,
  });
  const spec = normalizeTask({
    id: taskId, title: "Merged release source reconciliation fixture", lane: "backend", priority: 0,
    dependsOn: [], resources: [{ key: "source/facebook/memory", mode: "write" }],
    requiredCapabilities: ["source.write"], maxCostMicros: 0, maxDurationSeconds: 60, maxAttempts: 2,
    risk, acceptance: taskId === "FB-025" ? FB025_ACCEPTANCE : ["Fresh exact-head verification is required."],
    source: { repository: REPO, baseSha: taskId === "FB-025" ? FB025_BASE : BASE },
    verificationProfile: risk === "production" ? "production_release" : "backend_service",
  });
  await rpc("pandora_ops_ingest_v1", { ...scope, p_tasks: JSON.stringify([spec]) });
  if (taskId === "FB-025") await db.query(
    "update private.pandora_ops_tasks set spec_digest=$1 where organization_id=$2 and task_key=$3",
    [FB025_SPEC, org, taskId]);
  const handoff = { taskId, workerId: "builder", generation: 4, headSha: OLD,
    pullRequest: 786, implementationComplete: true, receiptRef: "historical:handoff", tests: ["historical"] };
  await db.query("update private.pandora_ops_tasks set status=$1,revision=12,generation=4,attempts=1," +
    "builder_worker_key='builder',builder_principal_key='builder-principal',head_sha=$2,handoff=$3 " +
    "where organization_id=$4 and task_key=$5", [status, OLD, JSON.stringify(handoff), org, taskId]);
  const row = (await db.query("select * from private.pandora_ops_tasks where organization_id=$1 and task_key=$2", [org, taskId])).rows[0];
  const args = { ...scope, p_request_id: randomUUID(), p_task_key: taskId,
    p_generation: 4, p_revision: 12, p_spec_digest: row.spec_digest, p_expected_head_sha: OLD,
    p_reconciler_worker_key: RELEASE_KEY, p_reconciler_principal_key: RELEASE_PRINCIPAL };
  await providerFixtures();
  return { org, project, taskId, scope, spec, handoff, args };
}
async function setResponse(url, body, status = 200) {
  await db.query("insert into private.github_fixture(path,response) values($1,$2) " +
    "on conflict(path) do update set response=excluded.response,seen=0,next_response=null",
    [url, JSON.stringify({ status, body })]);
}
function pr() {
  return { number: 786, state: "closed", merged: true, merged_at: "2026-09-27T11:15:45Z",
    head: { sha: HEAD, repo: { full_name: REPO } },
    base: { ref: "main", repo: { full_name: REPO } } };
}
function reviewBody(kind) {
  const anchors = kind === "full"
    ? ["fixture-full-review:", "57ff9a46-47b0-4ba2-bad8-cb80de09efd0", OLD]
    : ["fixture-carried-review:", OLD, HEAD, "a4bad29c027b4d78d821f94eb1aeddbbc5d46991",
      "13ea5c37f04d7c07fdf6439a0e1bbd97d27b6f36", "0f2f9eab39fab6a89f48ab52bb1f1d4e1726a04d"];
  const target = kind === "full" ? 10461 : 5465;
  const prefix = anchors.join("\n") + "\n";
  return prefix + "x".repeat(target - Buffer.byteLength(prefix));
}
function issueComment(id, kind, created, updated) {
  return { id, user: { login: "coderabbitai[bot]", id: 136622811, type: "Bot" },
    performed_via_github_app: { id: 347564, slug: "coderabbitai" },
    created_at: created, updated_at: updated, body: reviewBody(kind) };
}
const check = (id, name, appId, appSlug = "github-actions", conclusion = "success") => ({
  id, name, head_sha: HEAD, status: "completed", conclusion,
  app: { id: appId, slug: appSlug },
});
const checkRuns = [
  check(108608310169, "Pandora coordinator / integration", 4785021),
  check(108607598769, "node24", 15368),
  check(108607620011, "Windows worker contract", 15368),
  check(108607598884, "canonical-release-source-contract", 15368),
  check(108607599143, "Dependency review", 15368),
  check(108607661171, "CodeQL", 57789, "github-advanced-security"),
  check(108607599999, "Supabase Preview", 15368, "github-actions", "skipped"),
];
async function providerFixtures() {
  await db.exec("delete from private.github_fixture");
  await setResponse(ROOT + "/pulls/786", pr());
  await setResponse(ROOT + "/issues/786/timeline?per_page=100&page=1",
    [{ event: "merged", commit_id: MERGE, created_at: "2026-09-27T11:15:45Z" }]);
  await setResponse(ROOT + "/commits/" + MERGE, { sha: MERGE, parents: [{ sha: BASE }, { sha: HEAD }] });
  await setResponse(ROOT + "/git/ref/heads/main", { object: { sha: MAIN } });
  await setResponse(ROOT + "/commits/" + HEAD + "/check-runs?per_page=100",
    { total_count: checkRuns.length, check_runs: checkRuns });
  await setResponse(ROOT + "/issues/comments/5854323698",
    issueComment(5854323698, "full", "2026-09-27T08:46:48Z", "2026-09-27T11:10:38Z"));
  await setResponse(ROOT + "/issues/comments/5855325039",
    issueComment(5855325039, "carried", "2026-09-27T11:12:57Z", "2026-09-27T11:12:57Z"));
  for (const [itemPath, sha] of [
    ["docs/growth/FB025_GROWTH_LEARNING_SCHEMA.md", "a4bad29c027b4d78d821f94eb1aeddbbc5d46991"],
    ["src/pandora-growth-learning-schema.js", "13ea5c37f04d7c07fdf6439a0e1bbd97d27b6f36"],
    ["test/pandora-growth-learning-schema.test.js", "0f2f9eab39fab6a89f48ab52bb1f1d4e1726a04d"],
  ]) await setResponse(ROOT + "/contents/" + itemPath + "?ref=" + HEAD, { path: itemPath, type: "file", sha });
  for (const [from, to] of [[OLD, HEAD], [FB025_BASE, HEAD], [MERGE, MAIN]]) {
    await setResponse(ROOT + "/compare/" + from + "%2E%2E%2E" + to, { status: "ahead", behind_by: 0 });
  }
}
async function state(f) {
  return (await db.query("select status,generation,revision,head_sha,handoff,verification,spec_digest " +
    "from private.pandora_ops_tasks where organization_id=$1 and task_key=$2", [f.org, f.taskId])).rows[0];
}
async function adopt(f, changes = {}) {
  return rpc("pandora_ops_reconcile_merged_release_v1", { ...f.args, ...changes });
}
async function verifySource(f, receiptId, changes = {}) {
  const current = await state(f);
  return rpc("pandora_ops_verify_merged_release_source_v1", {
    ...f.scope, p_task_key: f.taskId, p_generation: Number(current.generation),
    p_spec_digest: current.spec_digest, p_expected_head_sha: current.head_sha,
    p_reconciliation_receipt_id: receiptId,
    p_verifier_worker_key: RELEASE_KEY, p_verifier_principal_key: RELEASE_PRINCIPAL,
    ...changes,
  });
}
async function sourceStep(f, changes = {}) {
  return rpc("pandora_ops_merged_release_source_step_v1", {
    ...f.scope, p_worker_key: RELEASE_KEY, p_principal_key: RELEASE_PRINCIPAL, ...changes,
  });
}
async function unchanged(f, before) {
  assert.deepEqual(await state(f), before);
  assert.equal((await db.query("select count(*)::int n from private.pandora_ops_merged_release_receipts where organization_id=$1", [f.org])).rows[0].n, 0);
}
test.before(async () => {
  db = await PGlite.create();
  await db.exec(`
    create role anon; create role authenticated; create role service_role;
    create schema private; create schema extensions; create schema auth;
    create table public.organizations(id uuid primary key);
    create table public.memberships(organization_id uuid,user_id uuid,role text,status text);
    create table public.pandora_verification_runs(id uuid primary key,organization_id uuid not null,
      project_id uuid not null,status text not null,source_commit text,required_check_profile text,completed_at timestamptz);
    create function auth.jwt() returns jsonb language sql stable as $$select '{}'::jsonb$$;
    create function extensions.digest(data bytea,algorithm text) returns bytea language plpgsql immutable
      as $$declare body text:=pg_catalog.convert_from(data,'UTF8');
      begin
        if body like 'fixture-full-review:%' then
          return pg_catalog.decode('defa2c5cfceab021d282fa1cd3904de894bf0c2abf1c3223d55a9d5612feda08','hex');
        elsif body like 'fixture-carried-review:%' then
          return pg_catalog.decode('4f5b0f33bfce1bdffafce66db3bf3af62c89ea9a2310f727cf87ad6f4e6061de','hex');
        end if;
        return pg_catalog.sha256(data);
      end$$;
  `);
  await db.exec(migration("20260925101319_pandora_operations_room_runtime_v1.sql"));
  await db.exec(migration("20260926045200_operations_native_verification_v1.sql"));
  await db.exec(`
    create table private.github_fixture(path text primary key,response jsonb not null,next_response jsonb,seen integer default 0);
    create function private.pandora_integration_github_api_20260825(p_method text,p_path text,p_body jsonb default null)
    returns jsonb language plpgsql set search_path='' as $$
    declare result jsonb;
    begin
      if p_method<>'GET' or p_body is not null then raise exception 'PROVIDER_MUTATION_FORBIDDEN'; end if;
      select case when seen>0 and next_response is not null then next_response else response end
      into result from private.github_fixture where path=p_path;
      update private.github_fixture set seen=seen+1 where path=p_path;
      return result;
    end $$;
  `);
  await db.exec(migration("20260928190000_operations_merged_release_reconciliation_v1.sql"));
});
test.after(async () => { await db?.close(); });

test("FB025-style adoption preserves history and requires a fresh verification generation", async () => {
  const f = await fixture();
  const oldEvidence = { taskId: f.taskId, generation: "4", headSha: OLD,
    taskSpecDigest: f.args.p_spec_digest, criteria: f.spec.acceptance, ref: "fixture:old-pass" };
  const oldPass = await rpc("pandora_ops_record_verification_v1", { ...f.scope,
    p_task_key: f.taskId, p_generation: 4, p_verifier_key: "release",
    p_principal_key: "release-principal", p_status: "PASS", p_evidence: oldEvidence });
  const result = await adopt(f);
  assert.equal(result.state, "verifying"); assert.equal(result.completionGranted, false);
  assert.equal(Number(result.generation), 5); assert.equal(result.headSha, HEAD);
  const after = await state(f);
  assert.equal(Number(after.revision), 13); assert.equal(after.verification, null);
  assert.deepEqual(after.handoff, f.handoff);
  const archived = (await db.query("select * from private.pandora_ops_merged_release_receipts where id=$1", [f.args.p_request_id])).rows[0];
  assert.equal(archived.merge_sha, MERGE); assert.equal(archived.canonical_main_sha, MAIN);
  assert.equal(archived.prior_task.head_sha, OLD);
  assert.equal((await db.query("select status from private.pandora_ops_verification_receipts where id=$1", [oldPass.verificationRunId])).rows[0].status, "PASS");
  await assert.rejects(rpc("pandora_ops_verify_v1", { ...f.scope, p_task_key: f.taskId,
    p_generation: 5, p_verifier_key: "release", p_principal_key: "release-principal",
    p_verification_run_id: oldPass.verificationRunId,
    p_receipt: { ...oldEvidence, generation: "5", headSha: HEAD, verificationRunId: oldPass.verificationRunId } }),
    /OPS_CANONICAL_VERIFICATION_REQUIRED/);
  const fresh = { ...oldEvidence, generation: "5", headSha: HEAD, ref: "fixture:fresh-pass" };
  const freshPass = await rpc("pandora_ops_record_verification_v1", { ...f.scope,
    p_task_key: f.taskId, p_generation: 5, p_verifier_key: "release",
    p_principal_key: "release-principal", p_status: "PASS", p_evidence: fresh });
  assert.notEqual(oldPass.verificationRunId, freshPass.verificationRunId);
  const accepted = await rpc("pandora_ops_verify_v1", { ...f.scope, p_task_key: f.taskId,
    p_generation: 5, p_verifier_key: "release", p_principal_key: "release-principal",
    p_verification_run_id: freshPass.verificationRunId,
    p_receipt: { ...fresh, verificationRunId: freshPass.verificationRunId } });
  assert.equal(accepted.complete, true);
});

test("FB-012 production stays at the historical handoff without provider reads or receipts", async () => {
  const f = await fixture({ taskId: "FB-012", risk: "production", status: "handed_off" });
  const before = await state(f);
  await assert.rejects(adopt(f), /OPS_MERGED_RELEASE_PRODUCTION_TASK_UNSUPPORTED/);
  assert.deepEqual(await state(f), before);
  assert.equal((await db.query("select count(*)::int n from private.pandora_ops_merged_release_receipts where organization_id=$1", [f.org])).rows[0].n, 0);
  assert.equal((await db.query("select count(*)::int n from private.pandora_ops_verification_receipts where organization_id=$1", [f.org])).rows[0].n, 0);
  assert.equal((await db.query("select coalesce(sum(seen),0)::int n from private.github_fixture")).rows[0].n, 0);
});

test("exact replay is stable and conflicting replay cannot overwrite evidence", async () => {
  const f = await fixture(); const first = await adopt(f), before = await state(f);
  const replay = await adopt(f);
  assert.equal(replay.replayed, true); assert.equal(replay.receiptId, first.receiptId);
  assert.deepEqual(await state(f), before);
  await assert.rejects(adopt(f, { p_expected_head_sha: "f".repeat(40) }), /OPS_MERGED_RELEASE_REPLAY_CONFLICT/);
  await assert.rejects(db.query("update private.pandora_ops_merged_release_receipts set head_sha=$1 where id=$2",
    [OLD, f.args.p_request_id]), /OPS_MERGED_RELEASE_RECEIPT_IMMUTABLE/);
});

test("task generation revision digest head and scope are fenced", async () => {
  for (const change of [{ p_generation: 3 }, { p_revision: 11 }, { p_spec_digest: "f".repeat(64) },
    { p_expected_head_sha: "f".repeat(40) }, { p_project_id: randomUUID() }]) {
    const f = await fixture(), before = await state(f);
    await assert.rejects(adopt(f, change), /OPS_MERGED_RELEASE_(TASK_FENCED|SOURCE_SPEC_UNSUPPORTED)|OPS_PROJECT_SCOPE_DENIED/);
    await unchanged(f, before);
  }
});

test("builder, mismatched principal and stale verifier cannot reconcile", async () => {
  const f = await fixture(), before = await state(f);
  for (const change of [{ p_reconciler_worker_key: "builder", p_reconciler_principal_key: "builder-principal" },
    { p_reconciler_principal_key: "other-principal" }]) {
    await assert.rejects(adopt(f, change), /OPS_MERGED_RELEASE_INDEPENDENT_RECONCILER_REQUIRED/);
  }
  await db.query("update private.pandora_ops_workers set heartbeat_at=clock_timestamp()-interval '61 seconds' where organization_id=$1 and worker_key=$2", [f.org,RELEASE_KEY]);
  await assert.rejects(adopt(f), /OPS_MERGED_RELEASE_INDEPENDENT_RECONCILER_REQUIRED/);
  await unchanged(f, before);
});

test("active leases and paused or revoked workspaces retain the hold", async () => {
  for (const condition of ["lease", "paused", "revoked"]) {
    const f = await fixture(), before = await state(f);
    if (condition === "lease") await db.query("insert into private.pandora_ops_leases(organization_id,project_id,task_key,worker_key,generation,claim_request_key,state,resources,reserved_micros,expires_at) values($1,$2,$3,'builder',4,'fixture','reconcile','[]',0,clock_timestamp()-interval '1 second')", [f.org,f.project,f.taskId]);
    if (condition === "paused") await db.query("update private.pandora_ops_workspaces set paused=true where organization_id=$1", [f.org]);
    if (condition === "revoked") await db.query("update private.pandora_ops_project_bindings set state='revoked' where organization_id=$1", [f.org]);
    await assert.rejects(adopt(f), /OPS_MERGED_RELEASE_ACTIVE_LEASE|OPS_WORKSPACE_PAUSED|OPS_PROJECT_SCOPE_DENIED/);
    await unchanged(f, before);
  }
});

test("unmerged wrong-repository wrong-PR and wrong-branch responses cannot adopt", async () => {
  for (const mutate of [p => { p.merged=false; p.state="open"; }, p => { p.number=999; },
    p => { p.head.repo.full_name="other/repo"; }, p => { p.base.ref="other"; }]) {
    const f=await fixture(), before=await state(f), body=pr(); mutate(body);
    await setResponse(ROOT+"/pulls/786", body);
    await assert.rejects(adopt(f), /OPS_MERGED_RELEASE_PR_IDENTITY_MISMATCH/);
    await unchanged(f,before);
  }
});

test("missing merge event and wrong merge parent cannot adopt", async () => {
  const f=await fixture(), before=await state(f);
  await setResponse(ROOT+"/issues/786/timeline?per_page=100&page=1", []);
  await assert.rejects(adopt(f), /OPS_MERGED_RELEASE_MERGE_BINDING_REQUIRED/);
  await providerFixtures();
  await setResponse(ROOT+"/commits/"+MERGE,{sha:MERGE,parents:[{sha:OLD}]});
  await assert.rejects(adopt(f), /OPS_MERGED_RELEASE_MERGE_PARENT_MISMATCH/);
  await unchanged(f,before);
});

test("unknown provider outcomes and divergent ancestry preserve original task state", async () => {
  for(const url of [ROOT+"/pulls/786", ROOT+"/git/ref/heads/main",
    ROOT+"/issues/786/timeline?per_page=100&page=1",ROOT+"/commits/"+MERGE,
    ROOT+"/compare/"+OLD+"%2E%2E%2E"+HEAD]) {
    const f=await fixture(), before=await state(f);
    await setResponse(url,{},503);
    await assert.rejects(adopt(f), /OPS_MERGED_RELEASE_/);
    await unchanged(f,before);
  }
  const f=await fixture(),before=await state(f);
  await setResponse(ROOT+"/compare/"+MERGE+"%2E%2E%2E"+MAIN,{status:"diverged",behind_by:1});
  await assert.rejects(adopt(f), /OPS_MERGED_RELEASE_LINEAGE_UNCONFIRMED/);
  await unchanged(f,before);
});

test("timeline pagination is bounded and the final PR read detects changed identity", async () => {
  const f=await fixture();
  await setResponse(ROOT+"/issues/786/timeline?per_page=100&page=1",Array.from({length:100},()=>({event:"labeled"})));
  await setResponse(ROOT+"/issues/786/timeline?per_page=100&page=2",[{event:"merged",commit_id:MERGE}]);
  await adopt(f);
  const other=await fixture(),before=await state(other),changed=pr();changed.head.sha=OLD;
  await db.query("update private.github_fixture set next_response=$1 where path=$2",
    [JSON.stringify({status:200,body:changed}),ROOT+"/pulls/786"]);
  await assert.rejects(adopt(other), /OPS_MERGED_RELEASE_READBACK_CHANGED/);
  await unchanged(other,before);
});

test("fixed native source step atomically reconciles, verifies, and replays FB-025", async () => {
  const f = await fixture();
  const result = await sourceStep(f);
  assert.equal(result.state, "complete");
  assert.equal(result.taskId, "FB-025");
  assert.equal(result.reconciled, true);
  assert.equal(result.generation, 5);
  assert.equal(result.headSha, HEAD);
  assert.equal(result.verification.providerReadbackVerified, true);
  assert.equal((await state(f)).status, "complete");
  const replay = await sourceStep(f);
  assert.equal(replay.state, "complete");
  assert.equal(replay.reconciled, false);
  assert.equal(replay.reconciliationReceiptId, result.reconciliationReceiptId);
  assert.equal(replay.verification.replayed, true);
  assert.equal((await db.query("select count(*)::int n from private.pandora_ops_merged_release_receipts where organization_id=$1", [f.org])).rows[0].n, 1);
  assert.equal((await db.query("select count(*)::int n from private.pandora_ops_verification_receipts where organization_id=$1", [f.org])).rows[0].n, 1);
});

test("fixed source step returns idle or held without provider reads or receipts", async () => {
  const production = await fixture({ taskId: "FB-012", risk: "production", status: "handed_off" });
  const beforeProduction = await state(production);
  const idle = await sourceStep(production);
  assert.deepEqual(idle, { state: "idle", taskId: "FB-025", reason: "task_missing" });
  assert.deepEqual(await state(production), beforeProduction);
  assert.equal((await db.query("select coalesce(sum(seen),0)::int n from private.github_fixture")).rows[0].n, 0);

  const drift = await fixture();
  await db.query("update private.pandora_ops_tasks set head_sha=$1 where organization_id=$2 and task_key=$3",
    ["f".repeat(40), drift.org, drift.taskId]);
  const held = await sourceStep(drift);
  assert.equal(held.state, "held");
  assert.equal(held.reason, "source_state_not_eligible");
  assert.equal((await db.query("select count(*)::int n from private.pandora_ops_merged_release_receipts where organization_id=$1", [drift.org])).rows[0].n, 0);
  assert.equal((await db.query("select count(*)::int n from private.pandora_ops_verification_receipts where organization_id=$1", [drift.org])).rows[0].n, 0);
  assert.equal((await db.query("select coalesce(sum(seen),0)::int n from private.github_fixture")).rows[0].n, 0);
});

test("source-step verification failure rolls back the adopted generation and receipts", async () => {
  const f = await fixture(), before = await state(f);
  await setResponse(ROOT + "/commits/" + HEAD + "/check-runs?per_page=100",
    { total_count: checkRuns.length, check_runs: checkRuns.map((run,i) => i ? run : { ...run, conclusion: "failure" }) });
  await assert.rejects(sourceStep(f), /OPS_MERGED_RELEASE_SOURCE_CHECKS_NOT_GREEN/);
  assert.deepEqual(await state(f), before);
  assert.equal((await db.query("select count(*)::int n from private.pandora_ops_merged_release_receipts where organization_id=$1", [f.org])).rows[0].n, 0);
  assert.equal((await db.query("select count(*)::int n from private.pandora_ops_verification_receipts where organization_id=$1", [f.org])).rows[0].n, 0);
});

test("FB-025 completes only through exact provider-owned merged-release proof", async () => {
  const f = await fixture({ taskId: "FB-025" });
  await assert.rejects(verifySource(f, randomUUID()), /OPS_MERGED_RELEASE_SOURCE_TASK_FENCED/);
  const reconciled = await adopt(f);
  const result = await verifySource(f, reconciled.receiptId);
  assert.equal(result.complete, true);
  assert.equal(result.providerReadbackVerified, true);
  const after = await state(f);
  assert.equal(after.status, "complete");
  assert.equal(after.verification.providerReadback.pullRequest, 786);
  assert.equal(after.verification.providerReadback.fullReview.commentId, 5854323698);
  assert.equal(after.verification.providerReadback.carriedReview.commentId, 5855325039);
  assert.equal(after.verification.ref, "ops-merged-release:" + reconciled.receiptId + ":" + HEAD);
  const replay = await verifySource(f, reconciled.receiptId);
  assert.equal(replay.complete, true);
  assert.equal(replay.replayed, true);
  assert.equal((await db.query("select count(*)::int n from private.pandora_ops_verification_receipts where organization_id=$1", [f.org])).rows[0].n, 1);
});

test("FB-025 receipt and current generation head spec are exact fences", async () => {
  const f = await fixture({ taskId: "FB-025" });
  const reconciled = await adopt(f);
  for (const change of [
    { p_reconciliation_receipt_id: randomUUID() },
    { p_generation: 4 },
    { p_expected_head_sha: OLD },
    { p_spec_digest: "f".repeat(64) },
    { p_verifier_worker_key: "release", p_verifier_principal_key: "release-principal" },
  ]) {
    await assert.rejects(verifySource(f, reconciled.receiptId, change),
      /OPS_MERGED_RELEASE_SOURCE_(RECEIPT_MISMATCH|TASK_FENCED|VERIFIER_DENIED)/);
  }
  assert.equal((await state(f)).status, "verifying");
  assert.equal((await db.query("select count(*)::int n from private.pandora_ops_verification_receipts where organization_id=$1", [f.org])).rows[0].n, 0);
});

test("changed FB-025 acceptance and recomputed digest fail closed", async () => {
  const f = await fixture();
  const reconciled = await adopt(f);
  await db.query("update private.pandora_ops_tasks set spec=jsonb_set(spec,'{acceptance}',$1::jsonb),spec_digest=$2 where organization_id=$3 and task_key=$4",
    [JSON.stringify(["Unreviewed replacement criterion."]), "f".repeat(64), f.org, f.taskId]);
  await assert.rejects(verifySource(f, reconciled.receiptId), /OPS_MERGED_RELEASE_SOURCE_TASK_FENCED/);
  assert.equal((await state(f)).status, "verifying");
  assert.equal((await db.query("select count(*)::int n from private.pandora_ops_verification_receipts where organization_id=$1", [f.org])).rows[0].n, 0);
});

test("pending failed missing duplicate or overflow check sets cannot create PASS", async () => {
  const variants = [
    runs => ({ total_count: runs.length, check_runs: runs.map((run,i) => i ? run : { ...run, status: "queued", conclusion: null }) }),
    runs => ({ total_count: runs.length, check_runs: runs.map((run,i) => i ? run : { ...run, conclusion: "failure" }) }),
    runs => ({ total_count: runs.length - 1, check_runs: runs.filter(run => run.name !== "node24") }),
    runs => ({ total_count: runs.length - 1, check_runs: runs.filter(run => run.name !== "CodeQL") }),
    runs => ({ total_count: runs.length + 1, check_runs: [...runs, { ...runs[1], id: 999999 }] }),
    runs => ({ total_count: 101, check_runs: runs }),
    runs => ({ total_count: runs.length, check_runs: runs.map((run,i) => i ? run : { ...run, head_sha: OLD }) }),
    runs => ({ total_count: runs.length, check_runs: runs.map((run,i) => i ? run : { ...run, app: { id: 1, slug: "other" } }) }),
    runs => ({ total_count: runs.length, check_runs: runs.map((run,i) => i !== 1 ? run : { ...run, id: 999998 }) }),
    runs => ({ total_count: runs.length, check_runs: runs.map((run,i) => i !== 1 ? run : { ...run, app: { ...run.app, id: 1 } }) }),
    runs => ({ total_count: runs.length, check_runs: runs.map((run,i) => i !== 5 ? run : { ...run, app: { ...run.app, slug: "other" } }) }),
  ];
  for (const mutate of variants) {
    const f = await fixture({ taskId: "FB-025" });
    const reconciled = await adopt(f);
    await setResponse(ROOT + "/commits/" + HEAD + "/check-runs?per_page=100", mutate(checkRuns));
    await assert.rejects(verifySource(f, reconciled.receiptId), /OPS_MERGED_RELEASE_SOURCE_/);
    assert.equal((await state(f)).status, "verifying");
    assert.equal((await db.query("select count(*)::int n from private.pandora_ops_verification_receipts where organization_id=$1", [f.org])).rows[0].n, 0);
  }
});

test("changed review, blob, or final PR readback cannot create PASS", async () => {
  const cases = [
    async () => setResponse(ROOT + "/issues/comments/5855325039",
      { ...issueComment(5855325039, "carried", "2026-09-27T11:12:57Z", "2026-09-27T11:12:57Z"), body: "bogus" }),
    async () => setResponse(ROOT + "/contents/src/pandora-growth-learning-schema.js?ref=" + HEAD,
      { path: "src/pandora-growth-learning-schema.js", type: "file", sha: OLD }),
    async () => setResponse(ROOT + "/commits/" + MERGE, { sha: MERGE, parents: [{ sha: BASE }, { sha: OLD }] }),
    async () => {
      const changed = pr(); changed.head.sha = OLD;
      await db.query("update private.github_fixture set seen=0,next_response=$1 where path=$2",
        [JSON.stringify({ status: 200, body: changed }), ROOT + "/pulls/786"]);
    },
  ];
  for (const mutate of cases) {
    const f = await fixture({ taskId: "FB-025" });
    const reconciled = await adopt(f);
    await mutate();
    await assert.rejects(verifySource(f, reconciled.receiptId), /OPS_MERGED_RELEASE_SOURCE_/);
    assert.equal((await state(f)).status, "verifying");
    assert.equal((await db.query("select count(*)::int n from private.pandora_ops_verification_receipts where organization_id=$1", [f.org])).rows[0].n, 0);
  }
});

test("control adapter rejects caller-selected identity and source authority", async () => {
  const { routeForMergedRelease } = await import("../supabase/functions/mcpmaster-supabase-control/merged-release-routes.mjs");
  const input={action:"operations_merged_release_reconcile",requestId:randomUUID(),taskId:"FB-025",
    generation:4,revision:12,taskSpecDigest:"a".repeat(64),expectedHeadSha:OLD};
  const route=routeForMergedRelease(input,"canonical-project");
  assert.equal(route.params.p_reconciler_worker_key,"pandora-native-release-v1");
  assert.equal(route.params.p_reconciler_principal_key,"vercel:mcpmaster:operations-native-release-v1");
  for(const extra of [{workerKey:"builder"},{principalKey:"owner"},{organizationId:randomUUID()},
    {headSha:HEAD},{repository:"other/repo"},{pullRequest:999}]) {
    assert.equal(routeForMergedRelease({...input,...extra},"canonical-project"),undefined);
  }
  assert.equal(routeForMergedRelease({...input,generation:1.5},"canonical-project"),undefined);
  const verifyInput={action:"operations_merged_release_verify_source",taskId:"FB-025",
    generation:5,taskSpecDigest:"a".repeat(64),expectedHeadSha:HEAD,reconciliationReceiptId:randomUUID()};
  const verifyRoute=routeForMergedRelease(verifyInput,"canonical-project");
  assert.equal(verifyRoute.rpc,"pandora_ops_verify_merged_release_source_v1");
  assert.equal(verifyRoute.params.p_verifier_worker_key,RELEASE_KEY);
  assert.equal(verifyRoute.params.p_verifier_principal_key,RELEASE_PRINCIPAL);
  for(const extra of [{workerKey:"builder"},{principalKey:"owner"},{criteria:[]},{status:"PASS"},
    {allPassed:true},{verificationRef:"opaque"},{approvalRef:"owner"},{rollbackRef:"rollback"}]) {
    assert.equal(routeForMergedRelease({...verifyInput,...extra},"canonical-project"),undefined);
  }
  assert.equal(routeForMergedRelease({...verifyInput,taskId:"FB-012"},"canonical-project"),undefined);
  const stepRoute=routeForMergedRelease({action:"operations_merged_release_source_step"},"canonical-project");
  assert.equal(stepRoute.rpc,"pandora_ops_merged_release_source_step_v1");
  assert.deepEqual(stepRoute.params,{
    p_project_id:"canonical-project",p_worker_key:RELEASE_KEY,p_principal_key:RELEASE_PRINCIPAL,
  });
  for(const extra of [{taskId:"FB-025"},{receiptId:randomUUID()},{status:"PASS"},{evidence:{}}]) {
    assert.equal(routeForMergedRelease({action:"operations_merged_release_source_step",...extra},"canonical-project"),undefined);
  }
  const control=fs.readFileSync(path.join(__dirname,"../supabase/functions/mcpmaster-supabase-control/index.ts"),"utf8");
  assert.ok(control.indexOf("await verifyVercelToken(token)") < control.lastIndexOf("const route = routeForInput(input)"));
  assert.match(control,/routeForMergedRelease\(input, OPERATIONS_PROJECT_ID\)/);
});

test("public clients have no reconciliation or source-verification execution privileges", async () => {
  const signatures=[
    "public.pandora_ops_reconcile_merged_release_v1(uuid,uuid,uuid,text,bigint,bigint,text,text,text,text)",
    "public.pandora_ops_verify_merged_release_source_v1(uuid,uuid,text,bigint,text,text,uuid,text,text)",
    "public.pandora_ops_merged_release_source_step_v1(uuid,uuid,text,text)",
  ];
  for(const signature of signatures) {
    for(const role of ["anon","authenticated"]) {
      const row=(await db.query("select has_function_privilege($1,$2,'EXECUTE') allowed",[role,signature])).rows[0];
      assert.equal(row.allowed,false);
    }
    assert.equal((await db.query("select has_function_privilege('service_role',$1,'EXECUTE') allowed",[signature])).rows[0].allowed,true);
  }
  assert.equal((await db.query("select has_table_privilege('service_role','private.pandora_ops_merged_release_receipts','UPDATE') allowed")).rows[0].allowed,false);
});
