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
const gateModule = fs.readFileSync(
  'supabase/functions/pandora-project-runtime/external-write-gate.mjs',
  'utf8',
);
const runtimeErrors = fs.readFileSync(
  'supabase/functions/pandora-project-runtime/runtime-errors.ts',
  'utf8',
);

const operations = [
  'project.create',
  'preview.create',
  'project.undo',
  'project.rollback',
  'project.publish',
  'production.verify',
];

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

test('external write control and executable gate enumerate the complete privileged POST surface', () => {
  for (const operation of operations) {
    assert.ok(
      migration.includes(`'${operation}'`),
      `missing migration operation ${operation}`,
    );
    assert.ok(
      gateModule.includes(`"${operation}"`),
      `missing executable gate operation ${operation}`,
    );
  }
});

test('runtime delegates external authorization to the shared executable request gate', () => {
  assert.match(
    runtime,
    /import \{ enforceExternalExperienceWriteRequest \} from "\.\/external-write-gate\.mjs";/,
  );
  assert.match(
    runtime,
    /serviceClient\(\)\.rpc\(\s*"pandora_external_experience_write_allowed_v1"/s,
  );
  assert.match(runtime, /p_origin: checkedOrigin/);
  assert.match(runtime, /p_operation: operation/);
  assert.match(runtime, /if \(error\) return false/);
  assert.match(runtime, /return data === true/);

  const routeIndex = runtime.indexOf(
    'const route = routePath(new URL(req.url).pathname);',
  );
  const gateIndex = runtime.indexOf(
    'await assertExternalExperienceWriteAllowed(origin, req.method, route);',
    routeIndex,
  );
  const firstPostIndex = runtime.indexOf(
    'if (req.method === "POST" && route === "/projects")',
    gateIndex,
  );
  assert.ok(routeIndex >= 0);
  assert.ok(gateIndex > routeIndex);
  assert.ok(firstPostIndex > gateIndex);
});

test('shared gate preserves first-party and no-Origin behavior and fails closed otherwise', () => {
  assert.match(
    gateModule,
    /if \(!origin \|\| firstPartyOrigins\.has\(origin\)\)/,
  );
  assert.match(
    gateModule,
    /allowed = \(await decide\(origin, operation\)\) === true/,
  );
  assert.match(gateModule, /catch \{\s*allowed = false;\s*\}/s);
  assert.match(
    gateModule,
    /throw new ExternalExperienceWriteDisabledError\(\)/,
  );
  assert.match(gateModule, /this\.status = 403/);
  assert.match(gateModule, /this\.retryable = false/);
  assert.match(gateModule, /this\.outcomeKnown = true/);
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
