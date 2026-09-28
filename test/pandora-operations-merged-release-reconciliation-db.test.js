"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { PGlite } = require("@electric-sql/pglite");
const { normalizeTask, REPOSITORIES } = require("../packages/pandora-operations-room/contracts");
const REPO = REPOSITORIES[0], ROOT = "/repos/" + REPO;
const BASE = "a".repeat(40), OLD = "b".repeat(40), HEAD = "c".repeat(40);
const MERGE = "d".repeat(40), MAIN = "e".repeat(40);
let db;
const migration = name => fs.readFileSync(path.join(__dirname, "../supabase/migrations", name), "utf8");
async function rpc(name, args) {
  const entries = Object.entries(args);
  const values = entries.map(([, value]) => typeof value === "object" && value !== null && !Array.isArray(value) ? JSON.stringify(value) : value);
  return (await db.query("select public." + name + "(" +
    entries.map(([key], i) => key + " => $" + (i + 1)).join(",") + ") value", values)).rows[0].value;
}
async function fixture({ risk = "source", status = "verifying" } = {}) {
  const org = randomUUID(), project = randomUUID(), taskId = "FB-FIXTURE-" + randomUUID();
  await db.query("insert into organizations(id) values($1)", [org]);
  const scope = { p_organization_id: org, p_project_id: project };
  await rpc("pandora_ops_project_binding_v1", { ...scope, p_state: "active", p_evidence_ref: "fixture:binding" });
  await rpc("pandora_ops_initialize_v1", { ...scope, p_budget_micros: 0, p_max_concurrency: 2 });
  await db.query("update private.pandora_ops_workspaces set paused=false where organization_id=$1", [org]);
  for (const worker of ["builder", "release"]) await rpc("pandora_ops_register_worker_v1", {
    ...scope, p_worker_key: worker, p_principal_key: worker + "-principal",
    p_lanes: worker === "builder" ? ["backend"] : ["release"],
    p_capabilities: ["source.write", "provider.readback", "release.verify"],
    p_capacity: 1, p_receipt_ref: "fixture:" + worker,
  });
  const spec = normalizeTask({
    id: taskId, title: "Merged release source reconciliation fixture", lane: "backend", priority: 0,
    dependsOn: [], resources: [{ key: "source/facebook/memory", mode: "write" }],
    requiredCapabilities: ["source.write"], maxCostMicros: 0, maxDurationSeconds: 60, maxAttempts: 2,
    risk, acceptance: ["Fresh exact-head verification is required."],
    source: { repository: REPO, baseSha: BASE },
    verificationProfile: risk === "production" ? "production_release" : "backend_service",
  });
  await rpc("pandora_ops_ingest_v1", { ...scope, p_tasks: JSON.stringify([spec]) });
  const handoff = { taskId, workerId: "builder", generation: 4, headSha: OLD,
    pullRequest: 786, implementationComplete: true, receiptRef: "historical:handoff", tests: ["historical"] };
  await db.query("update private.pandora_ops_tasks set status=$1,revision=12,generation=4,attempts=1," +
    "builder_worker_key='builder',builder_principal_key='builder-principal',head_sha=$2,handoff=$3 " +
    "where organization_id=$4 and task_key=$5", [status, OLD, JSON.stringify(handoff), org, taskId]);
  const row = (await db.query("select * from private.pandora_ops_tasks where organization_id=$1 and task_key=$2", [org, taskId])).rows[0];
  const args = { ...scope, p_request_id: randomUUID(), p_task_key: taskId,
    p_generation: 4, p_revision: 12, p_spec_digest: row.spec_digest, p_expected_head_sha: OLD,
    p_reconciler_worker_key: "release", p_reconciler_principal_key: "release-principal" };
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
async function providerFixtures() {
  await db.exec("delete from private.github_fixture");
  await setResponse(ROOT + "/pulls/786", pr());
  await setResponse(ROOT + "/issues/786/timeline?per_page=100&page=1",
    [{ event: "merged", commit_id: MERGE, created_at: "2026-09-27T11:15:45Z" }]);
  await setResponse(ROOT + "/commits/" + MERGE, { sha: MERGE, parents: [{ sha: BASE }, { sha: HEAD }] });
  await setResponse(ROOT + "/git/ref/heads/main", { object: { sha: MAIN } });
  for (const [from, to] of [[OLD, HEAD], [BASE, HEAD], [MERGE, MAIN]]) {
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
    create function extensions.digest(data bytea,algorithm text) returns bytea language sql immutable
      as $$select pg_catalog.sha256(data)$$;
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

test("FB012-style production adoption preserves production approval and rollback requirements", async () => {
  const f = await fixture({ risk: "production", status: "handed_off" });
  await adopt(f);
  const evidence = { taskId: f.taskId, generation: "5", headSha: HEAD,
    taskSpecDigest: f.args.p_spec_digest, criteria: f.spec.acceptance, ref: "fixture:production-check" };
  const recorded = await rpc("pandora_ops_record_verification_v1", { ...f.scope, p_task_key: f.taskId,
    p_generation: 5, p_verifier_key: "release", p_principal_key: "release-principal", p_status: "PASS", p_evidence: evidence });
  await assert.rejects(rpc("pandora_ops_verify_v1", { ...f.scope, p_task_key: f.taskId,
    p_generation: 5, p_verifier_key: "release", p_principal_key: "release-principal",
    p_verification_run_id: recorded.verificationRunId,
    p_receipt: { ...evidence, verificationRunId: recorded.verificationRunId } }), /OPS_PRODUCTION_PROOF_REQUIRED/);
  assert.equal((await state(f)).status, "verifying");
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
    await assert.rejects(adopt(f, change), /OPS_MERGED_RELEASE_TASK_FENCED|OPS_PROJECT_SCOPE_DENIED/);
    await unchanged(f, before);
  }
});

test("builder, mismatched principal and stale verifier cannot reconcile", async () => {
  const f = await fixture(), before = await state(f);
  for (const change of [{ p_reconciler_worker_key: "builder", p_reconciler_principal_key: "builder-principal" },
    { p_reconciler_principal_key: "other-principal" }]) {
    await assert.rejects(adopt(f, change), /OPS_MERGED_RELEASE_INDEPENDENT_RECONCILER_REQUIRED/);
  }
  await db.query("update private.pandora_ops_workers set heartbeat_at=clock_timestamp()-interval '61 seconds' where organization_id=$1 and worker_key='release'", [f.org]);
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
  const control=fs.readFileSync(path.join(__dirname,"../supabase/functions/mcpmaster-supabase-control/index.ts"),"utf8");
  assert.ok(control.indexOf("await verifyVercelToken(token)") < control.lastIndexOf("const route = routeForInput(input)"));
  assert.match(control,/routeForMergedRelease\(input, OPERATIONS_PROJECT_ID\)/);
});

test("public clients have no reconciliation execution or receipt table privileges", async () => {
  const signature="public.pandora_ops_reconcile_merged_release_v1(uuid,uuid,uuid,text,bigint,bigint,text,text,text,text)";
  for(const role of ["anon","authenticated"]) {
    const row=(await db.query("select has_function_privilege($1,$2,'EXECUTE') allowed",[role,signature])).rows[0];
    assert.equal(row.allowed,false);
  }
  assert.equal((await db.query("select has_function_privilege('service_role',$1,'EXECUTE') allowed",[signature])).rows[0].allowed,true);
  assert.equal((await db.query("select has_table_privilege('service_role','private.pandora_ops_merged_release_receipts','UPDATE') allowed")).rows[0].allowed,false);
});
