import test from 'node:test';
import assert from 'node:assert/strict';
import { dockerCreateArgs, DockerSandboxProvider } from '../src/sandbox/docker-sandbox-provider.mjs';
import { withCredentialLeases } from '../src/credentials/scoped-credential-lease.mjs';
import { assertRepairBudget, createRepairAttempt, finishRepairAttempt } from '../src/repair/repair-attempt-manager.mjs';
import { AdmissionController } from '../src/concurrency/admission-controller.mjs';
import { workerHealth } from '../src/health/worker-health.mjs';
import { BuildJobControlPort, CONTROL_PLANE_OPERATIONS } from '../src/control-plane/build-job-port.mjs';
import { createLeaseIdentity } from '../src/control-plane/lease-identity.mjs';
import { runIdempotentStep } from '../src/idempotency/idempotent-step.mjs';
import { runRepairLoop } from '../src/repair/repair-loop.mjs';
import { runResumableBuild } from '../src/execution/resumable-runner.mjs';

test('Docker plans deny network and apply platform-specific isolation', () => {
  const image = `node@sha256:${'a'.repeat(64)}`;
  const windows = dockerCreateArgs({ name: 'sandbox', image, workspaceRoot: 'C:\\work', limits: { memoryBytes: 1024, processCount: 8 }, platform: 'win32', networkPolicy: { mode: 'deny' } });
  assert.ok(windows.includes('none')); assert.ok(windows.includes('--read-only')); assert.ok(windows.includes('--isolation=hyperv')); assert.ok(windows.includes('ContainerUser'));
  const linux = dockerCreateArgs({ name: 'sandbox', image, workspaceRoot: '/work', limits: { memoryBytes: 1024, processCount: 8 }, platform: 'linux', networkPolicy: { mode: 'deny' } });
  assert.ok(linux.includes('ALL')); assert.ok(linux.includes('no-new-privileges')); assert.ok(linux.includes('65532:65532'));
  assert.throws(() => dockerCreateArgs({ name: 's', image, workspaceRoot: '/w', limits: { memoryBytes: 1, processCount: 1 }, networkPolicy: { mode: 'allowlist', allow: ['example.com'] } }), /EGRESS_ALLOWLIST_PROVIDER_REQUIRED/);
  assert.throws(() => dockerCreateArgs({ name: 's', image: 'node:24', workspaceRoot: '/w', limits: { memoryBytes: 1, processCount: 1 }, networkPolicy: { mode: 'deny' } }), /MUTABLE_SANDBOX_IMAGE_FORBIDDEN/);
});

test('Docker provider never invokes a host shell', async () => {
  const calls=[]; const runner={ run: async (exe,args,opts) => { calls.push({exe,args,opts}); return {status:'completed',exitCode:0}; } };
  const provider=new DockerSandboxProvider({runner,image:`node@sha256:${'a'.repeat(64)}`,platform:'linux'});
  const box=await provider.create({workspaceRoot:'/tmp/work',limits:{memoryBytes:1024,processCount:8},networkPolicy:{mode:'deny'}});
  await provider.execute({sandboxId:box.id,executable:'node',args:['--version'],env:{SAFE:'secret-value'},timeoutMs:1000,maxOutputBytes:1024});
  await provider.destroy(box.id);
  assert.ok(calls.every((c)=>c.opts.shell===false));
  assert.ok(calls.some((c)=>c.args.includes('--network')&&c.args.includes('none')));
  assert.ok(calls.every((c)=>!c.args.some((arg)=>String(arg).includes('secret-value'))));
});

test('credential leases are scope checked, ephemeral and revoked', async () => {
  let revoked=0; let seen;
  const result=await withCredentialLeases({leaseRefs:[{leaseId:'lease-1',envName:'PACKAGE_TOKEN',scope:'registry:read'}],allowedEnv:['PACKAGE_TOKEN'],resolver:async()=>({scope:'registry:read',value:'secret-value',expiresAt:new Date(Date.now()+60000).toISOString(),revoke:async()=>{revoked++;}}),execute:async(ctx)=>{seen=ctx;return 'ok';}});
  assert.equal(result,'ok'); assert.equal(seen.env.PACKAGE_TOKEN,'secret-value'); assert.deepEqual(seen.redact,['secret-value']); assert.equal(revoked,1);
  await assert.rejects(()=>withCredentialLeases({leaseRefs:[{leaseId:'x',envName:'VERCEL_TOKEN',scope:'x'}],allowedEnv:[],resolver:async()=>({}),execute:async()=>{}}),/SCOPE_DENIED/);
});

test('repair budgets stop autonomous loops and preserve attempt lineage', () => {
  assert.equal(assertRepairBudget({maxAttempts:2,maxBuildMs:100},{attempts:1,elapsedMs:1,buildMs:50,computeMillis:1,costMicrounits:0}),true);
  assert.throws(()=>assertRepairBudget({maxAttempts:2},{attempts:2}),/ATTEMPTS_EXHAUSTED/);
  const start=createRepairAttempt({attempt:2,parentAttempt:1,inputSourceDigest:'a'.repeat(64),proposalDigest:'b'.repeat(64),authorizedActionId:'auth'});
  const done=finishRepairAttempt(start,{status:'completed',changedFiles:[{path:'x'}],artifactDigest:'c'.repeat(64)});
  assert.equal(done.parentAttempt,1); assert.equal(done.changedFiles.length,1);
});

test('admission control protects worker and project capacity and health is owner-safe', () => {
  const a=new AdmissionController({maxConcurrentJobs:2,maxPerProject:1,minFreeDiskBytes:100,maxMemoryPressure:.8});
  assert.equal(a.admit({jobId:'a',projectId:'p1'},{freeDiskBytes:200,memoryPressure:.1}).admitted,true);
  assert.equal(a.admit({jobId:'b',projectId:'p1'},{freeDiskBytes:200,memoryPressure:.1}).reason,'project_capacity');
  assert.equal(a.admit({jobId:'c',projectId:'p2'},{freeDiskBytes:50,memoryPressure:.1}).reason,'disk_pressure');
  const h=workerHealth({admission:a,providerHealth:'healthy',pressure:{freeDiskBytes:200,minFreeDiskBytes:100,memoryPressure:.1,maxMemoryPressure:.8}});
  assert.equal(h.status,'healthy'); assert.equal(h.activeJobs,1);
});

test('control plane port uses durable Worker A operation names', async () => {
  const names=[]; const p=new BuildJobControlPort({call:async(name,args)=>{names.push(name);return name.includes('heartbeat')?true:{...args};}});
  await p.claim({jobId:'j',workerIdentity:'w',leaseTokenSha256:'a'.repeat(64)}); await p.heartbeat({jobId:'j',workerIdentity:'w',leaseTokenSha256:'a'.repeat(64)}); await p.requeueExpired({limit:5});
  assert.deepEqual(names,['pandora_claim_build_job','pandora_heartbeat_build_job','pandora_requeue_expired_build_jobs']);
});

test('resumable runner honors durable cancellation before execution', async () => {
  const admission=new AdmissionController({maxConcurrentJobs:1,maxPerProject:1,minFreeDiskBytes:0}); let executed=0,cancelled=0,finished;
  const control={claim:async()=>({}),readControl:async()=>({cancelRequestedAt:new Date().toISOString()}),finish:async(x)=>{finished=x;}};
  const result=await runResumableBuild({control,identity:{jobId:'j',workerIdentity:'w',leaseTokenSha256:'a'.repeat(64)},admission,projectId:'p',pressure:{freeDiskBytes:1},execute:async()=>{executed++;},cancel:async()=>{cancelled++;},cleanup:async()=>{}});
  assert.equal(result.status,'cancelled'); assert.equal(executed,0); assert.equal(cancelled,1); assert.equal(finished.outcome,'cancelled'); assert.equal(admission.snapshot().activeJobs,0);
});

test('lease identities are opaque random digests and generic Control Plane operations are not fabricated RPC names', async () => {
  const a=createLeaseIdentity({jobId:'j',workerIdentity:'w'}); const b=createLeaseIdentity({jobId:'j',workerIdentity:'w'});
  assert.match(a.leaseTokenSha256,/^[0-9a-f]{64}$/); assert.notEqual(a.leaseTokenSha256,b.leaseTokenSha256);
  const names=[]; const p=new BuildJobControlPort({call:async(name)=>{names.push(name); return {};}});
  await p.readControl({jobId:'j'}); await p.checkpoint({jobId:'j',stepKey:'build'}); await p.finish({jobId:'j',workerIdentity:'w',leaseTokenSha256:a.leaseTokenSha256,outcome:'succeeded'});
  assert.deepEqual(names,[CONTROL_PLANE_OPERATIONS.readControl,CONTROL_PLANE_OPERATIONS.checkpoint,CONTROL_PLANE_OPERATIONS.finish]);
});

test('idempotent step replays exact success and blocks ambiguous mutation redelivery', async () => {
  let executions=0; let prior={status:'succeeded',inputSha256:'a'.repeat(64),result:{ok:true},resultSha256:'b'.repeat(64)};
  const store={read:async()=>prior,begin:async()=>({}),complete:async()=>({})};
  const replay=await runIdempotentStep({store,identity:{jobId:'j',stepKey:'build'},inputSha256:'a'.repeat(64),mutation:true,execute:async()=>{executions++;}});
  assert.equal(replay.replay,true); assert.equal(executions,0);
  prior={status:'running',inputSha256:'a'.repeat(64)};
  await assert.rejects(()=>runIdempotentStep({store,identity:{jobId:'j',stepKey:'publish-like-mutation'},inputSha256:'a'.repeat(64),mutation:true,execute:async()=>{executions++;}}),/AMBIGUOUS_PRIOR_MUTATION_OUTCOME/);
  assert.equal(executions,0);
});

test('resumable runner aborts live work when durable cancellation appears', async () => {
  const admission=new AdmissionController({maxConcurrentJobs:1,maxPerProject:1,minFreeDiskBytes:0});
  let reads=0,cancelled=0,finished=null,observedAbort=false;
  const control={claim:async()=>({}),heartbeat:async()=>true,readControl:async()=>{reads++; return reads>2?{cancelRequestedAt:new Date().toISOString()}:{};},finish:async(x)=>{finished=x;}};
  const result=await runResumableBuild({control,identity:{jobId:'j',workerIdentity:'w',leaseTokenSha256:'a'.repeat(64)},admission,projectId:'p',pressure:{freeDiskBytes:1},heartbeatIntervalMs:5,cancelPollMs:1,execute:async({signal})=>new Promise((resolve)=>{signal.addEventListener('abort',()=>{observedAbort=true;resolve({status:'cancelled'});},{once:true});}),cancel:async()=>{cancelled++;},cleanup:async()=>{}});
  assert.equal(result.status,'cancelled'); assert.equal(observedAbort,true); assert.equal(cancelled,1); assert.equal(finished.outcome,'cancelled');
});

test('resumable runner treats lost durable lease as fatal and stops work', async () => {
  const admission=new AdmissionController({maxConcurrentJobs:1,maxPerProject:1,minFreeDiskBytes:0}); let heartbeats=0,cancelled=0,aborted=false;
  const control={claim:async()=>({}),readControl:async()=>({}),heartbeat:async()=>++heartbeats<2,finish:async()=>{throw new Error('must not finish after lost lease');}};
  await assert.rejects(()=>runResumableBuild({control,identity:{jobId:'j',workerIdentity:'w',leaseTokenSha256:'a'.repeat(64)},admission,projectId:'p',pressure:{freeDiskBytes:1},heartbeatIntervalMs:1,cancelPollMs:10,execute:async({signal})=>new Promise((resolve)=>signal.addEventListener('abort',()=>{aborted=true;resolve({status:'cancelled'});},{once:true})),cancel:async()=>{cancelled++;},cleanup:async()=>{}}),/BUILD_JOB_LEASE_LOST/);
  assert.equal(aborted,true); assert.equal(cancelled,1); assert.equal(admission.snapshot().activeJobs,0);
});

test('repair loop consumes only authorized repairs, isolates attempts, and stops at success', async () => {
  const proposalDigest='b'.repeat(64); const events=[]; let builds=0;
  const output=await runRepairLoop({initialResult:{status:'failed',failureClass:'syntax'},budget:{maxAttempts:2,maxBuildMs:1000},usage:{attempts:0,elapsedMs:0,buildMs:0,computeMillis:0,costMicrounits:0},sourceDigest:'a'.repeat(64),proposeAuthorizedRepair:async()=>({authorizationId:'auth-1',proposalDigest,proposal:{write:'fixed'}}),prepareAttempt:async({attempt})=>({root:`/work/attempt-${attempt}`}),applyRepair:async()=>({changedFiles:[{path:'index.js',operation:'modify'}],outputSourceDigest:'c'.repeat(64)}),rebuild:async()=>{builds++;return {status:'completed',manifest:{manifestSha256:'d'.repeat(64)},resourceUsage:{buildMs:10,computeMillis:5,costMicrounits:1}};},onAttempt:(e)=>events.push(e)});
  assert.equal(builds,1); assert.equal(output.attempts.length,1); assert.equal(output.attempts[0].parentAttempt,null); assert.equal(output.result.status,'completed'); assert.equal(events.length,2);
});
