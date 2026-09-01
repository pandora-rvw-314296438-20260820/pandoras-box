const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const migration = readFileSync(
  join(root, 'supabase/migrations/20260901080546_pandora_server_owned_build_admission_v1.sql'),
  'utf8',
);
const generator = readFileSync(
  join(root, 'supabase/functions/pandora-project-source-generator/index.ts'),
  'utf8',
);
const convergenceWorker = readFileSync(
  join(root, 'supabase/functions/pandora-source-convergence-worker/index.ts'),
  'utf8',
);

function offset(source, needle) {
  const value = source.indexOf(needle);
  assert.notEqual(value, -1, `missing contract fragment: ${needle}`);
  return value;
}

test('durable admission creates the BuildJob before source execution identities are acknowledged', () => {
  assert.match(migration, /pandora_admit_authorized_build_v1/);
  assert.match(migration, /pandora_build_authorization_receipts/);
  assert.match(migration, /approved_spec_sha256/);
  assert.match(migration, /status='active'/);
  assert.match(migration, /pandora_bind_build_authorization_v1/);

  const jobInsert = offset(migration, 'insert into public.pandora_build_jobs(');
  const queueInsert = offset(migration, 'insert into public.pandora_source_generation_queue(');
  const streamInsert = offset(migration, 'insert into public.pandora_build_stream_sessions(');
  const admittedEvent = offset(migration, "'build_admitted'");
  assert.ok(jobInsert < queueInsert, 'BuildJob must exist before source queue admission');
  assert.ok(jobInsert < streamInsert, 'BuildJob must exist before stream admission');
  assert.ok(queueInsert < admittedEvent, 'durable source queue must exist before Build admitted event');
  assert.ok(streamInsert < admittedEvent, 'stream binding must exist before Build admitted event');

  assert.match(migration, /'buildJobId',v_job\.id/);
  assert.match(migration, /'streamId',v_stream\.id/);
  assert.match(migration, /'sourceQueueId',v_queue\.id/);
  assert.match(migration, /'sourceIdempotencyKey',v_queue\.idempotency_key/);
  assert.match(migration, /'admittedAt',v_auth\.admitted_at/);
});

test('admission is idempotent and collision-safe against a different authorization lineage', () => {
  assert.match(migration, /pg_advisory_xact_lock/);
  assert.match(migration, /pandora-admission:/);
  assert.match(migration, /BUILD_ADMISSION_COLLISION/);
  assert.match(migration, /BUILD_ADMISSION_PARTIAL_STATE/);
  assert.match(migration, /'replayed',true/);
  assert.match(migration, /project_spec_id<>v_auth\.project_spec_id/);
  assert.match(migration, /source_intent_id is distinct from v_auth\.source_intent_id/);
  assert.match(migration, /requested_by is distinct from v_auth\.authorized_by/);
});

test('generated source attaches to the same pre-admitted BuildJob instead of creating a second job', () => {
  assert.match(migration, /pandora_commit_generated_build_intake_v3_20260901/);
  assert.match(migration, /target_project_version_id is null/);
  assert.match(migration, /set target_project_version_id=v_project_version_id/);
  assert.match(migration, /set build_job_id=v_job\.id/);
  assert.match(migration, /pandora_authorize_generated_build_20260829\(v_job\.id\)/);
  assert.match(migration, /BUILD_INTAKE_ATTACH_RACE/);
  assert.match(migration, /return private\.pandora_commit_generated_build_intake_v2_20260829/);

  const attach = offset(migration, 'set target_project_version_id=v_project_version_id');
  const workerAuthorization = offset(migration, 'pandora_authorize_generated_build_20260829(v_job.id)');
  assert.ok(attach < workerAuthorization, 'downstream Worker C authorization requires the attached candidate identity');
});

test('client request lifetime is no longer the build authority', () => {
  assert.match(generator, /pandora_authorize_project_build_v1/);
  assert.match(generator, /pandora_admit_authorized_build_service_v1/);
  assert.match(generator, /pandora_claim_source_fastpath_service_v1/);
  assert.doesNotMatch(generator, /BACKGROUND_STREAMING_UNAVAILABLE/);
  assert.doesNotMatch(generator, /pandora_build_stream_sessions"\)\.insert/);

  const authorize = offset(generator, 'pandora_authorize_project_build_v1');
  const admit = offset(generator, 'pandora_admit_authorized_build_service_v1');
  const waitUntil = offset(generator, 'runtime.waitUntil(runGenerationInBackground');
  assert.ok(authorize < admit, 'exact user authorization must precede durable admission');
  assert.ok(admit < waitUntil, 'durable admission must precede optional Edge continuation');

  assert.match(generator, /if \(runtime\?\.waitUntil && !admission\.projectVersionId\)/);
  assert.match(generator, /stage: admission\.projectVersionId \? "building" : fastPathStarted \? "generating_source" : "queued"/);
});

test('fast live source is a recoverable queue attempt and stale fastpaths cannot attach candidates', () => {
  assert.match(migration, /pandora_claim_source_fastpath_v1/);
  assert.match(migration, /status='dispatching'/);
  assert.match(migration, /dispatch_count=dispatch_count\+1/);
  assert.match(migration, /target_project_version_id is null/);
  assert.match(generator, /SOURCE_FASTPATH_LEASE_LOST/);
  assert.match(generator, /\.eq\("status", "dispatching"\)/);
  assert.match(generator, /status: terminal \? "failed" : "queued"/);
  assert.match(generator, /build_job_id: state\.buildJobId/);

  assert.match(
    convergenceWorker,
    /if \(existing\.data\?\.target_project_version_id\) \{/,
    'server recovery worker must not treat a pre-admitted target-null BuildJob as already generated',
  );
});

test('safe terminal source failure preserves the current verified product', () => {
  assert.match(generator, /Pandora couldn't finish this build\. Your current version is unchanged\./);
  assert.match(generator, /\.is\("target_project_version_id", null\)/);
  assert.match(generator, /event_type: "stream_error"/);
  assert.doesNotMatch(generator, /delete\(\)[\s\S]{0,200}pandora_project_versions/);
});
