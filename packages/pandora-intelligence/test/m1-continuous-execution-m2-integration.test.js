
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { runContinuousExecution } = require('../src/runtime/continuous-executor.js');
const { deriveActivityProjection } = require('../../pandora-activity-theatre');

function resolution() {
  return { contractVersion:'pandora-intent-capability-resolution-v1', intent:'research', actionMode:'read_only', requestedOutcome:'Verify the result.', riskAuthority:{resolverGrantsAuthority:false}, modelRoutingConstraints:{providerPreference:null,modelPreference:null,modelSelectionOwner:'M3'} };
}
function projectWithM2({ jobId, verification }) {
  const occurredAt = '2026-09-14T06:00:00+08:00';
  const admittedAt = '2026-09-14T06:00:01+08:00';
  return deriveActivityProjection({
    schemaVersion:1,eventId:'evt-m1-result-1',jobId,sequence:1,writerEpoch:1,admittedBy:'pandora-m1-runtime',admissionMode:'online',state:'result',
    message:'Request completed and verified.',occurredAt,admittedAt,
    provenance:{sourceType:'runtime',sourceId:'pandora-m1-runtime',sourceEventId:'runtime-verify-1',observedAt:occurredAt},
    evidence:[{type:'verification_receipt',relation:'verification',ref:verification.verificationReceiptRef}],
    domain:'research',capability:'knowledge.research',executionId:'exec-m1-result-1',
    outcome:{summary:verification.summary||'Outcome verified.',physicalDevice:false},
  });
}

test('M1 terminal result is accepted through the real M2 Activity Theatre projector with exact verification evidence', async () => {
  const result=await runContinuousExecution({jobId:'job-m2-integration',resolution:resolution()},{
    reason(){return{kind:'verify',decisionRef:'reason://verify'};},
    verify(){return{verified:true,verificationReceiptRef:'verification://receipt-1',summary:'Outcome verified.',progressMade:true,retryable:false};},
    projectResult:projectWithM2,
  });
  assert.equal(result.status,'result');
  assert.equal(result.activityProjection.state,'result');
  assert.deepEqual(result.activityProjection.evidenceRefs,[{type:'verification_receipt',relation:'verification',ref:'verification://receipt-1'}]);
});
