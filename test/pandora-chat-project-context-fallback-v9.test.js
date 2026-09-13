import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const migrationPath = new URL(
  '../supabase/migrations/20260913080649_pandora_chat_project_context_read_fallback_v9.sql',
  import.meta.url,
);
const mobilePath = new URL(
  '../apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart',
  import.meta.url,
);

const migration = await readFile(migrationPath, 'utf8');
const mobile = await readFile(mobilePath, 'utf8');

test('selected-project context reads are not coerced into repository reads', () => {
  assert.match(migration, /Project-context reads are not repository operations/);
  assert.match(migration, /p_project_id is not null/);
  assert.match(migration, /show\|read\|explain[\s\S]*plan\|roadmap\|requirements\|scope\|status/);
  assert.match(migration, /github\|repository\|repo\|code\|source/);
  assert.match(migration, /return public\.pandora_chat_universal_dispatch_v6/);
});

test('mobile capability preflight failure falls through to authenticated intelligence', () => {
  assert.match(
    mobile,
    /Future<PandoraIntelligenceTurn\?> _dispatchCapability[\s\S]*on PostgrestException \{[\s\S]*return null;/,
  );
  assert.doesNotMatch(mobile, /Pandora could not verify that capability right now/);
});
