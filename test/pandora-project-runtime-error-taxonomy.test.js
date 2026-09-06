const test = require('node:test');
const assert = require('node:assert/strict');
const { readFile } = require('node:fs/promises');
const { join } = require('node:path');

const errorsPath = join(
  process.cwd(),
  'supabase',
  'functions',
  'pandora-project-runtime',
  'runtime-errors.ts',
);
const runtimePath = join(
  process.cwd(),
  'supabase',
  'functions',
  'pandora-project-runtime',
  'index.ts',
);

test('project runtime exposes one shared public error taxonomy', async () => {
  const [errors, runtime] = await Promise.all([
    readFile(errorsPath, 'utf8'),
    readFile(runtimePath, 'utf8'),
  ]);

  assert.match(errors, /operation:/);
  assert.match(errors, /phase:/);
  assert.match(errors, /retryable:/);
  assert.match(errors, /outcomeKnown:/);
  assert.match(errors, /PROJECT_CREATE_IDEMPOTENCY_COLLISION/);
  assert.match(errors, /PREVIEW_RECONCILIATION_REQUIRED/);
  assert.match(errors, /PUBLISH_RECONCILIATION_REQUIRED/);
  assert.match(runtime, /classifyProjectRuntimeError\(code\)/);
  assert.doesNotMatch(
    runtime.slice(runtime.indexOf('} catch (error) {')),
    /const invalid = new Set/,
  );
});
