'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  NEEDS_YOU_APPROVAL_REASON_CODES,
  NEEDS_YOU_USER_ACTION_REASON_CODES,
  assertNeedsYouBoundary,
  needsYouBoundaryStatus,
} = require('../packages/pandora-activity-theatre');

const evidence = (type, relation, ref) => ({type, relation, ref});
const base = (overrides={}) => ({
  schemaVersion: 1,
  eventId: 'evt-needs-you-1',
  jobId: 'job-1',
  sequence: 4,
  writerEpoch: 1,
  admittedBy: 'pandora-runtime-1',
  admissionMode: 'online',
  state: 'needs_you',
  message: 'Your approval is required before publication.',
  occurredAt: '2026-09-14T00:40:00+08:00',
  admittedAt: '2026-09-14T00:40:01+08:00',
  provenance: {sourceType:'pandora', sourceId:'pandora-1', sourceEventId:'authority-1', observedAt:'2026-09-14T00:40:00.500+08:00'},
  evidence: [evidence('policy_decision','policy','policy://standing-authority/decision-1')],
  domain: 'release',
  capability: 'publish.release',
  blocker: {
    reasonCode:'authorization_required',
    reason:'Publishing crosses a production boundary without sufficient authority.',
    requiredAction:'Approve or cancel publication.',
    approvalRequired:true,
    policyRef:'policy:standing-authority:v1',
  },
  ...overrides,
});

test('reason partitions match frozen M0-003 policy', () => {
  assert.deepEqual(NEEDS_YOU_APPROVAL_REASON_CODES, ['authorization_required','missing_consequential_user_choice']);
  assert.deepEqual(NEEDS_YOU_USER_ACTION_REASON_CODES, [
    'account_connection_or_reauthentication_required',
    'protected_app_user_presence_required',
    'user_only_recovery_or_conflict_resolution',
    'external_blocker_only_user_can_resolve',
  ]);
});

test('authorization Needs You requires needs_approval policy decision', () => {
  const event = assertNeedsYouBoundary(base(), {authorityDecision:'needs_approval'});
  assert.equal(event.blocker.approvalRequired, true);
});

test('authorization Needs You rejects auto_execute and standing_authorized', () => {
  for (const decision of ['auto_execute','standing_authorized']) {
    assert.throws(() => assertNeedsYouBoundary(base(), {authorityDecision:decision}), /authorityDecision=needs_approval/);
  }
});

test('authorization Needs You requires policy evidence and policy reference', () => {
  assert.throws(() => assertNeedsYouBoundary(base({evidence:[]}), {authorityDecision:'needs_approval'}), /policy_decision evidence/);
  assert.throws(() => assertNeedsYouBoundary(base({blocker:{...base().blocker,policyRef:null}}), {authorityDecision:'needs_approval'}), /policyRef/);
});

test('approval reason cannot be labeled as non-approval', () => {
  assert.throws(() => assertNeedsYouBoundary(base({blocker:{...base().blocker,approvalRequired:false}}), {authorityDecision:'needs_approval'}), /approvalRequired=true/);
});

test('missing consequential user choice is an approval-class boundary', () => {
  const event = assertNeedsYouBoundary(base({
    blocker:{reasonCode:'missing_consequential_user_choice',reason:'A consequential destination choice is missing.',requiredAction:'Choose the destination or cancel.',approvalRequired:true,policyRef:'policy:standing-authority:v1'},
  }), {authorityDecision:'needs_approval'});
  assert.equal(event.blocker.reasonCode,'missing_consequential_user_choice');
});

test('account reauthentication is a user-action boundary, not approval', () => {
  const event = assertNeedsYouBoundary(base({
    message:'Reconnect the account to continue.',
    provenance:{sourceType:'provider',sourceId:'github',sourceEventId:'auth-expired-1',observedAt:'2026-09-14T00:40:00.500+08:00'},
    evidence:[],
    blocker:{reasonCode:'account_connection_or_reauthentication_required',reason:'The provider session expired.',requiredAction:'Reconnect the account.',approvalRequired:false,policyRef:null},
  }));
  assert.equal(event.blocker.approvalRequired,false);
});

test('protected app user presence requires device/runtime/tool provenance', () => {
  const event = assertNeedsYouBoundary(base({
    message:'Confirm the protected-app action on the device.',
    provenance:{sourceType:'device',sourceId:'android-device-agent',sourceEventId:'protected-presence-1',observedAt:'2026-09-14T00:40:00.500+08:00'},
    evidence:[],
    blocker:{reasonCode:'protected_app_user_presence_required',reason:'The protected app requires biometric or user presence.',requiredAction:'Confirm the action on the device.',approvalRequired:false,policyRef:null},
  }));
  assert.equal(event.blocker.reasonCode,'protected_app_user_presence_required');
  assert.throws(() => assertNeedsYouBoundary(base({
    provenance:{sourceType:'model',sourceId:'model-1',sourceEventId:'guess-1',observedAt:'2026-09-14T00:40:00.500+08:00'},
    evidence:[],
    blocker:{reasonCode:'protected_app_user_presence_required',reason:'Maybe user presence is needed.',requiredAction:'Confirm on the device.',approvalRequired:false,policyRef:null},
  })), /authoritative runtime\/device\/provider\/tool provenance/);
});

test('non-approval blocker cannot masquerade as needs_approval', () => {
  assert.throws(() => assertNeedsYouBoundary(base({
    provenance:{sourceType:'provider',sourceId:'provider-1',sourceEventId:'reauth-1',observedAt:'2026-09-14T00:40:00.500+08:00'},
    evidence:[],
    blocker:{reasonCode:'account_connection_or_reauthentication_required',reason:'Session expired.',requiredAction:'Reconnect the account.',approvalRequired:false,policyRef:null},
  }), {authorityDecision:'needs_approval'}), /must not masquerade as an approval boundary/);
});

test('routine waiting is never admitted as Needs You', () => {
  assert.throws(() => assertNeedsYouBoundary(base({
    blocker:{reasonCode:'waiting_for_ci_or_cloud_work',reason:'CI is running.',requiredAction:'Wait for CI.',approvalRequired:false,policyRef:null},
  })), /unsupported blocker.reasonCode/);
});

test('voluntary paused state is not Needs You', () => {
  assert.throws(() => assertNeedsYouBoundary(base({
    state:'paused',
    blocker:null,
    evidence:[evidence('runtime_event','authoritative_pause','runtime://pause/thermal')],
  })), /state=needs_you/);
});

test('Needs You status is explicit blocking paused semantics with exact action', () => {
  const status = needsYouBoundaryStatus(base(), {authorityDecision:'needs_approval'});
  assert.deepEqual(status, {
    state:'needs_you',paused:true,blocking:true,jobId:'job-1',eventId:'evt-needs-you-1',sequence:4,
    reasonCode:'authorization_required',
    reason:'Publishing crosses a production boundary without sufficient authority.',
    requiredAction:'Approve or cancel publication.',approvalRequired:true,policyRef:'policy:standing-authority:v1',
    occurredAt:'2026-09-13T16:40:00.000Z',admittedAt:'2026-09-13T16:40:01.000Z',
  });
});

test('unsupported authority decisions fail closed', () => {
  assert.throws(() => assertNeedsYouBoundary(base(), {authorityDecision:'probably'}), /unsupported authorityDecision/);
});
