import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const {
  ACTIVITY_EVENT_SCHEMA_VERSION,
  normalizeActivityEvent,
  validateActivityTimeline,
} = require('../packages/pandora-project-runtime/activity-theatre-event.js');

const event = (overrides = {}) => ({
  schemaVersion: ACTIVITY_EVENT_SCHEMA_VERSION,
  eventId: 'evt-1',
  jobId: 'job-1',
  sequence: 1,
  state: 'understanding',
  message: 'Understanding your request',
  occurredAt: '2026-09-13T03:06:00Z',
  provenance: {
    sourceType: 'runtime',
    sourceId: 'pandora-runtime-1',
    sourceEventId: 'runtime-event-1',
    observedAt: '2026-09-13T03:06:00Z',
    evidenceRef: 'runtime://job-1/events/1',
  },
  ...overrides,
});

test('timeline rejects duplicate event identity and actual timestamp regression', () => {
  assert.throws(
    () => validateActivityTimeline([
      event(),
      event({
        eventId: 'evt-1',
        sequence: 2,
        occurredAt: '2026-09-13T03:06:01Z',
        provenance: {
          ...event().provenance,
          sourceEventId: 'runtime-event-2',
          observedAt: '2026-09-13T03:06:01Z',
        },
      }),
    ]),
    /duplicate eventId/,
  );

  assert.throws(
    () => validateActivityTimeline([
      event({ occurredAt: '2026-09-13T03:06:01Z' }),
      event({
        eventId: 'evt-2',
        sequence: 2,
        occurredAt: '2026-09-13T03:06:00Z',
        provenance: {
          ...event().provenance,
          sourceEventId: 'runtime-event-2',
          observedAt: '2026-09-13T03:06:00Z',
        },
      }),
    ]),
    /timestamps must be nondecreasing/,
  );
});

test('nested blocker and outcome schema objects must also be plain objects', () => {
  const inheritedBlocker = Object.create({
    reason: 'A real approval is required.',
    requiredAction: 'Approve or cancel.',
    approvalRequired: true,
  });
  assert.throws(
    () => normalizeActivityEvent(event({
      state: 'needs_you',
      blocker: inheritedBlocker,
    })),
    /blocker must be a plain object/,
  );

  const inheritedOutcome = Object.create({ summary: 'Verified result.' });
  assert.throws(
    () => normalizeActivityEvent(event({
      state: 'result',
      outcome: inheritedOutcome,
    })),
    /outcome must be a plain object/,
  );
});

test('blocker and outcome fields remain scoped to their canonical states', () => {
  assert.throws(
    () => normalizeActivityEvent(event({
      blocker: {
        reason: 'Not valid here.',
        requiredAction: 'Nothing.',
        approvalRequired: false,
      },
    })),
    /blocker is only valid for needs_you events/,
  );

  assert.throws(
    () => normalizeActivityEvent(event({
      outcome: { summary: 'Not valid before Result.' },
    })),
    /outcome is only valid for result events/,
  );
});

test('schema version and sequence validation fail closed', () => {
  assert.throws(
    () => normalizeActivityEvent(event({ schemaVersion: ACTIVITY_EVENT_SCHEMA_VERSION + 1 })),
    /unsupported activity event schemaVersion/,
  );
  for (const sequence of [0, -1, 1.5, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(
      () => normalizeActivityEvent(event({ sequence })),
      /sequence must be a positive safe integer/,
    );
  }
});
