const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const sourcePath = path.join(
  process.cwd(),
  'apps',
  'pandora-mobile',
  'lib',
  'features',
  'simple',
  'project_source_files_screen.dart',
);
const source = fs.readFileSync(sourcePath, 'utf8');

test('paid Files experience selects only exact durable project versions', () => {
  assert.match(source, /loadProjectConversation\(/);
  assert.match(source, /item\.projectVersionId/);
  assert.match(source, /_selectedVersionId/);
  assert.match(source, /loadSourceTree\([\s\S]*?versionId: requestedVersionId/);
  assert.match(source, /loadSourceFile\([\s\S]*?versionId: versionId/);
  assert.match(source, /searchSourceFiles\([\s\S]*?versionId: versionId/);
  assert.match(source, /exportSourceZip\([\s\S]*?versionId: versionId/);
});

test('paid Files experience is hierarchical without inventing a second source authority', () => {
  assert.match(source, /_projectFolder\(/);
  assert.match(source, /relativePath\.split\('\/'\)/);
  assert.match(source, /_FolderBreadcrumbs/);
  assert.doesNotMatch(source, /\.from\(['"]pandora_/);
  assert.doesNotMatch(source, /\.rpc\(/);
  assert.doesNotMatch(source, /SupabaseClient/);
});

test('paid Files experience exposes explicit copy and bounded syntax presentation', () => {
  assert.match(source, /Clipboard\.setData/);
  assert.match(source, /tooltip: 'Copy source'/);
  assert.match(source, /_SyntaxSourceView/);
  assert.match(source, /_syntaxPreviewLimit = 128 \* 1024/);
  assert.match(source, /SelectableText\.rich/);
  assert.match(source, /_sourceLanguage\(/);
  assert.match(source, /_languageKeywords\(/);
});

test('paid Files compare is exact path plus SHA-256 and remains entitlement gated', () => {
  assert.match(source, /_SourceTreeDiff\.between/);
  assert.match(source, /prior\.sha256 != entry\.sha256/);
  assert.match(source, /baseByPath\[entry\.path\]/);
  assert.match(source, /currentByPath\.containsKey\(entry\.path\)/);
  const treeReads = source.match(/await api\.loadSourceTree\(/g) ?? [];
  assert.ok(
    treeReads.length >= 3,
    'version compare must re-read exact source trees through the governed API',
  );
});

test('existing search and governed ZIP export remain present', () => {
  assert.match(source, /hintText: 'Search source'/);
  assert.match(source, /searchSourceFiles\(/);
  assert.match(source, /exportSourceZip\(/);
  assert.match(source, /PandoraNativeIo\.saveBinaryDocument/);
});
