'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const theatre = require('../packages/pandora-activity-theatre');
const {
ACTIVITY_EVENT_SCHEMA_VERSION,
ACTIVITY_EVENT_STATES,
ACTIVITY_EVIDENCE_TYPES,
TERMINAL_ACTIVITY_STATES,
normalizeActivityEvent,
validateActivityTimeline,
validateActivityReplay,
activityReplayCheckpoint,
} = theatre;
const evidence = (type='runtime_event', relation='source', ref='runtime://job-1/events/1') => ({ type, relation, ref });
const base = (overrides={}) => ({
schemaVersion: ACTIVITY_EVENT_SCHEMA_VERSION,
eventId: 'evt-1',
jobId: 'job-1',
sequence: 1,
writerEpoch: 1,
admittedBy: 'pandora-runtime-1',
admissionMode: 'online',
state: 'understanding',
message: 'Understanding your request',
occurredAt: '2026-09-13T03:06:00Z',
admittedAt: '2026-09-13T03:06:01Z',
provenance: {
sourceType: 'runtime',
sourceId: 'pandora-runtime-1',
sourceEventId: 'runtime-event-1',
observedAt: '2026-09-13T03:06:00.500Z',
},
evidence: [],
domain: 'communications',
capability: 'sms.resolve-recipient',
...overrides,
});
const at = (n) => `2026-09-13T03:06:${String(n).padStart(2,'0')}Z`;
const eventN = (n, overrides={}) => base({
eventId: `evt-${n}`,
sequence: n,
occurredAt: at(n),
admittedAt: at(n+1),
provenance: {
sourceType: 'runtime',
sourceId: 'pandora-runtime-1',
sourceEventId: `runtime-event-${n}`,
observedAt: at(n),
},
...overrides,
});
test('taxonomy matches M0-004 including paused/resuming', () => {
assert.deepEqual(ACTIVITY_EVENT_STATES, [
'understanding','planning','acting','checking','needs_you','retrying','fallback','verifying','paused','resuming','result','failed','cancelled'
]);
assert.deepEqual(TERMINAL_ACTIVITY_STATES, ['result','failed','cancelled']);
assert.ok(ACTIVITY_EVIDENCE_TYPES.includes('verification_receipt'));
assert.ok(ACTIVITY_EVIDENCE_TYPES.includes('user_control'));
});
test('requires writer epoch, admission writer and admittedAt', () => {
assert.throws(() => normalizeActivityEvent(base({writerEpoch:null})), /writerEpoch/);
assert.throws(() => normalizeActivityEvent(base({admittedBy:''})), /admittedBy/);
assert.throws(() => normalizeActivityEvent(base({admittedAt:null})), /admittedAt/);
});
test('admittedAt cannot precede occurredAt', () => {
assert.throws(() => normalizeActivityEvent(base({occurredAt:'2026-09-13T03:06:05Z', admittedAt:'2026-09-13T03:06:04Z'})), /cannot precede/);
});
test('occurrence timestamps need not be monotonic because sequence is canonical', () => {
const events = validateActivityTimeline([
eventN(1,{occurredAt:'2026-09-13T03:06:05Z', admittedAt:'2026-09-13T03:06:06Z'}),
eventN(2,{occurredAt:'2026-09-13T03:06:03Z', admittedAt:'2026-09-13T03:06:07Z'}),
]);
assert.equal(events.length,2);
});
test('requires sourceEventId or typed evidence', () => {
assert.throws(() => normalizeActivityEvent(base({provenance:{...base().provenance,sourceEventId:null}})), /typed evidence/);
const normalized = normalizeActivityEvent(base({
provenance:{...base().provenance,sourceEventId:null},
evidence:[evidence('provider_receipt','source','provider://receipt/1')],
}));
assert.equal(normalized.evidence[0].type,'provider_receipt');
});
test('typed evidence rejects unsupported type/relation and duplicates', () => {
assert.throws(() => normalizeActivityEvent(base({evidence:[evidence('mystery','source')]})), /unsupported evidence type/);
assert.throws(() => normalizeActivityEvent(base({evidence:[evidence('runtime_event','mystery')]})), /unsupported evidence relation/);
assert.throws(() => normalizeActivityEvent(base({evidence:[evidence(),evidence()]})), /duplicate/);
});
test('offline admission requires policy evidence', () => {
assert.throws(() => normalizeActivityEvent(base({admissionMode:'offline'})), /policy evidence/);
const normalized = normalizeActivityEvent(base({admissionMode:'offline', evidence:[evidence('policy_decision','policy','policy://epoch/1')]}));
assert.equal(normalized.admissionMode,'offline');
});
test('single writer per epoch and writer handoff epoch advance are enforced', () => {
assert.throws(() => validateActivityTimeline([
eventN(1),
eventN(2,{admittedBy:'edge-writer-2', writerEpoch:1}),
]), /single writer|handoff/);
const events = validateActivityTimeline([
eventN(1),
eventN(2,{admittedBy:'edge-writer-2', writerEpoch:2}),
]);
assert.equal(events[1].writerEpoch,2);
});
test('sequence gaps and duplicates fail closed', () => {
assert.throws(() => validateActivityTimeline([eventN(1), eventN(3)]), /sequence gap or duplicate/);
assert.throws(() => validateActivityTimeline([eventN(1), eventN(2,{eventId:'evt-1'})]), /duplicate eventId/);
});
test('replay continues exactly from known cursor', () => {
const events = validateActivityReplay([eventN(4), eventN(5)], {afterSequence:3, expectedJobId:'job-1'});
assert.equal(events[0].sequence,4);
assert.throws(() => validateActivityReplay([eventN(5)], {afterSequence:3}), /known cursor/);
assert.throws(() => validateActivityReplay([eventN(4,{jobId:'job-2'})], {afterSequence:3, expectedJobId:'job-1'}), /job identity mismatch/);
});
test('checkpoint preserves canonical identity', () => {
const checkpoint = activityReplayCheckpoint([eventN(1),eventN(2)]);
assert.deepEqual(checkpoint,{jobId:'job-1',sequence:2,eventId:'evt-2',writerEpoch:1});
});
test('Needs You requires a real standing-authority reason and exact action', () => {
assert.throws(() => normalizeActivityEvent(base({state:'needs_you'})), /blocker/);
assert.throws(() => normalizeActivityEvent(base({state:'needs_you',blocker:{reasonCode:'waiting_for_ci',reason:'Waiting',requiredAction:'Wait',approvalRequired:false}})), /unsupported blocker.reasonCode/);
const event = normalizeActivityEvent(base({state:'needs_you',blocker:{reasonCode:'authorization_required',reason:'Publishing crosses a production boundary.',requiredAction:'Approve or cancel publication.',approvalRequired:true,policyRef:'policy:standing-authority:v1'}}));
assert.equal(event.blocker.reasonCode,'authorization_required');
});
test('accepted pause requires user-control evidence and emits paused', () => {
const pauseEvidence = [evidence('user_control','accepted_control','control://pause/1')];
assert.throws(() => normalizeActivityEvent(base({state:'paused',control:{type:'pause',requestId:'ctl-1',acceptedAt:at(1)}})), /user_control evidence/);
const event = normalizeActivityEvent(base({state:'paused',evidence:pauseEvidence,control:{type:'pause',requestId:'ctl-1',acceptedAt:at(1)}}));
assert.equal(event.state,'paused');
assert.throws(() => normalizeActivityEvent(base({state:'acting',evidence:pauseEvidence,control:{type:'pause',requestId:'ctl-1',acceptedAt:at(1)}})), /must emit paused/);
});
test('authoritative runtime pause is allowed without voluntary control', () => {
const event = normalizeActivityEvent(base({state:'paused',evidence:[evidence('runtime_event','authoritative_pause','runtime://pause/thermal')]}));
assert.equal(event.control,null);
});
test('resuming requires accepted resume and prior paused timeline state', () => {
const ctl = [evidence('user_control','accepted_control','control://resume/1')];
const resume = eventN(2,{state:'resuming',evidence:ctl,control:{type:'resume',requestId:'ctl-2',acceptedAt:at(2)}});
assert.throws(() => validateActivityTimeline([eventN(1),resume]), /prior paused/);
const pause = eventN(1,{state:'paused',evidence:[evidence('runtime_event','authoritative_pause','runtime://pause/1')]});
assert.equal(validateActivityTimeline([pause,resume])[1].state,'resuming');
});
test('cancelled requires accepted cancel or authoritative cancellation evidence', () => {
assert.throws(() => normalizeActivityEvent(base({state:'cancelled'})), /cancelled requires/);
const ctl = [evidence('user_control','accepted_control','control://cancel/1')];
const event = normalizeActivityEvent(base({state:'cancelled',evidence:ctl,control:{type:'cancel',requestId:'ctl-cancel',acceptedAt:at(1)}}));
assert.equal(event.state,'cancelled');
const authoritative = normalizeActivityEvent(base({state:'cancelled',evidence:[evidence('runtime_event','authoritative_cancellation','runtime://cancel/deadline')]}));
assert.equal(authoritative.state,'cancelled');
});
test('ambiguous control acceptance requires readback evidence', () => {
const ctl=[evidence('user_control','accepted_control','control://pause/1')];
assert.throws(() => normalizeActivityEvent(base({state:'paused',evidence:ctl,control:{type:'pause',requestId:'ctl-1',acceptedAt:at(1),acceptanceAmbiguous:true}})), /readback evidence/);
const e=normalizeActivityEvent(base({state:'paused',evidence:[...ctl,evidence('runtime_event','readback','runtime://controls/1/readback')],control:{type:'pause',requestId:'ctl-1',acceptedAt:at(1),acceptanceAmbiguous:true}}));
assert.equal(e.control.acceptanceAmbiguous,true);
});
test('retry requires prior attempt evidence and bounded authority reference', () => {
assert.throws(() => normalizeActivityEvent(base({state:'retrying',transition:{priorAttemptId:'attempt-1',priorAuthorityScopeRef:'authority://scope/1',authorityScopeRef:'authority://scope/1',consequential:false}})), /prior attempt evidence/);
const e=normalizeActivityEvent(base({state:'retrying',evidence:[evidence('provider_receipt','prior_attempt','provider://attempt/1')],transition:{priorAttemptId:'attempt-1',priorAuthorityScopeRef:'authority://scope/1',authorityScopeRef:'authority://scope/1',consequential:false}}));
assert.equal(e.transition.priorAttemptId,'attempt-1');
});
test('fallback requires prior attempt or capability evidence', () => {
assert.throws(() => normalizeActivityEvent(base({state:'fallback',transition:{priorAttemptId:'attempt-1',priorAuthorityScopeRef:'authority://scope/1',authorityScopeRef:'authority://scope/1',consequential:false}})), /prior attempt or capability/);
const e=normalizeActivityEvent(base({state:'fallback',evidence:[evidence('policy_decision','capability','capability://provider/b')],transition:{priorAttemptId:'attempt-1',priorAuthorityScopeRef:'authority://scope/1',authorityScopeRef:'authority://scope/1',consequential:false}}));
assert.equal(e.state,'fallback');
});
test('consequential retry/fallback requires idempotency identity', () => {
const ev=[evidence('provider_receipt','prior_attempt','provider://attempt/1')];
assert.throws(() => normalizeActivityEvent(base({state:'retrying',evidence:ev,transition:{priorAttemptId:'attempt-1',priorAuthorityScopeRef:'authority://scope/1',authorityScopeRef:'authority://scope/1',consequential:true}})), /idempotency identity/);
const e=normalizeActivityEvent(base({state:'retrying',evidence:ev,transition:{priorAttemptId:'attempt-1',priorAuthorityScopeRef:'authority://scope/1',authorityScopeRef:'authority://scope/1',consequential:true,priorIdempotencyKey:'idem-1',idempotencyKey:'idem-1'}}));
assert.equal(e.transition.idempotencyKey,'idem-1');
});
test('ambiguous retry/fallback requires provider/runtime readback', () => {
const ev=[evidence('provider_receipt','prior_attempt','provider://attempt/1')];
assert.throws(() => normalizeActivityEvent(base({state:'retrying',evidence:ev,transition:{priorAttemptId:'attempt-1',priorAuthorityScopeRef:'authority://scope/1',authorityScopeRef:'authority://scope/1',consequential:false,effectAmbiguous:true}})), /readback evidence/);
const e=normalizeActivityEvent(base({state:'retrying',evidence:[...ev,evidence('provider_receipt','readback','provider://attempt/1/readback')],transition:{priorAttemptId:'attempt-1',priorAuthorityScopeRef:'authority://scope/1',authorityScopeRef:'authority://scope/1',consequential:false,effectAmbiguous:true}}));
assert.equal(e.transition.effectAmbiguous,true);
});
test('retry/fallback authority scope cannot expand', () => {
const ev=[evidence('provider_receipt','prior_attempt','provider://attempt/1')];
assert.throws(() => normalizeActivityEvent(base({state:'retrying',evidence:ev,transition:{priorAttemptId:'attempt-1',priorAuthorityScopeRef:'authority://scope/1',authorityScopeRef:'authority://scope/2',consequential:false}})), /authority scope may not expand/);
});
test('consequential retry must reuse the prior idempotency identity', () => {
const ev=[evidence('provider_receipt','prior_attempt','provider://attempt/1')];
assert.throws(() => normalizeActivityEvent(base({state:'retrying',evidence:ev,transition:{priorAttemptId:'attempt-1',priorAuthorityScopeRef:'authority://scope/1',authorityScopeRef:'authority://scope/1',consequential:true,priorIdempotencyKey:'idem-1',idempotencyKey:'idem-2'}})), /reuse idempotency identity/);
});
test('Result requires overall-job verification evidence, not provider success alone', () => {
assert.throws(() => normalizeActivityEvent(base({state:'result',evidence:[evidence('provider_receipt','source','provider://ok')],outcome:{summary:'Provider said success.'}})), /overall-job verification/);
const e=normalizeActivityEvent(base({state:'result',evidence:[evidence('verification_receipt','verification','verification://job-1/final')],outcome:{summary:'Overall job outcome independently verified.'}}));
assert.equal(e.outcome.summary,'Overall job outcome independently verified.');
});
test('physical-device result requires physical device verification evidence', () => {
const verify=[evidence('verification_receipt','verification','verification://job-1/final')];
assert.throws(() => normalizeActivityEvent(base({state:'result',evidence:verify,outcome:{summary:'Phone action verified.',physicalDevice:true}})), /physical device verification evidence/);
const e=normalizeActivityEvent(base({state:'result',evidence:[...verify,evidence('device_event','verification','device://physical/receipt/1')],outcome:{summary:'Phone action verified on physical device.',physicalDevice:true}}));
assert.equal(e.outcome.physicalDevice,true);
});
test('Failed requires failure evidence', () => {
assert.throws(() => normalizeActivityEvent(base({state:'failed'})), /failure evidence/);
const e=normalizeActivityEvent(base({state:'failed',evidence:[evidence('runtime_event','failure','runtime://job-1/failure')]}));
assert.equal(e.state,'failed');
});
test('post-terminal events are rejected', () => {
const fail=eventN(1,{state:'failed',evidence:[evidence('runtime_event','failure','runtime://failure/1')]});
assert.throws(() => validateActivityTimeline([fail,eventN(2)]), /after a terminal state/);
});
test('schema rejects invented progress and secret/raw payload fields', () => {
for (const payload of [{fakePercent:50},{rawPrompt:'x'},{toolArgs:{}},{metadata:{}},{secret:'x'}]) {
assert.throws(() => normalizeActivityEvent(base(payload)), /not part of the canonical activity schema/);
}
});
test('credential-like material is rejected from public fields and typed refs', () => {
assert.throws(() => normalizeActivityEvent(base({message:'Authorization: Bearer abcdefghijklmnopqrstuvwxyz'})), /credential-like/);
assert.throws(() => normalizeActivityEvent(base({evidence:[evidence('runtime_event','source','https://user:password@example.test/evidence')]})), /credential-like/);
assert.throws(() => normalizeActivityEvent(base({executionId:'token:SecretValue1234'})), /credential-like/);
});
test('safe redacted status identifiers remain allowed', () => {
const e=normalizeActivityEvent(base({eventId:'token:expired',executionId:'private_key:redacted',message:'Provider status: token: expired; secret: unavailable; password = required.'}));
assert.equal(e.eventId,'token:expired');
});
test('impossible timestamps fail closed', () => {
assert.throws(() => normalizeActivityEvent(base({occurredAt:'2026-02-30T00:00:00Z'})), /offset-aware/);
assert.throws(() => normalizeActivityEvent(base({admittedAt:'2026-09-13T03:06:00+24:00'})), /offset-aware/);
});
test('plain-object boundaries reject prototypes throughout schema', () => {
assert.throws(() => normalizeActivityEvent(Object.create(base())), /event must be a plain object/);
assert.throws(() => normalizeActivityEvent(base({provenance:Object.create(base().provenance)})), /provenance must be a plain object/);
assert.throws(() => normalizeActivityEvent(base({evidence:[Object.create(evidence())]})), /evidence\[0\] must be a plain object/);
});
test('parent lineage remains privacy-safe and stable', () => {
const e=normalizeActivityEvent(base({parentEventId:'evt-parent-1'}));
assert.equal(e.parentEventId,'evt-parent-1');
assert.throws(() => normalizeActivityEvent(base({parentEventId:'api_key:SecretValue1234'})), /credential-like/);
});
