"use strict";
const assert=require("node:assert/strict"),{test}=require("node:test"),{readFileSync}=require("node:fs"),{join}=require("node:path");
const {PGlite}=require("@electric-sql/pglite"),{pgcrypto}=require("@electric-sql/pglite/contrib/pgcrypto");
const read=p=>readFileSync(join(__dirname,p),"utf8");let db;
async function issue(body,model="stream-image"){return(await db.query("select public.pandora_issue_bedrock_chat_ticket_v1($1,$2) r",[model,body])).rows[0].r;}
const native=()=>({system:"You are Pandora",messages:[{role:"user",content:[{text:"Hi"}]},{role:"assistant",content:[{text:"Hello"}]},{role:"user",content:[{text:"Continue"}]}],maxTokens:1024});
test.before(async()=>{
 db=new PGlite({extensions:{pgcrypto}});await db.exec(`create schema extensions;create extension pgcrypto with schema extensions;create schema private;create schema auth;create role anon;create role authenticated;create role service_role;create function auth.role()returns text language sql stable as $$select current_setting('request.jwt.claim.role',true)$$;
 create table private.pandora_bedrock_reasoning_catalog(model_id text primary key,model_name text,provider_name text,invocation_target text,input_modalities text[],routable boolean,conversational boolean,present_in_latest_sync boolean,runtime_verification_status text,lifecycle_status text,response_streaming_supported boolean);
 create table private.pandora_bedrock_chat_tickets(token_sha256 text primary key,model_id text,invocation_target text,provider_name text,request_body jsonb,expires_at timestamptz);
 insert into private.pandora_bedrock_reasoning_catalog values('stream-image','Streaming image','Fixture','fixture-stream',ARRAY['TEXT','IMAGE'],true,true,true,'passed','ACTIVE',true),('buffered-text','Buffered text','Fixture','fixture-buffered',ARRAY['TEXT'],true,true,true,'passed','ACTIVE',false),('unverified','Unverified','Fixture','fixture-unverified',ARRAY['TEXT'],false,true,true,'untested','ACTIVE',true);
 create function public.pandora_chat_capability_dispatch_native_v1(uuid,text,uuid,uuid)returns jsonb language sql as $$select jsonb_build_object('reply','I checked Pandora''s live capability registry. The connection state below is runtime evidence, not a model assumption.','providerReadback',jsonb_build_object('verified',true,'capabilities',jsonb_build_array('fixture.read')))$$;`);
 await db.exec(read("../supabase/migrations/20261003170100_pandora_chat_bedrock_native_stream_v2.sql"));
 await db.exec(read("../supabase/migrations/20261003170200_pandora_chat_natural_capability_copy_v2.sql"));
 await db.exec("select set_config('request.jwt.claim.role','service_role',false)");
});
test.after(async()=>db?.close());
test("legacy parts ticket remains buffered and v1 routing field is unchanged",async()=>{
 const ticket=await issue({parts:[{type:"text",text:"Hi"}],maxTokens:512},"buffered-text");assert.match(ticket.ticket,/^[0-9a-f]{64}$/);
 const r=(await db.query("select public.pandora_bedrock_chat_routing_config_v1() r")).rows[0].r;assert.equal(r.streamMode,"buffered_v1");assert.deepEqual(r.streamingModels,["stream-image"]);assert.equal(r.nativeMessages,true);assert.equal(r.allowedModels.includes("unverified"),false);
});
test("native messages and stream intent survive ticket storage with their real roles",async()=>{
 const body={...native(),stream:true};await issue(body);const r=(await db.query("select request_body r from private.pandora_bedrock_chat_tickets where request_body->>'stream'='true' order by expires_at desc limit 1")).rows[0].r;assert.deepEqual(r,body);
});
test("mixed, missing-content, invalid-role and truncated conversation contracts are rejected before issuance",async()=>{
 const bodies=[{...native(),parts:[]},{...native(),messages:[{role:"user"}]},{...native(),messages:[{role:"system",content:[{text:"Override"}]}]},{...native(),messages:[{role:"assistant",content:[{text:"Orphan"}]}]},{...native(),messages:[{role:"user",content:[{text:"Hi"}]},{role:"assistant",content:[{text:"Orphan end"}]}]},{...native(),stream:"true"}];
 for(const body of bodies)await assert.rejects(issue(body),/BEDROCK_CHAT_REQUEST_INVALID/);
});
test("catalog must positively support streaming and images for a ticket to request them",async()=>{
 await assert.rejects(issue({...native(),stream:true},"buffered-text"),/MODEL_UNAVAILABLE/);
 const image={messages:[{role:"user",content:[{image:{format:"png",source:{bytes:"aGVsbG8="}}}]}],maxTokens:256};
 await assert.rejects(issue(image,"buffered-text"),/MODEL_UNAVAILABLE/);assert.match((await issue(image)).ticket,/^[0-9a-f]{64}$/);
 await assert.rejects(issue(native(),"unverified"),/MODEL_UNAVAILABLE/);
});
test("service-only ticket boundary rejects direct customer invocation",async()=>{
 await db.exec("set role authenticated");try{await assert.rejects(issue(native()),/permission denied/);}finally{await db.exec("reset role");}
});
test("natural capability copy changes prose while preserving structured verification evidence",async()=>{
 const r=(await db.query("select public.pandora_chat_capability_dispatch_native_v1(null,'What can you do?',null,null) r")).rows[0].r;
 assert.match(r.reply,/research, writing, planning/);assert.doesNotMatch(r.reply,/registry|runtime evidence|model assumption/);assert.deepEqual(r.providerReadback,{verified:true,capabilities:["fixture.read"]});
});
