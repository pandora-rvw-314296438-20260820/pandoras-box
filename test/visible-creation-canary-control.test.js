const fs = require('node:fs');
const test = require('node:test');
const assert = require('node:assert/strict');

const migration = fs.readFileSync('supabase/migrations/20260903131045_pandora_visible_creation_canary_control_v1.sql', 'utf8');
const generator = fs.readFileSync('supabase/functions/pandora-project-source-generator/index.ts', 'utf8');

test('Visible Creation canary defaults off and is service-role only', () => {
  assert.match(migration, /enabled boolean not null default false/);
  assert.match(migration, /target_kind in \('user','project'\)/);
  assert.match(migration, /revoke all on table public\.pandora_visible_creation_canary_control from public, anon, authenticated/);
  assert.match(migration, /revoke all on table public\.pandora_visible_creation_canary_allowlist from public, anon, authenticated/);
  assert.match(migration, /grant execute on function public\.pandora_visible_creation_canary_allowed_v1\(uuid, uuid\) to service_role/);
});

test('canary decision requires global enable plus bounded user or project allowlist', () => {
  assert.match(migration, /coalesce\(\(select c\.enabled/);
  assert.match(migration, /a\.enabled = true/);
  assert.match(migration, /a\.target_kind = 'user' and a\.target_id = p_user_id/);
  assert.match(migration, /a\.target_kind = 'project' and a\.target_id = p_project_id/);
});

test('existing idempotent sessions replay before canary gates new work', () => {
  const existing = generator.indexOf('if (existingSession.data)');
  const gate = generator.indexOf('pandora_visible_creation_canary_allowed_v1');
  const spec = generator.indexOf('let { data: spec, error: specError }');
  assert.ok(existing >= 0);
  assert.ok(gate > existing);
  assert.ok(spec > gate);
  assert.match(generator, /canary\.error \|\| canary\.data !== true/);
  assert.match(generator, /VISIBLE_CREATION_CANARY_DISABLED/);
});

test('canary-disabled admission is terminal and maps to a truthful blocked response', () => {
  assert.match(generator, /\["BUILD_TYPE_NOT_SUPPORTED", "PROJECT_SPEC_NOT_READY", "PROJECT_NOT_AVAILABLE", "VISIBLE_CREATION_CANARY_DISABLED"\]\.includes\(code\)/);
  assert.match(generator, /code === "VISIBLE_CREATION_CANARY_DISABLED" \? 403/);
});
