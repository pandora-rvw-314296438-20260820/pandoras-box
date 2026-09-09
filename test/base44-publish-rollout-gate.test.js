const fs = require('node:fs');
const test = require('node:test');
const assert = require('node:assert/strict');

const migration = fs.readFileSync(
  'supabase/migrations/20260909070800_pandora_base44_publish_rollout_gate_v1.sql',
  'utf8',
);
const runtime = fs.readFileSync(
  'supabase/functions/pandora-project-runtime/index.ts',
  'utf8',
);
const errors = fs.readFileSync(
  'supabase/functions/pandora-project-runtime/runtime-errors.ts',
  'utf8',
);

test('Base44 publish rollout defaults off and is service-role only', () => {
  assert.match(migration, /action text primary key check \(action in \('publish'\)\)/);
  assert.match(migration, /values \('publish', false\)/);
  assert.match(migration, /revoke all on table public\.pandora_base44_rollout_projects from public, anon, authenticated/);
  assert.match(migration, /revoke all on table public\.pandora_base44_action_control from public, anon, authenticated/);
  assert.match(migration, /grant execute on function public\.pandora_base44_action_allowed_v1\(uuid, text\) to service_role/);
});

test('only the isolated Base44 acceptance project is seeded into the rollout boundary', () => {
  assert.match(migration, /db007811-fe55-42b4-b0be-3a11324dcfff/);
  assert.match(migration, /076a9306-5c4e-4d9d-98d3-e3a6fea968fb/);
  assert.match(migration, /p\.project_key = 'base44-acceptance'/);
});

test('legacy projects pass through while enrolled Base44 projects fail closed', () => {
  assert.match(migration, /when not exists \([\s\S]*pandora_base44_rollout_projects[\s\S]*then true/);
  assert.match(migration, /when btrim\(p_action\) <> 'publish' then false/);
  assert.match(migration, /where c\.action = btrim\(p_action\)/);
  assert.match(migration, /\), false\)/);
});

test('publish checks the Base44 rollout before any publish provider mutation path', () => {
  const publishStart = runtime.indexOf('async function publishProject');
  const publishEnd = runtime.indexOf('async function finalizeProductionVerification', publishStart);
  const publish = runtime.slice(publishStart, publishEnd);
  const gate = publish.indexOf('pandora_base44_action_allowed_v1');
  const previewRecovery = publish.indexOf('createPreview(context');
  const provider = publish.indexOf('ensureVercelProject(context, project)');
  const deployment = publish.indexOf('vercelRequest("/v13/deployments"');
  assert.ok(gate > 0);
  assert.ok(previewRecovery > gate);
  assert.ok(provider > gate);
  assert.ok(deployment > gate);
  assert.match(publish, /base44Rollout\.error \|\| base44Rollout\.data !== true/);
  assert.match(publish, /BASE44_ROLLOUT_DISABLED/);
});

test('disabled Base44 publish has a truthful fail-closed public error', () => {
  assert.match(errors, /code === "BASE44_ROLLOUT_DISABLED"/);
  assert.match(errors, /403/);
  assert.match(errors, /"publish"/);
  assert.match(errors, /"authorization"/);
  assert.match(errors, /Publishing is not enabled for this experience yet\./);
});
