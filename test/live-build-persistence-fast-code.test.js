
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
const projection = fs.readFileSync(
  'apps/pandora-mobile/lib/features/simple/live_build_theatre/project_build_stream_theatre_projection.dart',
  'utf8',
);
const theatre = fs.readFileSync(
  'apps/pandora-mobile/lib/features/simple/live_build_theatre/live_build_theatre.dart',
  'utf8',
);
const generator = fs.readFileSync(
  'supabase/functions/pandora-project-source-generator/index.ts',
  'utf8',
);

test('live source events are rendered in canonical chronological order', () => {
  assert.ok(api.includes('..sort((left, right) => left.sequence.compareTo(right.sequence))'));
  assert.ok(projection.includes('sequence: event.sequence'));
  assert.ok(projection.includes('contentChunk: event.contentChunk'));
  assert.ok(conversation.includes('ProjectBuildStreamTheatreProjection.fromSnapshot('));
  assert.ok(conversation.includes('LiveBuildTheatre(state: theatre)'));
  assert.ok(theatre.includes('if (state.hasVisibleRealSource)'));
  assert.ok(!conversation.includes("view.visibleCode.isEmpty ? ' ' : view.visibleCode"));
});

test('real provider source is exposed as rapid realtime display slices', () => {
  assert.ok(generator.includes('offset + 2048'));
  assert.ok(generator.includes('const liveChunk = content.slice(offset, end);'));
  assert.ok(generator.includes('queueStreamEvent(state, "code_chunk", path, liveChunk'));
  assert.ok(generator.includes('if (!state.pending.length || (!force && state.pending.length < 6)) return;'));
  assert.ok(generator.includes('await flushStreamEvents(admin, state);'));
  assert.ok(generator.includes('await flushStreamEvents(admin, state, true);'));
  const worstCaseRows = Math.ceil((4 * 1024 * 1024) / 2048) + (120 * 2) + 8;
  assert.ok(worstCaseRows <= 2500);
  assert.ok(!generator.includes('queueStreamEvent(state, "code_chunk", path, content, { byteSize: bytes.byteLength })'));
});

test('accepted builds are server-owned and survive the mobile app lifecycle', () => {
  assert.ok(generator.includes('runtime.waitUntil(runGenerationInBackground({'));
  assert.ok(generator.includes('output_mode: "structured"'));
  assert.ok(!generator.includes('output_mode: "streamed_source"'));
  assert.ok(generator.includes('pandora_admit_authorized_build_service_v1'));
  assert.ok(generator.includes('const buildJobId = text(admission.buildJobId);'));
  assert.ok(generator.includes('p_build_job_id: buildJobId'));
  assert.ok(generator.includes('      buildJobId,'));
  assert.ok(generator.includes('if (runtime?.waitUntil && !admission.projectVersionId)'));
  assert.ok(!generator.includes('pandora_build_stream_sessions").insert'));
});
