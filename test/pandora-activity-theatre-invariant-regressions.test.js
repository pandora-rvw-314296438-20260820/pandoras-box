import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const neutral = require('../packages/pandora-activity-theatre');
const runtimeCompat = require('../packages/pandora-project-runtime/activity-theatre-event.js');

test('neutral package owns the canonical Activity Theatre contract', () => {
  assert.equal(typeof neutral.normalizeActivityEvent, 'function');
  assert.equal(typeof neutral.validateActivityTimeline, 'function');
  assert.equal(typeof neutral.validateActivityReplay, 'function');
  assert.equal(typeof neutral.activityReplayCheckpoint, 'function');
  assert.deepEqual(neutral.ACTIVITY_EVENT_STATES, [
    'understanding', 'planning', 'acting', 'checking', 'needs_you',
    'retrying', 'fallback', 'verifying', 'paused', 'resuming',
    'result', 'failed', 'cancelled',
  ]);
});

test('project runtime compatibility surface delegates to the neutral package', () => {
  assert.equal(runtimeCompat.normalizeActivityEvent, neutral.normalizeActivityEvent);
  assert.equal(runtimeCompat.validateActivityTimeline, neutral.validateActivityTimeline);
  assert.equal(runtimeCompat.validateActivityReplay, neutral.validateActivityReplay);
  assert.equal(runtimeCompat.activityReplayCheckpoint, neutral.activityReplayCheckpoint);
});
