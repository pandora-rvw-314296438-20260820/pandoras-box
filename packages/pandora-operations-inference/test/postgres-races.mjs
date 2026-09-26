import test from 'node:test';
import assert from 'node:assert/strict';
import {execFile,spawn} from 'node:child_process';
import {promisify} from 'node:util';
import {readFile} from 'node:fs/promises';
import {randomUUID,createHash} from 'node:crypto';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url),{normalizeTask,REPOSITORIES}=require('../../pandora-operations-room/contracts.js');
const execute=promisify(execFile),SHA='a'.repeat(40),literal=x=>x===null?'null':"'"+String(x).replaceAll("'","''")+"'";
const json=x=>literal(JSON.stringify(x))+'::jsonb';
function env(){assert.equal(process.env.PGHOST,'127.0.0.1');assert.equal(process.env.PGDATABASE,'pandora_inference_ci');return{...process.env,PGOPTIONS:'-c statement_timeout=15000 -c lock_timeout=10000'};}
async function sql(query){const {stdout}=await execute('psql',['-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-c',query],{env:env(),timeout:20000,maxBuffer:1048576});return stdout.trim().split('\n').filter(x=>x.startsWith('{')).map(JSON.parse);}
const op=(s,name,payload)=>`public.pandora_ops_inference_transition_v1(${literal(name)},${json(s.actor)},${json(payload)})`;
const read=async(s,name,payload)=>(await sql('select '+op(s,name,payload)))[0];
/** Hold the real winning transaction open until the other independent session has started. */
function holding(query){let child,readyResolve,readyReject,doneResolve,doneReject,output='',error='',released=false;
 const ready=new Promise((a,b)=>{readyResolve=a;readyReject=b;}),done=new Promise((a,b)=>{doneResolve=a;doneReject=b;});
 child=spawn('psql',['-X','-q','-A','-t','-v','ON_ERROR_STOP=1'],{env:env(),stdio:['pipe','pipe','pipe'],shell:false});
 const timer=setTimeout(()=>{child.kill('SIGTERM');readyReject(new Error('fixture holder deadline'));doneReject(new Error('fixture holder deadline'));},10000);
 child.stdout.on('data',chunk=>{output+=chunk.toString();if(output.includes('HOLDER_READY'))readyResolve();});child.stderr.on('data',chunk=>{error+=chunk.toString();});
 child.on('error',e=>{clearTimeout(timer);readyReject(e);doneReject(e);});child.on('close',code=>{clearTimeout(timer);if(code===0)doneResolve(output.split('\n').filter(x=>x.startsWith('{')).map(JSON.parse));else{const e=new Error(error||'holder failed');readyReject(e);doneReject(e);}});
 child.stdin.write(`begin;select jsonb_build_object('pid',pg_backend_pid(),'value',${query});select 'HOLDER_READY';\n`);
 return{ready,done,release(){if(!released){released=true;child.stdin.end('commit;\n');}}};
}
async function competing(firstExpression,secondExpression){const h=holding(firstExpression);await h.ready;const second=sql(`begin;select jsonb_build_object('pid',pg_backend_pid(),'value',${secondExpression});commit;`);let completed=false;second.then(()=>{completed=true;},()=>{completed=true;});
 // Observe the blocked independent database session, not an arbitrary sleep used as proof.
 let blocked=false;for(let i=0;i<50;i++){const v=(await sql("select jsonb_build_object('blocked',exists(select 1 from pg_stat_activity where datname='pandora_inference_ci' and pid<>pg_backend_pid() and wait_event_type='Lock'))"))[0];if(v.blocked){blocked=true;break;}if(completed)break;await new Promise(r=>setTimeout(r,20));}
 h.release();const results=await Promise.allSettled([h.done,second]);assert.equal(blocked,true,'The second live PostgreSQL connection actually waited on a row lock');return results;}
async function setup({org=randomUUID(),budget=200,capacity=2}={}){const project=randomUUID(),digest=createHash('sha256').update(randomUUID()).digest('hex');const scope=[org,project].map(literal).join(',');
 const task=normalizeTask({id:'TASK',title:'Ephemeral PostgreSQL fixture',lane:'backend',priority:0,dependsOn:[],resources:[{key:'source/'+project,mode:'write'}],requiredCapabilities:[],maxCostMicros:budget,maxDurationSeconds:600,maxAttempts:2,risk:'source',acceptance:['fixture only'],source:{repository:REPOSITORIES[0],baseSha:SHA}});
 await sql(`insert into public.organizations values(${literal(org)}) on conflict do nothing;select public.pandora_ops_project_binding_v1(${scope},'active','fixture:project');select public.pandora_ops_initialize_v1(${scope},10000,4);select public.pandora_ops_register_worker_v1(${scope},'W','fixture-worker',array['backend'],array[]::text[],4,'fixture:not-real-enrollment');select public.pandora_ops_ingest_v1(${scope},${json([task])});select public.pandora_ops_control_v1(${scope},0,'resume');select public.pandora_ops_claim_v1(${scope},'TASK','W',0,1);`);
 const lease=(await sql(`select jsonb_build_object('id',id,'generation',generation) from private.pandora_ops_leases where organization_id=${literal(org)} and project_id=${literal(project)}`))[0];
 const now=Date.now();const policy={version:'fixture',models:[{provider:'fixture',model:'test',modelRevision:null,configurationDigest:'c'.repeat(64),classes:['complex_coding'],modalities:['text'],executionBoundary:'cloud',riskTier:3,contextTokens:4096,maxInputBytes:4096,maxOutputTokens:1024,imageTokenUpperBound:0,transport:'fixture',approved:true,approvalRef:'fixture:approval-not-production',approvalExpiresAt:new Date(now+3600000).toISOString(),available:true,healthObservedAt:new Date(now).toISOString(),estimatedLatencyMs:1,maxCostMicros:50,maxConcurrency:capacity}],maxAttempts:3,maxHealthAgeMs:60000,minimumRiskTier:{read:0,source:2,preview:1,production:3,destructive:3},allowedBoundaries:['cloud'],allowedProviders:['fixture']};
 await sql(`update private.pandora_ops_leases set state='running' where id=${literal(lease.id)};update private.pandora_ops_tasks set status='implementing' where organization_id=${literal(org)} and project_id=${literal(project)};insert into private.pandora_ops_inference_policies values(${scope},1,${json(policy)},true,'fixture:approval');insert into private.pandora_ops_inference_callers values(${literal(digest)},${scope},'W','fixture-worker',true,clock_timestamp()+interval '1 hour',array['complex_coding'],'fixture:enrollment');`);
 const actor=(await sql(`select public.pandora_ops_inference_authenticate_v1(${literal(digest)})`))[0];const metadata={requestId:randomUUID(),taskId:'TASK',leaseId:lease.id,generation:lease.generation,sourceSha:SHA,taskClass:'complex_coding',requestDigest:'d'.repeat(64),inputDigest:'e'.repeat(64),maxCostMicros:100,maxOutputTokens:128,deadlineMs:1000,textBytes:10,inputBytes:10,imageCount:0,modalities:['text']};
 const s={org,project,actor,metadata};const context=await read(s,'context',metadata);s.policyDigest=context.policyDigest;return s;}
const prep=s=>op(s,'prepare',{requestId:s.metadata.requestId,modelKey:'fixture:test',policyDigest:s.policyDigest});
test.before(async()=>{await sql(`create role anon;create role authenticated;create role service_role;create schema private;create schema extensions;create extension pgcrypto with schema extensions;create table public.organizations(id uuid primary key);create table public.memberships(organization_id uuid,user_id uuid,role text,status text);create table public.pandora_verification_runs(id uuid primary key,organization_id uuid not null,project_id uuid not null,status text not null,source_commit text,required_check_profile text,completed_at timestamptz,artifact_digest text,builder_identity text,verifier_identity text,runtime_target_digest text);`);
 await sql(await readFile(new URL('../../../supabase/migrations/20260925101319_pandora_operations_room_runtime_v1.sql',import.meta.url),'utf8'));
 await sql(await readFile(new URL('../schema.sql',import.meta.url),'utf8'));});
test('independent sessions atomically admit one exact request identity',async()=>{const s=await setup();const r=await competing(op(s,'admit',s.metadata),op(s,'admit',s.metadata));assert.ok(r.every(x=>x.status==='fulfilled'));const a=r[0].value[0],b=r[1].value[0];assert.notEqual(a.pid,b.pid);assert.equal([a,b].filter(x=>x.value.created).length,1);});
test('two simultaneous request reservations cannot exceed the parent lease',async()=>{const s=await setup({budget:100});const r=await competing(op(s,'admit',s.metadata),op(s,'admit',{...s.metadata,requestId:randomUUID()}));assert.equal(r.filter(x=>x.status==='fulfilled').length,1);assert.match(r.find(x=>x.status==='rejected').reason.message,/PARENT_BUDGET_EXHAUSTED/);});
test('two independent senders receive only one send permission',async()=>{const s=await setup();await read(s,'admit',s.metadata);const a=await read(s,'prepare',{requestId:s.metadata.requestId,modelKey:'fixture:test',policyDigest:s.policyDigest});const expression=op(s,'send',{requestId:s.metadata.requestId,attemptId:a.attemptId,policyDigest:s.policyDigest});const r=await competing(expression,expression);assert.ok(r.every(x=>x.status==='fulfilled'));assert.notEqual(r[0].value[0].pid,r[1].value[0].pid);assert.equal(r.filter(x=>x.value[0].value.canSend===true).length,1);});
test('global model capacity serializes separate project workspaces in one organization',async()=>{const s=await setup({capacity:1}),t=await setup({org:s.org,capacity:1});await read(s,'admit',s.metadata);await read(t,'admit',t.metadata);const r=await competing(prep(s),prep(t));assert.equal(r.filter(x=>x.status==='fulfilled').length,1);assert.match(r.find(x=>x.status==='rejected').reason.message,/CAPACITY_HELD/);});
test('half-open provider health admits one actual probe across independent sessions',async()=>{const s=await setup(),t=await setup({org:s.org});await read(s,'admit',s.metadata);await read(t,'admit',t.metadata);await sql(`insert into private.pandora_ops_inference_circuits(organization_id,model_key,state,retry_after) values(${literal(s.org)},'fixture:test','open',clock_timestamp()-interval '1 second')`);const r=await competing(prep(s),prep(t));assert.equal(r.filter(x=>x.status==='fulfilled').length,1);assert.match(r.find(x=>x.status==='rejected').reason.message,/CIRCUIT_HELD/);});
test('caller revocation waits for existing scoped transaction then prevents new admission',async()=>{const s=await setup();const h=holding(op(s,'context',s.metadata));await h.ready;const revocation=sql(`update private.pandora_ops_inference_callers set enabled=false where token_digest=${literal(s.actor.callerDigest)} returning jsonb_build_object('revoked',not enabled)`);let blocked=false;for(let i=0;i<50;i++){const r=(await sql("select jsonb_build_object('blocked',exists(select 1 from pg_stat_activity where datname='pandora_inference_ci' and pid<>pg_backend_pid() and wait_event_type='Lock'))"))[0];if(r.blocked){blocked=true;break;}await new Promise(r=>setTimeout(r,20));}h.release();await h.done;assert.equal((await revocation)[0].revoked,true);assert.equal(blocked,true);await assert.rejects(()=>read(s,'admit',s.metadata),/CALLER_DENIED/);});

test('legacy worker event and a concurrent control event cannot commit past an unobserved lower cursor',async()=>{
 const s=await setup(),owner=randomUUID();await sql(`insert into public.memberships values(${literal(s.org)},${literal(owner)},'owner','active')`);
 const feed=after=>`public.pandora_ops_event_feed_v1(${literal(s.org)},${literal(s.project)},${literal(owner)},${literal(after)}::bigint,200)`;
 const initial=(await sql('select '+feed('0')))[0];
 const registration=`public.pandora_ops_register_worker_v1(${literal(s.org)},${literal(s.project)},'LATE-W','fixture-late-worker',array['backend'],array[]::text[],1,'fixture:late-worker')`;
 const h=holding(registration);await h.ready;
 const later=sql(`select jsonb_build_object('value',public.pandora_ops_control_v1(${literal(s.org)},${literal(s.project)},1,'pause'))`);
 let blocked=false;for(let i=0;i<50;i++){const value=(await sql("select jsonb_build_object('blocked',exists(select 1 from pg_stat_activity where datname='pandora_inference_ci' and pid<>pg_backend_pid() and wait_event_type='Lock'))"))[0];if(value.blocked){blocked=true;break;}await new Promise(r=>setTimeout(r,20));}
 const during=(await sql('select '+feed(initial.nextCursor)))[0];assert.equal(during.nextCursor,initial.nextCursor);assert.equal(during.events.length,0);
 h.release();await h.done;await later;assert.equal(blocked,true);
 const after=(await sql('select '+feed(during.nextCursor)))[0];
 assert.deepEqual(after.events.map(e=>e.type),['worker_acknowledged','owner_pause']);
 assert.ok(BigInt(after.events[0].id)<BigInt(after.events[1].id));
});
test('two legacy event writers without workspace locks preserve the same commit-ordered cursor',async()=>{
 const s=await setup(),scope=[s.org,s.project].map(literal).join(',');
 const worker=name=>`public.pandora_ops_register_worker_v1(${scope},${literal(name)},${literal('fixture-'+name)},array['backend'],array[]::text[],1,'fixture:writer')`;
 const results=await competing(worker('EVENT-A'),worker('EVENT-B'));assert.ok(results.every(r=>r.status==='fulfilled'));
 const rows=(await sql(`select jsonb_build_object('events',jsonb_agg(jsonb_build_object('id',id,'key',event_key)order by id)) from private.pandora_ops_events where organization_id=${literal(s.org)} and project_id=${literal(s.project)} and event_key in ('worker:EVENT-A','worker:EVENT-B')`))[0];
 assert.deepEqual(rows.events.map(e=>e.key),['worker:EVENT-A','worker:EVENT-B']);
});
test('native prepare recovery wins the row lock and denies a concurrent delayed send',async()=>{
 const s=await setup();await read(s,'admit',s.metadata);const a=await read(s,'prepare',{requestId:s.metadata.requestId,modelKey:'fixture:test',policyDigest:s.policyDigest});
 const results=await competing(op(s,'recover_prepare',{requestId:s.metadata.requestId}),op(s,'send',{requestId:s.metadata.requestId,attemptId:a.attemptId,policyDigest:s.policyDigest}));
 assert.equal(results[0].status,'fulfilled');assert.equal(results[0].value[0].value.resolved,true);assert.equal(results[1].status,'rejected');assert.match(results[1].reason.message,/REQUEST_FENCED/);
 const current=await read(s,'status',{requestId:s.metadata.requestId});assert.equal(current.attempts[0].state,'not_sent');assert.equal(current.attempts[0].billed_micros,0);
});
test('a concurrent committed send prevents recovery from falsely reporting not_sent',async()=>{
 const s=await setup();await read(s,'admit',s.metadata);const a=await read(s,'prepare',{requestId:s.metadata.requestId,modelKey:'fixture:test',policyDigest:s.policyDigest});
 const results=await competing(op(s,'send',{requestId:s.metadata.requestId,attemptId:a.attemptId,policyDigest:s.policyDigest}),op(s,'recover_prepare',{requestId:s.metadata.requestId}));
 assert.ok(results.every(r=>r.status==='fulfilled'));assert.equal(results[0].value[0].value.canSend,true);assert.equal(results[1].value[0].value.resolved,false);
 assert.equal((await read(s,'status',{requestId:s.metadata.requestId})).attempts[0].state,'sent');
});
