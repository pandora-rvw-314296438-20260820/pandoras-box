const assert = require('node:assert/strict');
const test = require('node:test');
const express = require('express');

const { createOperatorApiApp } = require('../dist/operator/api.js');
const { normalizeFocusToken, focusIntentContext } = require('../dist/operator/project-change.js');

const USER_ID = 'e5f5744e-554b-4f92-aad2-3f58ae6a33ad';
const ORGANIZATION_ID = '2270b266-59da-4c39-bfd9-9f8d08352af0';
const PROJECT_ID = '11111111-1111-4111-8111-111111111111';
const VERSION_ID = '22222222-2222-4222-8222-222222222222';
const ACCESS_TOKEN = 'human-access-token-that-is-long-enough-for-the-test';
const DIGEST = 'a'.repeat(64);

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

function appFor({ role = 'owner', scopes = ['openid', 'projectos:execute'], executor }) {
  const app = express();
  app.use(express.json());
  app.use(createOperatorApiApp({
    authenticator: {
      async authenticate(header) {
        if (header !== `Bearer ${ACCESS_TOKEN}`) throw Object.assign(new Error('invalid session'), { status: 401 });
        return { userId: USER_ID, accessToken: ACCESS_TOKEN, scopeClaimsPresent: true, scopes };
      },
    },
    membershipResolver: {
      async resolve() {
        return { organizationId: ORGANIZATION_ID, userId: USER_ID, role };
      },
    },
    organizationId: ORGANIZATION_ID,
    supabaseUrl: 'https://example.supabase.co',
    supabasePublishableKey: 'sb_publishable_testkey012345678901234567890',
    allowedOrigins: ['https://mcpmaster.vercel.app'],
    requestsPerMinute: 100,
    statusProvider: { async refresh() { return { schemaVersion: '1.0.0', authoritative: false }; } },
    projectChangeExecutor: executor,
    runtimeFactory: () => express.Router(),
  }));
  return app;
}

test('owner project change uses the exact execute scope and durable route', async () => {
  let observed;
  const executor = async (input) => {
    observed = input;
    return { ok: true, httpStatus: 202, state: 'working', stage: 'building', intentId: '33333333-3333-4333-8333-333333333333' };
  };
  await withServer(appFor({ executor }), async (origin) => {
    const response = await fetch(`${origin}/projects/${PROJECT_ID}/change`, {
      method: 'POST',
      headers: { authorization: `Bearer ${ACCESS_TOKEN}`, 'content-type': 'application/json' },
      body: JSON.stringify({ change: 'Make the hero more premium.', idempotencyKey: 'web-change-12345678' }),
    });
    assert.equal(response.status, 202);
    assert.equal((await response.json()).stage, 'building');
  });
  assert.equal(observed.projectId, PROJECT_ID);
  assert.equal(observed.actor.identity.accessToken, ACCESS_TOKEN);
  assert.equal(observed.body.change, 'Make the hero more premium.');
});

test('operator role cannot execute project changes', async () => {
  await withServer(appFor({ role: 'operator', executor: async () => ({ ok: true }) }), async (origin) => {
    const response = await fetch(`${origin}/projects/${PROJECT_ID}/change`, {
      method: 'POST',
      headers: { authorization: `Bearer ${ACCESS_TOKEN}`, 'content-type': 'application/json' },
      body: JSON.stringify({ change: 'Change this.', idempotencyKey: 'web-change-12345678' }),
    });
    assert.equal(response.status, 403);
    assert.equal((await response.json()).error.code, 'EXECUTOR_ROLE_REQUIRED');
  });
});

test('project change rejects a session without projectos execute scope', async () => {
  await withServer(appFor({ scopes: ['openid', 'projectos:read'], executor: async () => ({ ok: true }) }), async (origin) => {
    const response = await fetch(`${origin}/projects/${PROJECT_ID}/change`, {
      method: 'POST',
      headers: { authorization: `Bearer ${ACCESS_TOKEN}`, 'content-type': 'application/json' },
      body: JSON.stringify({ change: 'Change this.', idempotencyKey: 'web-change-12345678' }),
    });
    assert.equal(response.status, 403);
    assert.match(response.headers.get('www-authenticate'), /projectos:execute/);
  });
});

test('FocusToken v2 is exact-version bound and expires after at most fifteen minutes', () => {
  const issued = new Date('2026-09-08T00:00:00.000Z');
  const expires = new Date(issued.getTime() + 15 * 60 * 1000);
  const token = normalizeFocusToken({
    schemaVersion: 2,
    projectId: PROJECT_ID,
    versionId: VERSION_ID,
    artifactDigest: DIGEST,
    componentId: 'hero-title',
    semanticId: 'heading:welcome',
    selector: '#hero-title',
    role: 'heading',
    accessibleName: 'Welcome',
    route: '/',
    sourceFile: 'index.html',
    sourceLine: 42,
    bounds: { x: 20, y: 30, width: 320, height: 64 },
    issuedAt: issued.toISOString(),
    expiresAt: expires.toISOString(),
  }, { projectId: PROJECT_ID, versionId: VERSION_ID, artifactDigest: DIGEST }, issued.getTime() + 1000);
  assert.match(focusIntentContext(token), /FocusToken\(v2\)/);
  assert.match(focusIntentContext(token), /component_id=hero-title/);
  assert.throws(() => normalizeFocusToken(token, {
    projectId: PROJECT_ID,
    versionId: '44444444-4444-4444-8444-444444444444',
    artifactDigest: DIGEST,
  }, issued.getTime() + 1000), /older preview/);
  assert.throws(() => normalizeFocusToken(token, {
    projectId: PROJECT_ID,
    versionId: VERSION_ID,
    artifactDigest: DIGEST,
  }, expires.getTime()), /older preview/);
});
