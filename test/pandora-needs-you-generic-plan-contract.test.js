const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '..');
const ownerApi = fs.readFileSync(
  path.join(root, 'supabase/functions/pandora-owner-api/index.ts'),
  'utf8',
);
const migration = fs.readFileSync(
  path.join(root, 'supabase/migrations/20260911164500_projectos_generic_owner_plan_decisions_v1.sql'),
  'utf8',
);

test('generic consequential execution plans are surfaced in Needs You without read plans', () => {
  assert.match(ownerApi, /plan\.tool !== "projectos\.worker\.verify"/);
  assert.match(ownerApi, /plan\.risk !== "read"/);
  assert.match(ownerApi, /plan\.status === "pending_approval"/);
  assert.match(ownerApi, /kind: "execution_plan"/);
  assert.match(ownerApi, /Approval records permission only/);
});

test('generic owner decision path approves or denies without claiming execution', () => {
  assert.match(migration, /private\.assert_live_plan_approver/);
  assert.match(migration, /private\.assert_control_service_role/);
  assert.match(migration, /public\.approve_execution_plan/);
  assert.match(migration, /'plan_denied'/);
  assert.match(migration, /status = 'denied'/);
  assert.doesNotMatch(migration, /claim_execution_plan/);
  assert.doesNotMatch(migration, /execution_dispatch_outbox/);
});

test('generic plan decision RPC fails closed to authenticated owners only', () => {
  assert.match(migration, /revoke all on function public\.decide_execution_plan_v1\(uuid,uuid,text\)[\s\S]*from public, anon/);
  assert.match(migration, /grant execute on function public\.decide_execution_plan_v1\(uuid,uuid,text\)[\s\S]*to authenticated/);
  assert.match(migration, /revoke all on function public\.decide_execution_plan_v1\(uuid,uuid,text,text\)[\s\S]*from public, anon, authenticated/);
  assert.match(migration, /to service_role/);
});

test('owner API tries specialized worker decision then generic ProjectOS plan then ordinary approval', () => {
  const workerIndex = ownerApi.indexOf('decide_governed_worker_execution_plan');
  const genericIndex = ownerApi.indexOf('decide_execution_plan_v1');
  const ordinaryIndex = ownerApi.indexOf('decide_approval');
  assert.ok(workerIndex >= 0);
  assert.ok(genericIndex > workerIndex);
  assert.ok(ordinaryIndex > genericIndex);
  assert.match(ownerApi, /No provider mutation is executed by this approval call/);
});
