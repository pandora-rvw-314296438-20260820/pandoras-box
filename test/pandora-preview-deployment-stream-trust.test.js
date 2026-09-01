
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const migration = fs.readFileSync('supabase/migrations/20260901162700_pandora_preview_deployment_stream_trust_v1.sql', 'utf8');
const runtime = fs.readFileSync('supabase/functions/pandora-project-runtime/index.ts', 'utf8');
const producer = fs.readFileSync('workers/pandora-builder/src/events/visible-execution-events.mjs', 'utf8');

const executionEvents = [
  'command_started','stdout_chunk','stderr_chunk','command_completed',
  'compile_started','compile_diagnostic','compile_completed',
  'test_started','test_result','test_completed',
  'repair_started','repair_completed',
];

test('database admission accepts every Chat E execution event emitted by the canonical producer', () => {
  for (const event of executionEvents) {
    assert.match(producer, new RegExp(`['\"]${event}['\"]`));
    assert.match(migration, new RegExp(`'${event}'`));
  }
  assert.match(migration, /pandora_build_stream_events_event_type_check/);
});

test('preview preparation evidence is emitted only from exact ProjectVersion and provider deployment lineage', () => {
  assert.match(migration, /new\.environment <> 'preview'/);
  assert.match(migration, /v\.build_job_id = new\.id/);
  assert.match(migration, /d\.version_id = v\.id/);
  assert.match(migration, /d\.source_sha256 = v\.source_sha256/);
  assert.match(migration, /d\.artifact_digest = v\.artifact_digest_sha256/);
  assert.match(migration, /d\.source_commit_sha is not distinct from v\.source_commit/);
  assert.match(migration, /providerDeploymentId/);
  assert.match(migration, /projectVersionId/);
  assert.match(migration, /sourceDigest/);
  assert.match(migration, /artifactDigest/);
  assert.match(migration, /stepKind', 'preview_deployment'/);
});

test('generic BuildJob state cannot claim preview_ready without exact provider evidence', () => {
  assert.match(migration, /if new\.current_stage = 'preview_ready' and new\.status = 'succeeded' then/);
  assert.match(migration, /if found then\s+v_event_type := 'preview_ready'/s);
  assert.match(migration, /v_event_type text := 'job_state'/);
  assert.match(migration, /when v_event_type = 'preview_ready' then 'completed'/);
});

test('preview stream evidence carries no customer URL or credential material', () => {
  assert.doesNotMatch(migration, /new\.url|previewUrl|immutable_url|stable_url/);
  assert.doesNotMatch(migration, /PANDORA_VERCEL_TOKEN|SUPABASE_SERVICE_ROLE_KEY|Bearer\s/);
});

test('runtime writes the exact lineage fields consumed by preview evidence', () => {
  const start = runtime.indexOf('async function createPreview');
  const end = runtime.indexOf('\n\nasync function publishProject', start);
  const preview = runtime.slice(start, end);
  assert.match(preview, /version_id: versionId/);
  assert.match(preview, /provider_deployment_id: providerDeploymentId/);
  assert.match(preview, /source_sha256: bundle\.sourceDigest/);
  assert.match(preview, /artifact_digest: bundle\.artifactDigest/);
  assert.match(preview, /source_commit_sha: bundle\.sourceCommit/);
  assert.match(preview, /buildJobId: bundle\.buildJobId/);
});
