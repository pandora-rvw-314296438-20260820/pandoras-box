const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

const migration = fs.readFileSync(
  'supabase/migrations/20260910161000_pandora_theatre_mid_generation_truth_v1.sql',
  'utf8',
);
const generator = fs.readFileSync(
  'supabase/functions/pandora-project-source-generator/index.ts',
  'utf8',
);

test('preexecution terminal is false when stream generation evidence exists', () => {
  assert.match(migration, /v_generation_evidence/);
  assert.match(migration, /'file_started'/);
  assert.match(migration, /'code_chunk'/);
  assert.match(migration, /'file_completed'/);
  assert.match(migration, /'impact_classified'/);
  assert.match(migration, /'generation_completed'/);
  assert.match(
    migration,
    /and not v_generation_evidence\s+and not v_mid_generation_error/s,
  );
});

test('mid-generation error codes are not treated as pre-execution', () => {
  assert.match(migration, /v_mid_generation_error/);
  assert.match(migration, /like 'INVALID_GENERATED_SOURCE%'/);
  assert.match(migration, /like 'SOURCE_STREAM_WRITE_FAILED%'/);
  assert.match(
    migration,
    /Pandora could not finish generating this project\. You can try again\./,
  );
  assert.doesNotMatch(
    migration.match(
      /when new\.status in \('failed','cancelled'\)\s+and \(v_generation_evidence or v_mid_generation_error\)[\s\S]*?then 'Pandora could not finish generating this project\. You can try again\.'/,
    )?.[0] ?? '',
    /did not start this build/,
  );
});

test('failed mid-generation Theatre stays Needs You / retry, never Live or Ready', () => {
  const sync = migration.match(
    /create or replace function private\.pandora_sync_build_theatre_from_job\(\)[\s\S]*?\$function\$;/,
  )?.[0] ?? '';
  assert.match(sync, /when v_terminal_failure then 'needs_you'/);
  assert.match(sync, /new\.status in \('failed','cancelled'\)/);
  assert.doesNotMatch(sync, /then 'live'/);
  assert.doesNotMatch(sync, /then 'preview_ready'/);
  assert.match(sync, /needs_you/);
  assert.match(sync, /retry_available/);
});

test('source-queue preexecution fail path tells mid-generation truth', () => {
  assert.match(
    migration,
    /create or replace function private\.pandora_fail_preexecution_job_from_source_queue_v1/,
  );
  assert.match(
    migration,
    /if v_generation_evidence or v_mid_generation_error then/,
  );
  assert.match(
    migration,
    /current_stage = 'failed'[\s\S]*public_error_summary =\s*'Pandora could not finish generating this project\. You can try again\.'/,
  );
});

test('source generator emits stable stream reason subtypes and keeps public copy generic', () => {
  assert.match(generator, /invalidGeneratedSourceStream\("STREAM_JSON_PARSE"\)/);
  assert.match(generator, /invalidGeneratedSourceStream\("FILE_START_PATH_REJECTED"\)/);
  assert.match(generator, /invalidGeneratedSourceStream\("STREAM_INCOMPLETE"\)/);
  assert.match(generator, /isMidGenerationSourceFailure\(code\)/);
  assert.match(
    generator,
    /Pandora could not finish generating this project\. You can try again\./,
  );
  assert.doesNotMatch(generator, /throw new Error\("INVALID_GENERATED_SOURCE_STREAM"\)/);
  // Queue / job_state still receive the full reason-coded message (family prefix preserved).
  assert.match(generator, /last_error_code: code\.slice\(0, 120\)/);
  assert.match(generator, /safe_payload: \{ stage: "source_generation", state: "retrying", code \}/);
});
