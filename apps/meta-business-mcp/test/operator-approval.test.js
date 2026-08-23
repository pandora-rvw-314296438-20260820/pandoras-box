const assert = require('node:assert/strict');
const test = require('node:test');

const express = require('express');
const { createOperatorApiApp } = require('../dist/operator/api.js');
const { createHttpApp } = require('../../../dist/http-app.js');

const USER_ID = 'e5f5744e-554b-4f92-aad2-3f58ae6a33ad';
const ORGANIZATION_ID = '2270b266-59da-4c39-bfd9-9f8d08352af0';
const PLAN_ID = 'ed34d145-f738-47b7-a985-15e75342ba2c';
const ACCESS_TOKEN = 'human-access-token-that-is-long-enough-for-the-test';

async function withServer(app, action) {
  const server = await new Promise((resolve) => {
    const value = app.listen(0, '127.0.0.1', () => resolve(value));
  });
  try {
    return await action(`http://127.0.0.1:${server.address().port}`);
  } finally {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  }
}

function bridge(role, seen, membershipOverrides = {}, identityOverrides = {}) {
  const runtimeFactory = () => {
    const embedded = express.Router();
    embedded.post('/tools/approve', (request, response) => {
      seen.push({
        authorization: request.header('authorization'),
        approval: request.header('x-approval-token'),
        approver: request.header('x-approver-id'),
        oidc: request.header('x-vercel-oidc-token'),
        scHeaders: request.header('x-vercel-sc-headers'),
      });
      response.json({ ok: true, plan: { planId: request.body.planId, status: 'approved' } });
    });
    embedded.get('/plans', (_request, response) => {
      seen.push({ route: 'read' });
      response.json({ ok: true, plans: [] });
    });
    embedded.post('/tools/plan', (_request, response) => {
      seen.push({ route: 'plan' });
      response.json({ ok: true });
    });
    embedded.post('/tools/execute', (_request, response) => {
      seen.push({ route: 'execute' });
      response.json({ ok: true });
    });
    return embedded;
  };
  const app = express();
  app.use(express.json());
  app.use(createOperatorApiApp({
    authenticator: {
      async authenticate(header) {
        if (header !== `Bearer ${ACCESS_TOKEN}`) throw Object.assign(new Error('invalid session'), { status: 401 });
        return { userId: USER_ID, accessToken: ACCESS_TOKEN, aal: 'aal1', ...identityOverrides };
      },
    },
    membershipResolver: {
      async resolve() {
        if (!role) return null;
        return { organizationId: ORGANIZATION_ID, userId: USER_ID, role, ...membershipOverrides };
      },
    },
    organizationId: ORGANIZATION_ID,
    supabaseUrl: 'https://example.supabase.co',
    supabasePublishableKey: 'sb_publishable_testkey012345678901234567890',
    allowedOrigins: ['https://mcpmaster.vercel.app'],
    requestsPerMinute: 100,
    runtimeFactory,
  }));
  return app;
}

for (const role of ['owner', 'admin']) {
  test(`operator bridge permits authenticated ${role} AAL1 approval`, async () => {
    const seen = [];
    await withServer(bridge(role, seen), async (origin) => {
      const response = await fetch(`${origin}/tools/approve`, {
        method: 'POST',
        headers: {
          authorization: `Bearer ${ACCESS_TOKEN}`,
          'content-type': 'application/json',
          'x-approval-token': 'attacker-approval-token',
          'x-approver-id': 'attacker-approver',
          'x-vercel-oidc-token': 'attacker-oidc',
          'x-vercel-sc-headers': 'attacker-internal-envelope',
        },
        body: JSON.stringify({ planId: PLAN_ID }),
      });
      assert.equal(response.status, 200);
    });
    assert.equal(seen.length, 1);
    assert.match(seen[0].authorization, /^Bearer /);
    assert.notEqual(seen[0].authorization, `Bearer ${ACCESS_TOKEN}`);
    assert.notEqual(seen[0].approval, 'attacker-approval-token');
    assert.equal(seen[0].approver, `supabase:${USER_ID}`);
    assert.equal(seen[0].oidc, undefined);
    assert.equal(seen[0].scHeaders, undefined);
    assert.doesNotMatch(seen[0].approver, /aal/i);
  });
}

for (const role of ['operator', 'member', 'viewer']) {
  test(`operator bridge denies ${role} approval`, async () => {
    const seen = [];
    await withServer(bridge(role, seen), async (origin) => {
      const response = await fetch(`${origin}/tools/approve`, {
        method: 'POST',
        headers: { authorization: `Bearer ${ACCESS_TOKEN}`, 'content-type': 'application/json' },
        body: JSON.stringify({ planId: PLAN_ID }),
      });
      assert.equal(response.status, role === 'operator' ? 403 : 403);
      const body = await response.json();
      assert.match(body.error.message, role === 'operator' ? /owner or admin/ : /membership/);
    });
    assert.equal(seen.length, 0);
  });
}

test('operator bridge denies unauthenticated approval', async () => {
  const seen = [];
  await withServer(bridge('owner', seen), async (origin) => {
    const response = await fetch(`${origin}/tools/approve`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ planId: PLAN_ID }),
    });
    assert.equal(response.status, 401);
  });
  assert.equal(seen.length, 0);
});

test('operator bridge rejects resolver output for another organization or user', async () => {
  for (const mismatch of [
    { organizationId: 'd2d4cf70-d915-477a-af62-218f90ef60c4' },
    { userId: 'f678af44-344d-412c-b5fd-63ec48dcce29' },
  ]) {
    const seen = [];
    await withServer(bridge('owner', seen, mismatch), async (origin) => {
      const response = await fetch(`${origin}/tools/approve`, {
        method: 'POST',
        headers: { authorization: `Bearer ${ACCESS_TOKEN}`, 'content-type': 'application/json' },
        body: JSON.stringify({ planId: PLAN_ID }),
      });
      assert.equal(response.status, 403);
    });
    assert.equal(seen.length, 0);
  }
});

test('operator auth config no longer claims MFA is required', async () => {
  await withServer(bridge('owner', []), async (origin) => {
    const response = await fetch(`${origin}/auth/config`);
    const body = await response.json();
    assert.equal(response.status, 200);
    assert.equal(body.mfaRequiredForApproval, false);
  });
});

test('operator approval rejects OAuth scope undergrant and malformed empty scope claims', async () => {
  for (const scopes of [
    ['openid', 'projectos:read'],
    ['openid', 'email', 'profile'],
    [],
  ]) {
    const seen = [];
    await withServer(bridge('owner', seen, {}, { scopeClaimsPresent: true, scopes }), async (origin) => {
      const response = await fetch(`${origin}/tools/approve`, {
        method: 'POST',
        headers: { authorization: `Bearer ${ACCESS_TOKEN}`, 'content-type': 'application/json' },
        body: JSON.stringify({ planId: PLAN_ID }),
      });
      const body = await response.json();
      assert.equal(response.status, 403);
      assert.equal(body.error.code, 'OPERATOR_SCOPE_REQUIRED');
      assert.match(response.headers.get('www-authenticate'), /projectos:approve/);
    });
    assert.equal(seen.length, 0);
  }
});

test('operator approval accepts the exact OAuth action scope without AAL2', async () => {
  const seen = [];
  await withServer(bridge('admin', seen, {}, {
    scopeClaimsPresent: true,
    scopes: ['openid', 'projectos:approve'],
  }), async (origin) => {
    const response = await fetch(`${origin}/tools/approve`, {
      method: 'POST',
      headers: { authorization: `Bearer ${ACCESS_TOKEN}`, 'content-type': 'application/json' },
      body: JSON.stringify({ planId: PLAN_ID }),
    });
    assert.equal(response.status, 200);
  });
  assert.equal(seen.length, 1);
});

test('operator bridge preserves only the platform-captured OIDC token for the real durable ledger', async () => {
  const trustedToken = 'trusted-platform-workload-token-'.padEnd(80, 't');
  const observedTokens = [];
  const ledger = {
    async createPlan(token, input) {
      observedTokens.push(token);
      return {
        planId: PLAN_ID,
        requestId: input.requestId,
        tool: input.tool,
        risk: input.risk,
        args: input.args,
        payloadHash: input.payloadHash,
        status: 'pending',
        expiresAt: input.expiresAt,
      };
    },
  };
  const app = express();
  app.use(express.json());
  app.use((request, _response, next) => {
    Object.defineProperty(request, '__canonicalVercelOidcToken', {
      configurable: false,
      enumerable: false,
      writable: false,
      value: trustedToken,
    });
    next();
  });
  app.use(createOperatorApiApp({
    authenticator: {
      async authenticate() {
        return {
          userId: USER_ID,
          accessToken: ACCESS_TOKEN,
          scopeClaimsPresent: true,
          scopes: ['openid', 'projectos:plan'],
        };
      },
    },
    membershipResolver: {
      async resolve() {
        return { organizationId: ORGANIZATION_ID, userId: USER_ID, role: 'owner' };
      },
    },
    organizationId: ORGANIZATION_ID,
    supabaseUrl: 'https://example.supabase.co',
    supabasePublishableKey: 'sb_publishable_testkey012345678901234567890',
    allowedOrigins: ['https://mcpmaster.vercel.app'],
    requestsPerMinute: 100,
    runtimeFactory: (config) => createHttpApp(
      config,
      { async resolve() { return { allowedOrigins: ['https://mcpmaster.vercel.app'] }; } },
      ledger,
      { async consume() { return { allowed: true }; } },
      async () => [],
      async () => ({}),
    ),
  }));

  await withServer(app, async (origin) => {
    const response = await fetch(`${origin}/tools/plan`, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${ACCESS_TOKEN}`,
        'content-type': 'application/json',
        'x-vercel-oidc-token': 'attacker-controlled-token',
      },
      body: JSON.stringify({
        tool: 'github.get-repository',
        args: { owner: 'banataosystems', repo: 'Pandoras-box' },
      }),
    });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).durable, true);
  });
  assert.deepEqual(observedTokens, [trustedToken]);
});

test('operator OAuth scopes remain separated across read, plan, and execute actions', async () => {
  const cases = [
    { method: 'GET', path: '/plans', granted: 'projectos:plan', required: 'projectos:read' },
    { method: 'POST', path: '/tools/plan', granted: 'projectos:read', required: 'projectos:plan' },
    { method: 'POST', path: '/tools/execute', granted: 'projectos:approve', required: 'projectos:execute' },
  ];
  for (const entry of cases) {
    const seen = [];
    await withServer(bridge('owner', seen, {}, {
      scopeClaimsPresent: true,
      scopes: ['openid', entry.granted],
    }), async (origin) => {
      const response = await fetch(`${origin}${entry.path}`, {
        method: entry.method,
        headers: { authorization: `Bearer ${ACCESS_TOKEN}`, 'content-type': 'application/json' },
        body: entry.method === 'POST' ? JSON.stringify({ planId: PLAN_ID }) : undefined,
      });
      assert.equal(response.status, 403);
      assert.match(response.headers.get('www-authenticate'), new RegExp(entry.required));
    });
    assert.equal(seen.length, 0);
  }
});
