
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { CONTINUOUS_EXECUTION_CONTRACT_VERSION, runContinuousExecution } = require('../src/runtime/continuous-executor.js');

const resolution = (intent='research', actionMode='read_only') => ({
  contractVersion:'pandora-intent-capability-resolution-v1', intent, actionMode,
  requestedOutcome:'Complete the requested outcome.', riskAuthority:{resolverGrantsAuthority:false},
  modelRoutingConstraints:{providerPreference:null,modelPreference:null,modelSelectionOwner:'M3'},
});
const readAction = (id, capability='knowledge.research') => ({actionId:id,capability,effect:'read_only'});
const writeAction = (id='change-1', key='idem-1') => ({actionId:id,capability:'repository.write',effect:'state_change',idempotencyKey:key,input:{tool:'repo.write'}});
const readOk = (ref) => ({status:'succeeded',receiptRef:ref,retryable:false});
const observed = (ref, progressMade=true) => ({observationRef:ref,effectState:'observed',progressMade,retryable:false});
const verification = (verified=true, ref='verify://done', retryable=false, progressMade=true) => ({verified,verificationReceiptRef:ref,summary:verified?'Outcome verified.':'Not verified.',retryable,progressMade});
const projection = (jobId, ref) => ({projectionVersion:1,eventId:'evt-result-1',jobId,sequence:9,state:'result',message:'Request completed and verified.',occurredAt:'2026-09-14T06:00:00+08:00',admittedAt:'2026-09-14T06:00:01+08:00',domain:'research',capability:'knowledge.research',executionId:'exec-1',source:{sourceType:'runtime',sourceId:'m1-runtime',sourceEventId:'verify-event-1',observedAt:'2026-09-14T06:00:00+08:00'},evidenceRefs:[{type:'verification_receipt',relation:'verification',ref}],blocker:null,outcome:{summary:'Outcome verified.',physicalDevice:false}});
function successfulProjector({jobId,verification:v}) { return projection(jobId, v.verificationReceiptRef); }

test('multi-step reads continue without another user prompt and terminate only after projected verification', async () => {
  const calls=[];
  const result=await runContinuousExecution({jobId:'job-read-1',resolution:resolution()},{
    reason(view){calls.push(`reason:${view.iteration}`);if(view.iteration===1)return{kind:'act',decisionRef:'reason://1',action:readAction('read-1')};if(view.iteration===2)return{kind:'act',decisionRef:'reason://2',action:readAction('read-2')};return{kind:'verify',decisionRef:'reason://3'};},
    actRead(action){calls.push(`act:${action.actionId}`);return readOk(`tool://${action.actionId}`);},
    observeRead({action}){calls.push(`observe:${action.actionId}`);return observed(`readback://${action.actionId}`);},
    verify(){calls.push('verify');return verification();},
    projectResult(input){calls.push('project');return successfulProjector(input);},
  });
  assert.equal(result.contractVersion,CONTINUOUS_EXECUTION_CONTRACT_VERSION);
  assert.equal(result.status,'result'); assert.equal(result.verified,true); assert.equal(result.iterations,3);
  assert.deepEqual(calls,['reason:1','act:read-1','observe:read-1','reason:2','act:read-2','observe:read-2','reason:3','verify','project']);
  assert.equal(result.activityProjection.state,'result');
});

test('legacy standalone authorize/act/observe path is rejected', async () => {
  await assert.rejects(() => runContinuousExecution({jobId:'job-legacy',resolution:resolution('coding_building','state_change')},{
    reason(){return{kind:'verify',decisionRef:'reason://verify'};}, verify(){return verification(false,null,false,false);},
    authorize(){return{};}, act(){return{};}, observe(){return{};},
  }), /legacy authorize\/act\/observe adapters are forbidden/);
});

test('state changes execute only through governed M3 seam and require provider readback', async () => {
  let governed=0;
  const result=await runContinuousExecution({jobId:'job-write-1',resolution:resolution('coding_building','state_change')},{
    reason(view){return view.iteration===1?{kind:'act',decisionRef:'reason://write',action:writeAction()}:{kind:'verify',decisionRef:'reason://verify'};},
    executeGoverned(action){governed++;assert.equal(action.effect,'state_change');return{state:'completed',receiptRef:'gateway://receipt-1',readbackRef:'provider://readback-1',effectState:'applied',progressMade:true,retryable:false};},
    verify(){return verification(true,'verify://write');}, projectResult:successfulProjector,
  });
  assert.equal(result.status,'result'); assert.equal(governed,1);
  assert.deepEqual(result.evidence.map(x=>x.phase),['reason','governed_execute','readback','reason','verify']);
});

test('state change cannot execute when governed M3 seam is unavailable', async () => {
  const result=await runContinuousExecution({jobId:'job-no-m3',resolution:resolution('communication','state_change')},{
    reason(){return{kind:'act',decisionRef:'reason://send',action:writeAction('send-1','idem-send')};}, verify(){return verification();}, projectResult:successfulProjector,
  });
  assert.equal(result.status,'blocked'); assert.equal(result.blocker.reasonCode,'governed_executor_unavailable');
});

test('M3 needs_approval maps to Needs You without M1 granting authority', async () => {
  const result=await runContinuousExecution({jobId:'job-needs-you',resolution:resolution('communication','state_change')},{
    reason(){return{kind:'act',decisionRef:'reason://send',action:writeAction('send-1','idem-send')};},
    executeGoverned(){return{state:'needs_approval',receiptRef:'policy://decision-1',readbackRef:null,effectState:null,progressMade:false,retryable:false,summary:'Approval required.',policyRef:'policy://standing-authority-v1'};},
    verify(){return verification();}, projectResult:successfulProjector,
  });
  assert.equal(result.status,'needs_you'); assert.equal(result.blocker.reasonCode,'authorization_required');
});

test('M3 deny maps to blocked and never Needs You', async () => {
  const result=await runContinuousExecution({jobId:'job-deny',resolution:resolution('device_operations','state_change')},{
    reason(){return{kind:'act',decisionRef:'reason://device',action:writeAction('device-1','idem-device')};},
    executeGoverned(){return{state:'denied',receiptRef:'policy://deny-1',readbackRef:null,effectState:null,progressMade:false,retryable:false,summary:'Protected boundary.',policyRef:'policy://device'};},
    verify(){return verification();}, projectResult:successfulProjector,
  });
  assert.equal(result.status,'blocked'); assert.equal(result.blocker.reasonCode,'policy_denied');
});

test('ambiguous governed mutation stops for authoritative reconciliation and never retries blindly', async () => {
  let calls=0;
  const result=await runContinuousExecution({jobId:'job-ambiguous',resolution:resolution('communication','state_change')},{
    reason(){return{kind:'act',decisionRef:'reason://send',action:writeAction('send-1','idem-send')};},
    executeGoverned(){calls++;return{state:'verification_required',receiptRef:'provider://ambiguous-1',readbackRef:'provider://readback-unknown',effectState:'unknown',progressMade:false,retryable:true,summary:'Effect ambiguous.'};},
    verify(){throw new Error('must not verify unresolved ambiguous mutation');}, projectResult:successfulProjector,
  });
  assert.equal(result.status,'blocked'); assert.equal(result.blocker.reasonCode,'ambiguous_effect_verification_required'); assert.equal(calls,1);
});

test('local replay invariant cannot replace M3 durable idempotency but blocks changed retry identity', async () => {
  let calls=0;
  const result=await runContinuousExecution({jobId:'job-retry-id',resolution:resolution('coding_building','state_change')},{
    reason(view){return{kind:'act',decisionRef:`reason://${view.iteration}`,action:writeAction('change-1',view.iteration===1?'idem-original':'idem-new')};},
    executeGoverned(){calls++;return{state:'failed',receiptRef:'gateway://failed-1',readbackRef:'provider://not-applied',effectState:'not_applied',progressMade:true,retryable:true};},
    verify(){return verification();}, projectResult:successfulProjector,
  });
  assert.equal(result.status,'blocked'); assert.equal(result.blocker.reasonCode,'idempotency_identity_changed'); assert.equal(calls,1);
});

test('verified=true without verification receipt cannot fabricate Result', async () => {
  const result=await runContinuousExecution({jobId:'job-no-receipt',resolution:resolution()},{
    reason(){return{kind:'verify',decisionRef:'reason://verify'};}, verify(){return{verified:true,verificationReceiptRef:null,summary:'Done',progressMade:true,retryable:false};}, projectResult:successfulProjector,
  });
  assert.equal(result.status,'blocked'); assert.equal(result.blocker.reasonCode,'verification_receipt_missing');
});

test('verified receipt without M2 projector cannot fabricate Result', async () => {
  const result=await runContinuousExecution({jobId:'job-no-projector',resolution:resolution()},{ reason(){return{kind:'verify',decisionRef:'reason://verify'};}, verify(){return verification();} });
  assert.equal(result.status,'blocked'); assert.equal(result.blocker.reasonCode,'activity_projection_unavailable');
});

test('M2 projection must contain exact verification_receipt relation', async () => {
  await assert.rejects(() => runContinuousExecution({jobId:'job-bad-projection',resolution:resolution()},{
    reason(){return{kind:'verify',decisionRef:'reason://verify'};}, verify(){return verification(true,'verify://exact');}, projectResult(){return projection('job-bad-projection','verify://wrong');},
  }), /exact overall-job verification receipt/);
});

test('accepted cancellation stops the loop', async () => {
  let reasonCalls=0;
  const result=await runContinuousExecution({jobId:'job-cancel',resolution:resolution()},{
    reason(){reasonCalls++;return{kind:'act',decisionRef:'reason://read',action:readAction('read-1')};}, actRead(){return readOk('tool://read');}, observeRead(){return observed('readback://read');}, verify(){return verification();}, projectResult:successfulProjector,
    control({phase}){return{cancelled:phase==='before_reason',controlRef:'control://cancel-1'};},
  });
  assert.equal(result.status,'cancelled'); assert.equal(reasonCalls,0);
});

test('no-progress loop fails closed', async () => {
  const result=await runContinuousExecution({jobId:'job-no-progress',resolution:resolution(),maxNoProgressIterations:2},{
    reason(view){return{kind:'act',decisionRef:`reason://${view.iteration}`,action:readAction(`read-${view.iteration}`)};}, actRead(action){return readOk(`tool://${action.actionId}`);}, observeRead({action}){return observed(`readback://${action.actionId}`,false);}, verify(){return verification();}, projectResult:successfulProjector,
  });
  assert.equal(result.status,'failed'); assert.equal(result.blocker.reasonCode,'no_progress');
});

test('reasoning cannot widen read-only resolution into mutation', async () => {
  let governed=false;
  const result=await runContinuousExecution({jobId:'job-widen',resolution:resolution('research','read_only')},{ reason(){return{kind:'act',decisionRef:'reason://bad',action:writeAction()};}, executeGoverned(){governed=true;return{};}, verify(){return verification();}, projectResult:successfulProjector });
  assert.equal(result.status,'blocked'); assert.equal(result.blocker.reasonCode,'effect_class_widened'); assert.equal(governed,false);
});

test('resolution is deeply immutable while reasoning executes', async () => {
  const inputResolution=resolution('business','read_only'); inputResolution.nested={value:'original'};
  const result=await runContinuousExecution({jobId:'job-freeze',resolution:inputResolution},{
    reason(view){assert.throws(()=>{view.resolution.nested.value='changed';},TypeError);return{kind:'verify',decisionRef:'reason://verify'};}, verify(){return verification();}, projectResult:successfulProjector,
  });
  assert.equal(result.status,'result'); assert.equal(inputResolution.nested.value,'original');
});

test('same executor remains domain-neutral rather than builder-first', async () => {
  for (const intent of ['communication','travel','business','scheduling','files','device_operations']) {
    const result=await runContinuousExecution({jobId:`job-${intent}`,resolution:resolution(intent,'read_only')},{
      reason(view){return view.iteration===1?{kind:'act',decisionRef:`reason://${intent}`,action:readAction(`read-${intent}`,`${intent}.read`)}:{kind:'verify',decisionRef:`reason://${intent}-verify`};}, actRead(action){return readOk(`tool://${action.actionId}`);}, observeRead({action}){return observed(`readback://${action.actionId}`);}, verify(){return verification(true,`verify://${intent}`);}, projectResult:successfulProjector,
    });
    assert.equal(result.status,'result',intent);
  }
});

test('credential-like material is rejected from evidence refs and summaries', async () => {
  await assert.rejects(() => runContinuousExecution({jobId:'job-secret',resolution:resolution()},{
    reason(){return{kind:'act',decisionRef:'reason://read',action:readAction('read-1')};}, actRead(){return readOk('Authorization: Bearer abcdefghijklmnopqrstuvwxyz');}, observeRead(){return observed('readback://x');}, verify(){return verification();}, projectResult:successfulProjector,
  }), /credential-like material/);
});
