import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const generator = readFileSync(
  'supabase/functions/pandora-project-source-generator/index.ts',
  'utf8',
);
const migration = readFileSync(
  'supabase/migrations/20260902181500_pandora_history_compaction_metrics_v1.sql',
  'utf8',
);

test('source generation persists file and line metrics on the exact version', () => {
  assert.match(generator, /const sourceFileCount = files\.length;/);
  assert.match(generator, /const sourceLineCount = files\.reduce/);
  assert.match(generator, /fileCount: sourceFileCount/);
  assert.match(generator, /lineCount: sourceLineCount/);
  assert.match(generator, /\.eq\("id", projectVersionId\)/);
});

test('conversation projection exposes only durable build summary metrics', () => {
  for (const metric of [
    "'buildNumber'",
    "'durationMs'",
    "'fileCount'",
    "'lineCount'",
    "'checksTotal'",
    "'checksPassed'",
    "'checksFailed'",
    "'checksBlocked'",
  ]) {
    assert.ok(migration.includes(metric), `missing ${metric}`);
  }
  assert.match(migration, /pv\.build_job_id = j\.id/);
  assert.match(migration, /vc\.verification_run_id = v\.verification_run_id/);
});
