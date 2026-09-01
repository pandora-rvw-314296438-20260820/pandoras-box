'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const migrationPath = path.join(__dirname, '..', 'supabase', 'migrations', '20260901184000_pandora_model_telemetry_economics_v1.sql');
const sql = fs.readFileSync(migrationPath, 'utf8');

test('extends the provider-neutral run ledger without creating a Kimi-only ledger', () => {
  assert.match(sql, /alter table public\.pandora_model_runs/i);
  assert.match(sql, /create table if not exists public\.pandora_model_attempts/i);
  assert.doesNotMatch(sql, /create table[^;]+kimi_model_runs/i);
});

test('keeps provider-reported usage, estimates, and billing evidence distinct', () => {
  assert.match(sql, /usage_source/i);
  assert.match(sql, /cached_input_tokens bigint null/i);
  assert.match(sql, /cost_estimate_status/i);
  assert.match(sql, /billing_reconciliation_status/i);
  assert.match(sql, /billedCostMicros',null/i);
});

test('uses one versioned pricing authority and current verified Kimi K3 rates', () => {
  assert.match(sql, /pandora_model_pricing_versions/i);
  assert.match(sql, /kimi-k3-usd-2026-09-02/i);
  assert.match(sql, /3000000, 300000, 15000000/);
  assert.match(sql, /pandora_estimate_model_cost_v1/i);
});

test('separates execution, routing, tool, verification, and downstream outcome evidence', () => {
  for (const field of [
    'routing_policy_version', 'fallback_chain_id', 'provider_latency_ms',
    'structured_output_schema_valid', 'tool_execution_succeeded',
    'verification_outcome', 'downstream_outcome_status', 'failure_domain',
  ]) assert.match(sql, new RegExp(field));
});

test('health read models expose samples, freshness and sparse percentile thresholds', () => {
  assert.match(sql, /pandora_provider_attempt_health_hourly_v1/i);
  assert.match(sql, /pandora_provider_outcome_health_hourly_v1/i);
  assert.match(sql, /sample_count/i);
  assert.match(sql, /freshest_observation_at/i);
  assert.match(sql, /count\(a\.provider_latency_ms\) >= 20/i);
  assert.match(sql, /count\(a\.provider_latency_ms\) >= 100/i);
});

test('telemetry surfaces are RLS-protected and exclude raw sensitive payload fields', () => {
  assert.match(sql, /alter table public\.pandora_model_attempts enable row level security/i);
  assert.match(sql, /private\.is_org_member\(organization_id\)/i);
  assert.match(sql, /with \(security_invoker = true\)/i);
  const declaredColumns = [...sql.matchAll(/(?:add column if not exists|^\s{2})([a-z_][a-z0-9_]*)\s+(?:text|jsonb|uuid|bigint|integer|boolean|numeric|timestamptz)/gmi)]
    .map((match) => match[1]);
  for (const forbidden of [
    'prompt', 'authorization_header', 'api_key', 'raw_response', 'raw_request',
    'request_body', 'response_body', 'secret_value',
  ]) assert.equal(declaredColumns.includes(forbidden), false, `forbidden telemetry column: ${forbidden}`);
});
