const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

const migration = fs.readFileSync(
  'supabase/migrations/20260910075705_pandora_theatre_preexecution_primitive_truth_v1.sql',
  'utf8',
);
const worker = fs.readFileSync(
  'supabase/functions/pandora-source-convergence-worker/index.ts',
  'utf8',
);

test('pre-execution primitive failures get truthful Theatre copy', () => {
  assert.match(migration, /TRUSTED_PRIMITIVE_UNAVAILABLE/);
  assert.match(migration, /MODEL_PRICING_UNAVAILABLE/);
  assert.match(
    migration,
    /required building blocks are not available yet\. Nothing was published\./,
  );
  assert.match(
    migration,
    /pricing for the selected model is unavailable\./,
  );
  assert.match(migration, /pandora_fail_preexecution_job_from_source_queue_v1/);
  assert.doesNotMatch(
    migration.match(/v_message := case[\s\S]*?end;/)?.[0] ?? '',
    /continuing this project in the background/,
  );
});

test('source convergence worker fails the linked pre-execution build job on TRUSTED_PRIMITIVE', () => {
  assert.match(worker, /TRUSTED_PRIMITIVE_UNAVAILABLE/);
  assert.match(worker, /row\.build_job_id/);
  assert.match(worker, /required building blocks are not available yet/);
  assert.match(worker, /\.in\("status", \["queued", "claimed", "dispatching"\]\)/);
});
