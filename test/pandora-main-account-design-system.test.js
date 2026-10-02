const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

const index = read('apps/control-tower/index.html');
const tokens = read('apps/control-tower/owner-design-system.css');
const ownerFirst = read('apps/control-tower/owner-first.css');
const ownerActions = read('apps/control-tower/owner-first-3.css');
const ownerData = read('apps/control-tower/owner-data.js');
const materializer = read('scripts/materialize-control-tower.mjs');

test('main account loads one canonical token layer before owner components', () => {
  const tokenIndex = index.indexOf('/control-tower/owner-design-system.css');
  const componentIndex = index.indexOf('/control-tower/owner-first.css');
  assert.ok(tokenIndex > -1, 'design-system stylesheet is loaded');
  assert.ok(tokenIndex < componentIndex, 'tokens load before owner components');
  assert.doesNotMatch(ownerFirst, /:root\s*\{/);
});

test('design system includes semantic color, spacing, motion, focus, and layout tokens', () => {
  for (const token of [
    '--owner-action',
    '--owner-on-action',
    '--owner-space-4',
    '--owner-motion-standard',
    '--owner-focus',
    '--owner-control-min',
    '--owner-content-width',
  ]) {
    assert.match(tokens, new RegExp(`${token}:`), `${token} is declared`);
  }
  assert.match(tokens, /prefers-reduced-motion:\s*reduce/);
  assert.match(tokens, /forced-colors:\s*active/);
});

test('routine primary actions do not use the Pandora brand red', () => {
  assert.match(ownerActions, /\.owner-button\.primary\s*\{[^}]*var\(--owner-action\)/s);
  assert.doesNotMatch(ownerActions, /\.owner-button\.primary\s*\{[^}]*owner-red/s);
});

test('the owner brand mark is a local release asset', () => {
  assert.match(ownerData, /BRAND_MARK = '\/assets\/brand\/pandora-product-mark-ui-1024\.png'/);
  assert.doesNotMatch(ownerData, /raw\.githubusercontent\.com/);
  assert.match(
    materializer,
    /apps\/pandora-mobile\/assets\/brand\/pandora-product-mark-ui-1024\.png/,
  );
  assert.match(
    materializer,
    /public\/assets\/brand\/pandora-product-mark-ui-1024\.png/,
  );
});
