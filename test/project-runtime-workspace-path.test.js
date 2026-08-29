
const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');

const source = readFileSync(
  resolve(process.cwd(), 'supabase/functions/pandora-project-runtime/index.ts'),
  'utf8',
);

test('customer project creation writes the canonical ProjectOS workspace path', () => {
  assert.match(
    source,
    /workspace_path:\s*`projectos\/projects\/\$\{projectKey\}`/,
  );
  assert.doesNotMatch(
    source,
    /workspace_path:\s*`projects\/\$\{projectKey\}`/,
  );
});
