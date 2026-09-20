'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  BUILD_THEATRE_PHASES,
  BUILD_THEATRE_WORKFLOWS,
  projectBuildTheatreEvent,
} = require('../packages/pandora-activity-theatre');

const evidence = (type, relation, ref) => ({ type, relation, ref });
const base = (overrides = {}) => ({
  schemaVersion: 1,
  eventId: 'evt-build-1',
  jobId: 'job-build-1',
  sequence: 1,
  writerEpoch: 1,
  admittedBy: 'pandora-runtime-1',
  admissionMode: 'online',
  state: 'acting',
  message: 'Executing the authorized build.',
  occurredAt: '2026-09-14T01:00:00+08:00',
  admittedAt: '2026-09-14T01:00:01+08:00',
  provenance: {
    sourceType: 'runtime',
    sourceId: 'pandora-builder-1',
    sourceEventId: 'builder-event-1',
    observedAt: '2026-09-14T01:00:00.500+08:00',
  },
  evidence: [],
  domain: 'build',
  capability: 'build.execute',
  ...overrides,
});

const verifiedResult = (summary) => base({
  state: 'result',
  message: summary,
  evidence: [evidence('verification_receipt', 'verification', 'verification://job-build-1/final')],
  outcome: { summary, physicalDevice: false },
});

test('Build Theatre workflows and phase labels are frozen projection vocabulary', () => {
  assert.deepEqual(BUILD_THEATRE_WORKFLOWS, ['build', 'edit', 'publish']);
  assert.equal(BUILD_THEATRE_PHASES.build.building.state, 'acting');
  assert.equal(BUILD_THEATRE_PHASES.build.preview_ready.state, 'result');
  assert.equal(BUILD_THEATRE_PHASES.edit.updated_preview.state, 'result');
  assert.equal(BUILD_THEATRE_PHASES.publish.live.state, 'result');
});

for (const [workflow, phase, state, label] of [
  ['build', 'understanding', 'understanding', 'Understanding'],
  ['build', 'planning', 'planning', 'Planning'],
  ['build', 'building', 'acting', 'Building'],
  ['build', 'testing', 'checking', 'Testing'],
  ['edit', 'edit_requested', 'planning', 'Edit Requested'],
  ['edit', 'rebuilding', 'acting', 'Rebuilding'],
  ['edit', 'verifying', 'verifying', 'Verifying'],
  ['publish', 'preparing', 'planning', 'Preparing'],
  ['publish', 'deploying', 'acting', 'Deploying'],
  ['publish', 'verifying_live', 'verifying', 'Verifying Live'],
]) {
  test(`${workflow}:${phase} is a label over canonical ${state}`, () => {
    const projected = projectBuildTheatreEvent(base({ state }), { workflow, phase });
    assert.equal(projected.state, state);
    assert.equal(projected.phase, phase);
    assert.equal(projected.label, label);
    assert.equal(projected.jobId, 'job-build-1');
    assert.equal(projected.eventId, 'evt-build-1');
  });
}

test('Preview Ready, Updated Preview and Live require verified canonical result truth', () => {
  for (const [workflow, phase, label] of [
    ['build', 'preview_ready', 'Preview Ready'],
    ['edit', 'updated_preview', 'Updated Preview'],
    ['publish', 'live', 'Live'],
  ]) {
    assert.throws(
      () => projectBuildTheatreEvent(base({ state: 'result', outcome: { summary: label, physicalDevice: false } }), { workflow, phase }),
      /overall-job verification evidence/,
    );
    const projected = projectBuildTheatreEvent(verifiedResult(label), { workflow, phase });
    assert.equal(projected.state, 'result');
    assert.equal(projected.label, label);
  }
});

test('build-specific phase can never override canonical Activity Theatre state', () => {
  assert.throws(
    () => projectBuildTheatreEvent(base({ state: 'planning' }), { workflow: 'build', phase: 'building' }),
    /cannot override canonical state planning/,
  );
});

test('Needs You remains universal and cannot be invented by Build Theatre', () => {
  const approval = base({
    state: 'needs_you',
    message: 'Approval is required before production publish.',
    provenance: {
      sourceType: 'pandora',
      sourceId: 'pandora-1',
      sourceEventId: 'authority-decision-1',
      observedAt: '2026-09-14T01:00:00.500+08:00',
    },
    evidence: [evidence('policy_decision', 'policy', 'policy://standing-authority/decision-1')],
    blocker: {
      reasonCode: 'authorization_required',
      reason: 'Production publish is not authorized.',
      requiredAction: 'Approve or cancel publication.',
      approvalRequired: true,
      policyRef: 'policy:standing-authority:v1',
    },
  });
  assert.throws(
    () => projectBuildTheatreEvent(approval, { workflow: 'publish', authorityDecision: 'auto_execute' }),
    /authorityDecision=needs_approval/,
  );
  assert.throws(
    () => projectBuildTheatreEvent(approval, { workflow: 'publish', authorityDecision: 'deny' }),
    /authorityDecision=needs_approval/,
  );
  const projected = projectBuildTheatreEvent(approval, { workflow: 'publish', authorityDecision: 'needs_approval' });
  assert.equal(projected.state, 'needs_you');
  assert.equal(projected.label, 'Needs You');
  assert.equal(projected.phase, null);
});

test('failure remains canonical failed truth and cannot be created by a Problem phase', () => {
  assert.throws(
    () => projectBuildTheatreEvent(base({ state: 'failed' }), { workflow: 'build' }),
    /failure evidence/,
  );
  const projected = projectBuildTheatreEvent(base({
    state: 'failed',
    message: 'Build failed.',
    evidence: [evidence('runtime_event', 'failure', 'runtime://job-build-1/failure')],
  }), { workflow: 'build' });
  assert.equal(projected.state, 'failed');
  assert.equal(projected.label, 'Problem');
  assert.equal(projected.phase, null);
});

test('retry, fallback, pause and cancellation stay universal rather than fake build phases', () => {
  for (const [state, label] of [
    ['retrying', 'Retrying'],
    ['fallback', 'Fallback'],
    ['paused', 'Paused'],
    ['resuming', 'Resuming'],
    ['cancelled', 'Cancelled'],
  ]) {
    const event = base({ state });
    if (state === 'retrying') {
      event.evidence = [evidence('provider_receipt', 'prior_attempt', 'provider://attempt/1')];
      event.transition = { priorAttemptId: 'attempt-1', priorAuthorityScopeRef: 'authority://scope/1', authorityScopeRef: 'authority://scope/1', consequential: false };
    } else if (state === 'fallback') {
      event.evidence = [evidence('policy_decision', 'capability', 'capability://provider/b')];
      event.transition = { priorAttemptId: 'attempt-1', priorAuthorityScopeRef: 'authority://scope/1', authorityScopeRef: 'authority://scope/1', consequential: false };
    } else if (state === 'paused') {
      event.evidence = [evidence('runtime_event', 'authoritative_pause', 'runtime://pause/1')];
    } else if (state === 'resuming') {
      event.evidence = [evidence('user_control', 'accepted_control', 'control://resume/1')];
      event.control = { type: 'resume', requestId: 'ctl-resume-1', acceptedAt: '2026-09-14T01:00:00.750+08:00' };
    } else if (state === 'cancelled') {
      event.evidence = [evidence('runtime_event', 'authoritative_cancellation', 'runtime://cancel/1')];
    }
    const projected = projectBuildTheatreEvent(event, { workflow: 'build' });
    assert.equal(projected.label, label);
    assert.equal(projected.phase, null);
  }
});

test('projection exposes no synthetic percentage or raw execution payload', () => {
  const projected = projectBuildTheatreEvent(base(), { workflow: 'build', phase: 'building' });
  assert.equal('progressPercent' in projected, false);
  assert.equal('rawPrompt' in projected, false);
  assert.equal('toolArgs' in projected, false);
  assert.equal('providerPayload' in projected, false);
});

test('universal-only states reject decorative build phases', () => {
  assert.throws(
    () => projectBuildTheatreEvent(base({ state: 'fallback', evidence: [evidence('policy_decision', 'capability', 'capability://provider/b')], transition: { priorAttemptId: 'attempt-1', priorAuthorityScopeRef: 'authority://scope/1', authorityScopeRef: 'authority://scope/1', consequential: false } }), { workflow: 'build', phase: 'building' }),
    /phase is not valid for canonical state fallback/,
  );
});
