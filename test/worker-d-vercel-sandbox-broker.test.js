
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/20260829113000_pandora_worker_d_vercel_sandbox_broker_v1.sql'), 'utf8');
const provider = fs.readFileSync(path.join(root, 'workers/pandora-builder/src/sandbox/vercel-sandbox-provider.mjs'), 'utf8');

test('Worker D Sandbox broker keeps Vercel credential in Vault and service role only', () => {
  assert.match(migration, /vault\.decrypted_secrets[\s\S]*name='vercel'/);
  assert.match(migration, /revoke all on function private\.pandora_worker_d_vercel_sandbox_api_20260829[\s\S]*from public,anon,authenticated/i);
  assert.match(migration, /grant execute on function public\.pandora_worker_d_vercel_sandbox_request_20260829[\s\S]*to service_role/i);
  assert.doesNotMatch(migration, /Bearer\s+[A-Za-z0-9_-]{20,}/);
});

test('Worker D Sandbox broker is team/project scoped and denies privilege expansion', () => {
  assert.match(migration, /teamId=/);
  assert.match(migration, /worker_d_sandbox_project_id/);
  assert.match(migration, /persistent.*boolean,true/s);
  assert.match(migration, /sudo.*boolean,true/s);
  assert.match(migration, /credential-shaped environment field rejected/);
  assert.match(migration, /Vercel Sandbox path outside Worker D lane/);
});

test('Worker D provider is non-production and uses direct executable commands only', () => {
  assert.match(provider, /validateBuildExecutionRequest/);
  assert.match(provider, /persistent: false/);
  assert.match(provider, /sudo: false/);
  assert.match(provider, /FORBIDDEN_EXECUTABLES/);
  assert.match(provider, /mode: 'deny-all'/);
  assert.doesNotMatch(provider, /process\.env|VERCEL_TOKEN|Bearer /);
});


test('Worker D service wrapper normalizes bodyless control POSTs without exposing credentials', () => {
  const protocolFix = fs.readFileSync(path.join(root, 'supabase/migrations/20260829120000_pandora_worker_d_vercel_sandbox_protocol_fix.sql'), 'utf8');
  assert.match(protocolFix, /upper\(coalesce\(p_method,''\)\)='POST'/i);
  assert.match(protocolFix, /p_body is null[\s\S]*'\{\}'::jsonb/i);
  assert.match(protocolFix, /private\.pandora_worker_d_vercel_sandbox_api_20260829/);
  assert.match(protocolFix, /revoke all on function public\.pandora_worker_d_vercel_sandbox_request_20260829[\s\S]*from public,anon,authenticated/i);
  assert.doesNotMatch(protocolFix, /vault\.decrypted_secrets|Bearer\s+[A-Za-z0-9_-]{20,}/);
});
