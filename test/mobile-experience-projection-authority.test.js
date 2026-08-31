const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const repositoryRoot = join(__dirname, '..');
const experienceSource = readFileSync(
  join(
    repositoryRoot,
    'apps',
    'pandora-mobile',
    'lib',
    'features',
    'simple',
    'project_experience_v2.dart',
  ),
  'utf8',
);

function section(start, end) {
  const startIndex = experienceSource.indexOf(start);
  assert.notEqual(startIndex, -1, `missing source anchor: ${start}`);
  const endIndex = experienceSource.indexOf(end, startIndex);
  assert.notEqual(endIndex, -1, `missing source anchor: ${end}`);
  return experienceSource.slice(startIndex, endIndex);
}

test('mobile workspace treats Experience Projection as lifecycle authority', () => {
  assert.ok(
    experienceSource.includes('PandoraDependencies.of(context).projectExperienceRepository'),
    'workspace must consume the canonical Experience Projection',
  );
  assert.ok(experienceSource.includes('ProjectWorkspaceV2View('));
  assert.ok(experienceSource.includes('canFocus: _projection?.canFocus == true'));
  assert.ok(experienceSource.includes('_projection?.canChange == true'));
  assert.ok(experienceSource.includes('_projection?.canUndo == true'));
  assert.ok(experienceSource.includes('_projection?.canPublish == true'));
  assert.equal(
    /\bProjectChangePhase\s+_phase\b/.test(experienceSource),
    false,
    'mutable local lifecycle phase must not return',
  );
});

test('change and publish completion are projection driven, not runtime polled', () => {
  const changeWatch = section(
    'Future<void> _watchExactChange(String? baseVersion) async {',
    'Future<void> _undoChange() async {',
  );
  assert.ok(changeWatch.includes('.watchExperience(widget.project.id)'));
  assert.equal(changeWatch.includes('projectRuntime'), false);
  assert.equal(changeWatch.includes('runtime.runtime('), false);
  assert.equal(changeWatch.includes('attempt < 90'), false);

  const publishWatch = section(
    'Future<void> _watchPublishCompletion(String versionId) async {',
    'Future<void> _publish(String domain, String versionId) async {',
  );
  assert.ok(publishWatch.includes('.watchExperience(widget.project.id)'));
  assert.equal(publishWatch.includes('_refresh()'), false);
  assert.equal(publishWatch.includes('runtime.runtime('), false);
  assert.equal(publishWatch.includes('attempt < 45'), false);
});

test('successful initial build flows directly into the product workspace', () => {
  assert.equal(
    experienceSource.includes("'Open project'"),
    false,
    'manual Open project boundary must not return',
  );
  assert.match(
    experienceSource,
    /ProjectWorkspaceV2Screen\(\s*project: _snapshot\?\.project \?\? widget\.project,\s*\)/,
    'successful build must enter the product workspace',
  );
});

test('only bounded exact-preview hydration retries remain in change completion', () => {
  const changeWatch = section(
    'Future<void> _watchExactChange(String? baseVersion) async {',
    'Future<void> _undoChange() async {',
  );
  assert.ok(changeWatch.includes('attempt < _previewRetryLimit'));
  assert.ok(changeWatch.includes('_loadExactPreviewFiles('));
});
