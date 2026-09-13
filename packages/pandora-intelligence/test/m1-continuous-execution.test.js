'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  CONTINUOUS_EXECUTION_CONTRACT_VERSION,
  runContinuousExecution,
} = require('../src/runtime/continuous-executor.js');

const resolution = (intent='research', actionMode='read_only') => ({
  contractVersion:'pandora-intent-capability-resolution-v1',
  intent,
  actionMode,
  requestedOutcome:'Complete the requested outcome.',
  riskAuthority:{resolverGrantsAuthority:false},
  modelRoutingConstraints:{providerPreference:null,modelPreference:null,modelSelectionOwner:'M3'},
});
const readAction = (id, capability='knowledge.research') => ({actionId:id,capability,effect:'read_only'});
const writeAction = (id='change-1', key='idem-1', scope='authority://owner/project-1') => ({
  actionId:id,
  capability:'repository.write',
  effect:'state_change',
  authorityScopeRef:scope,
  idempotencyKey:key,
});
const actOk = (ref) => ({status:'succeeded',receiptRef:ref});
const observed = (ref, progressMade=true) => ({observationRef:ref,effectState:'observed',progressMade});
const applied = (ref, progressMade=true) => ({observationRef:ref,effectState:'applied',progressMade});
const verifyOk = (ref='verify://done') => ({verified:true,verificationRef:ref,summary:'Outcome verified.'});


test('continuous runtime performs multiple read actions and verifies without another user prompt', async () => {
  const calls=[];
  const result=await runContinuousExecution({jobId:'job-read-1',resolution:resolution('research')},{
    reason(view){calls.push(`reason:${view.iteration}`);if(view.iteration===1)return{kind:'act',decisionRef:'reason://1',action:readAction('read-1')};if(view.iteration===2)return{kind:'act',decisionRef:'reason://2',action:readAction('read-2')};return{kind:'verify',decisionRef:'reason://3'};},
    act(action){calls.push(`act:${action.actionId}`);return actOk(`tool://${action.actionId}`);},
    observe({action}){calls.push(`observe:${action.actionId}`);return observed(`readback://${action.actionId}`);},
    verify(){calls.push('verify');return verifyOk();},
  });
  assert.equal(result.contractVersion,CONTINUOUS_EXECUTION_CONTRACT_VERSION);
  assert.equal(result.status,'result');
  assert.equal(result.verified,true);
  assert.equal(result.iterations,3);
  assert.deepEqual(calls,['reason:1','act:read-1','observe:read-1','reason:2','act:read-2','observe:read-2','reason:3','verify']);
  assert.deepEqual(result.evidence.map(x=>x.phase),['reason','act','observe','reason','act','observe','reason','verify']);
});

test('state-changing action requires external authority and provider/runtime readback before verification', async () => {
  let authorized=0, acted=0, observedCount=0;
  const result=await runContinuousExecution({jobId:'job-write-1',resolution:resolution('coding_building','state_change')},{
    reason(view){return view.iteration===1?{kind:'act',decisionRef:'reason://write',action:writeAction()}:{kind:'verify',decisionRef:'reason://verify'};},
    authorize(action){authorized++;assert.equal(action.effect,'state_change');return{decision:'standing_authorized',decisionRef:'policy://decision-1',policyRef:'policy://standing-authority-v1'};},
    act(){acted++;return actOk('github://commit-1');},
    observe(){observedCount++;return applied('github://readback-1');},
    verify(){return verifyOk('verification://write-1');},
  });
  assert.equal(result.status,'result');
  assert.equal(authorized,1);assert.equal(acted,1);assert.equal(observedCount,1);
  assert.deepEqual(result.evidence.map(x=>x.phase),['reason','authorize','act','observe','reason','verify']);
});

test('ambiguous state-changing effect is read back and blocks rather than blindly retrying', async () => {
  let acted=0, observedCount=0;
  const result=await runContinuousExecution({jobId:'job-ambiguous-1',resolution:resolution('communication','state_change')},{
    reason(){return{kind:'act',decisionRef:'reason://send',action:writeAction('send-1','idem-send-1','authority://message/send')};},
    authorize(){return{decision:'standing_authorized',decisionRef:'policy://send',policyRef:'policy://standing-authority-v1'};},
    act(){acted++;return{status:'ambiguous',receiptRef:'provider://ambiguous-1',retryable:true};},
    observe(){observedCount++;return{observationRef:'provider://readback-unknown',effectState:'unknown',progressMade:false,retryable:true};},
    verify(){throw new Error('must not verify ambiguous unresolved effect');},
  });
  assert.equal(result.status,'blocked');
  assert.equal(result.blocker.reasonCode,'ambiguous_effect_unresolved');
  assert.equal(acted,1);assert.equal(observedCount,1);
});

test('safe state-change retry reuses the same action id, authority scope and idempotency identity', async () => {
  let attempt=0;
  const action=writeAction('deploy-1','idem-deploy-1','authority://deploy/preview');
  const result=await runContinuousExecution({jobId:'job-retry-1',resolution:resolution('coding_building','state_change')},{
    reason(view){if(view.iteration<=2)return{kind:'act',decisionRef:`reason://attempt-${view.iteration}`,action};return{kind:'verify',decisionRef:'reason://verify'};},
    authorize(){return{decision:'standing_authorized',decisionRef:`policy://allow-${attempt+1}`,policyRef:'policy://standing-authority-v1'};},
    act(){attempt++;return attempt===1?{status:'failed',receiptRef:'provider://attempt-1',retryable:true}:actOk('provider://attempt-2');},
    observe(){return attempt===1?{observationRef:'readback://not-applied',effectState:'not_applied',progressMade:true,retryable:true}:applied('readback://applied');},
    verify(){return verifyOk('verify://deploy');},
  });
  assert.equal(result.status,'result');
  assert.equal(attempt,2);
});

test('state-change retry with a changed idempotency key fails closed before duplicate side effect', async () => {
  let acted=0;
  const result=await runContinuousExecution({jobId:'job-retry-bad-key',resolution:resolution('coding_building','state_change')},{
    reason(view){return{kind:'act',decisionRef:`reason://${view.iteration}`,action:writeAction('change-1',view.iteration===1?'idem-original':'idem-new')};},
    authorize(){return{decision:'standing_authorized',decisionRef:'policy://allow',policyRef:'policy://standing-authority-v1'};},
    act(){acted++;return{status:'failed',receiptRef:`provider://attempt-${acted}`,retryable:true};},
    observe(){return{observationRef:`readback://attempt-${acted}`,effectState:'not_applied',progressMade:true,retryable:true};},
    verify(){throw new Error('not reached');},
  });
  assert.equal(result.status,'blocked');
  assert.equal(result.blocker.reasonCode,'idempotency_identity_changed');
  assert.equal(acted,1);
});

test('real needs-approval policy boundary stops before action execution', async () => {
  let acted=false;
  const result=await runContinuousExecution({jobId:'job-approval-1',resolution:resolution('communication','state_change')},{
    reason(){return{kind:'act',decisionRef:'reason://send',action:writeAction('send-1','idem-1','authority://external-message')};},
    authorize(){return{decision:'needs_approval',decisionRef:'policy://needs-approval-1',policyRef:'policy://standing-authority-v1',summary:'External commitment requires approval.'};},
    act(){acted=true;return actOk('should-not-run');},
    observe(){return applied('should-not-run');},
    verify(){return verifyOk();},
  });
  assert.equal(result.status,'needs_you');
  assert.equal(result.blocker.reasonCode,'authorization_required');
  assert.equal(acted,false);
});

test('authoritative deny is blocked and never represented as Needs You', async () => {
  const result=await runContinuousExecution({jobId:'job-deny-1',resolution:resolution('device_operations','state_change')},{
    reason(){return{kind:'act',decisionRef:'reason://device',action:writeAction('device-1','idem-device-1','authority://device/protected')};},
    authorize(){return{decision:'deny',decisionRef:'policy://deny-1',policyRef:'policy://protected-app-v1',summary:'Protected operation is denied.'};},
    act(){throw new Error('must not execute denied action');},observe(){throw new Error('must not observe denied action');},verify(){throw new Error('must not verify');},
  });
  assert.equal(result.status,'blocked');
  assert.equal(result.blocker.reasonCode,'policy_denied');
});

test('accepted cancellation stops before the next action', async () => {
  let acted=0;
  const result=await runContinuousExecution({jobId:'job-cancel-1',resolution:resolution('files')},{
    reason(){return{kind:'act',decisionRef:'reason://read',action:readAction(`read-${acted+1}`,'files.read')};},
    act(){acted++;return actOk(`file://receipt-${acted}`);},
    observe(){return observed(`file://observation-${acted}`);},
    verify(){return verifyOk();},
    control({iteration,phase}){return iteration===2&&phase==='before_reason'?{cancelled:true,controlRef:'control://cancel-1'}:{cancelled:false};},
  });
  assert.equal(result.status,'cancelled');
  assert.equal(acted,1);
  assert.equal(result.evidence.at(-1).phase,'control');
});

test('repeated cycles with no observed progress fail closed instead of looping forever', async () => {
  let n=0;
  const result=await runContinuousExecution({jobId:'job-no-progress',resolution:resolution(),maxNoProgressIterations:2,maxIterations:10},{
    reason(){n++;return{kind:'act',decisionRef:`reason://${n}`,action:readAction(`read-${n}`)};},
    act(action){return actOk(`read://${action.actionId}`);},
    observe({action}){return observed(`observation://${action.actionId}`,false);},
    verify(){return verifyOk();},
  });
  assert.equal(result.status,'failed');
  assert.equal(result.blocker.reasonCode,'no_progress');
  assert.equal(result.iterations,2);
});

test('reasoning cannot self-declare completion; only verifier can produce result', async () => {
  let verificationCount=0;
  const result=await runContinuousExecution({jobId:'job-verify-loop',resolution:resolution('general_assistance','no_action'),maxNoProgressIterations:3},{
    reason(){return{kind:'verify',decisionRef:'reason://claims-done'};},
    act(){throw new Error('no action expected');},
    observe(){throw new Error('no observation expected');},
    verify(){verificationCount++;return verificationCount===1?{verified:false,verificationRef:'verify://not-yet',summary:'Evidence incomplete.',retryable:true,progressMade:true}:verifyOk('verify://real-result');},
  });
  assert.equal(result.status,'result');
  assert.equal(result.verified,true);
  assert.equal(verificationCount,2);
});

test('runtime stays capability-neutral across non-builder intent domains', async () => {
  for(const intent of ['communication','research','files','device_operations','business','travel','scheduling','future_capability','general_assistance']){
    const result=await runContinuousExecution({jobId:`job-${intent.replace('_','-')}`,resolution:resolution(intent,'read_only')},{
      reason(){return{kind:'verify',decisionRef:`reason://${intent}`};},act(){throw new Error('not reached');},observe(){throw new Error('not reached');},verify(){return verifyOk(`verify://${intent}`);},
    });
    assert.equal(result.status,'result',intent);
  }
});



test('reasoning cannot widen the resolver effect class into a mutation', async () => {
  let acted=false;
  const result=await runContinuousExecution({jobId:'job-effect-widen',resolution:resolution('research','read_only')},{
    reason(){return{kind:'act',decisionRef:'reason://bad-write',action:writeAction('bad-write-1','idem-bad-1','authority://should-not-expand')};},
    authorize(){throw new Error('authority adapter must not be reached for widened effect');},
    act(){acted=true;return actOk('should-not-run');},
    observe(){return applied('should-not-run');},
    verify(){return verifyOk();},
  });
  assert.equal(result.status,'blocked');
  assert.equal(result.blocker.reasonCode,'effect_class_widened');
  assert.equal(acted,false);
});

test('reasoning receives an immutable resolution so model routing/privacy constraints cannot be widened in place', async () => {
  const resolved=resolution('files','read_only');
  resolved.modelRoutingConstraints.allowedExecutionBoundaries=['device','pandora_trusted_cloud'];
  const result=await runContinuousExecution({jobId:'job-immutable-resolution',resolution:resolved},{
    reason(view){
      assert.throws(()=>view.resolution.modelRoutingConstraints.allowedExecutionBoundaries.push('external_provider'),TypeError);
      return{kind:'verify',decisionRef:'reason://immutable'};
    },
    act(){throw new Error('not reached');},observe(){throw new Error('not reached');},verify(){return verifyOk('verify://immutable');},
  });
  assert.equal(result.status,'result');
});

test('evidence references reject credential-like material before it can enter runtime receipts', async () => {
  await assert.rejects(()=>runContinuousExecution({jobId:'job-secret-guard',resolution:resolution()},{
    reason(){return{kind:'verify',decisionRef:'Authorization: Bearer secret-secret-secret'};},act(){throw new Error('not reached');},observe(){throw new Error('not reached');},verify(){return verifyOk();},
  }),/credential-like material/);
});
