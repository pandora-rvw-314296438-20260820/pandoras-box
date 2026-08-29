'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { buildPandoraLifecycleEvent } = require('../src/projectos/pandora-lifecycle.js');
const {
  normalizeHost,
  createPostHogCaptureTransport,
} = require('../src/projectos/pandora-posthog-transport.js');
const {
  runtimeEnvironment,
  createPandoraPostHogTelemetryFromEnv,
} = require('../src/projectos/pandora-posthog-runtime.js');

const KEY = 'k'.repeat(48);
const TOKEN = 'phc_' + 'a'.repeat(40);

function envelope(environment = 'preview') {
  return buildPandoraLifecycleEvent({
    event: 'pandora_intent_received',
    actorId: 'actor-real-id',
    organizationId: '11111111-1111-4111-8111-111111111111',
    projectId: '22222222-2222-4222-8222-222222222222',
    executionId: 'exec_posthog_transport_001',
    environment,
    proofStage: 'implemented',
    properties: { result: 'accepted' },
    timestamp: '2026-08-29T07:00:00.000Z',
  }, KEY);
}

test('PostHog transport sends only the bounded canonical lifecycle envelope', async () => {
  let request;
  const transport = createPostHogCaptureTransport({
    projectToken: TOKEN,
    host: 'https://us.i.posthog.com',
    fetchImpl: async (url, init) => {
      request = { url, init };
      return { ok: true, status: 200 };
    },
  });
  const result = await transport.capture(envelope());
  assert.equal(result.accepted, true);
  assert.equal(request.url, 'https://us.i.posthog.com/i/v0/e/');
  const body = JSON.parse(request.init.body);
  assert.equal(body.api_key, TOKEN);
  assert.equal(body.event, 'pandora_intent_received');
  assert.match(body.properties.distinct_id, /^actor_[A-Za-z0-9_-]{32}$/);
  assert.match(body.properties.organization_key, /^org_[A-Za-z0-9_-]{32}$/);
  assert.match(body.properties.project_key, /^project_[A-Za-z0-9_-]{32}$/);
  assert.equal(body.properties.product_key, 'pandoras_box');
  assert.equal(body.properties.environment, 'preview');
  assert.equal(body.properties.timestamp, '2026-08-29T07:00:00.000Z');
  assert.equal(JSON.stringify(body).includes('actor-real-id'), false);
});

test('PostHog transport rejects non-allowlisted hosts', () => {
  assert.throws(() => normalizeHost('https://example.com'), /allowlisted/);
});

test('PostHog transport keeps provider response bodies out of errors', async () => {
  const transport = createPostHogCaptureTransport({
    projectToken: TOKEN,
    fetchImpl: async () => ({ ok: false, status: 401, text: async () => `secret ${TOKEN}` }),
  });
  await assert.rejects(() => transport.capture(envelope()), error => {
    assert.equal(error.code, 'posthog_http_401');
    assert.equal(String(error.message).includes(TOKEN), false);
    return true;
  });
});

test('PostHog transport fails closed for production unless separately approved', async () => {
  const transport = createPostHogCaptureTransport({ projectToken: TOKEN, fetchImpl: async () => ({ ok: true, status: 200 }) });
  await assert.rejects(() => transport.capture(envelope('production')), /not approved/);
});

test('runtime environment maps Vercel environments without inventing production', () => {
  assert.equal(runtimeEnvironment({ VERCEL_ENV: 'preview' }), 'preview');
  assert.equal(runtimeEnvironment({ VERCEL_ENV: 'production' }), 'production');
  assert.equal(runtimeEnvironment({ NODE_ENV: 'test' }), 'test');
  assert.equal(runtimeEnvironment({}), 'unknown');
});

test('disabled runtime needs no provider credential', async () => {
  const telemetry = createPandoraPostHogTelemetryFromEnv({ env: { PANDORA_POSTHOG_TELEMETRY_ENABLED: 'false', VERCEL_ENV: 'preview' }, logger: null });
  assert.deepEqual(await telemetry.captureLifecycle({}), { sent: false, status: 'disabled' });
});

test('enabled runtime fails closed when secret inputs are missing', () => {
  assert.throws(() => createPandoraPostHogTelemetryFromEnv({ env: { PANDORA_POSTHOG_TELEMETRY_ENABLED: 'true', VERCEL_ENV: 'preview' } }), /project token/);
});

test('production runtime cannot be enabled without separate approval', () => {
  assert.throws(() => createPandoraPostHogTelemetryFromEnv({ env: {
    PANDORA_POSTHOG_TELEMETRY_ENABLED: 'true',
    PANDORA_POSTHOG_PROJECT_TOKEN: TOKEN,
    PANDORA_POSTHOG_PSEUDONYMIZATION_KEY: KEY,
    VERCEL_ENV: 'production',
  }, fetchImpl: async () => ({ ok: true, status: 200 }), logger: null }), /separate explicit approval/);
});
