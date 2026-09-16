const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

const generator = fs.readFileSync(
  'supabase/functions/pandora-project-source-generator/index.ts',
  'utf8',
);

const REQUIRED_REASONS = [
  'STREAM_JSON_PARSE',
  'STREAM_START_INVALID',
  'FILE_START_INVALID',
  'FILE_START_PATH_REJECTED',
  'FILE_CHUNK_INVALID',
  'FILE_CHUNK_STATE',
  'FILE_CHUNK_TOO_LARGE',
  'FILE_CHUNK_BUDGET',
  'FILE_CHUNK_SECRET',
  'FILE_END_INVALID',
  'FILE_END_STATE',
  'FILE_END_SECRET',
  'STREAM_DONE_INVALID',
  'STREAM_EVENT_UNKNOWN',
  'STREAM_OUTPUT_BUDGET',
  'STREAM_INCOMPLETE',
];

test('INVALID_GENERATED_SOURCE_STREAM reasons are stable diagnostic codes', () => {
  for (const reason of REQUIRED_REASONS) {
    assert.match(
      generator,
      new RegExp(`invalidGeneratedSourceStream\\("${reason}"\\)`),
      reason,
    );
    assert.doesNotMatch(reason, /[:\\s]/, 'reasons must stay colon-free tokens');
  }
});

test('mid-generation family matcher covers stream subtypes and write failures', () => {
  assert.match(
    generator,
    /code\.startsWith\("INVALID_GENERATED_SOURCE"\) \|\| code\.startsWith\("SOURCE_STREAM_WRITE_FAILED"\)/,
  );
  // Subtypes remain the same retry family: terminal list is exact and does not include them.
  const catchBlock = generator.match(/} catch \(error\) \{[\s\S]*?\n  \}/)?.[0] ?? '';
  assert.match(catchBlock, /dispatchCount >= 5/);
  assert.doesNotMatch(catchBlock, /INVALID_GENERATED_SOURCE_STREAM/);
});
