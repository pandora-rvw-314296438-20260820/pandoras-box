import assert from 'node:assert/strict';
import test from 'node:test';

import { verifyAuditChain } from '../packages/pandora-connections-quality/src/audit-chain.mjs';
import { evaluateConnectionHealth } from '../packages/pandora-connections-quality/src/health-monitor.mjs';

const now = '2026-10-01T12:00:00.000Z';

function healthy(overrides = {}) {
  return {
    connectionId: 'connection-1',
    organizationId: 'organization-1',
    provider: 'example',
    lifecycle: 'active',
    previousState: 'Connecting',
    credential: { state: 'active', expiresAt: '2026-12-01T00:00:00.000Z' },
    accountBinding: { accountId: 'account-1', tenantId: 'tenant-1' },
    requiredScopes: ['records.read'],
    requiredCapabilities: ['records.list'],
    providerReadback: {
      verified: true,
      receiptId: 'receipt-1',
      status: 'healthy',
      observedAt: '2026-10-01T11:59:30.000Z',
      identity: { accountId: 'account-1', tenantId: 'tenant-1' },
      scopes: ['records.read'],
      capabilities: ['records.list'],
    },
    ...overrides,
  };
}

test('only a fresh healthy provider readback projects Connected', () => {
  const projection = evaluateConnectionHealth(healthy(), { now });
  assert.equal(projection.state, 'Connected');
  assert.equal(projection.connected, true);
  assert.equal(projection.canUseNow, true);
  assert.equal(projection.reasonCode, 'provider_verified');
  assert.deepEqual(verifyAuditChain([projection.auditEvent]), {
    valid: true,
    eventCount: 1,
    headHash: projection.auditEvent.eventHash,
  });
});

test('expired, revoked, and expiring credentials become Needs attention', () => {
  const cases = [
    [{ state: 'active', expiresAt: '2026-10-01T11:59:59.000Z' }, 'credential_expired'],
    [{ state: 'revoked' }, 'credential_revoked'],
    [{ state: 'active', expiresAt: '2026-10-02T00:00:00.000Z' }, 'credential_expiring'],
  ];
  for (const [credential, reason] of cases) {
    const projection = evaluateConnectionHealth(healthy({ credential }), { now });
    assert.equal(projection.state, 'Needs attention');
    assert.equal(projection.connected, false);
    assert.equal(projection.canUseNow, false);
    assert.equal(projection.reasonCode, reason);
  }
});

test('revoked, degraded, unauthorized, and unavailable provider states fail closed', () => {
  for (const status of ['revoked', 'degraded', 'unauthorized', 'unavailable']) {
    const providerReadback = { ...healthy().providerReadback, status };
    const projection = evaluateConnectionHealth(healthy({ providerReadback }), { now });
    assert.equal(projection.state, 'Needs attention');
    assert.equal(projection.connected, false);
    assert.equal(projection.reasonCode, `provider_${status}`);
  }
});

test('missing, unverified, stale, or future provider evidence cannot claim Connected', () => {
  const cases = [
    [undefined, 'provider_readback_missing'],
    [{ ...healthy().providerReadback, verified: false }, 'provider_readback_unverified'],
    [{ ...healthy().providerReadback, observedAt: '2026-10-01T11:30:00.000Z' }, 'provider_readback_stale'],
    [{ ...healthy().providerReadback, observedAt: '2026-10-01T12:05:00.000Z' }, 'provider_readback_from_future'],
  ];
  for (const [providerReadback, reason] of cases) {
    const projection = evaluateConnectionHealth(healthy({ providerReadback }), { now });
    assert.equal(projection.state, 'Needs attention');
    assert.equal(projection.connected, false);
    assert.equal(projection.reasonCode, reason);
  }
});

test('account, tenant, scope, and capability drift fail closed', () => {
  const base = healthy().providerReadback;
  const cases = [
    [{ ...base, identity: { accountId: 'wrong', tenantId: 'tenant-1' } }, 'account_identity_mismatch'],
    [{ ...base, identity: { accountId: 'account-1', tenantId: 'wrong' } }, 'tenant_identity_mismatch'],
    [{ ...base, scopes: [] }, 'required_scope_denied'],
    [{ ...base, capabilities: [] }, 'capability_probe_failed'],
  ];
  for (const [providerReadback, reason] of cases) {
    const projection = evaluateConnectionHealth(healthy({ providerReadback }), { now });
    assert.equal(projection.state, 'Needs attention');
    assert.equal(projection.connected, false);
    assert.equal(projection.reasonCode, reason);
  }
});

test('audit evidence contains references but not credential material or provider payloads', () => {
  const projection = evaluateConnectionHealth(healthy(), { now });
  const encoded = JSON.stringify(projection.auditEvent);
  assert.match(encoded, /receipt-1/);
  assert.doesNotMatch(encoded, /expiresAt|credential|rawBody|authorization|token/i);
});

test('audit chain detects tampering and rejects secret-shaped evidence', async () => {
  const { appendAuditEvent } = await import('../packages/pandora-connections-quality/src/audit-chain.mjs');
  const first = evaluateConnectionHealth(healthy(), { now }).auditEvent;
  const second = evaluateConnectionHealth(
    healthy({ previousState: 'Connected' }),
    { now: '2026-10-01T12:01:00.000Z', previousEventHash: first.eventHash },
  ).auditEvent;
  assert.equal(verifyAuditChain([first, second]).valid, true);
  assert.deepEqual(verifyAuditChain([first, { ...second, reasonCode: 'tampered' }]), {
    valid: false,
    index: 1,
    reason: 'event_hash_mismatch',
  });
  assert.throws(
    () => appendAuditEvent({
      eventType: 'connection.test',
      actorId: 'tester',
      organizationId: 'organization-1',
      subjectId: 'connection-1',
      outcome: 'rejected',
      reasonCode: 'secret_test',
      occurredAt: now,
      evidence: { accessToken: 'should-never-appear' },
    }),
    /not allowed in audit evidence/,
  );
});
