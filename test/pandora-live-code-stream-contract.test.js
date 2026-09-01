const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const generator = fs.readFileSync('supabase/functions/pandora-project-source-generator/index.ts', 'utf8');
const migration = fs.readFileSync('supabase/migrations/20260901074500_pandora_live_code_stream_v1.sql', 'utf8');
const api = fs.readFileSync('apps/pandora-mobile/lib/core/data/project_experience_api.dart', 'utf8');
const conversation = fs.readFileSync('apps/pandora-mobile/lib/features/simple/project_build_conversation.dart', 'utf8');

test('live build theatre renders only real generated source chunks', () => {
  assert.match(generator, /streamGenerateContent\?alt=sse/);
  assert.match(generator, /"file_start"/);
  assert.match(generator, /"file_chunk"/);
  assert.match(generator, /"file_end"/);
  assert.match(generator, /"done"/);
  assert.match(generator, /Never emit fake code/);
  assert.match(generator, /event_type: "code_chunk"/);
  assert.match(generator, /content_chunk: contentChunk/);\n  assert.match(generator, /\\"x-goog-api-key\\": credential\\.data\\.trim\\(\\)/);\n  assert.doesNotMatch(generator, /[?&]key=\\$\\{/);
  assert.match(api, /watchBuildStream/);
  assert.match(api, /pandora_build_stream_events/);
  assert.match(conversation, /event\.contentChunk/);
  assert.match(conversation, /Pandora is coding/);
  assert.doesNotMatch(conversation, /LinearProgressIndicator/);
  assert.doesNotMatch(conversation, /progress_percent|progressPercent|% complete/i);
});

test('live source visibility is ephemeral and read-only to authenticated members', () => {
  assert.match(migration, /expires_at timestamptz not null default \(now\(\) \+ interval '20 minutes'\)/);
  assert.match(migration, /expires_at > now\(\)/);
  assert.match(migration, /revoke all on public\.pandora_build_stream_events from anon, authenticated/);
  assert.match(migration, /grant select on public\.pandora_build_stream_events to authenticated/);
  assert.match(migration, /coalesce\(auth\.role\(\), ''\) <> 'service_role'/);
  assert.match(migration, /revoke all on function public\.pandora_gemini_stream_credential_service_20260901\(\) from public, anon, authenticated/);
  assert.doesNotMatch(conversation, /SelectableText/);
  assert.doesNotMatch(conversation, /Download source|Open files|Copy source/);
});

test('conversation preserves the long request without letting it dominate the build', () => {
  assert.match(conversation, /maxLines: expanded \|\| !isLong \? null : 4/);
  assert.match(conversation, /Show full request/);
  assert.match(conversation, /Collapse request/);
  assert.match(conversation, /Live code view disconnected/);
});
