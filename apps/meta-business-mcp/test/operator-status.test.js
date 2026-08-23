const assert = require('node:assert/strict');
const test = require('node:test');
const express = require('express');

const { createOperatorApiApp } = require('../dist/operator/api.js');

const USER_ID = 'e5f5744e-554b-4f92-aad2-3f58ae6a33ad';
const ORGANIZATION_ID = '2270b266-59da-4c39-bfd9-9f8d08352af0';
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

function appFor(pack, identity = {}, workerContextProvider = undefined, statusProvider = undefined, platformOidc = undefined) {
  const app = express();
  app.use(express.json());
  if (platformOidc) {
    app.use((request, _response, next) => {
      Object.defineProperty(request, '__canonicalVercelOidcToken', { value: platformOidc });
      next();
    });
  }
  app.use(createOperatorApiApp({
    authenticator: {
      async authenticate(header) {
        if (header !== `Bearer ${ACCESS_TOKEN}`) throw Object.assign(new Error('invalid session'), { status: 401 });
        return { userId: USER_ID, accessToken: ACCESS_TOKEN, aal: 'aal1', ...identity };
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
    statusProvider: statusProvider || { async refresh() { return pack; } },
    workerContextProvider,
    runtimeFactory: () => express.Router(),
  }));
  return app;
}

test('operator status requires the authenticated ProjectOS read scope', async () => {
  await withServer(appFor({}, {
    scopeClaimsPresent: true,
    scopes: ['openid', 'projectos:plan'],
  }), async (origin) => {
    const response = await fetch(`${origin}/status`, { headers: { authorization: `Bearer ${ACCESS_TOKEN}` } });
    assert.equal(response.status, 403);
    assert.match(response.headers.get('www-authenticate'), /projectos:read/);
  });
});

test('operator status passes only the platform-captured workload identity to refresh', async () => {
  const pack = { schemaVersion: '1.0.0', authoritative: false, status: 'stale', phases: [], tasks: [] };
  let refreshContext;
  await withServer(appFor(pack, {}, undefined, {
    async refresh(context) {
      refreshContext = context;
      return pack;
    },
  }, 'platform-oidc-token'), async (origin) => {
    const response = await fetch(`${origin}/status`, {
      headers: {
        authorization: `Bearer ${ACCESS_TOKEN}`,
        'x-vercel-oidc-token': 'attacker-controlled-token',
      },
    });
    assert.equal(response.status, 503);
  });
  assert.deepEqual(refreshContext, { vercelOidcToken: 'platform-oidc-token' });
});

test('operator status returns the complete non-authoritative pack with 503 and no-store', async () => {
  const pack = {
    schemaVersion: '1.0.0',
    authoritative: false,
    status: 'stale',
    progress: { completed: 2, total: 5, percent: 40 },
    phases: [],
    tasks: [],
    blockers: ['rollback-unproven'],
  };
  await withServer(appFor(pack, {
    scopeClaimsPresent: true,
    scopes: ['openid', 'projectos:read'],
  }), async (origin) => {
    const response = await fetch(`${origin}/status`, { headers: { authorization: `Bearer ${ACCESS_TOKEN}` } });
    assert.equal(response.status, 503);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.deepEqual(await response.json(), pack);
  });
});

test('operator status returns 200 only for an authoritative pack', async () => {
  const pack = { schemaVersion: '1.0.0', authoritative: true, status: 'current', phases: [], tasks: [] };
  await withServer(appFor(pack), async (origin) => {
    const response = await fetch(`${origin}/status`, { headers: { authorization: `Bearer ${ACCESS_TOKEN}` } });
    assert.equal(response.status, 200);
  });
});

test('owner can attach fresh Memory context using only a durable plan id', async () => {
  const planId = '8ec3acda-4fb7-48b2-81f4-6885c005f561';
  let observedPlanId;
  await withServer(appFor({}, {
    scopeClaimsPresent: true,
    scopes: ['openid', 'projectos:plan'],
  }, {
    async attachExactPlan(value) {
      observedPlanId = value;
      return {
        planId: value,
        requestId: 'a4c6e81c-89d0-4a63-9b8f-18e41bd2619a',
        contextHash: 'a'.repeat(64),
        status: 'available',
      };
    },
  }), async (origin) => {
    const response = await fetch(`${origin}/worker-plans/${planId}/context`, {
      method: 'POST',
      headers: { authorization: `Bearer ${ACCESS_TOKEN}`, 'content-type': 'application/json' },
      body: '{}',
    });
    assert.equal(response.status, 200);
    assert.equal(observedPlanId, planId);
    assert.equal((await response.json()).context.contextHash, 'a'.repeat(64));
  });
});

test('worker context route rejects caller-supplied plan fields and wrong scopes', async () => {
  const planId = '8ec3acda-4fb7-48b2-81f4-6885c005f561';
  const provider = { async attachExactPlan(value) { return { planId: value }; } };
  await withServer(appFor({}, {
    scopeClaimsPresent: true,
    scopes: ['openid', 'projectos:read'],
  }, provider), async (origin) => {
    const response = await fetch(`${origin}/worker-plans/${planId}/context`, {
      method: 'POST',
      headers: { authorization: `Bearer ${ACCESS_TOKEN}`, 'content-type': 'application/json' },
      body: '{}',
    });
    assert.equal(response.status, 403);
    assert.match(response.headers.get('www-authenticate'), /projectos:plan/);
  });
  await withServer(appFor({}, {}, provider), async (origin) => {
    const response = await fetch(`${origin}/worker-plans/${planId}/context`, {
      method: 'POST',
      headers: { authorization: `Bearer ${ACCESS_TOKEN}`, 'content-type': 'application/json' },
      body: JSON.stringify({ exactSha: 'f'.repeat(40) }),
    });
    assert.equal(response.status, 400);
  });
});
