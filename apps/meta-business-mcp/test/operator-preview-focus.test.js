const assert = require('node:assert/strict');
const test = require('node:test');
const express = require('express');
const { createHash } = require('node:crypto');

const { createOperatorApiApp } = require('../dist/operator/api.js');
const { createFocusPreviewExecutor } = require('../dist/operator/preview-focus.js');

const USER_ID = 'e5f5744e-554b-4f92-aad2-3f58ae6a33ad';
const ORGANIZATION_ID = '2270b266-59da-4c39-bfd9-9f8d08352af0';
const PROJECT_ID = '11111111-1111-4111-8111-111111111111';
const VERSION_ID = '22222222-2222-4222-8222-222222222222';
const DEPLOYMENT_ID = '33333333-3333-4333-8333-333333333333';
const ACCESS_TOKEN = 'human-access-token-that-is-long-enough-for-the-test';
const ARTIFACT_DIGEST = 'a'.repeat(64);
const testPublishableKey = () => ['unit', 'test', 'value'].join('-');
const HTML = '<!doctype html><html><body><h1>Verified focus</h1></body></html>';
const HTML_BASE64 = Buffer.from(HTML, 'utf8').toString('base64');
const HTML_SHA = createHash('sha256').update(Buffer.from(HTML, 'utf8')).digest('hex');

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

function appFor({
  role = 'owner',
  scopes = ['openid', 'projectos:read'],
  focusPreviewExecutor = async () => ({
    ok: true,
    kind: 'pandora.web-focus-preview.v1',
    projectId: PROJECT_ID,
    versionId: VERSION_ID,
    artifactDigest: ARTIFACT_DIGEST,
    deploymentId: DEPLOYMENT_ID,
    provider: 'vercel',
    hostedUrl: 'https://pandora-example-mbanatao.vercel.app/',
    byteSize: Buffer.byteLength(HTML),
    sha256: HTML_SHA,
    htmlBase64: HTML_BASE64,
  }),
}) {
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
    supabasePublishableKey: testPublishableKey(),
    allowedOrigins: ['https://mcpmaster.vercel.app'],
    requestsPerMinute: 100,
    statusProvider: { async refresh() { return { schemaVersion: '1.0.0', authoritative: false }; } },
    projectChangeExecutor: async () => ({ ok: true, httpStatus: 202 }),
    focusPreviewExecutor,
    runtimeFactory: () => express.Router(),
  }));
  return app;
}

test('owner focus preview uses projectos read scope and exact project/version route', async () => {
  let observed;
  await withServer(appFor({
    focusPreviewExecutor: async (input) => {
      observed = input;
      return { ok: true, kind: 'pandora.web-focus-preview.v1', projectId: PROJECT_ID, versionId: VERSION_ID };
    },
  }), async (origin) => {
    const response = await fetch(`${origin}/projects/${PROJECT_ID}/focus-preview`, {
      method: 'POST',
      headers: { authorization: `Bearer ${ACCESS_TOKEN}`, 'content-type': 'application/json' },
      body: JSON.stringify({ versionId: VERSION_ID }),
    });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).versionId, VERSION_ID);
  });
  assert.equal(observed.projectId, PROJECT_ID);
  assert.equal(observed.actor.identity.accessToken, ACCESS_TOKEN);
  assert.deepEqual(observed.body, { versionId: VERSION_ID });
});

test('operator role cannot materialize focus preview', async () => {
  await withServer(appFor({ role: 'operator' }), async (origin) => {
    const response = await fetch(`${origin}/projects/${PROJECT_ID}/focus-preview`, {
      method: 'POST',
      headers: { authorization: `Bearer ${ACCESS_TOKEN}`, 'content-type': 'application/json' },
      body: JSON.stringify({ versionId: VERSION_ID }),
    });
    assert.equal(response.status, 403);
    assert.equal((await response.json()).error.code, 'EXECUTOR_ROLE_REQUIRED');
  });
});

test('focus preview rejects a session without projectos read scope', async () => {
  await withServer(appFor({ scopes: ['openid', 'projectos:execute'] }), async (origin) => {
    const response = await fetch(`${origin}/projects/${PROJECT_ID}/focus-preview`, {
      method: 'POST',
      headers: { authorization: `Bearer ${ACCESS_TOKEN}`, 'content-type': 'application/json' },
      body: JSON.stringify({ versionId: VERSION_ID }),
    });
    assert.equal(response.status, 403);
    assert.match(response.headers.get('www-authenticate') || '', /projectos:read/);
  });
});

function envelope(overrides = {}) {
  return {
    kind: 'pandora.web-focus-preview.v1',
    projectId: PROJECT_ID,
    versionId: VERSION_ID,
    artifactDigest: ARTIFACT_DIGEST,
    deploymentId: DEPLOYMENT_ID,
    provider: 'vercel',
    hostedUrl: 'https://pandora-example-mbanatao.vercel.app/',
    byteSize: Buffer.byteLength(HTML),
    sha256: HTML_SHA,
    htmlBase64: HTML_BASE64,
    ...overrides,
  };
}

test('broker forwards only the authenticated human bearer into exact focus materialization', async () => {
  let observed;
  const executor = createFocusPreviewExecutor({
    supabaseUrl: 'https://example.supabase.co',
    publishableKey: testPublishableKey(),
    async fetchFn(url, init) {
      observed = { url: String(url), init };
      return new Response(JSON.stringify(envelope()), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    },
  });
  const result = await executor({
    actor: { identity: { accessToken: ACCESS_TOKEN } },
    projectId: PROJECT_ID,
    body: { versionId: VERSION_ID },
  });
  assert.equal(result.sha256, HTML_SHA);
  assert.equal(result.artifactDigest, ARTIFACT_DIGEST);
  assert.match(observed.url, /\/functions\/v1\/pandora-preview-content$/);
  assert.equal(observed.init.headers.authorization, `Bearer ${ACCESS_TOKEN}`);
  assert.equal(JSON.parse(observed.init.body).mode, 'web_focus');
  assert.doesNotMatch(JSON.stringify(observed.init.headers), /service[_-]?role|github_pat_|Github_supabase/i);
});

test('broker rejects a digest-mismatched HTML envelope', async () => {
  const executor = createFocusPreviewExecutor({
    supabaseUrl: 'https://example.supabase.co',
    publishableKey: testPublishableKey(),
    async fetchFn() {
      return new Response(JSON.stringify(envelope({ sha256: 'b'.repeat(64) })), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    },
  });
  await assert.rejects(
    executor({
      actor: { identity: { accessToken: ACCESS_TOKEN } },
      projectId: PROJECT_ID,
      body: { versionId: VERSION_ID },
    }),
    /focus preview digest/,
  );
});

test('broker rejects extra client-controlled fields before calling Supabase', async () => {
  let fetches = 0;
  const executor = createFocusPreviewExecutor({
    supabaseUrl: 'https://example.supabase.co',
    publishableKey: testPublishableKey(),
    async fetchFn() {
      fetches += 1;
      return new Response('{}', { status: 200 });
    },
  });
  await assert.rejects(
    executor({
      actor: { identity: { accessToken: ACCESS_TOKEN } },
      projectId: PROJECT_ID,
      body: { versionId: VERSION_ID, url: 'https://attacker.example/' },
    }),
    /unsupported preview fields/,
  );
  assert.equal(fetches, 0);
});
