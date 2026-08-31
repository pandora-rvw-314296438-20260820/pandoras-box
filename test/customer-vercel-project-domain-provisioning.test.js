
const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');

const migration = readFileSync(
  resolve(process.cwd(), 'supabase/migrations/20260901060000_pandora_customer_vercel_project_domain_v1.sql'),
  'utf8',
);

test('Simple Mode project insert provisions a bounded Vercel project and stable address', () => {
  assert.match(migration, /before insert on public\.projectos_projects/i);
  assert.match(migration, /createdFrom.*simple_mode/is);
  assert.match(migration, /private\.pandora_worker_f_vercel_api_20260829/);
  assert.match(migration, /\/v11\/projects\?teamId=/);
  assert.match(migration, /skipGitConnectDuringLink',true/);
  assert.match(migration, /vercelDefaultDomainStatus','reserved'/);
  assert.match(migration, /\.vercel\.app/);
});

test('Vercel provisioning is deterministic and idempotently reconciles conflict', () => {
  assert.match(migration, /pandora_customer_vercel_project_name_20260901/);
  assert.match(migration, /if v_status = 409 then/);
  assert.match(migration, /\/v9\/projects\/' \|\| v_project_name/);
  assert.match(migration, /accountId.*v_team_id/is);
});

test('stable Vercel domain can become client liveUrl only after exact production proof', () => {
  assert.match(migration, /before update of config on public\.projectos_projects/i);
  assert.match(migration, /productionVerificationState.*live_verified/is);
  assert.match(migration, /d\.verification_state <> 'live_verified'/);
  assert.match(migration, /targets.*production.*id/is);
  assert.match(migration, /provider_deployment_id/is);
  assert.match(migration, /vercelDefaultDomainStatus','live_verified'/);
});

test('fully verified custom domain retains precedence over generated Vercel domain', () => {
  for (const fact of ['ownership_verified=true','dns_configured=true','tls_ready=true','routing_ready=true','runtime_healthy=true']) {
    assert.ok(migration.includes(fact));
  }
  assert.match(migration, /when nullif\(v_custom_domain,''\) is not null then 'https:\/\/' \|\| v_custom_domain/);
});

test('customer roles cannot directly execute provisioning functions', () => {
  assert.match(migration, /revoke all on function private\.pandora_provision_customer_vercel_project_20260901\(text,uuid\) from public,anon,authenticated/i);
});
