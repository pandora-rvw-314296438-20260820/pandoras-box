"use strict";
const assert = require("node:assert/strict");
const { readFileSync, readdirSync } = require("node:fs");
const { join } = require("node:path");
const { randomUUID } = require("node:crypto");
const { test } = require("node:test");
const { PGlite } = require("@electric-sql/pglite");
const { pgcrypto } = require("@electric-sql/pglite/contrib/pgcrypto");
const read = (p) => readFileSync(join(__dirname, p), "utf8");
const migrationFiles = readdirSync(join(__dirname,"../supabase/migrations")).filter(name=>name.endsWith("_pandora_core_automation_titles_v1.sql"));
assert.equal(migrationFiles.length,1,"exactly one automation-title migration must exist");
const migration = read("../supabase/migrations/" + migrationFiles[0]);
const owner = "a0d6f184-3039-4735-8d11-63ce403636e2";
const customer = "f17558e4-e1b2-4b8d-a215-b96775b1a470";
const platform = "2270b266-59da-4c39-bfd9-9f8d08352af0";
const client = "076a9306-5c4e-4d9d-98d3-e3a6fea968fb";
const session = "30000000-0000-4000-8000-000000000001";
let db, beforeMetadata, afterMetadata;

async function actor(user = owner) {
  await db.exec("reset role");
  await db.query("select set_config('request.jwt.claims',$1,false)", [JSON.stringify({
    sub: user, role: "authenticated", aal: "aal2", session_id: session, is_anonymous: false,
  })]);
  await db.exec("set role authenticated");
}
async function snapshot(org = null, user = owner) {
  await actor(user);
  return (await db.query("select public.pandora_core_snapshot_v1('platform',$1) r", [org])).rows[0].r;
}
async function task({ org = platform, project = randomUUID(), key = randomUUID(),
  spec = { title: "Reconcile verified delivery outcomes" }, state = "queued", attempts = 0,
  queued = "2026-10-03T12:00:00Z", head = "a".repeat(40) } = {}) {
  await db.exec("reset role");
  await db.query(`insert into private.pandora_ops_tasks
    (organization_id,project_id,task_key,spec,spec_digest,status,attempts,queued_at,head_sha)
    values($1,$2,$3,$4,$5,$6,$7,$8,$9)`, [org,project,key,spec,"d".repeat(64),state,attempts,queued,head]);
  return { org, project, key, spec, state, attempts, queued, head };
}
async function rejects(sql, args = [], pattern = /permission|ACCESS_DENIED/i) {
  await db.exec("savepoint rejected");
  try { await assert.rejects(db.query(sql, args), pattern); }
  finally { await db.exec("rollback to savepoint rejected;release savepoint rejected"); }
}
async function metadata() {
  return (await db.query(`select p.oid::regprocedure::text signature,
    encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') body_sha256,
    pg_get_userbyid(p.proowner) owner,p.prosecdef,p.provolatile,p.proconfig,
    has_function_privilege('anon',p.oid,'execute') anon_execute,
    has_function_privilege('authenticated',p.oid,'execute') authenticated_execute,
    has_function_privilege('service_role',p.oid,'execute') service_execute,
    (select count(*)::integer from pg_proc where pronamespace in ('public'::regnamespace,'private'::regnamespace)) function_count,
    (select count(*)::integer from pg_class where relnamespace in ('public'::regnamespace,'private'::regnamespace) and relkind='r') table_count
    from pg_proc p where p.oid='public.pandora_core_snapshot_v1(text,uuid)'::regprocedure`)).rows[0];
}
test.before(async () => {
  db = new PGlite({ extensions: { pgcrypto } });
  // These fixtures assert UTC JSON timestamps, independent of the runner's zone.
  await db.exec("set time zone 'UTC'");
  for (const p of ["fixtures/pandora-core-owner-schema.sql", "fixtures/pandora-core-composer-provider-schema.sql", "fixtures/pandora-chat-request-admission-schema.sql"]) await db.exec(read(p));
  await db.query("insert into auth.users(id,email,email_confirmed_at) values($1,'owner@example.invalid',now()),($2,'customer@example.invalid',now())",[owner,customer]);
  await db.query("insert into auth.sessions(id,user_id,aal,not_after) values($1,$2,'aal2',now()+interval '1 hour')",[session,owner]);
  await db.query("insert into public.organizations(id,name,slug,created_by) values($1,'MCPMaster Staging','mcpmaster-staging',$3),($2,'PLP Boracay','plp-boracay',$4)",[platform,client,owner,customer]);
  await db.query("insert into public.memberships(organization_id,user_id,role,status,joined_at) values($1,$3,'owner','active',now()),($2,$4,'owner','active',now())",[platform,client,owner,customer]);
  await db.query("insert into public.enterprise_properties(id,organization_id,slug,display_name,source_status,source_observed_at) values('ada9befb-b821-4ae6-86bf-a6d93376815b',$1,'plp-boracay','PLP Boracay','healthy',now())",[client]);
  for (const p of ["../supabase/migrations/20261003065936_pandora_core_owner_system_v1.sql", "fixtures/pandora-core-release-audit-schema.sql", "../supabase/migrations/20261003074407_pandora_core_release_observations_v1.sql", "../supabase/migrations/20261003083738_pandora_chat_request_admission_v1.sql", "fixtures/pandora-owner-decisions-provider-functions.sql", "../supabase/migrations/20261003124340_pandora_core_owner_decision_health_v1.sql"]) await db.exec(read(p));
  // Hosted Supabase's pre-existing default ACL includes this service grant.
  await db.exec("grant execute on function public.pandora_core_snapshot_v1(text,uuid) to service_role");
  beforeMetadata = await metadata();
  assert.equal(beforeMetadata.body_sha256,"54d09f1103c1471ffe5fb963e10916f119b1cde44330917c52811d7264d6d238");
  await db.exec(migration);
  afterMetadata = await metadata();
});
test.after(async () => { if (db) await db.close(); });
test.beforeEach(async () => { await db.exec("reset role;begin"); });
test.afterEach(async () => { await db.exec("rollback;reset role"); });

test("owner sees authoritative task title and exact execution scope and state", async () => {
  const t = await task({key:"opaque-task-046",state:"blocked",attempts:3});
  const [row] = (await snapshot()).automations;
  assert.deepEqual(row, {
    organization_id:platform,project_id:t.project,task_key:t.key,name:t.spec.title,title_state:"recorded",
    client_name:"Pandora",state:"blocked",attempts:3,queued_at:"2026-10-03T12:00:00+00:00",head_sha:t.head,
  });
  await db.exec("reset role");
  const stored = (await db.query("select spec,status,attempts,head_sha from private.pandora_ops_tasks where organization_id=$1 and project_id=$2 and task_key=$3",[t.org,t.project,t.key])).rows[0];
  assert.deepEqual(stored,{spec:t.spec,status:t.state,attempts:t.attempts,head_sha:t.head});
});
test("recorded titles are trimmed and capped at 200 characters without changing stored spec", async () => {
  const title = "  " + "Evidence ".repeat(40) + "  ";
  const t = await task({spec:{title}});
  const [row] = (await snapshot()).automations;
  assert.equal(row.name,title.trim().slice(0,200));assert.equal(row.name.length,200);
  await db.exec("reset role");
  assert.equal((await db.query("select spec->>'title' title from private.pandora_ops_tasks where task_key=$1",[t.key])).rows[0].title,title);
});
test("absent, blank, null and nonstring titles remain missing without invented names", async () => {
  for (const spec of [{},{title:"  "},{title:null},{title:42},{title:{name:"Untrusted"}}]) await task({spec});
  const rows = (await snapshot()).automations;
  assert.equal(rows.length,5);
  assert.ok(rows.every(r=>r.name===null && r.title_state==="missing" && typeof r.task_key==="string"));
});
test("customer names use canonical organization identity while only configured platform displays Pandora", async () => {
  await task();await task({org:client});
  const rows=(await snapshot()).automations;
  assert.equal(rows.find(r=>r.organization_id===platform).client_name,"Pandora");
  assert.equal(rows.find(r=>r.organization_id===client).client_name,"PLP Boracay");
  await db.exec("reset role");
  assert.equal((await db.query("select name from public.organizations where id=$1",[platform])).rows[0].name,"MCPMaster Staging");
});
test("scoped projection excludes other organizations while preserving the latest 30 ordering", async () => {
  for(let i=0;i<32;i++)await task({org:client,key:`task-${i}`,queued:new Date(Date.UTC(2026,9,3,12,i)).toISOString()});
  await task({key:"platform-hidden",queued:"2026-10-03T14:00:00Z"});
  const rows=(await snapshot(client)).automations;
  assert.equal(rows.length,30);assert.ok(rows.every(r=>r.organization_id===client));
  assert.deepEqual(rows.map(r=>r.task_key),Array.from({length:30},(_,i)=>`task-${31-i}`));
});
test("explicit client-scoped operator reads only its authorized tenant and cannot request global scope", async () => {
  const staff=randomUUID();
  await db.query("insert into auth.users(id,email,email_confirmed_at) values($1,'staff@example.invalid',now())",[staff]);
  await db.query("insert into public.memberships(organization_id,user_id,role,status,joined_at) values($1,$2,'admin','active',now())",[platform,staff]);
  await db.query("insert into private.pandora_operator_grants(user_id,organization_id,role,granted_by,reason) values($1,$2,'support',$3,'Scoped fixture access')",[staff,client,owner]);
  const other=(await db.query("select organization_id from public.pandora_enterprise_accounts where organization_id<>$1 limit 1",[client])).rows[0].organization_id;
  await task();await task({org:client});await task({org:other});
  const rows=(await snapshot(client,staff)).automations;
  assert.equal(rows.length,1);assert.equal(rows[0].organization_id,client);
  await rejects("select public.pandora_core_snapshot_v1('platform',null)");
  await rejects("select public.pandora_core_snapshot_v1('platform',$1)",[other]);
});
test("ordinary customer owner cannot access the owner automation projection or underlying private tasks", async () => {
  await task({org:client});await actor(customer);
  await rejects("select public.pandora_core_snapshot_v1('platform',$1)",[client]);
  await rejects("select * from private.pandora_ops_tasks");
});
test("revoked explicit owner grant and unauthenticated requests remain denied", async () => {
  await task();await db.query("update private.pandora_operator_grants set state='revoked' where user_id=$1",[owner]);
  await actor();await rejects("select public.pandora_core_snapshot_v1('platform',null)");
  await db.exec("reset role");await db.query("select set_config('request.jwt.claims','{}',false)");
  await db.exec("set role anon");await rejects("select public.pandora_core_snapshot_v1('platform',null)");
});
test("one existing function is replaced without changing ACL, owner, security mode, search path or schema objects", (t) => {
  const {body_sha256:before,...beforeRest}=beforeMetadata;
  const {body_sha256:after,...afterRest}=afterMetadata;
  assert.notEqual(before,after);assert.deepEqual(afterRest,beforeRest);
  assert.equal(afterMetadata.prosecdef,true);assert.equal(afterMetadata.provolatile,"s");
  assert.deepEqual(afterMetadata.proconfig,['search_path=""']);
  assert.equal(afterMetadata.anon_execute,false);assert.equal(afterMetadata.authenticated_execute,true);assert.equal(afterMetadata.service_execute,true);
  t.diagnostic(JSON.stringify({before:beforeMetadata,after:afterMetadata}));
});
test("unexpected source body fails closed before any replacement", async () => {
  // A second application is deliberately not allowed: its predecessor body differs.
  await rejects(migration.replace(/^begin;$/mi,"").replace(/^commit;$/mi,""),[],/CORE_AUTOMATION_SOURCE_DRIFT/);
  assert.deepEqual(await metadata(),afterMetadata);
});
test("existing model, release, admission and owner decision sections are retained", async () => {
  const s=await snapshot();
  assert.deepEqual(s.automations,[]);assert.deepEqual(s.deployments,[]);
  assert.deepEqual(s.models,[]);assert.deepEqual(s.needs_you,[]);
  assert.ok(Object.hasOwn(s,"model_routing"));assert.ok(Object.hasOwn(s,"usage_allowances"));
});
