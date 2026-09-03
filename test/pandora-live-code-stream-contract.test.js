const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');

const generator = fs.readFileSync('supabase/functions/pandora-project-source-generator/index.ts', 'utf8');
const migration = fs.readFileSync('supabase/migrations/20260901004825_pandora_live_code_stream_v1.sql', 'utf8');
const api = fs.readFileSync('apps/pandora-mobile/lib/core/data/project_experience_api.dart', 'utf8');
const conversation = fs.readFileSync('apps/pandora-mobile/lib/features/simple/project_build_conversation.dart', 'utf8');
const projection = fs.readFileSync('apps/pandora-mobile/lib/features/simple/live_build_theatre/project_build_stream_theatre_projection.dart', 'utf8');
const theatre = fs.readFileSync('apps/pandora-mobile/lib/features/simple/live_build_theatre/live_build_theatre.dart', 'utf8');
const createExperience = fs.readFileSync('apps/pandora-mobile/lib/features/simple/project_create_experience.dart', 'utf8');

test('live build theatre renders only real generated source chunks', () => {
  assert.match(generator, /streamGenerateContent\?alt=sse/);
  assert.match(generator, /"file_start"/);
  assert.match(generator, /"file_chunk"/);
  assert.match(generator, /"file_end"/);
  assert.match(generator, /"done"/);
  assert.match(generator, /Never emit fake code/);
  assert.match(generator, /queueStreamEvent\(state, "code_chunk", path, liveChunk,/);
  assert.match(generator, /content_chunk: contentChunk/);
  assert.match(generator, /const providerCredential = credential\.data\.trim\(\);/);
  assert.match(generator, /state\.knownSecrets\.push\(providerCredential\)/);
  assert.match(generator, /"x-goog-api-key": providerCredential/);
  assert.doesNotMatch(generator, /[?&]key=\$\{/);
  assert.match(api, /watchBuildStream/);
  assert.match(api, /watchResilientBuildStream/);
  assert.match(api, /pandora_build_stream_events/);
  assert.match(projection, /contentChunk: event\.contentChunk/);
  assert.match(projection, /sequence: event\.sequence/);
  assert.match(projection, /historyGapDueToRetention: snapshot\.historyGapDueToRetention/);
  assert.match(conversation, /ProjectBuildStreamTheatreProjection\.fromSnapshot/);
  assert.match(conversation, /LiveBuildTheatre\(state: theatre\)/);
  assert.match(conversation, /Source will appear only after real source bytes arrive\./);
  assert.match(theatre, /if \(state\.hasVisibleRealSource\)/);
  assert.doesNotMatch(conversation, /LinearProgressIndicator/);
  assert.doesNotMatch(conversation, /progress_percent|progressPercent|% complete/i);
  assert.equal(conversation.includes('scrollable: false,'), true);
  assert.equal(generator.includes('return typeof value === "string" ? value : "";'), true);
  assert.equal(generator.includes('parts.map((part) => text(rec(part).text))'), false);
  assert.equal(createExperience.includes("_buildIdempotencyKey ??="), true);
  assert.equal(createExperience.includes("_keys.create('pandora-v2-build:${widget.project.id}')"), true);
  assert.equal(createExperience.includes('idempotencyKey: _buildIdempotencyKey!'), true);
});

test('live source visibility is ephemeral and read-only to authenticated members', () => {
  assert.match(migration, /expires_at timestamptz not null default \(now\(\) \+ interval '20 minutes'\)/);
  assert.match(migration, /expires_at > now\(\)/);
  assert.match(migration, /revoke all on public\.pandora_build_stream_events from anon, authenticated/);
  assert.match(migration, /grant select on public\.pandora_build_stream_events to authenticated/);
  assert.match(migration, /coalesce\(auth\.role\(\), ''\) <> 'service_role'/);
  assert.match(migration, /revoke all on function public\.pandora_gemini_stream_credential_service_20260901\(\) from public, anon, authenticated/);
  assert.match(migration, /if tg_op = 'INSERT' then/);
  assert.doesNotMatch(migration, /if tg_op = 'INSERT'\s+or/);
  assert.doesNotMatch(conversation, /SelectableText/);
  assert.doesNotMatch(conversation, /Download source|Open files|Copy source/);
});

test('conversation preserves the long request without letting it dominate the build', () => {
  assert.match(conversation, /maxLines: expanded \|\| !isLong \? null : 4/);
  assert.match(conversation, /Show full request/);
  assert.match(conversation, /Collapse request/);
  assert.match(conversation, /Reconnecting to the live build/);
  assert.match(conversation, /Expired source is not recreated/);
});
