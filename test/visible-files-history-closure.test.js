const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '..');
const sourceFiles = fs.readFileSync(
  path.join(root, 'apps/pandora-mobile/lib/features/simple/project_source_files_screen.dart'),
  'utf8',
);
const history = fs.readFileSync(
  path.join(root, 'apps/pandora-mobile/lib/features/simple/project_history_screen.dart'),
  'utf8',
);

test('paid Files stays bound to authoritative versions and entitlement APIs', () => {
  assert.match(sourceFiles, /watchExperience\(widget\.project\.id\)/);
  assert.match(sourceFiles, /projection\.currentVersionId/);
  assert.match(sourceFiles, /projection\.candidateVersionId/);
  assert.match(sourceFiles, /projection\.productionVersionId/);
  assert.match(sourceFiles, /loadSourceTree\(/);
  assert.match(sourceFiles, /loadSourceFile\(/);
  assert.match(sourceFiles, /searchSourceFiles\(/);
  assert.match(sourceFiles, /exportSourceZip\(/);
});

test('paid Files exposes copy and digest-based exact-version comparison', () => {
  assert.match(sourceFiles, /Clipboard\.setData/);
  assert.match(sourceFiles, /selectedFile\.sha256 != otherFile\.sha256/);
  assert.match(sourceFiles, /Compare exact source/);
  assert.match(sourceFiles, /_selectedVersionId/);
  assert.doesNotMatch(sourceFiles, /signedUrl|createSignedUrl|publicUrl/i);
});

test('History exposes human-readable proof with technical lineage collapsed', () => {
  assert.match(history, /label: const Text\('Evidence'\)/);
  assert.match(history, /Technical IDs/);
  assert.match(history, /Exact lineage for advanced verification/);
  for (const field of [
    'sourceIntentId',
    'projectSpecId',
    'buildAuthorizationId',
    'buildJobId',
    'projectVersionId',
    'verificationRunId',
    'deploymentId',
  ]) {
    assert.match(history, new RegExp(`item\\.${field}`));
  }
});
