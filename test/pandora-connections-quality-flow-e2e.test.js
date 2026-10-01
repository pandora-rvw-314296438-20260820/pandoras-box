import assert from 'node:assert/strict';
import test from 'node:test';

import { verifyAuditChain } from '../packages/pandora-connections-quality/src/audit-chain.mjs';
import {
  createConnectionFlow,
  transitionConnectionFlow,
} from '../packages/pandora-connections-quality/src/flow-harness.mjs';

const now = '2026-10-01T12:00:00.000Z';

function readback(accountId = 'account-1', overrides = {}) {
  return {
    input: {
      lifecycle: 'active',
      credential: { state: 'active', expiresAt: '2026-12-01T00:00:00.000Z' },
      accountBinding: { accountId, tenantId: 'tenant-1' },
      requiredScopes: ['records.read'],
      requiredCapabilities: ['records.list'],
      providerReadback: {
        verified: true,
        receiptId: `receipt-${accountId}`,
        status: 'healthy',
        observedAt: '2026-10-01T11:59:30.000Z',
        identity: { accountId, tenantId: 'tenant-1' },
        scopes: ['records.read'],
        capabilities: ['records.list'],
        ...overrides,
      },
    },
  };
}

function initial(surface, status = 'Disconnected') {
  return createConnectionFlow({
    surface,
    connectionId: `connection-${surface}`,
    organizationId: 'organization-1',
    provider: 'example',
    status,
  });
}

function authorize(surface, state) {
  const started = transitionConnectionFlow(state, { type: 'CONNECT' }, { now });
  return transitionConnectionFlow(
    started,
    {
      type: 'PROVIDER_RETURN',
      outcome: 'approved',
      returnChannel: surface === 'web' ? 'https_callback' : 'app_link',
    },
    { now },
  );
}

for (const surface of ['web', 'mobile']) {
  test(`${surface} connect waits for provider readback and then becomes Connected`, () => {
    const verifying = authorize(surface, initial(surface));
    assert.equal(verifying.status, 'Verifying');
    assert.equal(verifying.connected, false);
    const connected = transitionConnectionFlow(verifying, { type: 'PROVIDER_READBACK', ...readback() }, { now });
    assert.equal(connected.status, 'Connected');
    assert.equal(connected.connected, true);
    assert.equal(connected.activeAccountId, 'account-1');
    assert.equal(verifyAuditChain(connected.auditChain).valid, true);
  });

  test(`${surface} back and cancel never create a false Connected state`, () => {
    for (const outcome of ['back', 'cancelled']) {
      const authorizing = transitionConnectionFlow(initial(surface), { type: 'CONNECT' }, { now });
      const returned = transitionConnectionFlow(
        authorizing,
        { type: 'PROVIDER_RETURN', outcome },
        { now },
      );
      assert.equal(returned.status, 'Disconnected');
      assert.equal(returned.connected, false);
    }
  });

  test(`${surface} denied scope and degraded readback become Needs attention`, () => {
    const authorizing = transitionConnectionFlow(initial(surface), { type: 'CONNECT' }, { now });
    const denied = transitionConnectionFlow(
      authorizing,
      { type: 'PROVIDER_RETURN', outcome: 'denied' },
      { now },
    );
    assert.equal(denied.status, 'Needs attention');
    assert.equal(denied.connected, false);

    const verifying = authorize(surface, initial(surface));
    const degraded = transitionConnectionFlow(
      verifying,
      { type: 'PROVIDER_READBACK', ...readback('account-1', { status: 'degraded' }) },
      { now },
    );
    assert.equal(degraded.status, 'Needs attention');
    assert.equal(degraded.connected, false);
  });

  test(`${surface} reconnect, account switch, and disconnect require fresh verification`, () => {
    let state = authorize(surface, initial(surface, 'Needs attention'));
    state = transitionConnectionFlow(state, { type: 'PROVIDER_READBACK', ...readback() }, { now });
    assert.equal(state.status, 'Connected');

    state = transitionConnectionFlow(state, { type: 'SWITCH_ACCOUNT', accountId: 'account-2' }, { now });
    assert.equal(state.status, 'Verifying');
    assert.equal(state.connected, false);
    state = transitionConnectionFlow(state, { type: 'PROVIDER_READBACK', ...readback('account-2') }, { now });
    assert.equal(state.status, 'Connected');
    assert.equal(state.activeAccountId, 'account-2');

    state = transitionConnectionFlow(state, { type: 'DISCONNECT' }, { now });
    assert.equal(state.status, 'Disconnected');
    assert.equal(state.connected, false);
    assert.equal(state.activeAccountId, null);
    assert.equal(verifyAuditChain(state.auditChain).valid, true);
  });
}

test('web and mobile reject each other\'s callback channels', () => {
  const cases = [
    ['web', 'app_link'],
    ['mobile', 'https_callback'],
  ];
  for (const [surface, returnChannel] of cases) {
    const authorizing = transitionConnectionFlow(initial(surface), { type: 'CONNECT' }, { now });
    const failed = transitionConnectionFlow(
      authorizing,
      { type: 'PROVIDER_RETURN', outcome: 'approved', returnChannel },
      { now },
    );
    assert.equal(failed.status, 'Needs attention');
    assert.equal(failed.connected, false);
  }
});

test('account switch identity mismatch cannot retain Connected', () => {
  let state = authorize('web', initial('web'));
  state = transitionConnectionFlow(state, { type: 'PROVIDER_READBACK', ...readback() }, { now });
  state = transitionConnectionFlow(state, { type: 'SWITCH_ACCOUNT', accountId: 'account-2' }, { now });
  const mismatched = readback('account-2');
  mismatched.input.providerReadback.identity.accountId = 'account-1';
  state = transitionConnectionFlow(state, { type: 'PROVIDER_READBACK', ...mismatched }, { now });
  assert.equal(state.status, 'Needs attention');
  assert.equal(state.connected, false);
  assert.equal(state.activeAccountId, 'account-1');
});
