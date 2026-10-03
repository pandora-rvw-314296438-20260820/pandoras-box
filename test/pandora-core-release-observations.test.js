"use strict";

const assert=require("node:assert/strict");
const {readFileSync}=require("node:fs");
const {join}=require("node:path");
const {test}=require("node:test");
const {PGlite}=require("@electric-sql/pglite");
const {pgcrypto}=require("@electric-sql/pglite/contrib/pgcrypto");
const read=(path)=>readFileSync(join(__dirname,path),"utf8");
const foundation=read("fixtures/pandora-core-owner-schema.sql");
const composer=read("fixtures/pandora-core-composer-provider-schema.sql");
const audit=read("fixtures/pandora-core-release-audit-schema.sql");
const core=read("../supabase/migrations/20261003065936_pandora_core_owner_system_v1.sql");
const release=read("../supabase/migrations/20261003074407_pandora_core_release_observations_v1.sql");
const platform="2270b266-59da-4c39-bfd9-9f8d08352af0";
const client="076a9306-5c4e-4d9d-98d3-e3a6fea968fb";
const owner="a0d6f184-3039-4735-8d11-63ce403636e2";
const customer="f17558e4-e1b2-4b8d-a215-b96775b1a470";
const session="30000000-0000-4000-8000-000000000001";
let db;
let now;
const copy=(value)=>JSON.parse(JSON.stringify(value));
function payload(kind="candidate",overrides={}) {
 const sha=kind==="candidate"?"a".repeat(40):"b".repeat(40);
 return {schema_version:1,observation_kind:kind,
  repository:"pandora-rvw-314296438-20260820/pandoras-box",
  observed_at:new Date(now-60000).toISOString(),
  source:{sha,tree_sha:"c".repeat(40)},
  vercel:{team_id:"team_3yw1CN59ce4pj5SwyQGCAqN3",project_id:"prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk",
   deployment_id:kind==="candidate"?"dpl_CandidateFixture000001":"dpl_ProductionFixture00001",
   url:"https://mcpmaster-fixture-mbanatao.vercel.app",state:"READY",
   environment:kind==="candidate"?"preview":"production",source_sha:sha,
   canonical_alias:kind==="candidate"?null:"mcpmaster.vercel.app"},
  supabase:{project_ref:"jcyqixttuebxqqfkjonq",migration_version:"20261003065936",
   migration_name:"pandora_core_owner_system_v1",source_file_version:"20261003044349",
   source_sha256:"d".repeat(64),statements_sha256:"d".repeat(64)},
  edge_functions:[{slug:"pandora-intelligence-chat",version:82,source_sha:"e".repeat(40),
   source_sha256:"f".repeat(64),observed_at:new Date(now-120000).toISOString()}],
  verification:{runtime_verified:false,owner_flow_verified:false,client_flow_verified:false,production_verified:false},
  ...overrides};
}
async function actor(user=owner,role="authenticated"){
 await db.exec("reset role");
 await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:user,role,aal:"aal2",session_id:session,is_anonymous:false})]);
 assert.ok(["authenticated","anon","service_role"].includes(role));
 await db.exec("set role "+role);
}
async function record(p=payload(),{org=platform,type="system",actorId=null,event="core.release_observed"}={}){
 await actor(null,"service_role");
 return (await db.query("select public.record_audit_event($1,$2,$3,$4::jsonb,null,null,$5) as id",
  [org,event,type,JSON.stringify(p),actorId])).rows[0].id;
}
async function snapshot(org=null){
 return (await db.query("select public.pandora_core_snapshot_v1($1,$2) as data",
  [org?"client":"platform",org])).rows[0].data;
}
async function rejects(sql,params=[],pattern=/permission|denied|immutable/i){
 await db.exec("savepoint expected_rejection");
 try {await assert.rejects(db.query(sql,params),pattern);}
 finally {await db.exec("rollback to savepoint expected_rejection; release savepoint expected_rejection");}
}
test.before(async()=>{
 db=new PGlite({extensions:{pgcrypto}});
 await db.exec(foundation);await db.exec(composer);
 now=Date.parse((await db.query("select now() as now")).rows[0].now);
 await db.query("insert into auth.users(id,email,email_confirmed_at) values($1,'release-owner@example.invalid',now()),($2,'release-customer@example.invalid',now())",[owner,customer]);
 await db.query("insert into auth.sessions(id,user_id,aal,not_after) values($1,$2,'aal2',now()+interval '1 hour')",[session,owner]);
 await db.query("insert into public.organizations(id,name,slug,created_by) values($1,'Pandora platform fixture','mcpmaster-staging',$3),($2,'PLP Boracay','plp-boracay',$4)",[platform,client,owner,customer]);
 await db.query("insert into public.memberships(organization_id,user_id,role,status,joined_at) values($1,$3,'owner','active',now()),($2,$4,'owner','active',now())",[platform,client,owner,customer]);
 await db.query("insert into public.enterprise_properties(id,organization_id,slug,display_name,source_status,source_observed_at) values('ada9befb-b821-4ae6-86bf-a6d93376815b',$1,'plp-boracay','PLP Boracay','healthy',now())",[client]);
 for(const [name,sql] of [["Core",core],["audit fixture",audit],["release",release]]) {
  try{await db.exec(sql);}catch(error){throw new Error(name+" SQL failed: "+error.message);}
 }
});
test.after(async()=>{if(db)await db.close();});
test.beforeEach(async()=>{await db.exec("reset role;begin");});
test.afterEach(async()=>{await db.exec("rollback;reset role");});

test("release projection has no legacy project dependency and truthful empty state",async()=>{
 const body=(await db.query("select prosrc from pg_proc where oid='public.pandora_core_snapshot_v1(text,uuid)'::regprocedure")).rows[0].prosrc;
 assert.doesNotMatch(body,/pandora_project_deployments|projectos_projects/);
 await db.exec("drop table public.pandora_project_deployments");
 await actor();
 assert.deepEqual((await snapshot()).deployments,[]);
});

test("service-captured candidate and canonical production remain separate with exact provider proof",async()=>{
 const candidate=await record();
 const production=await record(payload("canonical_production"));
 await actor();
 const rows=(await snapshot()).deployments;
 assert.equal(rows.length,2);
 assert.deepEqual(rows.map(r=>r.title),["Canonical production","Latest candidate"]);
 assert.deepEqual(rows.map(r=>String(r.audit_receipt_id)),[String(production),String(candidate)]);
 assert.deepEqual(rows.map(r=>r.source_sha),["b".repeat(40),"a".repeat(40)]);
 for(const row of rows){
  assert.equal(row.status,"READY");
  assert.equal(row.evidence_state,"deployment_ready");
  assert.equal(row.verification_state,"runtime_not_verified");
  for(const flag of ["runtime_verified","owner_flow_verified","client_flow_verified","production_verified"])assert.equal(row[flag],false);
  assert.equal(row.supabase_migration_version,"20261003065936");
  assert.equal(row.supabase_source_file_version,"20261003044349");
  assert.equal(row.supabase_source_sha256,row.supabase_statements_sha256);
  assert.equal(row.edge_functions[0].version,82);
  assert.equal(row.edge_functions[0].slug,"pandora-intelligence-chat");
  assert.match(row.evidence_ref,/^audit:[0-9]+:[0-9a-f]{64}$/);
 }
 await db.exec("reset role");
 const links=(await db.query("select run_id,step_id,project_id from public.audit_events where event_type='core.release_observed'")).rows;
 assert.ok(links.every(r=>r.run_id===null&&r.step_id===null&&r.project_id===null));
});

test("latest qualified provider observation wins and malformed later records cannot hide it",async()=>{
 const older=payload();older.observed_at=new Date(now-900000).toISOString();
 await record(older);
 const newest=await record(payload());
 const malformed=payload();malformed.source.sha="9".repeat(40);
 await record(malformed);
 // A delayed older observation must not replace more recent provider truth.
 await record(older);
 await actor();
 const rows=(await snapshot()).deployments;
 assert.equal(rows.length,1);assert.equal(String(rows[0].audit_receipt_id),String(newest));
});

test("schema, canonical identifiers, source equality, origin links and verification flags are fail-closed",async()=>{
 const mutations=[
  p=>{p.schema_version="1";},p=>{p.repository="lookalike/pandoras-box";},
  p=>{p.secret="must never be projected";},p=>{delete p.verification;},
  p=>{p.verification.runtime_verified=true;},p=>{p.vercel.project_id="prj_wrong";},
  p=>{p.vercel.team_id="team_wrong";},p=>{p.vercel.url="https://example.invalid";},
  p=>{p.vercel.source_sha="0".repeat(40);},p=>{p.supabase.project_ref="wrong";},
  p=>{p.supabase.statements_sha256="0".repeat(64);},
  p=>{p.supabase.extra="ignored is unsafe";},p=>{p.edge_functions[0].version="82";},
  p=>{p.edge_functions[0].slug="pandora-chat";},
  p=>{p.edge_functions.push(copy(p.edge_functions[0]));},
  p=>{p.edge_functions[0].authorization="must never be projected";},
  p=>{p.observed_at="not-a-timestamp";},
  p=>{p.observed_at=new Date(now+3600000).toISOString();},
  p=>{p.edge_functions[0].observed_at=new Date(now+3600000).toISOString();},
  p=>{p.vercel.canonical_alias="mcpmaster.vercel.app";},
  p=>{p.observation_kind="canonical_production";p.vercel.canonical_alias="mcpmaster.vercel.app";p.vercel.state="ERROR";},
 ];
 for(const mutate of mutations){
  const p=payload();mutate(p);
  const valid=(await db.query("select private.pandora_core_release_payload_valid_v1($1::jsonb,now()) as valid",[JSON.stringify(p)])).rows[0].valid;
  assert.equal(valid,false,JSON.stringify(p));
  await record(p);await db.exec("reset role");
 }
 await actor();
 assert.deepEqual((await snapshot()).deployments,[]);
});

test("human, foreign organization, unrelated event and linked execution records do not project",async()=>{
 await record(payload(),{type:"human",actorId:owner});
 await record(payload(),{org:client});
 await record(payload(),{event:"unrelated.observation"});
 const id=await record();
 await db.exec("reset role; alter table public.audit_events disable trigger audit_events_prevent_update");
 await db.query("update public.audit_events set project_id='10000000-0000-4000-8000-000000000001' where id=$1",[id]);
 await db.exec("alter table public.audit_events enable trigger audit_events_prevent_update");
 await actor();
 assert.deepEqual((await snapshot()).deployments,[]);
});

test("customer and revoked owner cannot read platform facts, client projection never inherits platform evidence",async()=>{
 await record();
 await actor();
 assert.deepEqual((await snapshot(client)).deployments,[]);
 await actor(customer);
 await rejects("select public.pandora_core_snapshot_v1('platform',null)");
 await db.exec("reset role;update private.pandora_operator_grants set state='revoked'");
 await actor();
 await rejects("select public.pandora_core_snapshot_v1('platform',null)");
});

test("authenticated and anonymous callers cannot mint reserved system observations",async()=>{
 for(const role of ["authenticated","anon"]){
  await actor(owner,role);
  await rejects("select public.record_audit_event($1,'core.release_observed','system',$2::jsonb)",[platform,JSON.stringify(payload())]);
  await rejects("select private.append_audit_event($1,null,null,'system',null,'core.release_observed',$2::jsonb)",[platform,JSON.stringify(payload())]);
  await rejects("insert into public.audit_events(organization_id,actor_type,event_type,payload_redacted,event_hash) values($1,'system','core.release_observed',$2::jsonb,repeat('0',64))",[platform,JSON.stringify(payload())]);
 }
});

test("existing audit receipts remain immutable and qualified observations show stale evidence",async()=>{
 const p=payload();p.observed_at=new Date(now-2*86400000).toISOString();
 p.edge_functions[0].observed_at=p.observed_at;
 const id=await record(p);
 await db.exec("reset role");
 await rejects("update public.audit_events set payload_redacted='{}' where id=$1",[id]);
 await rejects("delete from public.audit_events where id=$1",[id]);
 await actor();
 assert.equal((await snapshot()).deployments[0].evidence_state,"stale");
});

test("source guard refuses a drifted Core implementation before replacing the projection",async()=>{
 await db.exec("alter function private.pandora_core_release_payload_valid_v1(jsonb,timestamptz) rename to release_validator_saved");
 await db.exec("alter function private.pandora_core_release_observations_v1(uuid) rename to release_projection_saved");
 await db.exec("drop index public.audit_events_core_release_observed_idx");
 const patch=release.slice(release.indexOf("do $patch$"),release.indexOf("comment on function"));
 await rejects(patch,[],/CORE_SNAPSHOT_SOURCE_DRIFT/);
});
