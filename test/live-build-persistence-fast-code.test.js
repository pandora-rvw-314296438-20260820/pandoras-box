
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const api = fs.readFileSync(
  'apps/pandora-mobile/lib/core/data/project_experience_api.dart',
  'utf8',
);
const conversation = fs.readFileSync(
  'apps/pandora-mobile/lib/features/simple/project_build_conversation.dart',
  'utf8',
);
const generator = fs.readFileSync(
  'supabase/functions/pandora-project-source-generator/index.ts',
  'utf8',
);

test('live source events are rendered in canonical chronological order', () => {
  assert.ok(api.includes('..sort((left, right) => left.id.compareTo(right.id))'));
  assert.ok(conversation.includes('view.currentFile != null && view.visibleCode.isNotEmpty'));
  assert.ok(!conversation.includes("view.visibleCode.isEmpty ? ' ' : view.visibleCode"));
});

test('real provider source is exposed as rapid realtime display slices', () => {
  assert.ok(generator.includes('offset + 768'));
  assert.ok(generator.includes('const liveChunk = content.slice(offset, end);'));
  assert.ok(generator.includes('queueStreamEvent(state, "code_chunk", path, liveChunk'));
  assert.ok(!generator.includes('queueStreamEvent(state, "code_chunk", path, content, { byteSize: bytes.byteLength })'));
});

test('accepted builds are server-owned and survive the mobile app lifecycle', () => {
  assert.ok(generator.includes('runtime.waitUntil(runGenerationInBackground({'));
  assert.ok(generator.includes('output_mode: "structured"'));
  assert.ok(!generator.includes('output_mode: "streamed_source"'));
  assert.ok(generator.includes('event_type: "build_job_created"'));
});
