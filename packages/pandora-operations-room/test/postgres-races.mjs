import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { createRequire } from 'node:module';
const require=createRequire(import.meta.url);
const {normalizeTask,REPOSITORIES}=require('../contracts.js');
const execute=promisify(execFile);
const sha='a'.repeat(40);
const literal=x=>x===null?'null':"'"+String(x).replaceAll("'","''")+"'";
function spec(id,resources=[{key:'source/shared',mode:'write'}]) {return normalizeTask({id,title:id,lane:'backend',priority:1,dependsOn:[],resources,requiredCapabilities:[],maxCostMicros:10,maxDurationSeconds:120,maxAttempts:2,risk:'source',acceptance:['exact source'],source:{repository:REPOSITORIES[0],baseSha:sha}});}
async function sql(query) {
 assert.equal(process.env.PGHOST,'127.0.0.1','Ephemeral loopback database required');
 assert.equal(process.env.PGDATABASE,'pandora_ops_ci','Refuse non-test database');
 const {stdout}=await execute('psql',['-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-c',query],{timeout:30000,maxBuffer:1024*1024,env:{...process.env,PGOPTIONS:'-c statement_timeout=20000 -c lock_timeout=10000'}});
 return stdout.trim().split('\n').filter(line=>line.startsWith('{')).map(line=>JSON.parse(line));
}
function args(s){return [s.org,s.project].map(literal).join(',');}
async function setup({budget=100,slots=8,org=null}={}) {
 const s={org:org??randomUUID(),project:randomUUID()};
 await sql(`insert into public.organizations values(${literal(s.org)}) on conflict do nothing; insert into public.test_project_identity(id,organization_id) values(${literal(s.project)},${literal(s.org)}); select public.pandora_ops_initialize_v1(${args(s)},${budget},${slots}); select public.pandora_ops_register_worker_v1(${args(s)},'W1','fixture-builder-one',array['backend'],array[]::text[],4,'fixture:enrollment:one'); select public.pandora_ops_register_worker_v1(${args(s)},'W2','fixture-builder-two',array['backend'],array[]::text[],4,'fixture:enrollment:two'); select public.pandora_ops_control_v1(${args(s)},0,'resume');`);
 return s;
}
async function ingest(s,tasks){await sql(`select public.pandora_ops_ingest_v1(${args(s)},${literal(JSON.stringify(tasks))}::jsonb);`);}
function claimExpr(s,key,worker='W1'){return `public.pandora_ops_claim_v1(${args(s)},${literal(key)},${literal(worker)},0,1)`;}
async function callInTransaction(expr,hold=false){const r=await sql(`begin;select jsonb_build_object('pid',pg_backend_pid(),'value',${expr});${hold?'select pg_sleep(0.25);':''}commit;`);return r[0];}
async function snapshot(s){return (await sql(`select public.pandora_ops_snapshot_v1(${args(s)});`))[0];}
test.before(async()=>{
 await sql(`create role anon;create role authenticated;create role service_role;create schema private;create schema extensions;create extension pgcrypto with schema extensions;create table public.organizations(id uuid primary key);create table public.test_project_identity(id uuid primary key,organization_id uuid not null references public.organizations(id),status text not null default 'active');create view public.pandora_projects with(security_invoker=true) as select id,organization_id,status from public.test_project_identity;create table public.memberships(organization_id uuid,user_id uuid,role text,status text);create table public.pandora_verification_runs(id uuid primary key,organization_id uuid not null,project_id uuid not null,status text,source_commit text,required_check_profile text,completed_at timestamptz);`);
 await sql(await readFile(new URL('../../../supabase/migrations/20260925101319_pandora_operations_room_runtime_v1.sql',import.meta.url),'utf8'));
});
test('two PostgreSQL sessions cannot claim one task for different workers',async()=>{
 const s=await setup();await ingest(s,[spec('A')]);const r=await Promise.all([callInTransaction(claimExpr(s,'A','W1'),true),callInTransaction(claimExpr(s,'A','W2'),true)]);
 assert.notEqual(r[0].pid,r[1].pid);assert.equal(r.filter(x=>x.value.claimed).length,1);const p=await snapshot(s);assert.equal(p.leases.length,1);assert.equal(p.budget.availableMicros,90);
});
test('concurrent conflicting parent and child resources serialize',async()=>{
 const s=await setup();await ingest(s,[spec('A'),spec('B',[{key:'source/shared/file',mode:'write'}])]);const r=await Promise.all([callInTransaction(claimExpr(s,'A'),true),callInTransaction(claimExpr(s,'B','W2'),true)]);assert.notEqual(r[0].pid,r[1].pid);assert.equal(r.filter(x=>x.value.claimed).length,1);assert.equal(r.find(x=>!x.value.claimed).value.reason,'resource_conflict');
});
test('concurrent independent work is admitted without a fixed single-worker lane',async()=>{
 const s=await setup();await ingest(s,[spec('A',[{key:'source/a',mode:'write'}]),spec('B',[{key:'source/b',mode:'write'}])]);const r=await Promise.all([callInTransaction(claimExpr(s,'A'),true),callInTransaction(claimExpr(s,'B','W2'),true)]);assert.notEqual(r[0].pid,r[1].pid);assert.equal(r.filter(x=>x.value.claimed).length,2);assert.equal((await snapshot(s)).leases.length,2);
});
test('budget reservation cannot overspend under simultaneous independent claims',async()=>{
 const s=await setup({budget:15});await ingest(s,[spec('A',[{key:'source/a',mode:'write'}]),spec('B',[{key:'source/b',mode:'write'}])]);const r=await Promise.all([callInTransaction(claimExpr(s,'A'),true),callInTransaction(claimExpr(s,'B','W2'),true)]);assert.equal(r.filter(x=>x.value.claimed).length,1);assert.equal(r.find(x=>!x.value.claimed).value.reason,'cost_budget_exhausted');assert.equal((await snapshot(s)).budget.availableMicros,5);
});
test('concurrent exact claim replay returns one lease and one charge',async()=>{
 const s=await setup();await ingest(s,[spec('A')]);const r=await Promise.all([callInTransaction(claimExpr(s,'A'),true),callInTransaction(claimExpr(s,'A'),true)]);assert.equal(r[0].value.leaseId,r[1].value.leaseId);assert.equal(r.filter(x=>x.value.replayed===true).length,1);assert.equal((await snapshot(s)).budget.availableMicros,90);
});
test('dispatch outbox admits one sender across independent database sessions',async()=>{
 const s=await setup();await ingest(s,[spec('A')]);const c=await callInTransaction(claimExpr(s,'A'));const expr=`public.pandora_ops_dispatch_v1(${args(s)},${literal(c.value.leaseId)},1)`;const r=await Promise.all([callInTransaction(expr,true),callInTransaction(expr,true)]);assert.notEqual(r[0].pid,r[1].pid);assert.equal(r.filter(x=>x.value.canSend===true).length,1);assert.equal(r[0].value.dispatchId,r[1].value.dispatchId);
});
test('resource exclusion also serializes two projects in the same organization',async()=>{
 const s=await setup(),t=await setup({org:s.org});await ingest(s,[spec('A')]);await ingest(t,[spec('B')]);const r=await Promise.all([callInTransaction(claimExpr(s,'A'),true),callInTransaction(claimExpr(t,'B','W2'),true)]);assert.equal(r.filter(x=>x.value.claimed).length,1);assert.equal(r.find(x=>!x.value.claimed).value.reason,'resource_conflict');
});
