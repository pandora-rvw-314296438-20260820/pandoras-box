'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  legacyBuildEventProjection,
  projectBuildTheatreEvent,
} = require('../packages/pandora-activity-theatre');

const baseVerifying = () => ({
  schemaVersion: 1,
  eventId: 'evt-build-verifying-1',
  jobId: 'job-build-1',
  sequence: 9,
  writerEpoch: 1,
  admittedBy: 'pandora-runtime-1',
  admissionMode: 'online',
  state: 'verifying',
  message: 'Build completed; independently verifying the exact result.',
  occurredAt: '2026-09-14T01:10:00+08:00',
  admittedAt: '2026-09-14T01:10:01+08:00',
  provenance: {
    sourceType: 'runtime',
    sourceId: 'pandora-runtime-1',
    sourceEventId: 'verify-1',
    observedAt: '2026-09-14T01:10:00.500+08:00',
  },
  evidence: [],
  domain: 'build',
  capability: 'build.verify',
});

test('builder completion is never promoted to terminal Result', () => {
  const projection = legacyBuildEventProjection('build_completed');
  assert.equal(projection.state, 'verifying');
  assert.equal(projection.phase, null);
  assert.equal(projection.builderCompletionIsNotResult, true);
});

test('preview_ready requires verified canonical result truth before projection', () => {
  const projection = legacyBuildEventProjection('preview_ready');
  assert.equal(projection.state, 'result');
  assert.equal(projection.phase, 'preview_ready');
  assert.equal(projection.requiresVerifiedResult, true);
});

test('dynamic legacy events cannot be guessed without safe-payload admission', () => {
  for (const type of ['job_state', 'build_step', 'command_started', 'command_completed']) {
    assert.throws(() => legacyBuildEventProjection(type), /requires canonical runtime admission/);
  }
});

test('build workflow can show universal Verifying while independent verification is pending', () => {
  const projection = projectBuildTheatreEvent(baseVerifying(), { workflow: 'build' });
  assert.equal(projection.state, 'verifying');
  assert.equal(projection.label, 'Verifying');
  assert.equal(projection.phase, null);
});
