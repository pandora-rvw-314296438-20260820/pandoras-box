const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = process.cwd();
const client = fs.readFileSync(
  path.join(root, 'scripts/rdp-sync/pandora-rdp-sync-client.ps1'),
  'utf8',
);
const migration = fs.readFileSync(
  path.join(
    root,
    'supabase/migrations/20260919122500_retire_windows_rdp_execution_transport.sql',
  ),
  'utf8',
);

test('retired RDP publisher is fail-closed in source and database', () => {
  assert.match(client, /PANDORA_RDP_TRANSPORT_RETIRED/);
  assert.doesNotMatch(client, /supabase\.co|Invoke-RestMethod|machine-proof|publish_commit/);

  assert.match(
    migration,
    /create or replace function public\.pandora_rdp_github_request_v1/,
  );
  assert.match(
    migration,
    /create or replace function public\.pandora_rdp_memory_github_request_v1/,
  );
  assert.match(migration, /PANDORA_RDP_TRANSPORT_RETIRED/g);
  assert.match(
    migration,
    /to_regclass\('public\.pandora_local_ai_workers'\) is not null/,
  );
  assert.match(
    migration,
    /execute 'delete from public\.pandora_local_ai_workers where worker_id = \$1'[\s\S]*rdp-ec2amaz-spae2vg/,
  );
});

test('active GitHub workflows never depend on self-hosted runners', () => {
  const workflowDir = path.join(root, '.github/workflows');
  const workflows = fs
    .readdirSync(workflowDir)
    .filter((name) => /\.ya?ml$/i.test(name));

  assert.ok(workflows.length > 0);
  for (const name of workflows) {
    const source = fs.readFileSync(path.join(workflowDir, name), 'utf8');
    assert.doesNotMatch(
      source,
      /\bself-hosted\b/i,
      `${name} must use provider-hosted execution, not the retired RDP runner`,
    );
  }
});
