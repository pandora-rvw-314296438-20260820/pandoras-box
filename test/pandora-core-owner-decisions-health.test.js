"use strict";
const assert=require("node:assert/strict");
const {readFileSync}=require("node:fs");
const {join}=require("node:path");
const {randomUUID,createHash}=require("node:crypto");
const {test}=require("node:test");
const {PGlite}=require("@electric-sql/pglite");
const {pgcrypto}=require("@electric-sql/pglite/contrib/pgcrypto");
const read=(p)=>readFileSync(join(__dirname,p),"utf8");
const migration=read("../supabase/migrations/20261003124340_pandora_core_owner_decision_health_v1.sql");
const owner="a0d6f184-3039-4735-8d11-63ce403636e2";
const customer="f17558e4-e1b2-4b8d-a215-b96775b1a470";
const platform="2270b266-59da-4c39-bfd9-9f8d08352af0";
const client="076a9306-5c4e-4d9d-98d3-e3a6fea968fb";
const session="30000000-0000-4000-8000-000000000001";
const publicProvider="ph.namria.geoportal";
let db,priorAcl;
async function actor(user=owner,role="authenticated"){
 await db.exec("reset role");
 await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:user,role,aal:"aal2",session_id:session,is_anonymous:false})]);
 assert.ok(["authenticated","anon","service_role"].includes(role));await db.exec("set role "+role);
}
async function admin(){await db.exec("reset role");}
async function snapshot(org=null){await actor();return(await db.query("select public.pandora_core_snapshot_v1($1,$2) r",[org?"client":"platform",org])).rows[0].r;}
async function assess(id){await admin();return(await db.query("select private.pandora_connection_assessment_v1($1) r",[id])).rows[0].r;}
async function live(org=platform){await actor();return(await db.query("select public.pandora_live_connections_v1($1) r",[org])).rows[0].r.providers;}
async function reconcile(){await admin();return(await db.query("select private.pandora_connection_reconcile_health_v1() r")).rows[0].r;}
async function rejects(sql,args=[],pattern=/permission|denied|membership/i){
 await db.exec("savepoint rejected");try{await assert.rejects(db.query(sql,args),pattern);}
 finally{await db.exec("rollback to savepoint rejected;release savepoint rejected");}
}
async function connection({provider=publicProvider,org=platform,selected=true,age="1 minute",status="connected",health="healthy",failure=null,publicMetadata=true,rotation=null}={}){
 await admin();const id=randomUUID(),secret=randomUUID(),identity="Governed fixture identity "+id;
 const publicMode=provider===publicProvider;
 const metadata=publicMetadata?{connectionMode:"public_safe_read",credentialMode:"none",httpStatus:200,bodySha256:"b".repeat(64),providerIdentity:identity}:{verifiedBy:"provider_readback",probe:"fixture.read",identityVerified:true};
 await db.query("insert into vault.secrets(id) values($1)",[secret]);
 await db.query(`insert into private.pandora_connection_accounts_v1(id,organization_id,provider_key,manifest_version,connected_by,account_subject_hash,account_label,tenant_key,credential_secret_id,granted_scopes,granted_capabilities,status,health_state,last_verified_at,rotation_due_at,failure_code,provider_readback_hash,metadata_redacted)
 values($1,$2,$3,'1.0.0',$4,$5,'Fixture account',$2::uuid::text,$6,array['fixture.read'],array['fixture.read'],$7,$8,now()-$9::interval,$10,$11,$12,$13)`,
 [id,org,provider,owner,createHash("sha256").update(provider+":"+identity).digest("hex"),secret,status,health,age,rotation,failure,"a".repeat(64),metadata]);
 if(selected)await db.query("insert into private.pandora_connection_active_accounts_v1(organization_id,provider_key,connection_id,tenant_key,selected_by) values($1,$2,$3,$1::uuid::text,$4) on conflict(organization_id,provider_key) do update set connection_id=excluded.connection_id",[org,provider,id,owner]);
 return id;
}
async function gate({org=platform,project=randomUUID(),key="FB-046",status="queued",cancel=false,state="blocked",decided=false}={}){
 await admin();await db.query("insert into private.pandora_ops_tasks(organization_id,project_id,task_key,spec,spec_digest,status,cancel_requested) values($1,$2,$3,$4,$5,$6,$7)",[org,project,key,{title:"Review actual scoped pilot",risk:"production"},"d".repeat(64),status,cancel]);
 await db.query("insert into private.pandora_ops_human_gates(organization_id,project_id,task_key,gate_kind,state,evidence_ref,updated_at,decided_at) values($1,$2,$3,'spend_authorization',$4,'fixture:gate',now()-interval '30 days',case when $5 then now() else null end)",[org,project,key,state,decided]);
 return {org,project,key};
}
async function model(id,{conversational=true,present=true,routable=true,result="passed",age="1 hour",target="PRIVATE_INVOCATION_TARGET",lifecycle="ACTIVE"}={}){
 await admin();await db.query("insert into private.pandora_bedrock_reasoning_catalog(model_id,model_name,provider_name,invocation_target,input_modalities,observed_at,runtime_tested_at,region,runtime_verification_status,lifecycle_status,routable,conversational,present_in_latest_sync,runtime_reason) values($1,$2,'Fixture Model Provider',$3,array['TEXT'],now(),now()-$4::interval,'fixture-region',$5,$6,$7,$8,$9,'RAW_PROVIDER_ERROR_MUST_NOT_RENDER')",[id,"Model "+id,target,age,result,lifecycle,routable,conversational,present]);
}
async function acl(){return(await db.query(`select p.oid::regprocedure::text signature,p.prosecdef,p.proconfig,
 has_function_privilege('anon',p.oid,'execute') anon,has_function_privilege('authenticated',p.oid,'execute') authenticated,has_function_privilege('service_role',p.oid,'execute') service
 from pg_proc p where p.oid in('private.pandora_core_connections_v1(uuid)'::regprocedure,'private.pandora_connection_reconcile_health_v1()'::regprocedure,'public.pandora_live_connections_v1(uuid)'::regprocedure,'public.pandora_core_snapshot_v1(text,uuid)'::regprocedure,'private.pandora_core_usage_v1(uuid)'::regprocedure,'public.pandora_bedrock_chat_routing_config_v1()'::regprocedure) order by signature`)).rows;}
test.before(async()=>{
 db=new PGlite({extensions:{pgcrypto}});
 for(const p of ["fixtures/pandora-core-owner-schema.sql","fixtures/pandora-core-composer-provider-schema.sql","fixtures/pandora-chat-request-admission-schema.sql"])await db.exec(read(p));
 await db.query("insert into auth.users(id,email,email_confirmed_at) values($1,'owner@example.invalid',now()),($2,'customer@example.invalid',now())",[owner,customer]);
 await db.query("insert into auth.sessions(id,user_id,aal,not_after) values($1,$2,'aal2',now()+interval '1 hour')",[session,owner]);
 await db.query("insert into public.organizations(id,name,slug,created_by) values($1,'MCPMaster Staging','mcpmaster-staging',$3),($2,'PLP Boracay','plp-boracay',$4)",[platform,client,owner,customer]);
 await db.query("insert into public.memberships(organization_id,user_id,role,status,joined_at) values($1,$3,'owner','active',now()),($2,$4,'owner','active',now())",[platform,client,owner,customer]);
 await db.query("insert into public.enterprise_properties(id,organization_id,slug,display_name,source_status,source_observed_at) values('ada9befb-b821-4ae6-86bf-a6d93376815b',$1,'plp-boracay','PLP Boracay','healthy',now())",[client]);
 for(const p of ["../supabase/migrations/20261003065936_pandora_core_owner_system_v1.sql","fixtures/pandora-core-release-audit-schema.sql","../supabase/migrations/20261003074407_pandora_core_release_observations_v1.sql","../supabase/migrations/20261003083738_pandora_chat_request_admission_v1.sql","fixtures/pandora-owner-decisions-provider-functions.sql"])await db.exec(read(p));
 for(const [provider,mode] of [[publicProvider,"none"],["fixture.secure","required"]]){
  await db.query("insert into public.pandora_provider_manifests(provider_key,manifest_version,display_name,lifecycle_state,auth_scheme,regions,data_residency,data_handling,deprecation_policy,runbook_ref,escalation_ref) values($1,'1.0.0',$2,'active','public',array['PH'],array['PH'],'{}','{}','fixture','fixture')",[provider,provider===publicProvider?"NAMRIA Geoportal":"Secure Fixture"]);
  await db.query("insert into private.pandora_connection_manifest_contracts_v1(provider_key,manifest_version,auth,scopes,callback,health,capabilities,risk_class,account_identity,credential_policy,write_authorization,residency_policy) values($1,'1.0.0',$2,$3,'{}',$4,$5,'low','{}',$6,'{}','{}')",[provider,{type:"service_credential",credentialMode:mode},{required:["fixture.read"]},{probe:"fixture.read",maxAgeSeconds:900},[{key:"fixture.read",mode:"read"}],{credentialMode:mode}]);
 }
 priorAcl=await acl();await db.exec(migration);
});
test.after(async()=>{if(db)await db.close();});
test.beforeEach(async()=>{await db.exec("reset role;begin");});
test.afterEach(async()=>{await db.exec("rollback;reset role");});

test("governed credentialless fresh readback accepts null rotation without an owner decision",async()=>{
 const id=await connection();const a=await assess(id);
 assert.equal(a.health,"healthy");assert.equal(a.owner_action_required,false);assert.equal(a.readback_verified,true);
 assert.equal((await reconcile()).reconciled,0);
 assert.equal((await snapshot()).needs_you.length,0);
 const row=(await live()).find(x=>x.provider===publicProvider);
 assert.equal(row.connected,true);assert.equal(row.state,"Connected");assert.equal(row.activeAccount.providerReadbackVerified,true);
});
test("stale credentialless proof stays in Connections and is not a reauthorization demand",async()=>{
 const id=await connection({age:"2 days"});assert.equal((await assess(id)).health,"stale");
 assert.equal((await reconcile()).reconciled,1);
 const s=await snapshot();assert.equal(s.needs_you.length,0);assert.equal(s.connections[0].health,"stale");
 assert.equal(s.connections[0].client_name,"Pandora");assert.equal(s.connections[0].provider_display_name,"NAMRIA Geoportal");
 assert.equal((await live()).find(x=>x.provider===publicProvider).connected,false);
});
test("historical false rotation is reclassified without inventing a new successful receipt",async()=>{
 const id=await connection({age:"2 days",status:"needs_attention",health:"unhealthy",failure:"CREDENTIAL_ROTATION_DUE"});
 await reconcile();await admin();const r=(await db.query("select failure_code,status,last_verified_at from private.pandora_connection_accounts_v1 where id=$1",[id])).rows[0];
 assert.equal(r.failure_code,"PROVIDER_READBACK_STALE");assert.equal(r.status,"needs_attention");
 assert.equal((await snapshot()).needs_you.length,0);assert.equal((await reconcile()).reconciled,0);
});
test("newer partial timeout evidence cannot become healthy or require credential authorization",async()=>{
 const id=await connection();await db.query("insert into public.pandora_connection_verification_observations_v1(organization_id,provider_key,state,observed_at,stale_after,source,missing_reason,evidence_redacted) values($1,$2,'partial',now(),now()+interval '15 minutes','external_public_provider_readback','Control plane timed out','{}')",[platform,publicProvider]);
 assert.equal((await assess(id)).health,"verification_required");await reconcile();
 const s=await snapshot();assert.equal(s.needs_you.length,0);assert.equal(s.connections[0].health,"verification_required");
 assert.equal((await live()).find(x=>x.provider===publicProvider).connected,false);
});
test("credential-required rotation failure remains a real scoped owner decision",async()=>{
 await connection({provider:"fixture.secure",publicMetadata:false});
 const s=await snapshot();assert.equal(s.needs_you.length,1);const d=s.needs_you[0];
 assert.equal(d.kind,"connection");assert.equal(d.state,"needs_decision");assert.equal(d.needs_decision,true);
 assert.equal(d.client_name,"Pandora");assert.match(d.title,/Secure Fixture authorization required/);
 assert.equal((await live()).find(x=>x.provider==="fixture.secure").connected,false);
});
test("untrusted account credentialMode cannot bypass a credential-required manifest",async()=>{
 const id=await connection({provider:"fixture.secure",publicMetadata:true});
 assert.equal((await assess(id)).owner_action_required,true);assert.equal((await assess(id)).public_safe_read,false);
});
test("scope and capability requirements remain exact for credentialless readbacks",async()=>{
 const id=await connection();await db.query("update private.pandora_connection_accounts_v1 set granted_scopes=array['fixture.read','extra.write'] where id=$1",[id]);
 assert.equal((await assess(id)).failure_code,"REQUIRED_SCOPES_MISSING");await reconcile();assert.equal((await snapshot()).needs_you.length,0);
 await admin();await db.query("update private.pandora_connection_accounts_v1 set granted_scopes=array['fixture.read'],granted_capabilities=array[]::text[] where id=$1",[id]);
 assert.equal((await assess(id)).failure_code,"REQUIRED_CAPABILITIES_MISSING");
});
test("malformed public-safe-read identity and missing Vault marker fail closed",async()=>{
 const id=await connection();await db.query("update private.pandora_connection_accounts_v1 set metadata_redacted=jsonb_set(metadata_redacted,'{providerIdentity}','\"different identity\"') where id=$1",[id]);
 assert.equal((await assess(id)).health,"verification_required");
 const id2=await connection({selected:false});await db.query("delete from vault.secrets where id=(select credential_secret_id from private.pandora_connection_accounts_v1 where id=$1)",[id2]);
 assert.equal((await assess(id2)).health,"verification_required");
});
test("unselected and revoked connections are not owner decision requests",async()=>{
 const id=await connection({provider:"fixture.secure",selected:false,publicMetadata:false});assert.equal((await assess(id)).owner_action_required,false);
 await connection({provider:"fixture.secure",publicMetadata:false,status:"revoked"});assert.equal((await snapshot()).needs_you.length,0);
});
test("catalog availability alone creates neither a connection nor a human decision",async()=>{
 const s=await snapshot();assert.deepEqual(s.connections,[]);assert.deepEqual(s.needs_you,[]);
 for(const r of await live()){assert.equal(r.connected,false);assert.equal(r.state,"Not connected");}
});
test("legacy queued gate without a current decision authority stays in Operations, not Needs You",async()=>{
 const g=await gate();assert.deepEqual((await snapshot()).needs_you,[]);
 await admin();const row=(await db.query("select g.state,t.status,t.spec->>'risk' risk from private.pandora_ops_human_gates g join private.pandora_ops_tasks t using(organization_id,project_id,task_key) where g.organization_id=$1 and g.project_id=$2 and g.task_key=$3",[g.org,g.project,g.key])).rows[0];
 assert.deepEqual(row,{state:"blocked",status:"queued",risk:"production"});
});
test("a stopped canonical pilot is not resurrected as authorization demand by an old queued gate",async()=>{
 const g=await gate();const id=randomUUID();
 await db.query("insert into private.pandora_meta_paid_pilot_authorizations(id,organization_id,project_id,state) values($1,$2,$3,'stopped')",[id,g.org,g.project]);
 assert.deepEqual((await snapshot()).needs_you,[]);await admin();
 assert.equal((await db.query("select state from private.pandora_meta_paid_pilot_authorizations where id=$1",[id])).rows[0].state,"stopped");
 assert.equal((await db.query("select state from private.pandora_ops_human_gates where organization_id=$1 and project_id=$2 and task_key=$3",[g.org,g.project,g.key])).rows[0].state,"blocked");
});

test("terminal, cancelled, decided and orphaned legacy gates do not enter the owner queue",async()=>{
 for(const status of ["complete","failed","cancelled"])await gate({status,key:status});
 await gate({cancel:true,key:"cancel-requested"});await gate({decided:true,key:"already-decided"});
 const g=await gate({key:"orphan"});await db.query("delete from private.pandora_ops_tasks where organization_id=$1 and project_id=$2 and task_key=$3",[g.org,g.project,g.key]);
 assert.deepEqual((await snapshot()).needs_you,[]);
});
test("client-scoped snapshots retain customer names and exclude platform decisions",async()=>{
 await connection({provider:"fixture.secure",publicMetadata:false});await gate();
 await connection({provider:"fixture.secure",publicMetadata:false,org:client});
 const s=await snapshot(client);assert.equal(s.connections.length,1);assert.equal(s.connections[0].client_name,"PLP Boracay");
 assert.equal(s.needs_you.length,1);assert.equal(s.needs_you[0].organization_id,client);
});
test("current canonical approvals remain actionable with a decision state, not a verification badge",async()=>{
 const id=randomUUID();await db.query("insert into public.approvals(id,organization_id,run_id,requested_by,assigned_to,decision,action_hash,preview_redacted,request_reason,expires_at) values($1,$2,$3,$4,$4,'pending',$5,'{}','Review a real governed action',now()+interval '1 hour')",[id,platform,randomUUID(),owner,"e".repeat(64)]);
 await gate();const rows=(await snapshot()).needs_you;
 assert.equal(rows.length,1);assert.equal(rows[0].id,id);assert.equal(rows[0].kind,"approval");
 assert.equal(rows[0].state,"needs_decision");assert.equal(rows[0].needs_decision,true);assert.equal(rows[0].action,"open_approvals");assert.equal(rows[0].client_name,"Pandora");
});
test("Models uses actual conversational routing truth, never generic capability metrics",async()=>{
 await model("eligible");await model("failed",{result:"failed",routable:false});await model("not-routable",{routable:false});
 await model("no-target",{target:null});await model("embedding",{conversational:false});await model("removed",{present:false});
 await db.query("insert into public.pandora_provider_capability_metrics(organization_id,provider_key,capability_key,capability_version,window_start,window_end,accepted_count,verified_success_count,observed_at) values($1,'google_sheets','sheets.read','1.0.0',now()-interval '1 day',now(),50,50,now()-interval '3 days')",[platform]);
 const s=await snapshot();assert.deepEqual(s.models.map(x=>x.model_id).sort(),["eligible","failed","no-target","not-routable"]);
 assert.equal(s.model_routing.mode,"Auto");assert.equal(s.model_routing.policy_version,"bedrock-live-catalog-chat-v1");
 assert.equal(s.model_routing.configured_eligible_models,1);assert.equal(s.model_routing.verified_eligible_models,1);assert.equal(s.model_routing.fresh_verified_eligible_models,1);assert.equal(s.model_routing.conversational_models,4);
 assert.equal(s.models.find(x=>x.model_id==="failed").availability_reason,"runtime_verification_failed");
 assert.ok(s.models.find(x=>x.model_id==="failed").runtime_tested_at);assert.equal(s.models.find(x=>x.model_id==="failed").runtime_verified_at,null);
 assert.equal(s.models.find(x=>x.model_id==="not-routable").configured_eligible,false);
 assert.equal(s.models.find(x=>x.model_id==="no-target").availability_reason,"invocation_unavailable");
 assert.ok(s.models.every(x=>x.provider==="bedrock"));assert.doesNotMatch(JSON.stringify(s.models),/PRIVATE_INVOCATION_TARGET|RAW_PROVIDER_ERROR|google_sheets/);
});
test("stale model pass remains dated policy eligibility, never fresh runtime acceptance",async()=>{
 await model("stale",{age:"3 days"});const s=await snapshot();
 assert.equal(s.model_routing.enabled,true);assert.equal(s.model_routing.configured_eligible_models,1);
 assert.equal(s.model_routing.verified_eligible_models,1);assert.equal(s.model_routing.fresh_verified_eligible_models,0);
 assert.equal(s.models[0].verification_state,"passed");assert.equal(s.models[0].runtime_evidence_state,"stale");
 assert.equal(s.model_routing.policy_updated_at,null);assert.ok(s.model_routing.catalog_observed_at);
});
test("unverified or inactive model does not become configured eligible from discovery metadata",async()=>{
 await model("untested",{result:"untested"});await model("inactive",{lifecycle:"LEGACY"});
 const s=await snapshot();assert.equal(s.model_routing.enabled,false);assert.equal(s.model_routing.configured_eligible_models,0);
 assert.ok(s.models.every(x=>!x.configured_eligible));
});
test("platform model catalog never leaks into scoped client or finance-only projection",async()=>{
 await model("private-owner-model");await actor();
 const scoped=(await db.query("select public.pandora_core_snapshot_v1('platform',$1) r",[client])).rows[0].r;
 assert.deepEqual(scoped.models,[]);assert.equal(scoped.model_routing,null);
 await admin();await db.query("update private.pandora_operator_grants set role='finance' where user_id=$1",[owner]);
 const finance=await snapshot();assert.deepEqual(finance.models,[]);assert.equal(finance.model_routing,null);
});
test("platform usage display name changes without changing measured tokens or estimated costs",async()=>{
 await db.query("insert into public.pandora_model_runs(organization_id,request_id,task,request_sha256,provider,model,status,input_tokens,output_tokens,total_tokens,estimated_cost_micros,cost_estimate_status) values($1,'fixture-usage','chat',$2,'fixture-provider','fixture-model','succeeded',10,2,12,125000,'estimated')",[platform,"c".repeat(64)]);
 const s=await snapshot();assert.equal(s.usage.length,1);const u=s.usage[0];
 assert.equal(u.client_name,"Pandora");assert.equal(u.organization_id,platform);assert.equal(u.requests,1);assert.equal(u.tokens,12);assert.equal(u.estimated_cost_micros,125000);assert.equal(u.billed_cost_micros,null);assert.equal(u.coverage,"recorded_model_runs_only");
});
test("ordinary customer cannot read owner queue or invoke private health mutation",async()=>{
 await actor(customer);await rejects("select public.pandora_core_snapshot_v1('home',null)");
 await rejects("select public.pandora_live_connections_v1($1)",[platform]);
 await rejects("select private.pandora_connection_reconcile_health_v1()");
 await rejects("select private.pandora_connection_assessment_v1(null)");
 await rejects("select private.pandora_core_models_v1()");
});
test("existing function ACL/search-path boundaries are preserved and the helper is private",async()=>{
 assert.deepEqual(await acl(),priorAcl);
 const r=(await db.query("select has_function_privilege('anon','private.pandora_connection_assessment_v1(uuid)','execute') anon,has_function_privilege('authenticated','private.pandora_connection_assessment_v1(uuid)','execute') authenticated,has_function_privilege('service_role','private.pandora_connection_assessment_v1(uuid)','execute') service")).rows[0];
 assert.deepEqual(r,{anon:false,authenticated:false,service:false});
});
