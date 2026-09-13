'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  ACTIVITY_PUBLIC_PROJECTION_VERSION,
  assertActivityMessageTruth,
  deriveActivityProjection,
  messageClaimsMeasurement,
  messageClaimsOverallResult,
  validateActivityProjection,
} = require('../packages/pandora-activity-theatre');

const sourceEvidence = (type='runtime_event', ref='runtime://job-1/events/1') => ({type, relation:'source', ref});
const verificationEvidence = () => ({type:'verification_receipt', relation:'verification', ref:'verification://job-1/final'});
const base = (overrides={}) => ({
  schemaVersion: 1,
  eventId: 'evt-1',
  jobId: 'job-1',
  sequence: 1,
  writerEpoch: 1,
  admittedBy: 'pandora-runtime-1',
  admissionMode: 'online',
  state: 'acting',
  message: 'Working on the requested action',
  occurredAt: '2026-09-13T03:06:00.000Z',
  admittedAt: '2026-09-13T03:06:01.000Z',
  provenance: {sourceType:'runtime', sourceId:'runtime-1', sourceEventId:'src-1', observedAt:'2026-09-13T03:06:00.500Z'},
  evidence: [],
  domain: 'general',
  capability: 'runtime.action',
  executionId: 'exec-1',
  parentEventId: null,
  control: null,
  transition: null,
  blocker: null,
  outcome: null,
  ...overrides,
});

test('detects measurable percentage, stage and count claims', () => {
  assert.equal(messageClaimsMeasurement('75% complete'), true);
  assert.equal(messageClaimsMeasurement('Stage 2 of 4'), true);
  assert.equal(messageClaimsMeasurement('3 of 10 files processed'), true);
  assert.equal(messageClaimsMeasurement('Working on the files'), false);
});

test('detects named or numeric stages without requiring an N-of-M form', () => {
  assert.equal(messageClaimsMeasurement('Stage 2'), true);
  assert.equal(messageClaimsMeasurement('Phase: Deploying'), true);
  assert.equal(messageClaimsMeasurement('Planning the request'), false);
});

test('model text alone cannot substantiate measurable progress', () => {
  const event = base({message:'75% complete', provenance:{...base().provenance, sourceType:'model'}});
  assert.throws(() => assertActivityMessageTruth(event), /requires runtime\/device\/provider\/ProjectOS\/tool source evidence/);
});

test('runtime/provider/device/tool source events may substantiate measurable progress', () => {
  for (const sourceType of ['runtime','provider','device','projectos','tool']) {
    const event = base({message:'Stage 2 of 4', provenance:{...base().provenance, sourceType}});
    assert.equal(assertActivityMessageTruth(event), event);
  }
});

test('typed source evidence can substantiate measurement even when model observed it', () => {
  const event = base({
    message:'3 of 10 files processed',
    provenance:{...base().provenance, sourceType:'model', sourceEventId:null},
    evidence:[sourceEvidence('provider_receipt','provider://build/1/progress')],
  });
  assert.equal(assertActivityMessageTruth(event), event);
});

test('policy and user-control evidence do not substantiate measurement', () => {
  for (const evidence of [
    {type:'policy_decision', relation:'policy', ref:'policy://1'},
    {type:'user_control', relation:'accepted_control', ref:'control://1'},
  ]) {
    const event = base({message:'50 percent complete', provenance:{...base().provenance, sourceType:'model', sourceEventId:null}, evidence:[evidence]});
    assert.throws(() => assertActivityMessageTruth(event), /requires runtime\/device\/provider\/ProjectOS\/tool source evidence/);
  }
});

test('overall completion claims require result state', () => {
  for (const message of ['Done.', 'Build is complete', 'The deployment was successful', 'Release completed']) {
    assert.equal(messageClaimsOverallResult(message), true);
    assert.throws(() => assertActivityMessageTruth(base({message})), /requires verified result state/);
  }
});

test('attempt-scoped and verification-in-progress language is not misclassified as overall result', () => {
  for (const message of ['Provider attempt succeeded; verifying overall job.', 'Checking whether deployment succeeded.', 'Verifying the final result.']) {
    assert.equal(messageClaimsOverallResult(message), false);
    assert.equal(assertActivityMessageTruth(base({message})).message, message);
  }
});

test('100% complete is both a measurement and an overall-result claim', () => {
  const event = base({message:'100% complete'});
  assert.throws(() => assertActivityMessageTruth(event), /verified result state/);
});

test('result outcome summary cannot invent unsupported measurable progress', () => {
  const event = base({
    state:'result',
    message:'Done.',
    provenance:{...base().provenance, sourceType:'model', sourceEventId:null},
    evidence:[verificationEvidence()],
    outcome:{summary:'75% complete', physicalDevice:false},
  });
  assert.throws(() => assertActivityMessageTruth(event), /outcome\.summary measurable progress/);
});

test('verified result may state overall completion', () => {
  const event = base({
    state:'result',
    message:'Build is complete',
    evidence:[verificationEvidence()],
    outcome:{summary:'Overall job outcome verified.', physicalDevice:false},
  });
  assert.equal(assertActivityMessageTruth(event).state, 'result');
});

test('derived public projection contains only canonical event-derived truth', () => {
  const event = base({evidence:[sourceEvidence()]});
  const projection = deriveActivityProjection(event);
  assert.equal(projection.projectionVersion, ACTIVITY_PUBLIC_PROJECTION_VERSION);
  assert.equal(projection.eventId, event.eventId);
  assert.equal(projection.message, event.message);
  assert.deepEqual(projection.source, event.provenance);
  assert.deepEqual(projection.evidenceRefs, event.evidence);
  assert.equal(Object.hasOwn(projection, 'progressPercent'), false);
  assert.equal(Object.hasOwn(projection, 'stage'), false);
});

test('projection validator rejects invented progress fields', () => {
  const event = base();
  const projection = {...deriveActivityProjection(event), progressPercent:75};
  assert.throws(() => validateActivityProjection(projection, event), /exact derivation/);
});

test('projection validator rejects invented stage fields', () => {
  const event = base();
  const projection = {...deriveActivityProjection(event), stage:'Deploying'};
  assert.throws(() => validateActivityProjection(projection, event), /exact derivation/);
});

test('projection validator rejects altered message, state and provenance', () => {
  const event = base();
  const derived = deriveActivityProjection(event);
  assert.throws(() => validateActivityProjection({...derived, message:'75% complete'}, event), /exact derivation/);
  assert.throws(() => validateActivityProjection({...derived, state:'result'}, event), /exact derivation/);
  assert.throws(() => validateActivityProjection({...derived, source:{...derived.source, sourceId:'fake-source'}}, event), /exact derivation/);
});

test('projection validator accepts exact projection independent of object key order', () => {
  const event = base({evidence:[sourceEvidence()]});
  const derived = deriveActivityProjection(event);
  const reordered = Object.fromEntries(Object.entries(derived).reverse());
  assert.deepEqual(validateActivityProjection(reordered, event), derived);
});

test('projection validator rejects non-plain nested projection data', () => {
  const event = base();
  const derived = deriveActivityProjection(event);
  const projection = {...derived, source:new (class X { constructor(){ Object.assign(this, derived.source); } })()};
  assert.throws(() => validateActivityProjection(projection, event), /plain object/);
});
