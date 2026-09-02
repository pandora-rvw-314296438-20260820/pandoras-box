const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const migration = fs.readFileSync(
  path.join(root, 'supabase/migrations/20260902094000_pandora_build_model_cost_guard_v1.sql'),
  'utf8',
);

test('source generation has one shared ProjectSpec model budget with verified Gemini pricing', () => {
  assert.match(migration, /gemini-3\.5-flash-lite-usd-2026-09-02/);
  assert.match(migration, /300000,\s*30000,\s*2500000/);
  assert.match(migration, /'source-generation:'\|\|v_queue\.project_spec_id::text/);
  assert.match(migration, /400000,500000/);
  assert.match(migration, /pandora_build_jobs_spend_within_budget_check/);
});

test('fast path stays truthfully queued if it cannot reserve; background dispatch terminalizes', () => {
  const fast = migration.indexOf('create or replace function private.pandora_claim_source_fastpath_v1');
  const fastReserve = migration.indexOf('pandora_reserve_source_model_attempt_v1(p_queue_id,false)', fast);
  const fastDispatch = migration.indexOf("set status='dispatching'", fastReserve);
  assert.ok(fastReserve > fast && fastDispatch > fastReserve);

  const scheduler = migration.indexOf('create or replace function private.pandora_dispatch_source_generation_tick_20260831');
  const scheduledReserve = migration.indexOf('pandora_reserve_source_model_attempt_v1(v_row.id,true)', scheduler);
  const httpPost = migration.indexOf('net.http_post', scheduler);
  assert.ok(scheduledReserve > scheduler && httpPost > scheduledReserve);
});

test('deadline and verified pricing gate precede spend reservation', () => {
  const reserve = migration.indexOf('create or replace function private.pandora_reserve_source_model_attempt_v1');
  const deadline = migration.indexOf('BUILD_DEADLINE_EXCEEDED', reserve);
  const price = migration.indexOf('MODEL_PRICING_UNAVAILABLE', reserve);
  const budget = migration.indexOf('private.pandora_reserve_budget(v_budget_id,160000)', reserve);
  assert.ok(deadline > reserve && price > deadline && budget > price);
});

test('retries and acceptance repair share ProjectSpec budget and attempts are idempotent', () => {
  assert.match(migration, /unique \(queue_id, dispatch_attempt\)/);
  assert.match(migration, /v_attempt := v_queue\.dispatch_count \+ 1/);
  assert.match(migration, /where queue_id=p_queue_id and dispatch_attempt=v_attempt/);
  assert.match(migration, /BUILD_BUDGET_EXHAUSTED/);
  assert.match(migration, /hard_limit_micros,500000/);
  assert.match(migration, /reserve_budget\(v_budget_id,160000\)/);
});

test('source model run must bind to exactly one live reservation before success is persisted', () => {
  assert.match(migration, /MODEL_BUDGET_RESERVATION_MISSING/);
  assert.match(migration, /v_count <> 1/);
  assert.match(migration, /r\.dispatch_attempt=v_queue\.dispatch_count/);
  assert.match(migration, /new\.source_queue_id := v_queue\.id/);
  assert.match(migration, /new\.source_dispatch_attempt := v_queue\.dispatch_count/);
});

test('provider-reported usage is priced without inventing billed cost', () => {
  assert.match(migration, /pandora_estimate_model_cost_v1/);
  assert.match(migration, /new\.usage_source := 'provider_reported'/);
  assert.match(migration, /new\.billing_reconciliation_status := 'pending'/);
  assert.match(migration, /new\.estimated_cost_micros,0,new\.estimated_cost_micros/);
  assert.match(migration, /MODEL_COST_EXCEEDS_RESERVATION/);
});

test('successful model cost is append-only and mirrors shared spend to BuildJob', () => {
  assert.match(migration, /insert into public\.pandora_cost_entries/);
  assert.match(migration, /'source-model:'\|\|new\.source_queue_id::text/);
  assert.match(migration, /after update of build_job_id on public\.pandora_model_runs/);
  assert.match(migration, /spent_cents=least/);
});

test('budget exhaustion is explicit and terminal', () => {
  assert.match(migration, /pandora_source_budget_terminal_v1/);
  assert.match(migration, /'stream_error'/);
  assert.match(migration, /pandora_preserve_budget_terminal_queue_v1/);
});
