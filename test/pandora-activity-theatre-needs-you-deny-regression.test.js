'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { assertNeedsYouBoundary } = require('../packages/pandora-activity-theatre');

test('non-overridable deny decision can never be emitted as Needs You', () => {
  const event = {
    schemaVersion: 1,
    eventId: 'evt-needs-you-deny-1',
    jobId: 'job-deny-1',
    sequence: 1,
    writerEpoch: 1,
    admittedBy: 'pandora-runtime-1',
    admissionMode: 'online',
    state: 'needs_you',
    message: 'Reconnect the account to continue.',
    occurredAt: '2026-09-14T00:50:00+08:00',
    admittedAt: '2026-09-14T00:50:01+08:00',
    provenance: {
      sourceType: 'provider',
      sourceId: 'provider-1',
      sourceEventId: 'reauth-1',
      observedAt: '2026-09-14T00:50:00.500+08:00',
    },
    evidence: [],
    domain: 'accounts',
    capability: 'account.reauthenticate',
    blocker: {
      reasonCode: 'account_connection_or_reauthentication_required',
      reason: 'The provider session expired.',
      requiredAction: 'Reconnect the account.',
      approvalRequired: false,
      policyRef: null,
    },
  };

  assert.throws(
    () => assertNeedsYouBoundary(event, { authorityDecision: 'deny' }),
    /non-overridable.*must not emit Needs You/,
  );
});
