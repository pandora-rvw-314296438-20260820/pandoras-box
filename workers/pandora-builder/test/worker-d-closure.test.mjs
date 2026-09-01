import test from 'node:test';
import assert from 'node:assert/strict';
import { createAdmissionController } from '../src/admission/admission-controller.mjs';
import { createWorkerAControlPlane, sha256Hex } from '../src/control/worker-a-control-plane.mjs';
import { createCredentialLeaseManager } from '../src/credentials/credential-lease-manager.mjs';
import { executeManagedBuild } from '../src/execution/managed-build-runtime.mjs';
import { createWorkerHealthSnapshot } from '../src/health/worker-health.mjs';
import { createDurableStepJournal } from '../src/idempotency/durable-step-journal.mjs';
import { createRepairController } from '../src/repair/repair-controller.mjs';
import { executeRepairAttempt } from '../src/repair/repair-runtime.mjs';
import { classifyBuildJobRecovery, orphanSandboxCleanupPlan } from '../src/recovery/crash-recovery.mjs';

const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const snapshot = { activeGlobal: 0, activeByOrganization: {}, activeByProject: {}, controlPlaneHealthy: true, sandboxProviderHealthy: true };
const req = (n = 1, refs = []) => ({ buildJobId: uuid(n), organizationId: uuid(100+n), projectId: uuid(200+n), projectVersionId: uuid(300+n), idempotencyKey: `idem-${n}-12345678`, attempt: 1, credentialLeaseRefs: refs });
function store() { const rows = new Map(); const k=(s,i)=>`${s}|${i}`; return { rows, get: async(s,i)=>rows.get(k(s,i))??null, put: async r=>rows.set(k(r.stepKey,r.idempotencyKey),{...(rows.get(k(r.stepKey,r.idempotencyKey))??{}),...structuredClone(r)}) }; }

test('Worker A lease transport hashes raw token', async () => {
  const calls=[]; const c=createWorkerAControlPlane({workerIdentity:'worker-d-1',rpc:async(name,args)=>{calls.push({name,args});return true;}});
  const token='lease-secret-1234567890'; await c.claim(uuid(1),token); await c.heartbeat(uuid(1),token);
  assert.equal(calls[0].args.p_lease_token_sha256,sha256Hex(token)); assert.equal(JSON.stringify(calls).includes(token),false);
});

test('temporary credential leases clean up and stale/standing values fail closed', async () => {
  const released=[]; const clock=()=>new Date('2026-08-29T00:00:00Z');
  const m=createCredentialLeaseManager({clock,releaseLease:async r=>released.push(r),resolveLease:async r=>({ref:r,scope:'registry:read',credentialClass:'temporary_scoped',expiresAt:'2026-08-29T00:10:00Z',environment:{TEMP_TOKEN:`secret-${r}`}})});
  const l=await m.acquire(['lease-1']); assert.deepEqual(l.redactionValues,['secret-lease-1']); await m.release(l.refs); assert.deepEqual(released,['lease-1']);
  await assert.rejects(()=>createCredentialLeaseManager({clock,resolveLease:async r=>({ref:r,scope:'x',expiresAt:'2026-08-28T23:59:59Z',environment:{TEMP:'x'}})}).acquire(['x']),/EXPIRED/);
  await assert.rejects(()=>createCredentialLeaseManager({clock,resolveLease:async r=>({ref:r,scope:'x',expiresAt:'2026-08-29T00:05:00Z',environment:{GITHUB_TOKEN:'master'}})}).acquire(['x']),/STANDING_PROVIDER_CREDENTIAL_FORBIDDEN/);
});

test('durable journal replays exact duplicates, rejects conflicts, quarantines ambiguous expiry', async () => {
  const s=store(); const j=createDurableStepJournal({store:s,clock:()=>new Date('2026-08-29T00:00:00Z')});
  const p=await j.prepare({stepKey:'build:1',idempotencyKey:'i',input:{a:1}}); await j.complete({stepKey:'build:1',idempotencyKey:'i',inputSha256:p.inputSha256,result:{status:'completed'}});
  assert.equal((await j.prepare({stepKey:'build:1',idempotencyKey:'i',input:{a:1}})).action,'replay'); await assert.rejects(()=>j.prepare({stepKey:'build:1',idempotencyKey:'i',input:{a:2}}),/IDEMPOTENCY_CONFLICT/);
  const q=await j.prepare({stepKey:'build:2',idempotencyKey:'j',input:{b:1}}); await j.begin({stepKey:'build:2',idempotencyKey:'j',inputSha256:q.inputSha256,attemptCount:1,maxAttempts:3,leaseExpiresAt:'2026-08-28T23:59:00Z'});
  assert.equal((await j.prepare({stepKey:'build:2',idempotencyKey:'j',input:{b:1}})).reason,'LEASE_EXPIRED_OUTCOME_UNKNOWN');
});

test('authorized repair uses distinct workspace, budgets changes, rebuilds, and cleans up', async () => {
  const destroyed=[]; const c=createRepairController({buildJobId:uuid(9),sourceDigest:'a'.repeat(64),budget:{maxAttempts:1,maxChangedFiles:2,maxChangedBytes:100,maxCostCents:5}});
  const r=await executeRepairAttempt({controller:c,failureClass:'compile',authorizationId:'auth-repair',estimatedCostCents:2,changedFiles:[{path:'src/a.js',operation:'modify',sizeBytes:5}],createWorkspace:async({workspaceKey})=>({root:`/sandbox/${workspaceKey}`}),applyChanges:async()=>({appliedCount:1}),rebuild:async()=>({status:'completed',manifestSha256:'b'.repeat(64)}),destroyWorkspace:async({workspaceKey})=>destroyed.push(workspaceKey)});
  assert.equal(r.status,'completed'); assert.match(r.workspaceKey,/:repair:1$/); assert.deepEqual(destroyed,[r.workspaceKey]); assert.throws(()=>c.authorize({failureClass:'compile',authorizationId:'auth-2',changedFiles:[]}),/REPAIR_ATTEMPT_BUDGET_EXCEEDED/);
});

test('admission, health, crash recovery, and orphan cleanup are fail closed', () => {
  const a=createAdmissionController({maxGlobal:2,maxPerOrganization:1,maxPerProject:1,minFreeDiskBytes:100,minFreeMemoryBytes:100}); const job={organizationId:'o',projectId:'p'};
  assert.equal(a.decide({job,snapshot:{...snapshot,freeDiskBytes:1000,freeMemoryBytes:1000}}).admitted,true); assert.equal(a.decide({job,snapshot:{...snapshot,freeDiskBytes:50,freeMemoryBytes:1000}}).reason,'DISK_PRESSURE');
  assert.equal(createWorkerHealthSnapshot({workerIdentity:'worker-d',activeJobs:1,capacity:2}).ready,true);
  const now=new Date('2026-08-29T00:00:00Z'); assert.equal(classifyBuildJobRecovery({status:'claimed',lease_expires_at:'2026-08-28T23:59:00Z'},now).action,'requeue'); assert.equal(classifyBuildJobRecovery({status:'running',lease_expires_at:'2026-08-28T23:59:00Z'},now).reason,'LEASE_EXPIRED_OUTCOME_UNKNOWN');
  assert.deepEqual(orphanSandboxCleanupPlan({sandboxes:[{id:'s1',buildJobId:'j1'},{id:'s2',buildJobId:'j2'}],liveBuildJobIds:['j2']}),[{sandboxId:'s1',buildJobId:'j1',action:'destroy'}]);
});

test('managed build checkpoints, redacts scoped credentials, heartbeats, releases, and replays', async () => {
  const s=store(); const journal=createDurableStepJournal({store:s}); const calls=[]; const released=[]; let executions=0;
  const control={leaseSeconds:300,claim:async()=>calls.push('claim'),heartbeat:async()=>calls.push('heartbeat'),cancellationRequested:async()=>false,checkpoint:async e=>calls.push(e.stage)};
  const credentials=createCredentialLeaseManager({resolveLease:async r=>({ref:r,scope:'build',credentialClass:'temporary_scoped',expiresAt:new Date(Date.now()+60000).toISOString(),environment:{TEMP_BUILD_KEY:'secret'}}),releaseLease:async r=>released.push(r)});
  const args={request:req(1,['lease-1']),leaseToken:'lease-token-1234567890',controlPlane:control,admissionController:createAdmissionController(),admissionSnapshot:snapshot,journal,credentialManager:credentials,execute:async({environment,credentialValues,eventSink})=>{executions++;assert.equal(environment.TEMP_BUILD_KEY,'secret');assert.deepEqual(credentialValues,['secret']);await eventSink({stage:'building',detail:{safe:true}});return{status:'completed',manifestSha256:'c'.repeat(64)}}};
  assert.equal((await executeManagedBuild(args)).status,'completed'); assert.deepEqual(released,['lease-1']); assert.ok(calls.includes('building')); assert.equal((await executeManagedBuild(args)).status,'replayed'); assert.equal(executions,1);
});

test('managed build isolates concurrent projects and observes mid-run cancellation', async () => {
  const make=(n)=>({journal:createDurableStepJournal({store:store()}),credentialManager:createCredentialLeaseManager({resolveLease:async r=>({ref:r,scope:`project:${n}`,credentialClass:'temporary_scoped',expiresAt:new Date(Date.now()+60000).toISOString(),environment:{PROJECT_EPHEMERAL:`secret-${n}`}})}),controlPlane:{leaseSeconds:300,claim:async()=>{},heartbeat:async()=>{},cancellationRequested:async()=>false,checkpoint:async()=>{}}});
  const a=make(1),b=make(2); const run=(n,r)=>executeManagedBuild({request:req(n,[`l-${n}`]),leaseToken:`lease-${n}-1234567890123456`,admissionController:createAdmissionController(),admissionSnapshot:snapshot,...r,execute:async({environment})=>({status:'completed',seen:environment.PROJECT_EPHEMERAL})});
  const [ra,rb]=await Promise.all([run(1,a),run(2,b)]); assert.equal(ra.seen,'secret-1'); assert.equal(rb.seen,'secret-2');
  let polls=0,aborted=false; const result=await executeManagedBuild({request:req(7),leaseToken:'lease-token-1234567890',heartbeatIntervalMs:5,controlPlane:{leaseSeconds:300,claim:async()=>{},heartbeat:async()=>{},cancellationRequested:async()=>++polls>=2,checkpoint:async()=>{}},admissionController:createAdmissionController(),admissionSnapshot:snapshot,journal:createDurableStepJournal({store:store()}),credentialManager:createCredentialLeaseManager({resolveLease:async()=>{throw new Error('unused')}}),execute:({signal})=>new Promise(resolve=>signal.addEventListener('abort',()=>{aborted=true;resolve({status:'cancelled',failureClass:'cancelled'})},{once:true}))});
  assert.equal(result.status,'cancelled'); assert.equal(aborted,true);
});
