const assert = require('node:assert/strict');
const test = require('node:test');

const { normalizeProductSignal, sanitizeProductProperties } = require('../dist/projectos/product-intelligence.js');

const HASH_SALT = 'phase-one-repository-test-hash-salt';

function lifecycleEnvelope(overrides = {}) {
  return {
    event: 'pandora_execution_failed',
    timestamp: '2026-08-20T00:00:00.000Z',
    distinct_id: `actor_${'0'.repeat(32)}`,
    properties: {
      product_key: 'pandoras_box',
      environment: 'staging',
      source_sha: 'a'.repeat(40),
      release_sha: 'b'.repeat(40),
      release_id: 'release-123',
      deployment_id: 'deployment-123',
      rollback_of_deployment_id: 'deployment-122',
      schema_version: '1.0.0',
      event_schema_version: 1,
      source_repo: 'pandora-rvw-314296438-20260820/pandoras-box',
      privacy_tier: 'pseudonymous_product',
      privacy_mode: 'strict_metadata_only',
      proof_stage: 'tested',
      organization_key: `org_${'1'.repeat(32)}`,
      project_key: `project_${'2'.repeat(32)}`,
      execution_id: 'exec_abc12345',
      failure_class: 'provider.unavailable',
      tool_class: 'github.read',
      model_provider: 'openai',
      model_name: 'gpt-5.6-pro',
      outcome_type: 'governed_execution',
      result: 'blocked',
      retry_count: 1,
      input_tokens: 10,
      output_tokens: 20,
      total_cost_usd: 0.01,
      evaluation_score: 1,
      evidence_count: 2,
      duration_ms: 125,
      latency_ms: 120,
      ...overrides,
    },
  };
}

test('approved Pandora lifecycle metadata survives the shared normalizer', () => {
  const event = lifecycleEnvelope();
  const normalized = normalizeProductSignal(event, HASH_SALT);

  assert.equal(normalized.productKey, 'pandoras_box');
  assert.equal(normalized.eventName, 'pandora_execution_failed');
  assert.equal(normalized.environment, 'staging');
  assert.equal(normalized.privacyTier, 'pseudonymous_product');
  assert.equal(normalized.releaseSha, 'b'.repeat(40));
  assert.equal(normalized.deploymentId, 'deployment-123');
  assert.match(normalized.anonymousActorHash, /^[a-f0-9]{64}$/);

  for (const key of [
    'source_sha', 'release_sha', 'release_id', 'deployment_id',
    'rollback_of_deployment_id', 'schema_version', 'event_schema_version',
    'source_repo', 'privacy_mode', 'proof_stage', 'organization_key',
    'project_key', 'execution_id', 'failure_class', 'tool_class',
    'model_provider', 'model_name', 'outcome_type', 'result', 'retry_count',
    'input_tokens', 'output_tokens', 'total_cost_usd', 'evaluation_score',
    'evidence_count',
  ]) {
    assert.deepEqual(normalized.properties[key], event.properties[key], `${key} should survive`);
  }
});

test('content-bearing, unknown, and direct-identifier fields remain stripped', () => {
  const sanitized = sanitizeProductProperties({
    product_key: 'pandoras_box',
    prompt: 'private prompt',
    input: 'private input',
    output: 'private output',
    tool_result: 'private result',
    customer_message: 'private message',
    authorization: 'Bearer secret',
    unreviewed_context: 'private context',
    route_group: 'owner@example.com',
    failure_class: 'provider.unavailable',
  });
  assert.deepEqual(sanitized, {
    product_key: 'pandoras_box',
    failure_class: 'provider.unavailable',
  });
});

test('digit-heavy valid pseudonyms and token counts are preserved without raw identifiers', () => {
  const event = lifecycleEnvelope();
  const normalized = normalizeProductSignal(event, HASH_SALT);
  assert.equal(normalized.properties.organization_key, `org_${'1'.repeat(32)}`);
  assert.equal(normalized.properties.project_key, `project_${'2'.repeat(32)}`);
  assert.equal(normalized.properties.input_tokens, 10);
  assert.equal(normalized.properties.output_tokens, 20);
  const serialized = JSON.stringify(normalized);
  assert.equal(serialized.includes(event.distinct_id), false);
  assert.equal(serialized.includes(HASH_SALT), false);
});

test('dedupe remains deterministic and changes with approved metadata', () => {
  const first = normalizeProductSignal(lifecycleEnvelope(), HASH_SALT);
  const second = normalizeProductSignal(lifecycleEnvelope(), HASH_SALT);
  const changed = normalizeProductSignal(lifecycleEnvelope({ retry_count: 2 }), HASH_SALT);
  assert.equal(first.dedupeKey, second.dedupeKey);
  assert.notEqual(first.dedupeKey, changed.dedupeKey);
});


test('real phone-number metadata remains stripped while structural pseudonyms survive', () => {
  const pseudonym = `org_${'1'.repeat(32)}`;
  const sanitized = sanitizeProductProperties({
    product_key: 'pandoras_box',
    route_group: '+63 917 123 4567',
    organization_key: pseudonym,
  });
  assert.deepEqual(sanitized, {
    product_key: 'pandoras_box',
    organization_key: pseudonym,
  });
});

test('missing lifecycle timestamps fail closed instead of using ingest time', () => {
  const event = lifecycleEnvelope();
  delete event.timestamp;
  assert.throws(
    () => normalizeProductSignal(event, HASH_SALT),
    /invalid_timestamp/,
  );
});
