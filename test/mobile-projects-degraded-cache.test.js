const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(process.cwd(), 'apps/pandora-mobile/lib/features/simple/projects_screen.dart'),
  'utf8',
);

test('cached project fallback remains visibly degraded instead of masquerading as fresh', () => {
  assert.equal(source.includes('result.isCached'), true);
  assert.equal(source.includes('result.degradedReason'), true);
  assert.equal(source.includes('last safe project list while it reconnects'), true);
});
