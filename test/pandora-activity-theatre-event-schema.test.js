import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const {
  ACTIVITY_EVENT_SCHEMA_VERSION,
  ACTIVITY_EVENT_SOURCE_TYPES,
  ACTIVITY_EVENT_STATES,
  TERMINAL_ACTIVITY_STATES,
  isTerminalActivityState,
  normalizeActivityEvent,
  validateActivityTimeline,
} = require('../packages/pandora-project-runtime/activity-theatre-event.js');
const runtimePackage = require('../packages/pandora-project-runtime');

const base = (overrides = {}) => ({
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
  domain: 'communications',
  capability: 'sms.resolve-recipient',
  ...overrides,
});

test('normal package entrypoint exports the canonical Activity Theatre contract', () => {
  assert.equal(runtimePackage.ACTIVITY_EVENT_SCHEMA_VERSION, ACTIVITY_EVENT_SCHEMA_VERSION);
  assert.equal(runtimePackage.normalizeActivityEvent, normalizeActivityEvent);
  assert.equal(runtimePackage.validateActivityTimeline, validateActivityTimeline);
});

test('canonical taxonomy exactly matches the universal Activity Theatre contract', () => {
  assert.deepEqual(ACTIVITY_EVENT_STATES, [
    'understanding',
    'planning',
    'acting',
    'checking',
    'needs_you',
    'retrying',
    'fallback',
    'verifying',
    'result',
    'failed',
    'cancelled',
  ]);
  assert.deepEqual(TERMINAL_ACTIVITY_STATES, ['result', 'failed', 'cancelled']);
  assert.deepEqual(ACTIVITY_EVENT_SOURCE_TYPES, [
    'runtime',
    'device',
    'provider',
    'projectos',
    'model',
    'tool',
  ]);
});

test('normalizes a real-source activity event with job identity and timestamps', () => {
  const event = normalizeActivityEvent(base());
  assert.equal(event.jobId, 'job-1');
  assert.equal(event.state, 'understanding');
  assert.equal(event.occurredAt, '2026-09-13T03:06:00.000Z');
  assert.equal(event.provenance.sourceType, 'runtime');
  assert.equal(event.provenance.sourceId, 'pandora-runtime-1');
  assert.ok(Object.isFrozen(event));
  assert.ok(Object.isFrozen(event.provenance));
});

test('rejects visible events that lack real source provenance, timestamp or job identity', () => {
  assert.throws(() => normalizeActivityEvent(base({ jobId: '' })), /jobId is required/);
  assert.throws(() => normalizeActivityEvent(base({ occurredAt: 'today' })), /offset-aware ISO-8601/);
  assert.throws(
    () => normalizeActivityEvent(base({ provenance: { sourceType: 'runtime' } })),
    /provenance.sourceId/,
  );
  assert.throws(
    () => normalizeActivityEvent(base({
      provenance: {
        sourceType: 'runtime',
        sourceId: 'pandora-runtime-1',
        observedAt: '2026-09-13T03:06:00Z',
      },
    })),
    /requires sourceEventId or evidenceRef/,
  );
  assert.throws(
    () => normalizeActivityEvent(base({ provenance: { ...base().provenance, sourceType: 'decorative' } })),
    /unsupported provenance.sourceType/,
  );
});

test('accepts either a source event id or evidence reference as the real-source linkage', () => {
  const byEventId = normalizeActivityEvent(base({
    provenance: { ...base().provenance, evidenceRef: null },
  }));
  assert.equal(byEventId.provenance.sourceEventId, 'runtime-event-1');
  assert.equal(byEventId.provenance.evidenceRef, null);

  const byEvidence = normalizeActivityEvent(base({
    provenance: { ...base().provenance, sourceEventId: null },
  }));
  assert.equal(byEvidence.provenance.sourceEventId, null);
  assert.equal(byEvidence.provenance.evidenceRef, 'runtime://job-1/events/1');
});

test('Needs You is explicit and requires the exact blocker plus required user action', () => {
  assert.throws(() => normalizeActivityEvent(base({ state: 'needs_you' })), /blocker must be an object/);
  const event = normalizeActivityEvent(base({
    state: 'needs_you',
    message: 'Approval is required before sending the payment instruction.',
    blocker: {
      reason: 'This action crosses the financial-action policy boundary.',
      requiredAction: 'Approve or cancel the payment instruction.',
      approvalRequired: true,
      policyRef: 'policy:financial-actions:v1',
    },
  }));
  assert.equal(event.blocker.approvalRequired, true);
  assert.match(event.blocker.requiredAction, /Approve or cancel/);
});

test('Result carries an explicit outcome and terminal states are recognized', () => {
  assert.throws(() => normalizeActivityEvent(base({ state: 'result' })), /outcome must be an object/);
  const result = normalizeActivityEvent(base({
    state: 'result',
    message: 'Message sent',
    outcome: {
      summary: 'SMS was accepted by the device messaging provider.',
      verificationRef: 'device://sms/outbox/42',
    },
  }));
  assert.equal(result.outcome.verificationRef, 'device://sms/outbox/42');
  assert.equal(isTerminalActivityState(result.state), true);
  assert.equal(isTerminalActivityState('checking'), false);
});

test('timeline validation enforces one job, strict sequence, timestamp order and terminal finality', () => {
  const timeline = validateActivityTimeline([
    base(),
    base({
      eventId: 'evt-2',
      sequence: 2,
      state: 'checking',
      message: 'Checking the resolved recipient',
      occurredAt: '2026-09-13T03:06:01Z',
      provenance: { ...base().provenance, sourceEventId: 'runtime-event-2', observedAt: '2026-09-13T03:06:01Z' },
    }),
    base({
      eventId: 'evt-3',
      sequence: 3,
      state: 'result',
      message: 'Recipient resolved',
      occurredAt: '2026-09-13T03:06:02Z',
      provenance: { ...base().provenance, sourceEventId: 'runtime-event-3', observedAt: '2026-09-13T03:06:02Z' },
      outcome: { summary: 'Maria Santos resolved to contact contact-7.' },
    }),
  ]);
  assert.equal(timeline.length, 3);
  assert.ok(Object.isFrozen(timeline));

  assert.throws(
    () => validateActivityTimeline([base(), base({ eventId: 'evt-2', jobId: 'job-2', sequence: 2 })]),
    /cannot mix job identities/,
  );
  assert.throws(
    () => validateActivityTimeline([base(), base({ eventId: 'evt-2', sequence: 1 })]),
    /strictly increasing/,
  );
  assert.throws(
    () => validateActivityTimeline([
      base({ state: 'failed' }),
      base({ eventId: 'evt-2', sequence: 2, state: 'retrying' }),
    ]),
    /after a terminal state/,
  );
});

test('schema is strict so decorative or invented fields cannot silently enter the universal contract', () => {
  assert.throws(
    () => normalizeActivityEvent(base({ fakePercent: 87 })),
    /not part of the canonical activity schema/,
  );
  assert.throws(
    () => normalizeActivityEvent(base({ state: 'busy' })),
    /unsupported activity state/,
  );
});

test('public Activity Theatre boundary rejects arbitrary metadata and sensitive payload fields', () => {
  for (const payload of [
    { metadata: { safeLabel: 'looks-safe' } },
    { metadata: { nested: { token: 'secret-value' } } },
    { secret: 'secret-value' },
    { token: 'token-value' },
    { rawPrompt: 'system prompt contents' },
    { toolArgs: { recipient: 'private-value' } },
  ]) {
    assert.throws(
      () => normalizeActivityEvent(base(payload)),
      /not part of the canonical activity schema/,
    );
  }
});

test('public Activity Theatre text fields reject credential-like material without blocking safe status prose', () => {
  const githubPat = ['github', '_pat_11AAABBBCCCDDDEEEFFF000111222333444'].join('');
  const slackToken = ['xox', 'b-123456789012-123456789012-abcdefghijklmnopqrstuvwx'].join('');
  const slackWebhook = ['https://hooks.', 'slack.com/services/T12345678/B12345678/abcdefghijklmnopqrstuvwx'].join('');
  const credentialCases = [
    { message: 'Provider returned ghp_1234567890abcdefghijklmnop' },
    { message: 'Provider returned AKIA1234567890ABCDEF' },
    { message: 'AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF' },
    { message: 'AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY' },
    { message: `Provider returned ${githubPat}` },
    { message: `Provider returned ${slackToken}` },
    { message: `Slack webhook ${slackWebhook}` },
    { message: 'SERVICE_SECRET_KEY=NotARealSecret1234' },
    { provenance: { ...base().provenance, evidenceRef: 'runtime://job-1/events/1?token=abcd1234' } },
    {
      state: 'needs_you',
      message: 'Authorization is required.',
      blocker: {
        reason: 'Provider sent Bearer abcdefghijklmnopqrstuvwxyz',
        requiredAction: 'Reconnect the provider account.',
        approvalRequired: false,
      },
    },
    {
      state: 'result',
      message: 'Provider responded.',
      outcome: { summary: 'Provider echoed sk-1234567890abcdefghijklmnop.' },
    },
    { executionId: 'eyJabcdefghijklmnopqrstuv.abcdefghijklmnopqrstuv.abcdefghijklmnop' },
    { message: 'Authorization: Basic dXNlcjpwYXNzd29yZA==' },
    { message: 'Provider returned sb_secret_1234567890abcdefghijklmnop' },
    { provenance: { ...base().provenance, evidenceRef: 'https://user:password@example.test/evidence' } },
  ];

  for (const payload of credentialCases) {
    assert.throws(
      () => normalizeActivityEvent(base(payload)),
      /contains credential-like material/,
    );
  }

  assert.throws(
    () => normalizeActivityEvent(base({ message: 'password=NotARealSecret1234' })),
    /contains credential-like material/,
  );

  const safe = normalizeActivityEvent(base({
    message: 'Provider status: token: expired; secret: unavailable; password = required; access_token: revoked; AWS_ACCESS_KEY_ID=missing; AWS_SECRET_ACCESS_KEY=unavailable; SERVICE_SECRET_KEY=unavailable.',
    provenance: { ...base().provenance, evidenceRef: 'runtime://job-1/events/1?token=redacted' },
    executionId: 'token:expired',
  }));
  assert.match(safe.message, /token: expired/);
  assert.match(safe.message, /secret: unavailable/);
  assert.match(safe.message, /password = required/);
  assert.match(safe.message, /access_token: revoked/);
  assert.match(safe.message, /AWS_ACCESS_KEY_ID=missing/);
  assert.match(safe.message, /AWS_SECRET_ACCESS_KEY=unavailable/);
  assert.match(safe.message, /SERVICE_SECRET_KEY=unavailable/);
  assert.match(safe.provenance.evidenceRef, /token=redacted/);
  assert.equal(safe.executionId, 'token:expired');
});



test('public Activity Theatre opaque identifiers reject named credential assignments while allowing safe status identifiers', () => {
  const credentialCases = [
    { eventId: 'password:SecretValue1234' },
    { jobId: 'token:SecretValue1234' },
    { provenance: { ...base().provenance, sourceId: 'secret:SecretValue1234' } },
    { provenance: { ...base().provenance, sourceEventId: 'access_token:SecretValue1234' } },
    { executionId: 'private_key:SecretValue1234' },
    { parentEventId: 'api_key:SecretValue1234' },
  ];

  for (const payload of credentialCases) {
    assert.throws(
      () => normalizeActivityEvent(base(payload)),
      /contains credential-like material/,
    );
  }

  const safe = normalizeActivityEvent(base({
    eventId: 'token:expired',
    jobId: 'secret:unavailable',
    provenance: {
      ...base().provenance,
      sourceId: 'password:required',
      sourceEventId: 'access_token:revoked',
    },
    executionId: 'private_key:redacted',
    parentEventId: 'api_key:missing',
  }));
  assert.equal(safe.eventId, 'token:expired');
  assert.equal(safe.jobId, 'secret:unavailable');
  assert.equal(safe.provenance.sourceId, 'password:required');
  assert.equal(safe.provenance.sourceEventId, 'access_token:revoked');
  assert.equal(safe.executionId, 'private_key:redacted');
  assert.equal(safe.parentEventId, 'api_key:missing');
});

test('strict timestamps reject impossible calendar dates while preserving valid offsets', () => {
  for (const occurredAt of [
    '2026-02-30T00:00:00Z',
    '2025-02-29T03:06:00Z',
    '2026-09-13 03:06:00Z',
    '2026-09-13T03:06:00+24:00',
  ]) {
    assert.throws(
      () => normalizeActivityEvent(base({ occurredAt })),
      /offset-aware ISO-8601/,
    );
  }

  const leapDay = normalizeActivityEvent(base({
    occurredAt: '2024-02-29T03:06:00+08:00',
    provenance: {
      ...base().provenance,
      observedAt: '2024-02-29T03:06:00+08:00',
    },
  }));
  assert.equal(leapDay.occurredAt, '2024-02-28T19:06:00.000Z');
  assert.equal(leapDay.provenance.observedAt, '2024-02-28T19:06:00.000Z');
});

test('schema boundaries reject prototype-backed objects', () => {
  const inheritedEvent = Object.create(base());
  assert.throws(
    () => normalizeActivityEvent(inheritedEvent),
    /event must be a plain object/,
  );

  const inheritedProvenance = Object.create(base().provenance);
  assert.throws(
    () => normalizeActivityEvent(base({ provenance: inheritedProvenance })),
    /provenance must be a plain object/,
  );
});
