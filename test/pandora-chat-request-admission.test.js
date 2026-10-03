"use strict";
const assert=require("node:assert/strict");
const {readFileSync}=require("node:fs");
const {join}=require("node:path");
const {randomUUID}=require("node:crypto");
const {test}=require("node:test");
const {PGlite}=require("@electric-sql/pglite");
const {pgcrypto}=require("@electric-sql/pglite/contrib/pgcrypto");
const read=(p)=>readFileSync(join(__dirname,p),"utf8");
const sql=read("../supabase/migrations/20261003080000_pandora_chat_request_admission_v1.sql");
const owner="a0d6f184-3039-4735-8d11-63ce403636e2";
const customer="f17558e4-e1b2-4b8d-a215-b96775b1a470";
const platform="2270b266-59da-4c39-bfd9-9f8d08352af0";
const client="076a9306-5c4e-4d9d-98d3-e3a6fea968fb";
const session="30000000-0000-4000-8000-000000000001";
let db,entry;
async function actor(user=owner,role="authenticated",aal="aal2"){
 await db.exec("reset role");
 await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:user,role,aal,session_id:session,is_anonymous:false})]);
 assert.ok(["authenticated","anon","service_role"].includes(role));
 await db.exec("set role "+role);
}
async function rejected(query,args=[],pattern=/denied|permission|CONFLICT|IMMUTABLE|RETAINED|INVALID|REQUIRED|UNAVAILABLE|IN_USE/i){
 await db.exec("savepoint reject");
 try{await assert.rejects(db.query(query,args),pattern);}
 finally{await db.exec("rollback to savepoint reject;release savepoint reject");}
}
async function operate(op,org,payload,key=randomUUID()){
 return (await db.query("select public.pandora_core_operate_v1($1,$2,$3,$4) as r",[op,org,payload,key])).rows[0].r;
}
async function plan(limit=2,policy="block"){
 await actor();
 return (await operate("plan.save",null,{code:"fixture-"+randomUUID(),name:"Admission fixture",state:"active",currency:"USD",
  limits:limit===null?{}:{monthly_requests:limit},request_admission_policy:policy})).id;
}
async function subscribe(id,enabled=true,extra={}){
 await actor();return operate("subscription.save",client,{plan_id:id,state:"active",request_admission_enabled:enabled,...extra});
}
async function scope(){
 await actor();return (await db.query("select public.pandora_core_enter_client_v1($1,'Admission fixture verification') as r",[client])).rows[0].r.entry_id;
}
async function turn(org=client,user=owner,{thread=null,job=true,claim=randomUUID(),fingerprint="b".repeat(64)}={}){
 await db.exec("reset role");const tid=thread||randomUUID(),mid=randomUUID(),jid=job?randomUUID():null;
 if(!thread)await db.query("insert into public.pandora_intelligence_threads(id,organization_id,created_by,title) values($1,$2,$3,'Admission fixture')",[tid,org,user]);
 await db.query("insert into public.pandora_intelligence_messages(id,organization_id,thread_id,author_role,content) values($1,$2,$3,'user','Fixture request')",[mid,org,tid]);
 if(job)await db.query("insert into public.pandora_activity_jobs(id,organization_id,requested_by,thread_id,request_id,request_fingerprint,execution_state,execution_claim_id) values($1,$2,$3,$4,$5,$6,'running',$7)",[jid,org,user,tid,randomUUID(),fingerprint,claim]);
 const t={org,tid,mid,jid,claim,fingerprint};
 await actor(user);return t;
}
function metadata(t,extra={}){
 return {intelligence_project_id:null,max_attempts:3,reasoning_tier:"auto",routing_policy_version:"fixture-v1",
  routing_candidates:[],routing_exclusions:[],routing_scores:{},session_stickiness_state:"none",
  requested_selection_mode:"auto",requested_provider:null,requested_model:null,
  requested_fallback_mode:"allow_fallback",requested_reasoning_mode:"auto",
  activity_job_id:t.jid,activity_claim_id:t.jid?t.claim:null,activity_request_fingerprint:t.jid?t.fingerprint:null,...extra};
}
async function admit(t,{sha="a".repeat(64),meta={},entryId=entry}={}){
 return (await db.query("select public.pandora_chat_request_admit_v1($1,$2,$3,$4,$5,$6) as r",
  [t.org,t.tid,t.mid,sha,metadata(t,meta),t.org===platform?null:entryId])).rows[0].r;
}
async function policy(){
 await db.exec("reset role");return (await db.query("select private.pandora_chat_request_policy_v1($1,clock_timestamp()) as r",[client])).rows[0].r;
}
async function snapshot(){await actor();return(await db.query("select public.pandora_core_snapshot_v1('client',$1) as r",[client])).rows[0].r;}
async function legacyInsert(org=client,request="chat-"+randomUUID()){
 return db.query("insert into public.pandora_model_runs(organization_id,request_id,task,request_sha256) values($1,$2,'chat',$3)",[org,request,"c".repeat(64)]);
}
test.before(async()=>{
 db=new PGlite({extensions:{pgcrypto}});
 for(const path of ["fixtures/pandora-core-owner-schema.sql","fixtures/pandora-core-composer-provider-schema.sql",
  "fixtures/pandora-chat-request-admission-schema.sql"])await db.exec(read(path));
 await db.query("insert into auth.users(id,email,email_confirmed_at) values($1,'admission-owner@example.invalid',now()),($2,'admission-client@example.invalid',now())",[owner,customer]);
 await db.query("insert into auth.sessions(id,user_id,aal,not_after) values($1,$2,'aal2',now()+interval '1 hour')",[session,owner]);
 await db.query("insert into public.organizations(id,name,slug,created_by) values($1,'Pandora fixture','mcpmaster-staging',$3),($2,'PLP Boracay','plp-boracay',$4)",[platform,client,owner,customer]);
 await db.query("insert into public.memberships(organization_id,user_id,role,status,joined_at) values($1,$3,'owner','active',now()),($2,$3,'owner','active',now()),($2,$4,'owner','active',now())",[platform,client,owner,customer]);
 await db.query("insert into public.enterprise_properties(id,organization_id,slug,display_name,source_status,source_observed_at) values('ada9befb-b821-4ae6-86bf-a6d93376815b',$1,'plp-boracay','PLP Boracay','healthy',now())",[client]);
 for(const [name,script] of [
  ["Core",read("../supabase/migrations/20261003044349_pandora_core_owner_system_v1.sql")],
  ["audit",read("fixtures/pandora-core-release-audit-schema.sql")],
  ["release",read("../supabase/migrations/20261003073000_pandora_core_release_observations_v1.sql")],
  ["admission",sql]])try{await db.exec(script);}catch(error){throw new Error(name+" SQL: "+error.message);}
});
test.after(async()=>{if(db)await db.close();});
test.beforeEach(async()=>{await db.exec("reset role;begin");entry=await scope();});
test.afterEach(async()=>{await db.exec("rollback;reset role");});

test("explicit enrollment starts once and defaults preserve unmanaged customers",async()=>{
 const t=await turn();const r=await admit(t);
 assert.equal(r.admitted,true);assert.equal(r.admission_enforced,false);assert.equal(r.requests_used,null);
 const before=await policy();assert.equal(before.request_admission_state,"not_enrolled");
 const id=await plan();await subscribe(id);
 const p=await policy();assert.equal(p.request_admission_state,"enforcing");assert.equal(p.requests_admitted,0);
 assert.ok(p.request_admission_started_at);assert.equal(p.requests_remaining,2);
});

test("monthly allowance admits exactly the limit and durably denies the next request",async()=>{
 await subscribe(await plan(2));
 for(let i=1;i<=2;i++){const r=await admit(await turn());assert.equal(r.admitted,true);assert.equal(r.requests_used,i);}
 const denied=await admit(await turn());assert.equal(denied.admitted,false);assert.equal(denied.code,"CHAT_REQUEST_LIMIT_REACHED");
 await db.exec("reset role");
 assert.equal((await db.query("select count(*)::int as n from public.pandora_model_runs")).rows[0].n,2);
 assert.equal((await db.query("select count(*)::int as n from public.audit_events where event_type='core.chat_request_admission.denied'")).rows[0].n,1);
 const p=await policy();assert.equal(p.requests_remaining,0);assert.equal(p.request_admission_state,"limit_reached");
});

test("stable activity replay with a new user-message row never reserves or dispatches twice",async()=>{
 await subscribe(await plan(1));
 const t=await turn();const first=await admit(t);
 await db.exec("reset role");
 const newMessage=randomUUID();
 await db.query("insert into public.pandora_intelligence_messages(id,organization_id,thread_id,author_role,content) values($1,$2,$3,'user','Fixture retry')",[newMessage,client,t.tid]);
 await actor();const again=await admit({...t,mid:newMessage});
 assert.equal(again.replay,true);assert.equal(again.id,first.id);assert.equal(again.fallback_chain_id,first.id);
 assert.equal((await policy()).requests_admitted,1);
});

test("changed request hash or activity fingerprint cannot reuse an admitted identity",async()=>{
 await subscribe(await plan());const t=await turn();await admit(t);
 await rejected("select public.pandora_chat_request_admit_v1($1,$2,$3,$4,$5,$6)",[client,t.tid,t.mid,"d".repeat(64),metadata(t),entry]);
 await rejected("select public.pandora_chat_request_admit_v1($1,$2,$3,$4,$5,$6)",[client,t.tid,t.mid,"a".repeat(64),metadata(t,{activity_request_fingerprint:"e".repeat(64)}),entry]);
});

test("failed provider completion remains one consumed turn, with fallback attempts uncharged separately",async()=>{
 await subscribe(await plan(1));const t=await turn();const r=await admit(t);
 await actor(null,"service_role");
 await db.query("update public.pandora_model_runs set status='failed',error_code='timeout',attempt=3 where id=$1",[r.id]);
 await actor();const replay=await admit(t);assert.equal(replay.replay,true);
 assert.equal((await policy()).requests_admitted,1);
});

test("enabled policy requires stable owned activity identity; unmanaged raw requests remain compatible",async()=>{
 const raw=await turn(client,owner,{job:false});const allowed=await admit(raw);assert.equal(allowed.admitted,true);
 await subscribe(await plan());const missing=await turn(client,owner,{job:false});const denied=await admit(missing);
 assert.equal(denied.code,"CHAT_REQUEST_IDEMPOTENCY_REQUIRED");assert.equal(denied.admitted,false);
 assert.equal((await policy()).requests_admitted,0);
});

test("enabled invalid, expired and missing active policy states fail closed without creating runs",async()=>{
 const id=await plan();await subscribe(id);
 for(const update of [
  "update public.pandora_customer_subscriptions set state='past_due'",
  "update public.pandora_customer_subscriptions set state='active',ends_on=current_date-1",
  "update public.pandora_customer_subscriptions set ends_on=null;update public.pandora_service_plans set request_admission_policy='record_only'",
  "update public.pandora_service_plans set request_admission_policy='block',limits='{}'"]){
  await db.exec("reset role");await db.exec(update);
  const r=await admit(await turn());assert.equal(r.admitted,false);assert.equal(r.code,"CHAT_REQUEST_POLICY_UNAVAILABLE");
 }
 assert.equal((await policy()).requests_admitted,0);
});

test("disable, off-period use, reenable and plan switch preserve prior protected consumption",async()=>{
 const id=await plan(2);await subscribe(id);await admit(await turn());
 const first=(await policy()).request_admission_started_at;
 await subscribe(id,false);const off=await admit(await turn());assert.equal(off.admission_enforced,false);
 await subscribe(id,true);
 let p=await policy();assert.equal(p.request_admission_started_at,first);assert.equal(p.requests_admitted,1);
 const second=await plan(3);await subscribe(second,true);
 p=await policy();assert.equal(p.request_admission_started_at,first);assert.equal(p.requests_admitted,1);assert.equal(p.requests_remaining,2);
});

test("enrollment cannot silently switch to record-only; plan edits cannot weaken enabled subscriptions",async()=>{
 const id=await plan();await subscribe(id);
 const recordOnly=await plan(null,"record_only");await actor();
 await rejected("select public.pandora_core_operate_v1('subscription.save',$1,$2,$3)",[client,{plan_id:recordOnly,state:"active"},randomUUID()]);
 await rejected("select public.pandora_core_operate_v1('plan.save',null,$1,$2)",[{id,code:"disabled-policy",name:"Invalid weakening",state:"active",currency:"USD",request_admission_policy:"record_only"},randomUUID()]);
});

test("current period reservations cannot be deleted or relabeled during a temporary disable",async()=>{
 const id=await plan();await subscribe(id);const r=await admit(await turn());await subscribe(id,false);
 await actor(null,"service_role");
 await rejected("delete from public.pandora_model_runs where id=$1",[r.id]);
 for(const field of ["request_admission_enforced=false","actor_user_id=null","request_admitted_at=now()-interval '32 days'","request_admission_window_start=now()-interval '32 days'","intelligence_project_id=gen_random_uuid()"]){
  await rejected("update public.pandora_model_runs set "+field+" where id=$1",[r.id]);
 }
 await db.query("update public.pandora_model_runs set status='succeeded',provider='gemini',model='fixture',input_tokens=10,output_tokens=5,total_tokens=15 where id=$1",[r.id]);
 await subscribe(id,true);assert.equal((await policy()).requests_admitted,1);
});

test("old service runtime insertion is blocked only for an explicitly enrolled chat path",async()=>{
 await actor(null,"service_role");await legacyInsert();
 await subscribe(await plan());
 await actor(null,"service_role");
 await rejected("insert into public.pandora_model_runs(organization_id,request_id,task,request_sha256) values($1,$2,'chat',$3)",[client,"chat-"+randomUUID(),"f".repeat(64)]);
 // Existing diagnostic probes are not charged as user chat requests.
 await legacyInsert(client,"provider-probe-fixture-"+randomUUID());
 await legacyInsert(platform);
});

test("forged service admission fields do not substitute for the real caller JWT",async()=>{
 await subscribe(await plan());const t=await turn();
 await actor(null,"service_role");
 await rejected("insert into public.pandora_model_runs(organization_id,request_id,task,request_sha256,actor_user_id,request_admitted_at,request_admission_enforced,request_admission_plan_id,request_admission_window_start,admission_activity_job_id,admission_activity_fingerprint) select $1,$2,'chat',$3,$4,clock_timestamp(),true,plan_id,date_trunc('month',now()),$5,$6 from public.pandora_customer_subscriptions where organization_id=$1",
  [client,"chat-activity-"+t.jid,"a".repeat(64),owner,t.jid,t.fingerprint]);
});

test("customer, anonymous and service-only contexts cannot call the paid owner route",async()=>{
 for(const [user,role] of [[customer,"authenticated"],[null,"anon"],[null,"service_role"]]){
  const t=await turn(client,customer);await actor(user,role);
  await rejected("select public.pandora_chat_request_admit_v1($1,$2,$3,$4,$5,null)",[client,t.tid,t.mid,"a".repeat(64),metadata(t)]);
 }
});

test("foreign thread, message, project metadata, job and claim are rejected before reservation",async()=>{
 await subscribe(await plan());const t=await turn();const foreign=await turn(platform);
 await actor();
 for(const args of [
  [platform,t.tid,t.mid,"a".repeat(64),metadata(t),null],
  [client,t.tid,foreign.mid,"a".repeat(64),metadata(t),entry],
  [client,t.tid,t.mid,"a".repeat(64),metadata(t,{intelligence_project_id:randomUUID()}),entry],
  [client,t.tid,t.mid,"a".repeat(64),metadata(t,{activity_job_id:foreign.jid,activity_claim_id:foreign.claim,activity_request_fingerprint:foreign.fingerprint}),entry],
  [client,t.tid,t.mid,"a".repeat(64),metadata(t,{activity_claim_id:randomUUID()}),entry],
 ])await rejected("select public.pandora_chat_request_admit_v1($1,$2,$3,$4,$5,$6)",args);
 assert.equal((await policy()).requests_admitted,0);
});

test("revoked tenant entry and authority deny before an existing reservation replay",async()=>{
 await subscribe(await plan());const t=await turn();await admit(t);
 await db.exec("reset role;update private.pandora_client_entry_sessions set ended_at=now()");
 await actor();
 await rejected("select public.pandora_chat_request_admit_v1($1,$2,$3,$4,$5,$6)",[client,t.tid,t.mid,"a".repeat(64),metadata(t),entry]);
});

test("one derived Needs You exception resolves with a genuine governed allowance change",async()=>{
 const id=await plan(0);await subscribe(id);
 let s=await snapshot();const attention=s.needs_you.filter(x=>x.kind==="request_allowance");
 assert.equal(attention.length,1);assert.equal(attention[0].organization_id,client);assert.equal(attention[0].action,"open_client_commercial");
 assert.equal(s.usage_allowances[0].request_admission_state,"limit_reached");
 await admit(await turn());await admit(await turn());
 s=await snapshot();assert.equal(s.needs_you.filter(x=>x.kind==="request_allowance").length,1);
 await subscribe(await plan(2));
 s=await snapshot();assert.equal(s.needs_you.filter(x=>x.kind==="request_allowance").length,0);
 assert.equal(s.usage_allowances[0].requests_remaining,2);
});

test("UTC period resets counts without resetting immutable first enrollment",async()=>{
 await subscribe(await plan(1));await admit(await turn());
 await db.exec("reset role");
 const p=(await db.query("select private.pandora_chat_request_policy_v1($1,(date_trunc('month',clock_timestamp() at time zone 'UTC')+interval '1 month') at time zone 'UTC') as r",[client])).rows[0].r;
 assert.equal(p.requests_admitted,0);assert.equal(p.requests_remaining,1);
 assert.ok(Date.parse(p.request_admission_started_at)<Date.parse(p.request_window_start));
});

test("commercial writes still require live AAL2 and reject forged initial enrollment timestamps",async()=>{
 const id=await plan();await actor(owner,"authenticated","aal1");
 await rejected("select public.pandora_core_operate_v1('subscription.save',$1,$2,$3)",[client,{plan_id:id,state:"active",request_admission_enabled:true},randomUUID()]);
 await actor();
 await rejected("select public.pandora_core_operate_v1('subscription.save',$1,$2,$3)",[client,{plan_id:id,state:"active",request_admission_enabled:true,request_admission_started_at:"2000-01-01"},randomUUID()]);
 await subscribe(id);await db.exec("reset role");
 await rejected("update public.pandora_customer_subscriptions set request_admission_started_at=clock_timestamp()-interval '1 day' where organization_id=$1",[client]);
});

test("client model-run DML remains closed and structural lock ordering precedes policy/count/insert",async()=>{
 await actor();
 await rejected("insert into public.pandora_model_runs(organization_id,request_id,task,request_sha256) values($1,'forged','chat',$2)",[client,"a".repeat(64)]);
 await rejected("update public.pandora_model_runs set request_admission_enforced=false");
 await rejected("delete from public.pandora_model_runs");
 await db.exec("reset role");
 const body=(await db.query("select prosrc from pg_proc where oid='public.pandora_chat_request_admit_v1(uuid,uuid,uuid,text,jsonb,uuid)'::regprocedure")).rows[0].prosrc;
 assert.ok(body.indexOf("pg_advisory_xact_lock")<body.indexOf("v_policy:=private.pandora_chat_request_policy_v1"));
 assert.ok(body.indexOf("v_policy:=private.pandora_chat_request_policy_v1")<body.indexOf("insert into public.pandora_model_runs"));
 const volatility=(await db.query("select provolatile from pg_proc where oid='private.pandora_chat_request_policy_v1(uuid,timestamptz)'::regprocedure")).rows[0].provolatile;
 assert.equal(volatility,"v");
});

test("legacy no-job admission uses a separate bounded server rate bucket and replay does not debit it",async()=>{
 const t=await turn(client,owner,{job:false});const first=await admit(t);
 assert.equal(first.admitted,true);
 await db.exec("reset role");
 const before=(await db.query("select sum(request_count)::int as n from public.runtime_rate_limit_buckets")).rows[0].n;
 await actor();assert.equal((await admit(t)).replay,true);
 await db.exec("reset role");
 assert.equal((await db.query("select sum(request_count)::int as n from public.runtime_rate_limit_buckets")).rows[0].n,before);
 // Fill neighboring minute buckets too so the assertion is not wall-clock-boundary flaky.
 await db.query("insert into public.runtime_rate_limit_buckets(organization_id,key_hash,window_started_at,request_count) select $1,encode(extensions.digest($2,'sha256'),'hex'),to_timestamp(floor(extract(epoch from clock_timestamp())/60)*60)+n*interval '1 minute',30 from generate_series(-1,1) n on conflict(organization_id,key_hash,window_started_at) do update set request_count=30",[client,owner+":pandora-chat-admission-legacy"]);
 const denied=await admit(await turn(client,owner,{job:false}));
 assert.equal(denied.admitted,false);assert.equal(denied.code,"CHAT_REQUEST_RATE_LIMITED");
 await db.exec("reset role");
 assert.equal((await db.query("select count(*)::int as n from public.pandora_model_runs")).rows[0].n,1);
});

test("onboarding distinguishes a recorded commercial allowance from active request protection",async()=>{
 const id=await plan();await subscribe(id,false);await actor();
 await operate("onboarding.verify",client,{});
 let s=await snapshot();let limits=s.onboarding.find(x=>x.key==="limits");
 assert.notEqual(limits.state,"verified");assert.match(limits.reason,/Enable.*request protection/);
 await subscribe(id,true);await actor();await operate("onboarding.verify",client,{});
 s=await snapshot();limits=s.onboarding.find(x=>x.key==="limits");
 assert.equal(limits.state,"verified");assert.match(limits.reason,/protection is enabled/);
 const recorded=await plan(10,"record_only");await subscribe(recorded,false);await actor();await operate("onboarding.verify",client,{});
 s=await snapshot();limits=s.onboarding.find(x=>x.key==="limits");
 assert.equal(limits.state,"verified");assert.match(limits.reason,/protection is not enabled/);
});
