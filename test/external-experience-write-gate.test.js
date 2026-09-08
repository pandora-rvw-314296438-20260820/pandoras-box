const fs = require('node:fs');
const test = require('node:test');
const assert = require('node:assert/strict');

const migration = fs.readFileSync(
  'supabase/migrations/20260909030000_pandora_external_experience_write_control_v1.sql',
  'utf8',
);
const runtime = fs.readFileSync(
  'supabase/functions/pandora-project-runtime/index.ts',
  'utf8',
);
const runtimeErrors = fs.readFileSync(
  'supabase/functions/pandora-project-runtime/runtime-errors.ts',
  'utf8',
);

test('external experience write control defaults off and is service-role only', () => {
  assert.match(migration, /enabled boolean not null default false/);
  assert.match(
    migration,
    /revoke all on table public\.pandora_external_experience_write_control from public, anon, authenticated/,
  );
  assert.match(
    migration,
    /revoke all on table public\.pandora_external_experience_write_allowlist from public, anon, authenticated/,
  );
  assert.match(
    migration,
    /grant execute\s+on function public\.pandora_external_experience_write_allowed_v1\(text, text\)\s+to service_role/s,
  );
});

test('external write control enumerates the complete privileged runtime POST surface', () => {
  for (const operation of [
    'project.create',
    'preview.create',
    'project.undo',
    'project.rollback',
    'project.publish',
    'production.verify',
  ]) {
    assert.ok(migration.includes(`'${operation}'`), `missing migration operation ${operation}`);
    assert.ok(
      runtime.includes(`assertExternalExperienceWriteAllowed(origin, "${operation}")`),
      `missing runtime gate for ${operation}`,
    );
  }
});

test('first-party and no-Origin clients preserve existing behavior while configured external origins require service decision', () => {
  assert.match(runtime, /if \(!origin \|\| DEFAULT_ORIGINS\.has\(origin\)\) return;/);
  assert.match(
    runtime,
    /serviceClient\(\)\.rpc\(\s*"pandora_external_experience_write_allowed_v1"/s,
  );
  assert.match(runtime, /p_origin: origin/);
  assert.match(runtime, /p_operation: operation/);
  assert.match(runtime, /if \(error \|\| data !== true\)/);
  assert.match(runtime, /EXTERNAL_EXPERIENCE_WRITE_DISABLED/);
});

test('every external gate runs before request body parsing and privileged handler invocation', () => {
  const routeChecks = [
    [
      'assertExternalExperienceWriteAllowed(origin, "project.create")',
      'await bodyJson(req)',
    ],
    [
      'assertExternalExperienceWriteAllowed(origin, "preview.create")',
      'createPreview(context',
    ],
    [
      'assertExternalExperienceWriteAllowed(origin, "project.undo")',
      'undoProject(context',
    ],
    [
      'assertExternalExperienceWriteAllowed(origin, "project.rollback")',
      'rollbackProject(context',
    ],
    [
      'assertExternalExperienceWriteAllowed(origin, "project.publish")',
      'publishProject(context',
    ],
    [
      'assertExternalExperienceWriteAllowed(origin, "production.verify")',
      'finalizeProductionVerification(context',
    ],
  ];

  for (const [gate, action] of routeChecks) {
    const gateIndex = runtime.indexOf(gate);
    const actionIndex = runtime.indexOf(action, gateIndex);
    assert.ok(gateIndex >= 0, `missing gate ${gate}`);
    assert.ok(actionIndex > gateIndex, `action runs before gate: ${action}`);
  }
});

test('external write denial is truthful, known, non-retryable authorization failure', () => {
  const marker = 'if (code === "EXTERNAL_EXPERIENCE_WRITE_DISABLED")';
  const start = runtimeErrors.indexOf(marker);
  assert.ok(start >= 0);
  const block = runtimeErrors.slice(start, start + 360);
  assert.match(block, /403/);
  assert.match(block, /not enabled for this project action/);
  assert.match(block, /"authorization"/);
});
