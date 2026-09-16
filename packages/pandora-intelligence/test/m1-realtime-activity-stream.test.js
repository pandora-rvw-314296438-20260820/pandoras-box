'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  runRealtimeContinuousExecution,
} = require('../src/runtime/realtime-activity-stream.js');

const resolution = {
  contractVersion: 'pandora-intent-capability-resolution-v1',
  intent: 'research',
  actionMode: 'read_only',
  requestedOutcome: 'Return verified evidence.',
  riskAuthority: { resolverGrantsAuthority: false },
  modelRoutingConstraints: { modelSelectionOwner: 'M3' },
};

function clock() {
  let tick = 0;
  return () => new Date(Date.UTC(2026, 8, 14, 10, 0, tick++)).toISOString();
}

function projector({ jobId, verification, activityCursor }) {
  const at = new Date(Date.UTC(2026, 8, 14, 10, 1, 0)).toISOString();
  return {
    projectionVersion: 1,
    eventId: `result-${jobId}`,
    jobId,
    sequence: activityCursor.nextSequence,
    state: 'result',
    message: 'Requested evidence is verified.',
    occurredAt: at,
    admittedAt: at,
    domain: 'research',
    capability: 'knowledge.research',
    executionId: 'exec-research-1',
    source: {
      sourceType: 'runtime',
      sourceId: 'm1-runtime',
      sourceEventId: 'verify-event-1',
      observedAt: at,
    },
    evidenceRefs: [{
      type: 'verification_receipt',
      relation: 'verification',
      ref: verification.verificationReceiptRef,
    }],
    blocker: null,
    outcome: { summary: 'Requested evidence is verified.', physicalDevice: false },
  };
}

test('admission and runtime evidence stream incrementally before verified result', async () => {
  const appended = [];
  const completed = [];
  const calls = [];
  const sink = {
    async append(value) {
      appended.push(value);
      calls.push(`event:${value.event.state}:${value.event.sequence}`);
    },
    async complete(value) {
      completed.push(value);
      calls.push(`complete:${value.status}`);
    },
  };

  const result = await runRealtimeContinuousExecution(
    { jobId: 'job-stream-1', resolution },
    {
      reason(view) {
        calls.push(`reason:${view.iteration}`);
        if (view.iteration === 1) {
          return {
            kind: 'act',
            decisionRef: 'reason://read-1',
            action: {
              actionId: 'read-1',
              capability: 'knowledge.research',
              effect: 'read_only',
            },
          };
        }
        return { kind: 'verify', decisionRef: 'reason://verify' };
      },
      actRead(action) {
        calls.push(`act:${action.actionId}`);
        return { status: 'succeeded', receiptRef: 'tool://read-1', retryable: false };
      },
      observeRead({ action }) {
        calls.push(`observe:${action.actionId}`);
        return {
          observationRef: 'readback://read-1',
          effectState: 'observed',
          progressMade: true,
          retryable: false,
        };
      },
      verify() {
        calls.push('verify');
        return {
          verified: true,
          verificationReceiptRef: 'verify://research-1',
          summary: 'Requested evidence is verified.',
          progressMade: true,
          retryable: false,
        };
      },
      projectResult: projector,
    },
    {
      sink,
      admittedBy: 'm1-runtime',
      admissionRef: 'runtime://turn-admitted-1',
      domain: 'research',
      capability: 'knowledge.research',
      clock: clock(),
    },
  );

  assert.equal(result.status, 'result');
  assert.deepEqual(
    appended.map((entry) => entry.event.state),
    ['understanding', 'planning', 'acting', 'checking', 'planning', 'verifying', 'result'],
  );
  assert.deepEqual(
    appended.map((entry) => entry.event.sequence),
    [1, 2, 3, 4, 5, 6, 7],
  );
  assert.equal(appended[0].event.jobId, 'job-stream-1');
  assert.equal(appended[6].projection.outcome.summary, 'Requested evidence is verified.');
  assert.equal(completed.length, 1);
  assert.equal(completed[0].status, 'result');
  assert.ok(calls.indexOf('event:planning:2') < calls.indexOf('act:read-1'));
  assert.ok(calls.indexOf('event:acting:3') < calls.indexOf('observe:read-1'));
});

test('stream rejects a result projection that skips the next canonical sequence', async () => {
  await assert.rejects(
    () => runRealtimeContinuousExecution(
      { jobId: 'job-gap', resolution },
      {
        reason() { return { kind: 'verify', decisionRef: 'reason://verify' }; },
        verify() {
          return {
            verified: true,
            verificationReceiptRef: 'verify://gap',
            summary: 'Outcome verified.',
            progressMade: true,
            retryable: false,
          };
        },
        projectResult(payload) {
          const value = projector(payload);
          return { ...value, sequence: payload.activityCursor.nextSequence + 1 };
        },
      },
      {
        sink: { append() {}, complete() {} },
        admittedBy: 'm1-runtime',
        admissionRef: 'runtime://turn-gap',
        domain: 'research',
        capability: 'knowledge.research',
        clock: clock(),
      },
    ),
    /next canonical sequence/,
  );
});
