const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const migration = fs.readFileSync(
  path.join(
    root,
    'supabase',
    'migrations',
    '20260918051723_pandora_local_ai_queue_v1.sql',
  ),
  'utf8',
);

test('local AI provider history prerequisites are reconstructable from source', () => {
  assert.match(migration, /create table if not exists public\.pandora_local_ai_jobs/);
  assert.match(migration, /create table if not exists public\.pandora_local_ai_workers/);
  assert.match(migration, /create table if not exists public\.pandora_local_ai_build_receipts/);
  assert.match(migration, /source_sha text/);
  assert.match(migration, /apk_sha256 text/);
  assert.match(migration, /apk_size_bytes bigint/);
  assert.match(migration, /pandora_local_ai_jobs_queue_idx/);
});

test('reconstructed local AI history stays server-side', () => {
  assert.match(
    migration,
    /revoke all on table public\.pandora_local_ai_jobs[\s\S]*from public, anon, authenticated/,
  );
  assert.match(
    migration,
    /revoke all on table public\.pandora_local_ai_workers[\s\S]*from public, anon, authenticated/,
  );
  assert.match(
    migration,
    /revoke all on table public\.pandora_local_ai_build_receipts[\s\S]*from public, anon, authenticated/,
  );
  assert.doesNotMatch(migration, /create\s+policy/i);
  assert.doesNotMatch(migration, /grant[\s\S]{0,120}\b(?:anon|authenticated)\b/i);
});
