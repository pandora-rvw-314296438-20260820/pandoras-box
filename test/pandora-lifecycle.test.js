const assert = require('node:assert/strict');
const test = require('node:test');

const {
  PANDORA_LIFECYCLE_EVENTS,
  PANDORA_PRODUCT_KEY,
  PANDORA_PRIVACY_MODE,
  buildPandoraLifecycleEvent,
  createPandoraLifecycleTelemetry,
  derivePandoraPseudonymousKey,
  isPandoraPseudonymousKey,
  normalizePandoraEnvironment,
  pandoraLifecycleTelemetryEnabled,
  pandoraProductionTelemetryApproved,
} = require('../dist/pandora/pandora-lifecycle.js');

const KEY = 'phase-one-test-only-pseudonymization-key-00000000';

function validInput(overrides = {}) {
  return {
    event: 'pandora_execution_started',
    actorId: 'user-123',
    organizationId: 'organization-123',
    projectId: 'project-123',
    executionId: 'exec_abc12345',
    environment: 'staging',
    proofStage: 'implemented',
    timestamp: '2026-08-20T00:00:00.000Z',
    properties: {
      source_sha: 'a'.repeat(40),
      release_sha: 'b'.repeat(40),
      result: 'success',
      retry_count: 0,
      duration_ms: 125,
      model_provider: 'openai',
      model_name: 'gpt-5.6-pro',
      input_tokens: 10,
      output_tokens: 20,
      total_cost_usd: 0.01,
      latency_ms: 120,
      tool_class: 'github.read',
      evaluation_score: 1,
      evidence_count: 2,
    },
    ...overrides,
  };
}

test('exports exactly ten unique Pandora lifecycle events', () => {
  assert.equal(PANDORA_LIFECYCLE_EVENTS.length, 10);
  assert.equal(new Set(PANDORA_LIFECYCLE_EVENTS).size, 10);
});

test('derives deterministic HMAC pseudonyms without raw identifiers', () => {
  const actor = derivePandoraPseudonymousKey('actor', 'user-123', KEY);
  assert.equal(actor, derivePandoraPseudonymousKey('actor', 'user-123', KEY));
  assert.equal(isPandoraPseudonymousKey('actor', actor), true);
  assert.equal(actor.includes('user-123'), false);
  assert.notEqual(actor, derivePandoraPseudonymousKey('actor', 'user-124', KEY));
});

test('rejects weak pseudonymization keys', () => {
  assert.throws(
    () => derivePandoraPseudonymousKey('actor', 'user-123', 'short'),
    /at least 32/,
  );
});

test('builds a frozen metadata-only lifecycle envelope', () => {
  const event = buildPandoraLifecycleEvent(validInput(), KEY);
  assert.equal(event.event, 'pandora_execution_started');
  assert.equal(event.properties.product_key, PANDORA_PRODUCT_KEY);
  assert.equal(event.properties.privacy_mode, PANDORA_PRIVACY_MODE);
  assert.equal(event.properties.proof_stage, 'implemented');
  assert.equal(event.properties.environment, 'staging');
  assert.equal(event.properties.total_cost_usd, 0.01);
  assert.equal(isPandoraPseudonymousKey('actor', event.distinct_id), true);
  assert.equal(isPandoraPseudonymousKey('organization', event.properties.organization_key), true);
  assert.equal(isPandoraPseudonymousKey('project', event.properties.project_key), true);
  assert.equal(Object.isFrozen(event), true);
  assert.equal(Object.isFrozen(event.properties), true);
});

test('normalizes local and test to the database-compatible development environment', () => {
  assert.equal(normalizePandoraEnvironment('local'), 'development');
  assert.equal(normalizePandoraEnvironment('test'), 'development');
  assert.equal(normalizePandoraEnvironment('production'), 'production');
});

test('rejects unsupported lifecycle events, proof stages, environments, and execution ids', () => {
  assert.throws(
    () => buildPandoraLifecycleEvent(validInput({ event: 'pandora_prompt_captured' }), KEY),
    /unsupported lifecycle event/,
  );
  assert.throws(
    () => buildPandoraLifecycleEvent(validInput({ proofStage: 'done' }), KEY),
    /unsupported proof stage/,
  );
  assert.throws(
    () => buildPandoraLifecycleEvent(validInput({ environment: 'qa' }), KEY),
    /unsupported environment/,
  );
  assert.throws(
    () => buildPandoraLifecycleEvent(validInput({ executionId: 'raw-customer-id' }), KEY),
    /executionId/,
  );
});

test('rejects unknown metadata keys instead of forwarding them', () => {
  const input = validInput();
  input.properties.unreviewed_context = 'not-allowed';
  assert.throws(
    () => buildPandoraLifecycleEvent(input, KEY),
    /unknown telemetry key/,
  );
});

for (const forbiddenKey of [
  'prompt',
  'tool_arguments',
  'tool_result',
  'source_code',
  'authorization',
  'api_key',
  'customer_message',
]) {
  test(`rejects forbidden metadata key ${forbiddenKey}`, () => {
    const input = validInput();
    input.properties[forbiddenKey] = 'redacted';
    assert.throws(
      () => buildPandoraLifecycleEvent(input, KEY),
      /forbidden telemetry key/,
    );
  });
}

test('rejects sensitive-looking values in otherwise allowlisted string fields', () => {
  const bearer = validInput();
  bearer.properties.model_name = 'Bearer abcdefghijklmnopqrstuvwxyz123456';
  assert.throws(
    () => buildPandoraLifecycleEvent(bearer, KEY),
    /does not satisfy|sensitive data/,
  );

  const email = validInput();
  email.properties.model_name = 'owner@example.com';
  assert.throws(
    () => buildPandoraLifecycleEvent(email, KEY),
    /does not satisfy|sensitive data/,
  );
});

test('enforces numeric bounds for costs, evaluation scores, and token counts', () => {
  const cost = validInput();
  cost.properties.total_cost_usd = 10001;
  assert.throws(
    () => buildPandoraLifecycleEvent(cost, KEY),
    /outside the allowed range/,
  );

  const score = validInput();
  score.properties.evaluation_score = 1.1;
  assert.throws(
    () => buildPandoraLifecycleEvent(score, KEY),
    /outside the allowed range/,
  );

  const tokens = validInput();
  tokens.properties.input_tokens = -1;
  assert.throws(
    () => buildPandoraLifecycleEvent(tokens, KEY),
    /outside the allowed range/,
  );
});

test('serialized output contains no raw actor, organization, project, or HMAC key', () => {
  const serialized = JSON.stringify(buildPandoraLifecycleEvent(validInput(), KEY));
  for (const raw of ['user-123', 'organization-123', 'project-123', KEY]) {
    assert.equal(serialized.includes(raw), false);
  }
});

test('telemetry is disabled by default and performs no capture', async () => {
  let calls = 0;
  const telemetry = createPandoraLifecycleTelemetry({
    environment: 'staging',
    capture: async () => { calls += 1; },
  });
  const result = await telemetry.captureLifecycle(validInput());
  assert.deepEqual(result, { sent: false, status: 'disabled' });
  assert.equal(calls, 0);
});

test('production telemetry requires a separate explicit approval', () => {
  assert.throws(
    () => createPandoraLifecycleTelemetry({
      enabled: true,
      environment: 'production',
      capture: async () => {},
      pseudonymizationKey: KEY,
    }),
    /separate explicit approval/,
  );
});

test('enabled non-production telemetry captures only the validated envelope', async () => {
  const captured = [];
  const telemetry = createPandoraLifecycleTelemetry({
    enabled: true,
    environment: 'staging',
    capture: async (event) => captured.push(event),
    pseudonymizationKey: KEY,
  });
  const result = await telemetry.captureLifecycle(validInput({ environment: 'production' }));
  assert.equal(result.sent, true);
  assert.equal(captured.length, 1);
  assert.equal(captured[0].properties.environment, 'staging');
  assert.equal(captured[0].properties.product_key, 'pandoras_box');
});

test('capture failures expose only a bounded error code and not sensitive messages', async () => {
  const warnings = [];
  const telemetry = createPandoraLifecycleTelemetry({
    enabled: true,
    environment: 'staging',
    capture: async () => {
      const error = new Error('Bearer should-not-leak');
      error.code = 'UPSTREAM_502';
      throw error;
    },
    pseudonymizationKey: KEY,
    logger: { warn: (...args) => warnings.push(args) },
  });
  const result = await telemetry.captureLifecycle(validInput());
  assert.deepEqual(result, {
    sent: false,
    status: 'capture_failed',
    errorCode: 'UPSTREAM_502',
  });
  assert.equal(JSON.stringify(warnings).includes('should-not-leak'), false);
});

test('shutdown flush is optional, bounded, and failure-safe', async () => {
  let flushed = 0;
  const telemetry = createPandoraLifecycleTelemetry({
    enabled: true,
    environment: 'staging',
    capture: async () => {},
    flush: async () => { flushed += 1; },
    pseudonymizationKey: KEY,
  });
  assert.deepEqual(await telemetry.shutdown(), {
    flushed: true,
    status: 'flushed',
  });
  assert.equal(flushed, 1);
});

test('environment switches remain exact and default closed', () => {
  assert.equal(pandoraLifecycleTelemetryEnabled({}), false);
  assert.equal(
    pandoraLifecycleTelemetryEnabled({ PANDORA_POSTHOG_TELEMETRY_ENABLED: 'true' }),
    true,
  );
  assert.equal(
    pandoraLifecycleTelemetryEnabled({ PANDORA_POSTHOG_TELEMETRY_ENABLED: 'TRUE' }),
    false,
  );
  assert.equal(pandoraProductionTelemetryApproved({}), false);
  assert.equal(
    pandoraProductionTelemetryApproved({ PANDORA_POSTHOG_PRODUCTION_APPROVED: 'true' }),
    true,
  );
});
