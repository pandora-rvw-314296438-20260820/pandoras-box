const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const sourcePath = path.join(
  process.cwd(),
  'supabase/functions/pandora-github-uiux-convergence-20260828/index.ts',
);
const source = fs.readFileSync(sourcePath, 'utf8');
const secretLine = source
  .split('\n')
  .find((line) => line.startsWith('const SECRET=/'));
assert.ok(secretLine, 'production SECRET detector must be present');
const secretPattern = secretLine.slice('const SECRET=/'.length, -2);
const secretDetector = new RegExp(secretPattern);

test('RDP secret detector ignores ask-* UI identifiers', () => {
  const uiKey = 'ask-pandora-communication-status-key';
  assert.equal(secretDetector.test(uiKey), false);
});

test('RDP secret detector still catches a standalone sk token shape', () => {
  const token = 's' + 'k-' + 'A'.repeat(24);
  assert.equal(secretDetector.test(`'${token}'`), true);
});
