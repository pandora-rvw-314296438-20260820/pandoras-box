const assert = require('node:assert/strict');
const { readFile } = require('node:fs/promises');
const test = require('node:test');

let sql;
let edge;
let config;
let tableSql;
let providerApi;

test.before(async () => {
  [sql, edge, config, tableSql, providerApi] = await Promise.all([
    readFile('docs/recovery/sql/execution-ledger-functions.sql', 'utf8'),
    readFile('supabase/functions/mcpmaster-supabase-control/index.ts', 'utf8'),
    readFile('supabase/config.toml', 'utf8'),
    readFile('supabase/migrations/20260731092908_projectos_operating_kernel.sql', 'utf8'),
    readFile('src/tools/provider-api.js', 'utf8'),
  ]);
});

function functionBody(name, next) {
  const start = sql.indexOf(`-- ${name}`);
  assert.notEqual(start, -1, `missing recovered ${name}`);
  const end = next ? sql.indexOf(`-- ${next}`, start + name.length) : sql.length;
  return sql.slice(start, end < 0 ? sql.length : end);
}

test('active create function binds organization, exact payload hash, risk, expiry, and pending state', () => {
  const body = functionBody('create_execution_plan', 'finish_execution_plan');
  assert.match(body, /where id = p_intake_id\s+and organization_id = p_organization_id/);
  assert.match(body, /p_payload_hash !~ '\^\[0-9a-f\]\{64\}\$'/);
  assert.match(body, /p_risk not in \('read', 'write', 'destructive'\)/);
  assert.match(body, /p_expires_at <= now\(\) or p_expires_at > now\(\) \+ interval '30 minutes'/);
  assert.match(body, /case when p_risk = 'read' then 'approved' else 'pending_approval' end/);
  assert.match(body, /private\.append_execution_audit/);
});

test('active approve function rejects non-pending state and cannot approve expiry', () => {
  const body = functionBody('approve_execution_plan', 'claim_execution_plan');
  assert.match(body, /where id = p_plan_id and organization_id = p_organization_id\s+for update/);
  assert.match(body, /plan\.expires_at <= now\(\) and plan\.status in \('pending_approval', 'approved'\)/);
  assert.match(body, /set status = 'expired'/);
  assert.match(body, /if plan\.status <> 'pending_approval'/);
  assert.match(body, /set status = 'approved'/);
  assert.match(body, /'approvedBy', plan\.approved_by/);
  assert.match(body, /private\.append_execution_audit/);
});

test('active claim function is one-time, unexpired, approved-only, and returns the bound payload', () => {
  const body = functionBody('claim_execution_plan', 'create_execution_plan');
  assert.match(body, /where id = p_plan_id and organization_id = p_organization_id\s+for update/);
  assert.match(body, /if plan\.expires_at <= now\(\)/);
  assert.match(body, /if plan\.status <> 'approved'/);
  assert.match(body, /set status = 'executing', claimed_at = now\(\)/);
  assert.match(body, /'args', plan\.args/);
  assert.match(body, /'payloadHash', plan\.payload_hash/);
  assert.match(body, /private\.append_execution_audit/);
});

test('child-deletion reservations use one immutable external-event uniqueness domain', () => {
  assert.match(tableSql, /unique \(organization_id, provider, delivery_id\)/);
  assert.match(providerApi, /const CONTROL_PROJECT_REF = 'jcyqixttuebxqqfkjonq'/);
  assert.match(providerApi, /const CONTROL_ORGANIZATION_ID = '2270b266-59da-4c39-bfd9-9f8d08352af0'/);
  assert.match(providerApi, /on conflict \(organization_id,provider,delivery_id\) do nothing returning/);
  assert.doesNotMatch(providerApi, /projectos_record_external_event/);
});

test('active finish and audit-chain functions preserve one-time lifecycle and tamper evidence', () => {
  const finish = functionBody('finish_execution_plan', 'list_execution_audit');
  const verify = functionBody('verify_execution_audit_chain');
  assert.match(finish, /if plan\.status <> 'executing'/);
  assert.match(finish, /p_status not in \('completed', 'failed'\)/);
  assert.match(finish, /private\.append_execution_audit/);
  assert.match(verify, /event\.previous_hash <> expected_previous/);
  assert.match(verify, /extensions\.digest\(convert_to\(canonical, 'UTF8'\), 'sha256'\)/);
  assert.match(verify, /expected_hash <> event\.event_hash/);
});

test('active control Edge Function accepts only verified production Vercel OIDC and server-side service role', () => {
  assert.match(config, /\[functions\.mcpmaster-supabase-control\]\s+verify_jwt = false/);
  assert.match(edge, /await verifyVercelToken\(token\)/);
  assert.match(edge, /assertProductionVercelClaims/);
  assert.match(edge, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(edge, /authorization: `Bearer \$\{key\}`/);
  assert.match(edge, /p_organization_id: CONTROL_ORGANIZATION_ID/);
  assert.match(edge, /redirect: "error"/);
  assert.match(edge, /execution_plan_approve[\s\S]*requiredUuid\(input, "planId"\)/);
  assert.match(edge, /execution_plan_claim[\s\S]*requiredUuid\(input, "planId"\)/);
  assert.match(edge, /execution_plan_finish[\s\S]*requiredUuid\(input, "planId"\)/);
});
