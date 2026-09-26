"use strict";
const test=require("node:test"),assert=require("node:assert/strict"),{randomUUID}=require("node:crypto"),fs=require("node:fs"),path=require("node:path");
const {PGlite}=require("@electric-sql/pglite");
const root=path.join(__dirname,"..");
const base=fs.readFileSync(path.join(root,"supabase/migrations/20260925101319_pandora_operations_room_runtime_v1.sql"),"utf8");
const toggle=fs.readFileSync(path.join(root,"supabase/migrations/20260926070600_operations_allow_production_v1.sql"),"utf8");

async function rpc(db,name,args){
 const keys=Object.keys(args),vals=Object.values(args).map(v=>typeof v==="object"&&v!==null&&!Array.isArray(v)?JSON.stringify(v):v);
 const q="select public."+name+"("+keys.map((k,i)=>k+"=>$"+(i+1)).join(",")+") value";
 return (await db.query(q,vals)).rows[0].value;
}
async function fixture(){
 const db=await PGlite.create();
 await db.exec(`create role anon;create role authenticated;create role service_role;create schema private;create schema extensions;
 create table public.organizations(id uuid primary key);
 create table public.memberships(organization_id uuid,user_id uuid,role text,status text);
 create table public.pandora_verification_runs(id uuid primary key,organization_id uuid not null,project_id uuid not null,status text not null,source_commit text,required_check_profile text,completed_at timestamptz);
 create function extensions.digest(data bytea,algorithm text) returns bytea language plpgsql immutable as $$begin if algorithm<>'sha256' then raise exception 'unsupported digest';end if;return pg_catalog.sha256(data);end$$;`);
 await db.exec(base);await db.exec(toggle);
 const org=randomUUID(),project=randomUUID(),owner=randomUUID(),member=randomUUID();
 await db.query("insert into public.organizations values($1)",[org]);
 await db.query("insert into public.memberships values($1,$2,'owner','active'),($1,$3,'member','active')",[org,owner,member]);
 const scope={p_organization_id:org,p_project_id:project};
 await rpc(db,"pandora_ops_project_binding_v1",{...scope,p_state:"active",p_evidence_ref:"fixture:allow-production"});
 await rpc(db,"pandora_ops_initialize_v1",{...scope,p_budget_micros:0,p_max_concurrency:4});
 return {db,org,project,owner,member,scope};
}

test("owner allow_production clears only production hold under exact revision",async()=>{
 const f=await fixture();
 const before=await rpc(f.db,"pandora_ops_snapshot_v1",f.scope);
 assert.equal(before.controls.paused,true);assert.equal(before.controls.noProduction,true);assert.equal(before.controls.revision,0);
 const result=await rpc(f.db,"pandora_ops_owner_request_v1",{...f.scope,p_actor_id:f.owner,p_operation:"allow_production",p_payload:{expectedRevision:0}});
 assert.equal(result.revision,1);assert.equal(result.paused,true);assert.equal(result.noProduction,false);
 const after=await rpc(f.db,"pandora_ops_snapshot_v1",f.scope);
 assert.equal(after.controls.paused,true);assert.equal(after.controls.noProduction,false);
 const event=await f.db.query("select event_type from private.pandora_ops_events order by id desc limit 1");
 assert.equal(event.rows[0].event_type,"owner_allow_production");
 await f.db.close();
});

test("allow_production remains owner/admin-only and revision-fenced",async()=>{
 const f=await fixture();
 await assert.rejects(()=>rpc(f.db,"pandora_ops_owner_request_v1",{...f.scope,p_actor_id:f.member,p_operation:"allow_production",p_payload:{expectedRevision:0}}),/OPS_OWNER_SCOPE_DENIED/);
 await rpc(f.db,"pandora_ops_owner_request_v1",{...f.scope,p_actor_id:f.owner,p_operation:"allow_production",p_payload:{expectedRevision:0}});
 await assert.rejects(()=>rpc(f.db,"pandora_ops_owner_request_v1",{...f.scope,p_actor_id:f.owner,p_operation:"no_production",p_payload:{expectedRevision:0}}),/OPS_CONTROL_REVISION_CONFLICT/);
 await f.db.close();
});

test("HTTP owner adapter exposes allow_production only through existing owner RPC",async()=>{
 const {createOperationsHandler}=await import("../supabase/functions/pandora-operations-runtime/handler.mjs");
 const org=randomUUID(),project=randomUUID(),user=randomUUID();let call;
 const handler=createOperationsHandler({
  allowedOrigins:["https://mcpmaster.vercel.app"],
  authenticate:async()=>({userId:user,active:true,role:"owner",organizationId:org,projectId:project}),
  rpc:async(name,params)=>{call={name,params};return {data:{revision:11,paused:false,noProduction:false},error:null};}
 });
 const request=new Request("https://ops.invalid",{method:"POST",headers:{"content-type":"application/json",origin:"https://mcpmaster.vercel.app"},body:JSON.stringify({organizationId:org,projectId:project,operation:"allow_production",expectedRevision:10})});
 const response=await handler(request),body=await response.json();
 assert.equal(response.status,200);assert.equal(body.operation,"allow_production");
 assert.equal(call.name,"pandora_ops_owner_request_v1");assert.equal(call.params.p_operation,"allow_production");assert.deepEqual(call.params.p_payload,{expectedRevision:10});
});
