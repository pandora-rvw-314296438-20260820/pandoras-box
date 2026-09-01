const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const eventMigration = fs.readFileSync(path.join(root, 'supabase/migrations/20260901162600_pandora_visible_execution_event_protocol_v2.sql'), 'utf8');
const vercelMigration = fs.readFileSync(path.join(root, 'supabase/migrations/20260901162500_pandora_worker_d_vercel_sandbox_log_readback_v1.sql'), 'utf8');
const contract = fs.readFileSync(path.join(root, 'docs/pandora-visible-execution-events-v2.md'), 'utf8');
const provider = fs.readFileSync(path.join(root, 'workers/pandora-builder/src/sandbox/vercel-sandbox-provider.mjs'), 'utf8');

const requiredEvents = [
  'command_started','stdout_chunk','stderr_chunk','command_completed',
  'compile_started','compile_diagnostic','compile_completed',
  'test_started','test_result','test_completed','repair_started','repair_completed',
];

test('Protocol V2 extension freezes Chat E execution event semantics without a second stream', () => {
  for (const event of requiredEvents) assert.match(contract, new RegExp(`\\b${event}\\b`));
  assert.match(contract, /canonical `pandora_build_stream_events` stream/);
  assert.match(contract, /database-assigned per-stream `sequence`/);
  assert.match(contract, /BuildJob\/attempt\/step, ProjectVersion, artifact and verification records remain authority/);
});

test('raw stdout and stderr are ephemeral while lifecycle events remain durable projections', () => {
  assert.match(eventMigration, /'file_started','file_completed','stdout_chunk','stderr_chunk'/);
  assert.match(eventMigration, /interval '20 minutes'/);
  assert.match(eventMigration, /else 'durable_projection'/);
  assert.match(eventMigration, /BUILD_STREAM_LOG_CHUNK_INVALID/);
  assert.match(eventMigration, /octet_length\(coalesce\(new\.safe_payload->>'text',''\)\) > 8192/);
});

test('Vercel log readback remains Vault-backed, GET-only, team-scoped and bounded', () => {
  assert.match(vercelMigration, /name='vercel'/);
  assert.match(vercelMigration, /teamId=/);
  assert.match(vercelMigration, /\/cmd\/cmd_\[A-Za-z0-9\]\+\/logs/);
  assert.match(vercelMigration, /unsafe Worker D Vercel Sandbox log request/);
  assert.match(vercelMigration, /left\(v_response\.content,65536\)/);
  assert.match(vercelMigration, /from public,anon,authenticated/);
  assert.match(vercelMigration, /to service_role/);
  assert.doesNotMatch(vercelMigration, /Bearer\s+[A-Za-z0-9_-]{20,}/);
});

test('provider reads command logs but never reads Vercel credentials from process environment', () => {
  assert.match(provider, /\/cmd\/\$\{command\.id\}\/logs/);
  assert.match(provider, /parseCommandLogResponse/);
  assert.match(provider, /MAX_PROVIDER_LOG_BYTES = 64 \* 1024/);
  assert.doesNotMatch(provider, /process\.env|VERCEL_TOKEN|Bearer /);
});
