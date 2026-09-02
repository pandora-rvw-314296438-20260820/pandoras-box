const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(
  path.join(
    root,
    'apps/pandora-mobile/lib/features/simple/project_workspace_v2_view.dart',
  ),
  'utf8',
);

test('safe exact preview becomes the primary workspace surface', () => {
  assert.match(source, /hasExactPreview: hasExactPreview/);
  assert.match(source, /previewPrimaryExtent = \.14/);
  assert.match(source, /pendingExtent = \.28/);
  assert.match(source, /minChildSize: _restingExtent/);
  assert.doesNotMatch(source, /initialChildSize: \.18/);
});

test('preview readiness animates the composer into a secondary strip', () => {
  assert.match(source, /oldWidget\.hasExactPreview == widget\.hasExactPreview/);
  assert.match(source, /_controller\.animateTo\(/);
  assert.match(source, /duration: const Duration\(milliseconds: 360\)/);
  assert.match(source, /curve: Curves\.easeOutCubic/);
});

test('secondary composer remains deliberately expandable', () => {
  assert.match(source, /maxExtent = \.64/);
  assert.match(source, /snapSizes: const \[\.38\]/);
  assert.match(source, /workspace-progressive-composer/);
  assert.match(source, /_PandoraComposerSheet\(/);
});
