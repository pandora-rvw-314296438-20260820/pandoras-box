const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(
  path.join(root, 'apps/pandora-mobile/lib/features/simple/project_source_files_screen.dart'),
  'utf8',
);

test('paid Files projects exact source into a navigable folder hierarchy', () => {
  assert.match(source, /_projectFolder\(tree\.files, _folderPath\)/);
  assert.match(source, /_FolderBreadcrumbs\(/);
  assert.match(source, /for \(final directory in folder\.folders\)/);
  assert.match(source, /for \(final entry in folder\.files\)/);
  assert.match(source, /_folderPath = ''/);
  assert.doesNotMatch(source, /for \(final entry in tree\.files\)\s+ListTile/);
});

test('paid Files syntax preview is byte-bounded while Copy keeps exact returned source', () => {
  assert.match(source, /const _syntaxPreviewLimit = 128 \* 1024/);
  assert.match(source, /utf8\.encode\(content\)/);
  assert.match(source, /_boundedUtf8Prefix\(bytes, _syntaxPreviewLimit\)/);
  assert.match(source, /SelectableText\.rich\(/);
  assert.match(source, /_languageKeywords\(/);
  assert.match(source, /Clipboard\.setData/);
  assert.match(source, /ClipboardData\(text: file\.content\)/);
});

test('paid Files preserves authoritative version identity and governed source APIs', () => {
  assert.match(source, /watchExperience\(widget\.project\.id\)/);
  assert.match(source, /projection\.currentVersionId/);
  assert.match(source, /projection\.candidateVersionId/);
  assert.match(source, /projection\.productionVersionId/);
  assert.match(source, /selectedFile\.sha256 != otherFile\.sha256/);
  assert.match(source, /versionId: _selectedVersionId/);
  assert.match(source, /\$\{_selectedVersionId\}\.zip/);
  assert.match(source, /searchSourceFiles\(/);
  assert.match(source, /exportSourceZip\(/);
  assert.doesNotMatch(source, /signedUrl|createSignedUrl|publicUrl/i);
});
