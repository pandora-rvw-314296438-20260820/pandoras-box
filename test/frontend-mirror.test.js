const assert = require('node:assert/strict');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const test = require('node:test');

const execFileAsync = promisify(execFile);

test('Control Tower has one tracked canonical source and generated public output', async () => {
  const { stdout } = await execFileAsync(process.execPath, [
    'scripts/verify-frontend-mirrors.mjs',
  ]);
  assert.match(stdout, /one tracked authority/);
});

test('all browser JavaScript passes syntax checks', async () => {
  const { stdout } = await execFileAsync(process.execPath, [
    'scripts/check-browser-syntax.mjs',
  ]);
  assert.match(stdout, /Browser syntax checks passed/);
});
